"""Procedurelle teksturer til mach1ne_counterfeit (diffuse + normal + spec), gemt som DDS med mipmaps.

    python make_textures.py <output-mappe>
"""
import io, os, sys, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(1337)


# ------------------------------------------------------------------ DDS med mipmaps
def save_dds(img, path, fmt='DXT1'):
    img = img.convert('RGBA')
    levels, w = [], img.width
    cur = img
    while True:
        buf = io.BytesIO()
        cur.save(buf, format='DDS', pixel_format=fmt)
        levels.append(buf.getvalue())
        if cur.width <= 4 or cur.height <= 4:
            break
        cur = cur.resize((cur.width // 2, cur.height // 2), Image.LANCZOS)
    head = bytearray(levels[0][:128])
    data = b''.join(l[128:] for l in levels)
    flags = struct.unpack_from('<I', head, 8)[0] | 0x20000
    struct.pack_into('<I', head, 8, flags)
    struct.pack_into('<I', head, 28, len(levels))
    caps = struct.unpack_from('<I', head, 108)[0] | 0x8 | 0x400000 | 0x1000
    struct.pack_into('<I', head, 108, caps)
    with open(path, 'wb') as f:
        f.write(bytes(head) + data)


# ------------------------------------------------------------------ støj
def vnoise(size, cx, cy=None, seed=None):
    cy = cy or cx
    rng = np.random.default_rng(seed) if seed is not None else RNG
    g = rng.random((cy, cx))
    ys, xs = np.arange(size) * cy / size, np.arange(size) * cx / size
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = ys - y0, xs - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    y1, x1 = (y0 + 1) % cy, (x0 + 1) % cx
    a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]; d = g[np.ix_(y1, x1)]
    fx, fy = fx[None, :], fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size, cells=4, octaves=5, persistence=0.5, aniso=(1, 1)):
    out, amp, tot = np.zeros((size, size)), 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        out += vnoise(size, max(1, int(c * aniso[0])), max(1, int(c * aniso[1]))) * amp
        tot += amp
        amp *= persistence
    return out / tot


def norm01(a):
    return (a - a.min()) / (a.max() - a.min() + 1e-9)


def lerp(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return np.asarray(a, float) * (1 - t) + np.asarray(b, float) * t


def to_img(rgb, alpha=None):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        return Image.fromarray(rgb)
    a = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, a]))


def normal_from_height(h, strength=4.0):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return to_img((n * 0.5 + 0.5) * 255)


def spec_img(intensity, gloss):
    i = np.clip(intensity, 0, 1) * 255
    g = np.clip(gloss if np.ndim(gloss) else np.full_like(intensity, gloss), 0, 1)
    return to_img(np.dstack([i, i, i]), g)


def write(name, rgb, height=None, spec=None, gloss=0.3, nstrength=4.0, alpha=None):
    save_dds(to_img(rgb, alpha), os.path.join(OUT, name + '_d.dds'), 'DXT5' if alpha is not None else 'DXT1')
    to_img(rgb, alpha).save(os.path.join(OUT, name + '_d.png'))
    if height is not None:
        save_dds(normal_from_height(height, nstrength), os.path.join(OUT, name + '_n.dds'), 'DXT1')
    if spec is not None:
        save_dds(spec_img(spec, gloss), os.path.join(OUT, name + '_s.dds'), 'DXT5')
    print(name)


def uv(size):
    v, u = np.mgrid[0:size, 0:size] / size
    return u, 1.0 - v   # Blender-UV: v = 0 i bunden



import math

rng = np.random.default_rng(42)
try:
    ImageFont.truetype('arialbd.ttf', 10)
    FB = lambda s: ImageFont.truetype('arialbd.ttf', max(6, s))
    FR = lambda s: ImageFont.truetype('arial.ttf', max(6, s))
except OSError:
    FB = FR = lambda s: ImageFont.load_default()


def write_img(name, img, height=None, spec=None, gloss=0.3, nstrength=4.0):
    """Som write(), men fra et færdigt PIL-billede (kan være ikke-kvadratisk)."""
    img.convert('RGB').save(os.path.join(OUT, name + '_d.png'))
    save_dds(img, os.path.join(OUT, name + '_d.dds'), 'DXT1')
    if height is not None:
        save_dds(normal_from_height(height, nstrength), os.path.join(OUT, name + '_n.dds'), 'DXT1')
    if spec is not None:
        save_dds(spec_img(spec, gloss), os.path.join(OUT, name + '_s.dds'), 'DXT5')
    print(name)


# ------------------------------------------------------------------ pengeseddel (fiktiv "Los Santos Reserve")
def guilloche(d, box, color, n=26, amp=0.32):
    x0, y0, x1, y1 = box
    cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    for k in range(n):
        pts = []
        ph = k / n * 2 * math.pi
        for i in range(181):
            t = i / 180 * 2 * math.pi
            r = 1 - amp * (0.5 + 0.5 * math.sin(7 * t + ph)) * (0.6 + 0.4 * math.cos(3 * t - ph * 2))
            pts.append((cx + math.cos(t) * rx * r, cy + math.sin(t) * ry * r))
        d.line(pts, fill=color, width=1)


def noise_wh(W, H, cells, octaves):
    S = max(W, H)
    return norm01(fbm(S, cells, octaves))[:H, :W]


def bill_image(W, H, wet=False, seed=1):
    r = np.random.default_rng(seed)
    v, u = np.mgrid[0:H, 0:W]
    u, v = u / W, v / H
    base = lerp((196, 214, 184), (226, 234, 210), noise_wh(W, H, 6, 4))
    wav = 0.5 + 0.5 * np.sin((u * 60 + np.sin(v * 9) * 2.5) * 2 * np.pi)
    base = lerp(base, (150, 184, 150), wav * 0.25)
    img = to_img(base)
    d = ImageDraw.Draw(img)
    s = H / 256
    ink, ink2, gold = (34, 82, 60), (70, 118, 92), (170, 136, 60)
    d.rectangle([6 * s, 6 * s, W - 6 * s, H - 6 * s], outline=ink, width=max(2, int(4 * s)))
    d.rectangle([14 * s, 14 * s, W - 14 * s, H - 14 * s], outline=ink2, width=max(1, int(1.5 * s)))
    guilloche(d, (W * 0.06, H * 0.14, W * 0.36, H * 0.86), ink2, 30)
    guilloche(d, (W * 0.66, H * 0.2, W * 0.94, H * 0.8), ink2, 24, 0.4)
    mx, my, mr = W * 0.5, H * 0.5, H * 0.3
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(176, 198, 168), outline=ink, width=max(2, int(3 * s)))
    d.ellipse([mx - mr * 0.42, my - mr * 0.62, mx + mr * 0.42, my + mr * 0.2], fill=(96, 130, 104))
    d.chord([mx - mr * 0.85, my + mr * 0.1, mx + mr * 0.85, my + mr * 1.7], 180, 360, fill=(96, 130, 104))
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], outline=ink, width=max(2, int(3 * s)))
    d.text((W * 0.5, H * 0.1), 'LOS SANTOS RESERVE', fill=ink, font=FB(int(22 * s)), anchor='mm')
    d.text((W * 0.21, H * 0.5), '1000', fill=ink, font=FB(int(64 * s)), anchor='mm')
    d.text((W * 0.8, H * 0.5), '1000', fill=gold, font=FB(int(46 * s)), anchor='mm')
    d.text((W * 0.5, H * 0.9), 'ET TUSINDE  -  SAN ANDREAS', fill=ink, font=FR(int(15 * s)), anchor='mm')
    serial = 'LS %07d' % r.integers(0, 9999999)
    d.text((W * 0.8, H * 0.2), serial, fill=(140, 30, 30), font=FB(int(14 * s)), anchor='mm')
    d.text((W * 0.21, H * 0.82), serial, fill=(140, 30, 30), font=FB(int(14 * s)), anchor='mm')
    d.line([(W * 0.62, 0), (W * 0.62, H)], fill=(120, 128, 120), width=max(2, int(4 * s)))
    a = np.asarray(img).astype(float)
    if wet:   # mættet, mørkere og lidt udløbet blæk
        a = np.asarray(img.filter(ImageFilter.GaussianBlur(1.0 * s))).astype(float)
        a = a * np.array([0.52, 0.66, 0.56]) + np.array([-4, 8, 0])
    return to_img(a)


B = bill_image(512, 256, seed=3)
h = np.asarray(B.convert('L').resize((256, 256))).astype(float) / 255
write_img('m1f_bill', B, h * 0.3, np.full((256, 256), 0.12), 0.25, nstrength=2.0)


def sheet(wet):
    S, pad = 1024, 22
    img = to_img(lerp((232, 230, 218), (246, 244, 236), fbm(S, 10, 4)) * (np.array([0.62, 0.68, 0.64]) if wet else 1.0))
    cw, ch = (S - pad * 2) // 2, (S - pad * 2) // 4
    for i in range(2):
        for j in range(4):
            img.paste(bill_image(cw - 8, ch - 8, wet=wet, seed=10 + i * 4 + j), (pad + i * cw + 4, pad + j * ch + 4))
    d = ImageDraw.Draw(img)
    for k in range(1, 4):
        y = pad + k * ch
        d.line([(0, y), (14, y)], fill=(40, 40, 40), width=2)
        d.line([(S - 14, y), (S, y)], fill=(40, 40, 40), width=2)
    d.line([(S // 2, 0), (S // 2, 14)], fill=(40, 40, 40), width=2)
    d.line([(S // 2, S - 14), (S // 2, S)], fill=(40, 40, 40), width=2)
    for (x, y), c in zip([(6, 6), (S - 30, 6)], [(0, 160, 220), (220, 0, 140)]):
        d.rectangle([x, y, x + 24, y + 10], fill=c)
    fib = fbm(S, 24, 3)
    write_img('m1f_sheet_wet' if wet else 'm1f_sheet', img, fib * 0.4,
              np.full((S, S), 0.55 if wet else 0.1), 0.85 if wet else 0.2, nstrength=2.5)


sheet(False)
sheet(True)

# ------------------------------------------------------------------ banderole
S = 256
img = to_img(lerp((196, 154, 52), (214, 176, 72), fbm(S, 8, 3)))
d = ImageDraw.Draw(img)
d.rectangle([0, 0, S, 18], fill=(120, 40, 110))
d.rectangle([0, S - 18, S, S], fill=(120, 40, 110))
d.text((S // 2, S // 2 - 28), '100 x 1000', fill=(50, 30, 20), font=FB(30), anchor='mm')
d.text((S // 2, S // 2 + 22), 'LSR - 100.000', fill=(50, 30, 20), font=FR(22), anchor='mm')
write_img('m1f_band', img, fbm(S, 16, 2) * 0.2, np.full((S, S), 0.15), 0.3)

# ------------------------------------------------------------------ blankt bomuldspapir
fib = fbm(S, 30, 3)
write('m1f_paper', lerp((236, 234, 224), (250, 249, 244), fib), fib * 0.4, np.full((S, S), 0.08), 0.15, nstrength=2.0)

# ------------------------------------------------------------------ grøn maskinlak med slid
S = 512
u, v = uv(S)
n = fbm(S, 6, 5)
chips = np.clip((norm01(fbm(S, 24, 3, persistence=0.6)) - 0.9) * 6, 0, 1) * 0.6 * np.clip(1.4 - v * 1.2, 0, 1)
grime = norm01(fbm(S, 3, 4)) * np.clip(1.2 - v, 0, 1)
rgb = lerp((52, 84, 72), (70, 106, 90), n)
rgb = lerp(rgb, (34, 34, 30), grime * 0.45)
rgb = lerp(rgb, (96, 100, 94), chips)
pits = (np.random.default_rng(5).random((S, S)) > 0.998).astype(float)
write('m1f_iron', rgb, n * 0.2 - chips * 0.6 - pits * 0.4, 0.35 * (1 - grime) + chips * 0.5, 0.55, nstrength=3.0)

# ------------------------------------------------------------------ børstet stål
S = 256
brush = norm01(fbm(S, 8, 4, aniso=(0.25, 16)))
sim = Image.new('L', (S, S))
sd = ImageDraw.Draw(sim)
for _ in range(40):
    x, y = int(rng.integers(0, S)), int(rng.integers(0, S))
    sd.line([(x, y), (x + int(rng.integers(-30, 30)), y + int(rng.integers(-6, 6)))], fill=int(rng.integers(60, 140)), width=1)
scr = np.asarray(sim) / 255
write('m1f_steel', lerp((104, 106, 110), (140, 142, 146), 0.85 * brush + 0.15 * scr),
      brush * 0.15 - scr * 0.1, 0.8 + 0.15 * brush, 0.85, nstrength=2.0)

# ------------------------------------------------------------------ gummivalse / blækvalse
n = fbm(S, 10, 4)
write('m1f_rubber', lerp((16, 16, 18), (34, 34, 36), n), n * 0.3, 0.25 + 0.1 * n, 0.45, nstrength=2.0)
streak = norm01(fbm(S, 4, 4, aniso=(8, 0.5)))
write('m1f_inkroll', lerp((14, 52, 36), (34, 96, 66), streak), streak * 0.2, 0.9 * np.ones((S, S)), 0.9, nstrength=1.5)

# ------------------------------------------------------------------ plast og LCD
n = fbm(S, 16, 3)
write('m1f_plastic', lerp((34, 36, 40), (48, 50, 56), n), n * 0.5, 0.3 + 0.1 * n, 0.5, nstrength=3.0)
write('m1f_plastic_lt', lerp((176, 178, 182), (200, 202, 206), n), n * 0.5, 0.35 + 0.1 * n, 0.55, nstrength=3.0)

img = Image.new('RGB', (256, 128), (10, 30, 24))
d = ImageDraw.Draw(img)
d.text((236, 64), '100', fill=(90, 255, 170), font=FB(78), anchor='rm')
d.text((20, 26), 'PCS', fill=(60, 200, 130), font=FB(18), anchor='lm')
d.text((20, 100), 'UV  MG', fill=(60, 200, 130), font=FB(16), anchor='lm')
write_img('m1f_lcd', img.resize((256, 256)))

# ------------------------------------------------------------------ typeskilt
img = Image.new('RGB', (512, 256), (172, 160, 120))
d = ImageDraw.Draw(img)
d.rectangle([8, 8, 503, 247], outline=(60, 50, 30), width=6)
d.text((256, 90), 'KRAUSE  OFFSET', fill=(40, 34, 20), font=FB(54), anchor='mm')
d.text((256, 160), 'MODELL  KO-52   -   NR. 41877', fill=(60, 50, 30), font=FR(28), anchor='mm')
d.text((256, 210), 'MAX 9000 BOGEN/H', fill=(60, 50, 30), font=FR(22), anchor='mm')
h = np.asarray(img.convert('L').resize((256, 256))).astype(float) / 255
write_img('m1f_plate', img, h * 0.8, np.full((256, 256), 0.6), 0.7, nstrength=3.0)

# ------------------------------------------------------------------ træ
S = 512
u, v = uv(S)
warp = fbm(S, 2, 3, aniso=(0.5, 2)) * 1.4
grain = 0.5 + 0.5 * np.sin((v * 12 + warp) * 2 * np.pi)
fine = norm01(fbm(S, 8, 4, aniso=(0.15, 6)))
write('m1f_wood', lerp((126, 92, 60), (168, 128, 86), 0.4 * grain + 0.6 * fine),
      grain * 0.25 + fine * 0.4, 0.08 + fine * 0.08, 0.2, nstrength=2.0)

# ------------------------------------------------------------------ snor
S = 256
u, v = uv(S)
twist = 0.5 + 0.5 * np.sin((u * 6 + v * 10) * 2 * np.pi)
write('m1f_cord', lerp((180, 180, 170), (226, 226, 216), 0.6 * twist + 0.4 * fbm(S, 8, 3)), twist,
      0.15 * np.ones((S, S)), 0.3, nstrength=5.0)

# ------------------------------------------------------------------ skæremåtte / advarselsstriber
grid = ((((u * 16) % 1) < 0.04) | (((v * 16) % 1) < 0.04)).astype(float)
write('m1f_mat', lerp((28, 70, 52), (230, 230, 220), grid * 0.7), -grid * 0.2, 0.15 + grid * 0.1, 0.3, nstrength=2.0)
stripes = ((((u + v) * 8) % 1) < 0.5).astype(float)
n = fbm(S, 10, 3)
write('m1f_hazard', lerp(lerp((20, 20, 20), (226, 180, 20), stripes), (90, 80, 60), n * 0.3), n * 0.2,
      0.4 * np.ones((S, S)), 0.5)
print('done')
