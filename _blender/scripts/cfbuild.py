# Bygger mach1ne_counterfeit props (med skelet) + prop-animationer i Blender + Sollumz.
#   exec(open(<denne fil>).read())
#   clear_scene(); rigs = build_all(); anims = build_anims(rigs)
#   export_all(<stream-mappe>)          # ydr (GEN8) + ytyp + ycd.xml
import bpy, bmesh, math, random, os
from mathutils import Vector, Matrix, Quaternion
from importlib import import_module

SZ = 'bl_ext.repo_sollumz_org.sollumz'
sh = import_module(SZ + '.ydr.shader_materials')
_bh = import_module(SZ + '.tools.blenderhelper')
_dh = import_module(SZ + '.tools.drawablehelper')
_ycdi = import_module(SZ + '.ycd.ycdimport')
SollumType = import_module(SZ + '.sollumz_properties').SollumType

# _blender-mappen: der hvor .blend-filen ligger (åbn _blender/mach1ne_counterfeit.blend før du kører scriptet)
HERE = os.path.dirname(bpy.data.filepath)
TEX = os.path.join(HERE, 'tex')
ANIM_DICT = 'm1_cf_anims'
TXD = 'm1_cf_tex'            # fælles texture dictionary (stream/m1_cf_tex.ytd) i stedet for embedded teksturer
EMBED_TEXTURES = False
# LOD: fuld model til LOD_HIGH m, forenklet (decimeret) model til LOD_MED m, derefter skjult
LOD_HIGH, LOD_MED = 15.0, 70.0
LOD_SMALL = 35.0             # små ting (sedeltæller) forsvinder tidligere
FPS = 24
Z = Vector((0, 0, 1))

NS = 'normal_spec.sps'
MATS = {
    'm1f_iron':       dict(shader=NS, spec=0.6, falloff=40, bump=1.0),
    'm1f_steel':      dict(shader=NS, spec=1.3, falloff=90, bump=0.4),
    'm1f_rubber':     dict(shader=NS, spec=0.4, falloff=25, bump=0.5),
    'm1f_inkroll':    dict(shader=NS, spec=1.2, falloff=80, bump=0.3),
    'm1f_paper':      dict(shader=NS, spec=0.1, falloff=10, bump=0.5),
    'm1f_sheet':      dict(shader=NS, spec=0.15, falloff=12, bump=0.4),
    'm1f_sheet_wet':  dict(shader=NS, spec=0.9, falloff=60, bump=0.4),
    'm1f_bill':       dict(shader=NS, spec=0.15, falloff=12, bump=0.4),
    'm1f_band':       dict(shader=NS, spec=0.2, falloff=15, bump=0.3),
    'm1f_plastic':    dict(shader=NS, spec=0.5, falloff=40, bump=0.6),
    'm1f_plastic_lt': dict(shader=NS, spec=0.5, falloff=40, bump=0.6),
    'm1f_lcd':        dict(shader='emissive.sps', emissive=3.0),
    'm1f_plate':      dict(shader=NS, spec=0.8, falloff=60, bump=0.8),
    'm1f_wood':       dict(shader=NS, spec=0.15, falloff=10, bump=1.0),
    'm1f_cord':       dict(shader=NS, spec=0.1, falloff=10, bump=1.2),
    'm1f_mat':        dict(shader=NS, spec=0.2, falloff=15, bump=0.4),
    'm1f_hazard':     dict(shader=NS, spec=0.4, falloff=30, bump=0.5),
}
ICON_MATS = {}

exec(open(os.path.join(HERE, 'scripts', 'mbcore.py'), encoding='utf-8').read())


def rot_x(a):
    return Matrix.Rotation(a, 3, 'X')


def rot_y(a):
    return Matrix.Rotation(a, 3, 'Y')


def rot_z(a):
    return Matrix.Rotation(a, 3, 'Z')


# ---------------------------------------------------------------- geometri-hjælpere
def transformed(mb, fn, M, recalc=False):
    """Kør fn(), og flyt de nye vertices med 4x4-matrix M."""
    before = set(mb.bm.verts)
    fbefore = set(mb.bm.faces)
    fn()
    new = [v for v in mb.bm.verts if v not in before]
    for v in new:
        v.co = M @ v.co
    if recalc:
        bmesh.ops.recalc_face_normals(mb.bm, faces=[f for f in mb.bm.faces if f not in fbefore])


def cyl_x(mb, c, r, L, mat, segs=24, urep=1.0, caps=True, cap_mat=None):
    """Cylinder langs X-aksen centreret i c (lukket, med endeflader)."""
    prof = [(r, -L / 2), (r, L / 2)]
    if caps:
        prof = [(0.0, -L / 2)] + prof + [(0.0, L / 2)]
    M = Matrix.Translation(Vector(c)) @ rot_y(math.pi / 2).to_4x4()
    transformed(mb, lambda: mb.revolve((0, 0, 0), prof, segs, mat, urep=urep, vmode='norm'), M, recalc=caps)


def cyl_z(mb, c, r, h, mat, segs=20, caps=True):
    prof = [(r, 0.0), (r, h)]
    if caps:
        prof = [(0.0, 0.0)] + prof + [(0.0, h)]
    transformed(mb, lambda: mb.revolve((0, 0, 0), prof, segs, mat, vmode='norm'),
                Matrix.Translation(Vector(c)), recalc=caps)


def rod(mb, a, b, r, mat, segs=10):
    mb.tube([a, b], r, segs, mat, cap0=True, cap1=True)


def beam(mb, a, b, w, d, mat, bevel=0.004):
    """Firkantet lægte fra a til b (træets årer følger længden)."""
    a, b = Vector(a), Vector(b)
    v = b - a
    R = v.to_track_quat('Z', 'Y').to_matrix()
    mb.box((a + b) / 2, (w, d, v.length), mat, rot=R, bevel=bevel)


def sheet_grid(mb, c, w, h, mat, nu=4, nv=4, plane='XY', bend=None, uvrect=(0, 0, 1, 1), double=True, flipu=False):
    """Tyndt ark. plane 'XY' ligger ned (normal +Z), 'XZ' hænger (normal -Y). bend(u, v) -> forskydning langs normal."""
    c = Vector(c)
    bend = bend or (lambda u, v: 0.0)
    u0, v0, u1, v1 = uvrect
    for back in ((False, True) if double else (False,)):
        rows = []
        for j in range(nv + 1):
            row = []
            for i in range(nu + 1):
                u, v = i / nu, j / nv
                x, y = (u - 0.5) * w, (v - 0.5) * h
                d = bend(u, v) + (-0.0006 if back else 0.0)
                if plane == 'XY':
                    p = c + Vector((x, y, d))
                else:
                    p = c + Vector((x, -d, y))
                row.append(mb.bm.verts.new(p))
            rows.append(row)
        for j in range(nv):
            for i in range(nu):
                q = [rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]]
                t = [(i / nu, j / nv), ((i + 1) / nu, j / nv), ((i + 1) / nu, (j + 1) / nv), (i / nu, (j + 1) / nv)]
                t = [(u0 + (u1 - u0) * ((1 - a) if flipu else a), v0 + (v1 - v0) * b) for a, b in t]
                if plane == 'XZ':
                    q = [q[0], q[3], q[2], q[1]]
                    t = [t[0], t[3], t[2], t[1]]
                if back:
                    q.reverse(); t.reverse()
                mb.face(q, mat, t)


def ream(mb, c, w, d, h, top_mat, side_mat='m1f_paper', top_uv=(0, 0, 1, 1)):
    """Stak papir/sedler: kasse med tekstur på toppen og papirkanter på siderne."""
    c = Vector(c)
    mb.box(c + Vector((0, 0, h / 2 - 0.0008)), (w, d, h - 0.0016), side_mat, bevel=0.0006, scale=3.0)
    sheet_grid(mb, c + Vector((0, 0, h)), w, d, top_mat, 1, 1, uvrect=top_uv, double=False)


# ---------------------------------------------------------------- rig
class Rig:
    """Drawable med skelet. Hver knogle har sin egen MB; geometri bygges i verdenskoordinater."""

    def __init__(self, name):
        self.name = name
        self.bones = {'root': dict(parent=None, pivot=Vector(), tag=0, anim=False)}
        self.order = ['root']
        self.mbs = {'root': MB()}

    def bone(self, name, pivot, tag, parent='root'):
        self.bones[name] = dict(parent=parent, pivot=Vector(pivot), tag=tag, anim=True)
        self.order.append(name)
        self.mbs[name] = MB()
        return self.mbs[name]

    def mb(self, name='root'):
        return self.mbs[name]

    def finish(self, coll):
        arm = bpy.data.armatures.new(self.name + '.skel')
        obj = bpy.data.objects.new(self.name, arm)
        obj.sollum_type = SollumType.DRAWABLE
        coll.objects.link(obj)
        select_only(obj)
        bpy.ops.object.mode_set(mode='EDIT')
        for n in self.order:
            b = self.bones[n]
            eb = arm.edit_bones.new(n)
            eb.head = b['pivot']
            eb.tail = b['pivot'] + Vector((0, 0.05, 0))
            eb.roll = 0.0
            if b['parent']:
                eb.parent = arm.edit_bones[b['parent']]
        bpy.ops.object.mode_set(mode='OBJECT')
        for n in self.order:
            b = self.bones[n]
            bone = arm.bones[n]
            bone.bone_properties.tag = b['tag']
            bone.bone_properties.flags.clear()
            if b['anim']:
                for f in ('RotX', 'RotY', 'RotZ', 'TransX', 'TransY', 'TransZ'):
                    bone.bone_properties.flags.add().name = f
            obj.pose.bones[n].rotation_mode = 'QUATERNION'
        for n in self.order:
            mb = self.mbs[n]
            if not mb.bm.faces:
                mb.bm.free()
                continue
            piv = self.bones[n]['pivot']
            for v in mb.bm.verts:
                v.co -= piv
            ob = mb.finish(f'{self.name}.{n}', coll)
            _dh.convert_obj_to_model(ob)
            ob.parent = obj
            _bh.add_child_of_bone_constraint(ob, obj, n)
        return obj


def select_only(ob):
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def add_bound(drawable, name, bound):
    sc = bpy.context.scene
    select_only(drawable)
    sc.create_bound_type = 'sollumz_bound_composite'
    bpy.ops.sollumz.createbound()
    comp = [c for c in drawable.children if c.sollum_type == 'sollumz_bound_composite'][-1]
    comp.name = name + '.col'
    select_only(comp)
    sc.create_bound_type = 'sollumz_bound_box'
    bpy.ops.sollumz.createbound()
    box = [c for c in comp.children if c.sollum_type == 'sollumz_bound_box'][-1]
    box.name = name + '.box'
    (cx, cy, cz), (sx, sy, sz) = bound
    for v in box.data.vertices:
        v.co = Vector((v.co.x * sx + cx, v.co.y * sy + cy, v.co.z * sz + cz))
    select_only(box)
    bpy.ops.sollumz.createcollisionmaterial()
    box.hide_render = True


# Bone-tags (unikke pr. maskine, så alle clips kan ligge i én ycd)
T_PRESS = dict(imp=2101, plate=2102, ink_a=2103, ink_b=2104, fly=2105, sheet=2106, gear=2107)
T_DRY = {f'sheet_{i}': 2200 + i for i in range(1, 11)}
T_CUT = dict(lever=2301, blade=2302, clamp=2303, strip=2304)
T_CNT = dict(f1=2401, f2=2402, f3=2403, f4=2404, wheel=2405)

SHEET_W, SHEET_H = 0.31, 0.34   # trykark (2 x 4 sedler)
BILL_W, BILL_H = 0.155, 0.078   # seddel


# ================================================================ TRYKPRESSE
def build_press(name, state, coll):
    r = Rig(name)
    m = r.mb()
    # fod og underskab
    m.box((0, 0, 0.32), (0.96, 0.62, 0.56), 'm1f_iron', bevel=0.02, scale=1.2)
    m.box((0, 0, 0.025), (1.02, 0.68, 0.05), 'm1f_iron', bevel=0.008, scale=1.2)
    for x in (-0.44, 0.44):
        for y in (-0.27, 0.27):
            cyl_z(m, (x, y, -0.0), 0.035, 0.012, 'm1f_rubber', 12)
    # låge med typeskilt og håndtag
    m.box((-0.18, -0.312, 0.32), (0.4, 0.012, 0.4), 'm1f_iron', bevel=0.006, scale=1.2)
    sheet_grid(m, (-0.18, -0.3195, 0.45), 0.2, 0.1, 'm1f_plate', 1, 1, plane='XZ', double=False)
    rod(m, (-0.02, -0.33, 0.28), (-0.02, -0.33, 0.36), 0.008, 'm1f_steel')
    # kontrolpanel med knapper
    m.box((0.28, -0.32, 0.5), (0.22, 0.03, 0.12), 'm1f_plastic', bevel=0.006)
    for i, mat in enumerate(('m1f_hazard', 'm1f_inkroll', 'm1f_rubber')):
        transformed(m, lambda mat=mat: cyl_z(m, (0, 0, 0), 0.018, 0.018, mat, 12),
                    Matrix.Translation(Vector((0.21 + i * 0.07, -0.335, 0.5))) @ rot_x(math.pi / 2).to_4x4())
    # sidestel (to støbte sider med afrundet top)
    for x in (-0.43, 0.43):
        m.box((x, 0.02, 0.84), (0.05, 0.56, 0.48), 'm1f_iron', bevel=0.02, scale=1.2)
        cyl_x(m, (x, 0.02, 1.08), 0.28, 0.05, 'm1f_iron', 28)
        for y, z in ((-0.05, 0.82), (0.12, 0.98), (0.2, 1.1), (0.08, 1.12)):
            cyl_x(m, (x * 1.13, y, z), 0.03, 0.04, 'm1f_steel', 14)   # lejer
    # tværstivere
    rod(m, (-0.43, 0.27, 0.66), (0.43, 0.27, 0.66), 0.018, 'm1f_steel')
    rod(m, (-0.43, -0.22, 1.2), (0.43, -0.22, 1.2), 0.014, 'm1f_steel')
    # blækkar bagpå
    m.box((0, 0.3, 1.16), (0.78, 0.1, 0.07), 'm1f_iron', bevel=0.008)
    m.box((0, 0.3, 1.196), (0.74, 0.08, 0.004), 'm1f_inkroll', bevel=0.0)
    # elmotor + remskive
    cyl_x(m, (0.3, 0.16, 0.7), 0.075, 0.2, 'm1f_iron', 20)
    cyl_x(m, (0.42, 0.16, 0.7), 0.04, 0.03, 'm1f_steel', 16)
    # indføringsbord bagpå (papirstak) og udlægningsbakke foran
    feed = rot_x(math.radians(-12))
    m.box((0, 0.48, 1.0), (0.5, 0.36, 0.015), 'm1f_steel', rot=feed, bevel=0.003)
    for x in (-0.2, 0.2):
        rod(m, (x, 0.62, 0.66), (x, 0.62, 0.98), 0.012, 'm1f_steel')
    m.box((0, -0.46, 0.64), (0.46, 0.34, 0.012), 'm1f_steel', bevel=0.003)
    for x in (-0.235, 0.235):
        m.box((x, -0.46, 0.665), (0.01, 0.34, 0.05), 'm1f_steel', bevel=0.002)
    for x in (-0.18, 0.18):
        rod(m, (x, -0.6, 0.32), (x, -0.6, 0.64), 0.012, 'm1f_steel')
    if state in ('on', 'off'):
        # blankt papir på indføringsbordet (vippet som bordet)
        h = 0.05 if state == 'on' else 0.08
        transformed(m, lambda: ream(m, (0, 0, 0), SHEET_W, SHEET_H, h, 'm1f_paper'),
                    Matrix.Translation(Vector((0, 0.5, 1.008))) @ feed.to_4x4())
    out_h = {'off': 0.0, 'on': 0.012, 'done': 0.06}[state]
    if out_h:
        ream(m, (0, -0.46, 0.646), SHEET_W, SHEET_H, out_h, 'm1f_sheet_wet')

    # bevægelige dele
    imp = r.bone('imp', (0, -0.05, 0.82), T_PRESS['imp'])
    cyl_x(imp, (0, -0.05, 0.82), 0.11, 0.78, 'm1f_rubber', 32, urep=2)
    cyl_x(imp, (0, -0.05, 0.82), 0.025, 0.9, 'm1f_steel', 12)
    imp.box((0, -0.05, 0.93), (0.76, 0.012, 0.006), 'm1f_steel', bevel=0.001)     # gribekant (viser rotation)
    pl = r.bone('plate', (0, 0.12, 0.98), T_PRESS['plate'])
    cyl_x(pl, (0, 0.12, 0.98), 0.09, 0.76, 'm1f_steel', 32, urep=2)
    pl.box((0, 0.12, 1.07), (0.7, 0.012, 0.006), 'm1f_iron', bevel=0.001)
    for key, c in (('ink_a', (0, 0.2, 1.1)), ('ink_b', (0, 0.08, 1.12))):
        b = r.bone(key, c, T_PRESS[key])
        cyl_x(b, c, 0.035, 0.74, 'm1f_inkroll', 18, urep=3)
        cyl_x(b, c, 0.01, 0.84, 'm1f_steel', 8)
    fly = r.bone('fly', (0.5, 0.0, 0.82), T_PRESS['fly'])
    cyl_x(fly, (0.5, 0.0, 0.82), 0.2, 0.03, 'm1f_iron', 36, caps=False)
    cyl_x(fly, (0.5, 0.0, 0.82), 0.17, 0.035, 'm1f_iron', 36, caps=False)
    transformed(fly, lambda: fly.revolve((0, 0, 0), [(0.17, 0.0175), (0.2, 0.0175)], 36, 'm1f_iron', planar=True),
                Matrix.Translation(Vector((0.5, 0, 0.82))) @ rot_y(math.pi / 2).to_4x4())
    transformed(fly, lambda: fly.revolve((0, 0, 0), [(0.2, -0.0175), (0.17, -0.0175)], 36, 'm1f_iron', planar=True),
                Matrix.Translation(Vector((0.5, 0, 0.82))) @ rot_y(math.pi / 2).to_4x4())
    cyl_x(fly, (0.5, 0.0, 0.82), 0.04, 0.06, 'm1f_steel', 16)
    for k in range(5):
        a = k / 5 * 2 * math.pi
        rod(fly, (0.5, math.cos(a) * 0.035, 0.82 + math.sin(a) * 0.035),
            (0.5, math.cos(a) * 0.172, 0.82 + math.sin(a) * 0.172), 0.012, 'm1f_iron', 8)
    rod(fly, (0.52, 0.0, 0.99), (0.6, 0.0, 0.99), 0.012, 'm1f_wood', 8)                  # håndsving
    gear = r.bone('gear', (-0.47, 0.035, 0.9), T_PRESS['gear'])
    cyl_x(gear, (-0.47, 0.035, 0.9), 0.09, 0.025, 'm1f_steel', 24)
    for k in range(16):
        a = k / 16 * 2 * math.pi
        gear.box((-0.47, 0.035 + math.cos(a) * 0.095, 0.9 + math.sin(a) * 0.095), (0.025, 0.018, 0.018),
                 'm1f_steel', rot=rot_x(a), bevel=0.002)
    # arket der kører gennem maskinen (kun i 'on')
    if state == 'on':
        sh_ = r.bone('sheet', (0, 0.5, 1.07), T_PRESS['sheet'])
        sheet_grid(sh_, (0, 0.5, 1.07), SHEET_W, SHEET_H, 'm1f_sheet_wet', 3, 3)
    return r.finish(coll)


# ================================================================ TØRRESNOR
def build_dryline(name, state, coll):
    r = Rig(name)
    m = r.mb()
    X, LINES = 0.82, (1.62, 1.22)
    for sx in (-1, 1):
        x = sx * X
        for sy in (-1, 1):
            beam(m, (x, sy * 0.38, 0.02), (x, sy * 0.03, 1.72), 0.045, 0.035, 'm1f_wood')
        m.box((x, 0, 0.03), (0.06, 0.9, 0.05), 'm1f_wood', bevel=0.006)
        m.box((x, 0, 0.6), (0.04, 0.5, 0.04), 'm1f_wood', bevel=0.005)
        m.box((x, 0, 1.73), (0.08, 0.12, 0.05), 'm1f_wood', bevel=0.006)
        for z in LINES:
            cyl_x(m, (x, 0, z), 0.012, 0.09, 'm1f_steel', 10)                            # krog/øje
    sag = lambda t: -0.035 * math.sin(math.pi * t)
    for z in LINES:
        pts = [(-X + 2 * X * t, 0, z + sag(t)) for t in [i / 16 for i in range(17)]]
        m.tube(pts, 0.004, 6, 'm1f_cord', cap1=False, vscale=20)
    n = 5
    tag = 0
    for li, z in enumerate(LINES):
        for k in range(n):
            tag += 1
            t = (k + 0.5) / n
            x = -X + 2 * X * t
            top = z + sag(t)
            b = r.bone(f'sheet_{tag}', (x, 0, top), T_DRY[f'sheet_{tag}'])
            # klemmer (to pr. ark)
            for dx in (-0.1, 0.1):
                b.box((x + dx, 0, top - 0.012), (0.012, 0.016, 0.07), 'm1f_wood', bevel=0.002)
                b.box((x + dx, 0, top - 0.004), (0.014, 0.018, 0.006), 'm1f_steel', bevel=0.001)
            if state == 'empty':
                continue
            rng = random.Random(tag * 7 + (1 if state == 'wet' else 2))
            wet = state == 'wet'
            curl = 0.0 if wet else 0.012
            bend = lambda u, v, rng=rng, curl=curl, wet=wet: (
                0.006 * math.sin(u * math.pi * 2 + rng.random() * 3) * (1 - v)
                + curl * (1 - v) ** 2 * math.sin(u * math.pi)
                + (0.004 * (1 - v) if wet else 0.0))
            sheet_grid(b, (x, 0, top - 0.025 - SHEET_H / 2), SHEET_W, SHEET_H,
                       'm1f_sheet_wet' if wet else 'm1f_sheet', 4, 5, plane='XZ', bend=bend)
    return r.finish(coll)


# ================================================================ SKÆREMASKINE (guillotine)
def build_cutter(name, state, coll):
    r = Rig(name)
    m = r.mb()
    # stålstativ
    for x in (-0.32, 0.32):
        for y in (-0.24, 0.24):
            m.box((x, y, 0.42), (0.04, 0.04, 0.84), 'm1f_steel', bevel=0.004)
    for z in (0.12, 0.8):
        for y in (-0.24, 0.24):
            m.box((0, y, z), (0.64, 0.03, 0.03), 'm1f_steel', bevel=0.003)
        for x in (-0.32, 0.32):
            m.box((x, 0, z), (0.03, 0.48, 0.03), 'm1f_steel', bevel=0.003)
    m.box((0, 0, 0.12), (0.6, 0.44, 0.01), 'm1f_wood', bevel=0.002)                         # hylde
    # bord med skæremåtte
    m.box((0, 0, 0.84), (0.72, 0.56, 0.05), 'm1f_iron', bevel=0.01, scale=1.2)
    sheet_grid(m, (0, 0.04, 0.8655), 0.6, 0.46, 'm1f_mat', 1, 1, double=False)
    m.box((0, 0.27, 0.9), (0.62, 0.025, 0.07), 'm1f_iron', bevel=0.004)                    # anslag bagpå
    m.box((-0.31, 0.04, 0.89), (0.012, 0.46, 0.05), 'm1f_steel', bevel=0.002)               # sidevinkel
    # søjler + tværbjælke
    for x in (-0.34, 0.34):
        m.box((x, -0.02, 1.07), (0.06, 0.09, 0.42), 'm1f_iron', bevel=0.01, scale=1.2)
    m.box((0, -0.02, 1.3), (0.74, 0.09, 0.06), 'm1f_iron', bevel=0.01, scale=1.2)
    m.box((0, -0.067, 1.3), (0.5, 0.004, 0.04), 'm1f_hazard', bevel=0.0)
    m.box((0, -0.11, 0.87), (0.6, 0.02, 0.006), 'm1f_hazard', bevel=0.0)                    # skærelinje-advarsel
    # stak på bordet / færdige sedler
    if state == 'loaded':
        ream(m, (0, 0.09, 0.866), SHEET_W, SHEET_H, 0.035, 'm1f_sheet')
    if state == 'done':
        for i in range(4):
            for j in range(2):
                ream(m, (-0.17 + j * 0.17, 0.0 + i * 0.085, 0.866), BILL_W, BILL_H, 0.025 + 0.01 * ((i + j) % 2), 'm1f_bill')
    if state in ('loaded', 'done'):
        for i in range(3):
            ream(m, (-0.12 + i * 0.12, 0.0, 0.132), BILL_W, BILL_H, 0.03, 'm1f_bill')        # på hylden

    # kniv (glider op/ned), pressebjælke, arm
    blade = r.bone('blade', (0, -0.08, 1.12), T_CUT['blade'])
    blade.box((0, -0.08, 1.14), (0.62, 0.02, 0.1), 'm1f_steel', bevel=0.003)
    transformed(blade, lambda: blade.box((0, 0, 0), (0.62, 0.006, 0.03), 'm1f_steel', bevel=0.001),
                Matrix.Translation(Vector((0, -0.085, 1.08))) @ rot_x(math.radians(12)).to_4x4())
    blade.box((0, -0.0915, 1.15), (0.5, 0.002, 0.03), 'm1f_hazard', bevel=0.0)
    clamp = r.bone('clamp', (0, 0.0, 1.05), T_CUT['clamp'])
    clamp.box((0, 0.0, 1.0), (0.6, 0.04, 0.03), 'm1f_iron', bevel=0.004)
    rod(clamp, (0, 0.0, 1.015), (0, 0.0, 1.25), 0.014, 'm1f_steel')
    cyl_z(clamp, (0, 0.0, 1.25), 0.03, 0.02, 'm1f_iron', 16)
    lever = r.bone('lever', (0.4, -0.02, 1.2), T_CUT['lever'])
    cyl_x(lever, (0.4, -0.02, 1.2), 0.045, 0.06, 'm1f_iron', 18)
    lever.box((0.43, -0.25, 1.26), (0.03, 0.46, 0.04), 'm1f_iron', rot=rot_x(math.radians(-14)), bevel=0.006)
    rod(lever, (0.43, -0.48, 1.32), (0.02, -0.48, 1.32), 0.016, 'm1f_steel', 10)        # langt håndtag til to hænder
    rod(lever, (0.35, -0.48, 1.32), (0.03, -0.48, 1.32), 0.021, 'm1f_rubber', 12)
    # strimmel sedler der skæres af og glider frem (kun loaded)
    if state == 'loaded':
        strip = r.bone('strip', (0, -0.12, 0.866), T_CUT['strip'])
        ream(strip, (0, -0.12, 0.866), SHEET_W, BILL_H, 0.035, 'm1f_sheet', top_uv=(0, 0, 1, 0.25))
    return r.finish(coll)


# ================================================================ SEDDELTÆLLER
def build_counter(name, state, coll):
    r = Rig(name)
    m = r.mb()
    # krop
    m.box((0, 0.01, 0.07), (0.24, 0.22, 0.14), 'm1f_plastic', bevel=0.014)
    for x in (-0.106, 0.106):
        for y in (-0.085, 0.105):
            cyl_z(m, (x, y, -0.005), 0.012, 0.007, 'm1f_rubber', 10)
    # tragt ovenpå (sedlerne læner bagud)
    tilt = rot_x(math.radians(28)).to_4x4()
    transformed(m, lambda: m.box((0, 0, 0), (0.18, 0.1, 0.008), 'm1f_plastic', bevel=0.002),
                Matrix.Translation(Vector((0, 0.07, 0.162))) @ tilt)
    transformed(m, lambda: m.box((0, 0, 0), (0.19, 0.008, 0.1), 'm1f_plastic_lt', bevel=0.003),
                Matrix.Translation(Vector((0, 0.13, 0.2))) @ rot_x(math.radians(-24)).to_4x4())
    for x in (-0.096, 0.096):
        transformed(m, lambda x=x: m.box((0, 0, 0), (0.006, 0.11, 0.05), 'm1f_plastic_lt', bevel=0.002),
                    Matrix.Translation(Vector((x, 0.07, 0.19))) @ tilt)
    # skrå frontpanel med display og knapper
    panel = Matrix.Translation(Vector((0, -0.08, 0.15))) @ rot_x(math.radians(25)).to_4x4()
    transformed(m, lambda: m.box((0, 0, 0), (0.24, 0.075, 0.014), 'm1f_plastic_lt', bevel=0.004), panel)
    transformed(m, lambda: sheet_grid(m, (0.035, 0, 0.0075), 0.1, 0.045, 'm1f_lcd', 1, 1, double=False), panel)
    for i in range(4):
        transformed(m, lambda i=i: m.box((-0.085 + (i % 2) * 0.026, -0.012 + (i // 2) * 0.024, 0.009),
                                         (0.018, 0.014, 0.006), 'm1f_plastic', bevel=0.002), panel)
    # lomme foran (stacker)
    m.box((0, -0.135, 0.008), (0.2, 0.075, 0.008), 'm1f_plastic', bevel=0.002)
    m.box((0, -0.171, 0.022), (0.2, 0.006, 0.036), 'm1f_plastic_lt', bevel=0.002)
    for x in (-0.1, 0.1):
        m.box((x, -0.135, 0.028), (0.006, 0.075, 0.048), 'm1f_plastic_lt', bevel=0.002)
    wheel = r.bone('wheel', (0, 0.02, 0.145), T_CNT['wheel'])
    cyl_x(wheel, (0, 0.02, 0.145), 0.02, 0.15, 'm1f_rubber', 16, urep=2)
    if state == 'run':
        transformed(m, lambda: ream(m, (0, 0, 0), BILL_W, BILL_H, 0.028, 'm1f_bill'),
                    Matrix.Translation(Vector((0, 0.07, 0.168))) @ tilt @ Matrix.Translation(Vector((0, 0, 0.0))))
        ream(m, (0, -0.135, 0.012), BILL_W, BILL_H, 0.014, 'm1f_bill')
        # sedler der bladres ned i maskinen og ud i lommen
        for k in range(1, 5):
            b = r.bone(f'f{k}', (0, 0.02, 0.15), T_CNT[f'f{k}'])
            sheet_grid(b, (0, 0.02 + BILL_H / 2 + 0.006, 0.15), BILL_W, BILL_H, 'm1f_bill', 2, 2)
    return r.finish(coll)


# ================================================================ ARBEJDSBORD
def build_table(name, coll):
    r = Rig(name)
    m = r.mb()
    W, D, H = 1.4, 0.7, 0.9
    for i in range(5):
        pw = (D - 0.016) / 5
        y = -D / 2 + pw / 2 + i * (pw + 0.004)
        m.box((0, y, H - 0.02), (W, pw, 0.04), 'm1f_wood', bevel=0.005)
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        for y in (-D / 2 + 0.06, D / 2 - 0.06):
            m.box((x, y, (H - 0.04) / 2), (0.05, 0.05, H - 0.04), 'm1f_wood', bevel=0.004)
    for y in (-D / 2 + 0.06, D / 2 - 0.06):
        m.box((0, y, 0.18), (W - 0.12, 0.04, 0.04), 'm1f_wood', bevel=0.004)
    m.box((0, 0, 0.2), (W - 0.16, D - 0.16, 0.02), 'm1f_wood', bevel=0.003)
    for i in range(3):
        ream(m, (-0.55 + i * 0.03, 0.2 - i * 0.04, 0.22), SHEET_W, SHEET_H, 0.06, 'm1f_paper')
    sheet_grid(m, (0.45, 0.18, H + 0.0012), SHEET_W, SHEET_H, 'm1f_sheet', 1, 1, double=False)
    return r.finish(coll)


MODELS = [
    # navn, builder, bound ((center), (size)), animeret
    ('m1_cf_press_off',      lambda n, c: build_press(n, 'off', c),       ((0, 0, 0.62), (1.1, 1.3, 1.24)), True),
    ('m1_cf_press_on',       lambda n, c: build_press(n, 'on', c),        ((0, 0, 0.62), (1.1, 1.3, 1.24)), True),
    ('m1_cf_press_done',     lambda n, c: build_press(n, 'done', c),      ((0, 0, 0.62), (1.1, 1.3, 1.24)), True),
    ('m1_cf_dryline_empty',  lambda n, c: build_dryline(n, 'empty', c),   ((0, 0, 0.88), (1.75, 0.8, 1.76)), True),
    ('m1_cf_dryline_wet',    lambda n, c: build_dryline(n, 'wet', c),     ((0, 0, 0.88), (1.75, 0.8, 1.76)), True),
    ('m1_cf_dryline_dry',    lambda n, c: build_dryline(n, 'dry', c),     ((0, 0, 0.88), (1.75, 0.8, 1.76)), True),
    ('m1_cf_cutter_empty',   lambda n, c: build_cutter(n, 'empty', c),    ((0, -0.05, 0.68), (0.82, 0.7, 1.36)), True),
    ('m1_cf_cutter_loaded',  lambda n, c: build_cutter(n, 'loaded', c),   ((0, -0.05, 0.68), (0.82, 0.7, 1.36)), True),
    ('m1_cf_cutter_done',    lambda n, c: build_cutter(n, 'done', c),     ((0, -0.05, 0.68), (0.82, 0.7, 1.36)), True),
    ('m1_cf_counter',        lambda n, c: build_counter(n, 'idle', c),    ((0, 0, 0.12), (0.28, 0.3, 0.24)), True),
    ('m1_cf_counter_run',    lambda n, c: build_counter(n, 'run', c),     ((0, 0, 0.12), (0.28, 0.3, 0.24)), True),
    ('m1_cf_table',          lambda n, c: build_table(n, c),              ((0, 0, 0.45), (1.4, 0.7, 0.9)), False),
]


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials, bpy.data.images):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def build_all(only=None):
    coll = bpy.data.collections.get('mach1ne_counterfeit') or bpy.data.collections.new('mach1ne_counterfeit')
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    out = {}
    for name, fn, bound, _ in MODELS:
        if only and name not in only:
            continue
        ob = fn(name, coll)
        add_bound(ob, name, bound)
        out[name] = ob
    return out


# ================================================================ ANIMATIONER
def _q(axis, angle):
    return Quaternion(Vector(axis), angle)


def bake(arm, act_name, frames, fn):
    """fn(bone_name, t 0..1) -> (location Vector | None, Quaternion | None). Én nøgle pr. frame."""
    arm.animation_data_create()
    act = bpy.data.actions.new(act_name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for f in range(frames + 1):
        t = f / frames
        for pb in arm.pose.bones:
            res = fn(pb.name, t)
            if res is None:
                continue
            loc, rot = res
            if loc is not None:
                pb.location = loc
                pb.keyframe_insert('location', frame=f)
            if rot is not None:
                pb.rotation_quaternion = rot
                pb.keyframe_insert('rotation_quaternion', frame=f)
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    return act


def _fcurves(act):
    try:
        return list(act.fcurves)
    except AttributeError:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def smooth(a, b, t):
    """0 før a, 1 efter b, blød overgang imellem."""
    if t <= a:
        return 0.0
    if t >= b:
        return 1.0
    x = (t - a) / (b - a)
    return x * x * (3 - 2 * x)


def anim_press(t):
    """2 s loop. Valserne drejer en hel omgang, arket kører fra indføring til udlægning."""
    X = (1, 0, 0)
    a = t * 2 * math.pi

    def fn(bone, t=t):
        if bone == 'imp':
            return None, _q(X, -a)
        if bone == 'plate':
            return None, _q(X, a)
        if bone in ('ink_a', 'ink_b'):
            return None, _q(X, (-3 if bone == 'ink_a' else 3) * a)
        if bone == 'fly':
            return None, _q(X, -a)
        if bone == 'gear':
            return None, _q(X, 2 * a)
        if bone == 'sheet':
            # bane (relativt til pivot 0, 0.5, 1.07): ind under valserne -> frem -> ned på bakken
            keys = [(0.0, (0, 0.0, 0.0)), (0.08, (0, 0.0, 0.004)), (0.45, (0, -0.48, -0.2)),
                    (0.62, (0, -0.62, -0.3)), (0.82, (0, -0.96, -0.41)), (1.0, (0, -0.96, -0.412))]
            for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
                if t0 <= t <= t1:
                    k = smooth(t0, t1, t)
                    loc = Vector(p0).lerp(Vector(p1), k)
                    break
            tilt = -math.radians(12) * (1 - smooth(0.0, 0.3, t)) + math.radians(10) * smooth(0.3, 0.5, t) * (1 - smooth(0.6, 0.85, t))
            return loc, _q(X, tilt)
        return None
    return fn


def anim_dryline(t):
    """4 s loop. Arkene svajer i vinden med hver sin fase."""
    def fn(bone, t=t):
        if not bone.startswith('sheet_'):
            return None
        i = int(bone.split('_')[1])
        ph = i * 1.7
        w = 2 * math.pi * t
        swing = math.radians(7) * math.sin(w + ph) + math.radians(3) * math.sin(2 * w + ph * 0.6)
        twist = math.radians(4) * math.sin(w * (1 + i % 2) + ph * 1.3)
        return None, _q((1, 0, 0), swing) @ _q((0, 0, 1), twist)
    return fn


def anim_cutter(t):
    """2.5 s cyklus: pressebjælken går ned, armen trækkes ned, kniven skærer, alt går op igen."""
    def fn(bone, t=t):
        down = smooth(0.12, 0.38, t) * (1 - smooth(0.56, 0.8, t))
        if bone == 'clamp':
            c = smooth(0.0, 0.12, t) * (1 - smooth(0.8, 0.95, t))
            return Vector((0, 0, -0.095 * c)), None
        if bone == 'blade':
            return Vector((0, 0, -0.2 * down)), None
        if bone == 'lever':
            return None, _q((1, 0, 0), math.radians(36) * down)
        if bone == 'strip':
            s = smooth(0.4, 0.55, t)
            fall = smooth(0.48, 0.6, t)
            return Vector((0, -0.07 * s, 0)), _q((1, 0, 0), math.radians(-6) * fall)
        return None
    return fn


def anim_counter(t):
    """1 s loop. Fire sedler i træk: vipper ned i maskinen fra tragten og glider ud i lommen foran."""
    def lerpkeys(keys, p):
        for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
            if t0 <= p <= t1:
                k = smooth(t0, t1, p)
                if isinstance(v0, tuple):
                    return Vector(v0).lerp(Vector(v1), k)
                return v0 + (v1 - v0) * k
        return keys[-1][1] if not isinstance(keys[-1][1], tuple) else Vector(keys[-1][1])

    def fn(bone, t=t):
        if bone == 'wheel':
            return None, _q((1, 0, 0), -t * 2 * math.pi * 4)
        if bone.startswith('f'):
            k = int(bone[1:])
            p = (t + (k - 1) / 4) % 1.0
            ang = lerpkeys([(0.0, 62.0), (0.35, -20.0), (0.45, 0.0), (1.0, 0.0)], p)
            loc = lerpkeys([(0.0, (0, 0, 0)), (0.35, (0, 0, 0)), (0.45, (0, -0.13, -0.122)),
                            (0.8, (0, -0.205, -0.122)), (1.0, (0, -0.205, -0.124))], p)
            return loc, _q((1, 0, 0), math.radians(ang))
        return None
    return fn


ANIMS = [
    # clip, model (skelet), frames, fn
    ('press_run',     'm1_cf_press_on',     48, anim_press),
    ('dryline_sway',  'm1_cf_dryline_wet',  96, anim_dryline),
    ('cutter_cut',    'm1_cf_cutter_loaded', 60, anim_cutter),
    ('counter_count', 'm1_cf_counter_run',  24, anim_counter),
]


def build_anims(rigs=None):
    rigs = rigs or {n: bpy.data.objects.get(n) for n, *_ in MODELS}
    old = bpy.data.objects.get(ANIM_DICT)
    if old:
        for ob in list(old.children_recursive) + [old]:
            bpy.data.objects.remove(ob, do_unlink=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    cd, clips, anims = _ycdi.create_clip_dictionary_template(ANIM_DICT)
    out = []
    for clip_name, model, frames, maker in ANIMS:
        arm = rigs[model]
        act = bake(arm, clip_name, frames, lambda b, t, maker=maker: maker(t)(b))
        a = _ycdi.create_anim_obj(SollumType.ANIMATION)
        a.name = clip_name + '_anim'
        a.parent = anims
        ap = a.animation_properties
        ap.hash = clip_name + '_anim'
        ap.target_id_type = 'ARMATURE'
        ap.target_id = arm.data
        ap.action = act
        c = _ycdi.create_anim_obj(SollumType.CLIP)
        c.name = clip_name
        c.parent = clips
        cp = c.clip_properties
        cp.hash = clip_name
        cp.name = clip_name
        cp.duration = frames / FPS
        ca = cp.animations.add()
        ca.animation = a
        ca.start_frame = 0
        ca.end_frame = frames
        out.append(clip_name)
    return cd, out


def preview(clip_name, frame):
    """Sæt en model i pose til preview-render."""
    for cn, model, frames, maker in ANIMS:
        if cn == clip_name:
            arm = bpy.data.objects[model]
            fn = maker(frame / frames)
            for pb in arm.pose.bones:
                res = fn(pb.name)
                if res:
                    if res[0] is not None:
                        pb.location = res[0]
                    if res[1] is not None:
                        pb.rotation_quaternion = res[1]
            return arm


def reset_poses():
    for ob in bpy.data.objects:
        if ob.type == 'ARMATURE':
            for pb in ob.pose.bones:
                pb.location = (0, 0, 0)
                pb.rotation_quaternion = (1, 0, 0, 0)


PREVIEW_LAYOUT = {
    'm1_cf_press_off': (-3.0, 2.0), 'm1_cf_press_on': (-1.7, 2.0), 'm1_cf_press_done': (-0.4, 2.0),
    'm1_cf_dryline_empty': (-2.6, 4.0), 'm1_cf_dryline_wet': (-0.6, 4.0), 'm1_cf_dryline_dry': (1.4, 4.0),
    'm1_cf_cutter_empty': (1.0, 2.0), 'm1_cf_cutter_loaded': (2.0, 2.0), 'm1_cf_cutter_done': (3.0, 2.0),
    'm1_cf_table': (3.4, 4.0), 'm1_cf_counter': (3.15, 4.0), 'm1_cf_counter_run': (3.55, 4.0),
}


def layout_preview(origin=False):
    for n, (x, y) in PREVIEW_LAYOUT.items():
        ob = bpy.data.objects.get(n)
        if ob:
            z = 0.9 if n.startswith('m1_cf_counter') and not origin else 0.0
            ob.location = (0, 0, 0) if origin else (x, y, z)


# ================================================================ EKSPORT
def _model_objs(drawable):
    return [c for c in drawable.children_recursive if c.type == 'MESH' and c.sollum_type == SollumType.DRAWABLE_MODEL]


def add_lods():
    """Forenklet medium-LOD (decimate) for hver model + LOD-afstande på drawables."""
    LOD = import_module(SZ + '.sollumz_properties').LODLevel
    stats = {}
    for name, *_ in MODELS:
        d = bpy.data.objects[name]
        small = name.startswith('m1_cf_counter')
        d.drawable_properties.lod_dist_high = min(LOD_HIGH, LOD_SMALL * 0.4) if small else LOD_HIGH
        d.drawable_properties.lod_dist_med = LOD_SMALL if small else LOD_MED
        d.drawable_properties.lod_dist_low = 9998
        d.drawable_properties.lod_dist_vlow = 9998
        hi_tris = lo_tris = 0
        for ob in _model_objs(d):
            hi = ob.sz_lods.get_lod(LOD.HIGH).mesh or ob.data
            tris = sum(len(p.vertices) - 2 for p in hi.polygons)
            hi_tris += tris
            old = ob.sz_lods.get_lod(LOD.MEDIUM).mesh
            if old and old != hi and old.users <= 1:
                bpy.data.meshes.remove(old)
            if tris < 150:
                med = hi
            else:
                tmp = bpy.data.objects.new('_lodtmp', hi)
                bpy.context.scene.collection.objects.link(tmp)
                mod = tmp.modifiers.new('dec', 'DECIMATE')
                mod.ratio = 0.25 if tris > 2000 else 0.4
                mod.use_collapse_triangulate = True
                bpy.context.view_layer.update()
                med = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
                med.name = hi.name + '.med'
                bpy.data.objects.remove(tmp, do_unlink=True)
            ob.sz_lods.get_lod(LOD.MEDIUM).mesh = med
            lo_tris += sum(len(p.vertices) - 2 for p in med.polygons)
        stats[name] = (hi_tris, lo_tris)
    return stats


def unembed_textures():
    """Slå embedded teksturer fra og returnér {teksturnavn: dds-sti} til den fælles ytd."""
    used = {}
    for name, *_ in MODELS:
        for ob in _model_objs(bpy.data.objects[name]):
            for m in ob.data.materials:
                if not m or not m.node_tree:
                    continue
                for node in m.node_tree.nodes:
                    if isinstance(node, bpy.types.ShaderNodeTexImage) and node.image:
                        node.texture_properties.embedded = False
                        tname = node.sollumz_texture_name or os.path.splitext(node.image.name)[0]
                        used[tname] = os.path.basename(bpy.path.abspath(node.image.filepath))
    return used


def export_all(stream_dir, ycd_xml_dir):
    import json
    layout_preview(origin=True)
    reset_poses()
    names = [n for n, *_ in MODELS]
    lods = add_lods()
    used = unembed_textures()
    with open(os.path.join(ycd_xml_dir, TXD + '.json'), 'w', encoding='utf-8') as f:
        json.dump(used, f, indent=1)
    bpy.ops.object.select_all(action='DESELECT')
    for n in names:
        bpy.data.objects[n].select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects[names[0]]
    prefs = bpy.context.preferences.addons[SZ].preferences
    es = prefs.export_settings
    old_lts = es.limit_to_selected
    bpy.ops.sollumz.export_assets(directory=stream_dir, direct_export=True, use_custom_settings=True,
                                  target_formats={'NATIVE'}, target_versions={'GEN8'}, limit_to_selected=True)
    es.limit_to_selected = old_lts

    # ycd (XML - konverteres til binær med CodeWalker.Core bagefter, ligesom ytd'en)
    exp = import_module(SZ + '.ycd.ycdexport')
    exp.export_ycd(bpy.data.objects[ANIM_DICT], os.path.join(ycd_xml_dir, ANIM_DICT + '.ycd.xml'))

    # ytyp
    sc = bpy.context.scene
    while len(sc.ytyps):
        sc.ytyps.remove(0)
    bpy.ops.sollumz.createytyp()
    yt = sc.ytyps[0]
    yt.name = 'mach1ne_counterfeit'
    bpy.ops.object.select_all(action='DESELECT')
    for n in names:
        bpy.data.objects[n].select_set(True)
    bpy.ops.sollumz.createarchetypefromselected()
    animated = {n for n, _, _, a in MODELS if a}
    for arch in yt.archetypes:
        arch.lod_dist = LOD_SMALL if arch.name.startswith('m1_cf_counter') else LOD_MED
        arch.texture_dictionary = TXD
        if arch.name in animated:
            arch.clip_dictionary = ANIM_DICT
            arch.flags.flag10 = True        # Has Anim (YCD)
    bpy.ops.sollumz.export_ytyp_io(directory=stream_dir)
    xml = os.path.join(stream_dir, 'mach1ne_counterfeit.ytyp.xml')
    if os.path.exists(xml):
        os.replace(xml, os.path.join(ycd_xml_dir, 'mach1ne_counterfeit.ytyp.xml'))
    layout_preview()
    return {'archetypes': [a.name for a in yt.archetypes], 'lods': lods, 'textures': len(used)}
