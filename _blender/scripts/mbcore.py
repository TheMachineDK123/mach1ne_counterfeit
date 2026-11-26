# Fælles mesh-builder (kopieret fra mach1ne_cocaine/cocabuild.py). Forventer TEX, MATS, ICON_MATS, sh, NS.
def get_icon_mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    d = ICON_MATS[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = d.get('rough', 0.5)
    if 'image' in d:
        tex = nt.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(os.path.join(TEX, d['image']), check_existing=True)
        nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    else:
        bsdf.inputs['Base Color'].default_value = d['color']
    if 'alpha' in d:
        bsdf.inputs['Alpha'].default_value = d['alpha']
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            m.blend_method = 'BLEND'
    return m


def _set(node, value):
    if node is None:
        return
    try:
        node.set_float(value)
    except Exception:
        pass


def get_mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    d = MATS[name]
    m = sh.create_shader(d['shader'])
    m.name = name
    nt = m.node_tree.nodes
    for sampler, suffix in (('DiffuseSampler', '_d'), ('BumpSampler', '_n'), ('SpecSampler', '_s')):
        node = nt.get(sampler)
        path = os.path.join(TEX, name + suffix + '.dds')
        if node and os.path.exists(path):
            img = bpy.data.images.load(path, check_existing=True)
            if suffix != '_d':
                img.colorspace_settings.name = 'Non-Color'
            node.image = img
            node.texture_properties.embedded = globals().get('EMBED_TEXTURES', True)
    _set(nt.get('specularIntensityMult'), d.get('spec', 0.5))
    _set(nt.get('specularFalloffMult'), d.get('falloff', 30))
    _set(nt.get('bumpiness'), d.get('bump', 1.0))
    _set(nt.get('emissiveMultiplier'), d.get('emissive', 1.0))
    return m


# ---------------------------------------------------------------- mesh builder
class MB:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap 0')
        self.mats = []

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def face(self, verts, mat, uvs, smooth=True):
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.material_index = self.mi(mat)
        f.smooth = smooth
        for l, t in zip(f.loops, uvs):
            l[self.uv].uv = t
        return f

    # -- afrundet kasse. u følger kassens længste akse (træets årer)
    def box(self, c, size, mat, rot=None, bevel=0.004, scale=1.0, uvoff=(0.0, 0.0)):
        sx, sy, sz = size
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0, matrix=Matrix.Diagonal((sx, sy, sz, 1)))
        b = min(bevel, min(size) * 0.3)
        if b > 0:
            bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=b, segments=1, affect='EDGES', profile=0.5)
        tmp.normal_update()
        long_ax = max(range(3), key=lambda i: size[i])
        R = rot if rot is not None else Matrix.Identity(3)
        c = Vector(c)
        vmap = {v: self.bm.verts.new(c + R @ v.co) for v in tmp.verts}
        for f in tmp.faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            others = [i for i in range(3) if i != ax]
            if long_ax in others:
                ua, va = long_ax, [i for i in others if i != long_ax][0]
            else:
                ua, va = others
            flip = -1.0 if (ax == 1 and n.y > 0) or (ax == 0 and n.x < 0) else 1.0
            uvs = [(flip * l.vert.co[ua] * scale + uvoff[0], l.vert.co[va] * scale + uvoff[1]) for l in f.loops]
            self.face([vmap[v] for v in f.verts], mat, uvs, smooth=False)
        tmp.free()

    # -- drejet profil [(r, z), ...] om Z gennem c. r = 0 i enderne giver lukket flade.
    def revolve(self, c, profile, segs, mat, urep=1.0, vmode='len', vscale=2.0, planar=False, smooth=True):
        c = Vector(c)
        R = max(r for r, _ in profile) or 1.0
        cum = [0.0]
        for i in range(1, len(profile)):
            (r0, z0), (r1, z1) = profile[i - 1], profile[i]
            cum.append(cum[-1] + math.hypot(r1 - r0, z1 - z0))
        rings = []
        for r, z in profile:
            if r < 1e-6:
                rings.append([self.bm.verts.new(c + Vector((0, 0, z)))])
            else:
                rings.append([self.bm.verts.new(c + Vector((math.cos(a) * r, math.sin(a) * r, z)))
                              for a in [i / segs * 2 * math.pi for i in range(segs)]])
        faces = []

        def tuv(k, i):
            r, z = profile[k]
            if planar:
                a = i / segs * 2 * math.pi
                return (0.5 + math.cos(a) * r / (2 * R), 0.5 + math.sin(a) * r / (2 * R))
            v = cum[k] / cum[-1] if vmode == 'norm' else cum[k] * vscale
            return (i / segs * urep, v)

        for k in range(len(rings) - 1):
            A, B = rings[k], rings[k + 1]
            for i in range(segs):
                j = i + 1
                if len(A) == 1:
                    f = self.face([A[0], B[j % segs], B[i]], mat, [tuv(k, i + 0.5), tuv(k + 1, j), tuv(k + 1, i)], smooth)
                elif len(B) == 1:
                    f = self.face([A[i], A[j % segs], B[0]], mat, [tuv(k, i), tuv(k, j), tuv(k + 1, i + 0.5)], smooth)
                else:
                    f = self.face([A[i], A[j % segs], B[j % segs], B[i]], mat,
                                  [tuv(k, i), tuv(k, j), tuv(k + 1, j), tuv(k + 1, i)], smooth)
                if f:
                    faces.append(f)
        return faces

    # -- rør langs en kurve
    def tube(self, pts, radii, segs, mat, cap0=False, cap1=True, vscale=4.0, urep=1.0):
        pts = [Vector(p) for p in pts]
        if not isinstance(radii, (list, tuple)):
            radii = [radii] * len(pts)
        tang = []
        for i in range(len(pts)):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            tang.append((b - a).normalized())
        ref = Vector((1, 0, 0)) if abs(tang[0].dot(Vector((1, 0, 0)))) < 0.9 else Vector((0, 1, 0))
        nrm = tang[0].cross(ref).normalized()
        rings, length = [], [0.0]
        for i, p in enumerate(pts):
            if i:
                length.append(length[-1] + (p - pts[i - 1]).length)
                nrm = (nrm - tang[i] * nrm.dot(tang[i])).normalized()
            bi = tang[i].cross(nrm)
            rings.append([self.bm.verts.new(p + (nrm * math.cos(a) + bi * math.sin(a)) * radii[i])
                          for a in [k / segs * 2 * math.pi for k in range(segs)]])
        for i in range(len(rings) - 1):
            for k in range(segs):
                j = k + 1
                self.face([rings[i][k], rings[i][j % segs], rings[i + 1][j % segs], rings[i + 1][k]], mat,
                          [(k / segs * urep, length[i] * vscale), (j / segs * urep, length[i] * vscale),
                           (j / segs * urep, length[i + 1] * vscale), (k / segs * urep, length[i + 1] * vscale)])
        if cap1:
            self.face(list(rings[-1]), mat, [(0.5 + 0.5 * math.cos(k / segs * 6.28), 0.5 + 0.5 * math.sin(k / segs * 6.28)) for k in range(segs)])
        if cap0:
            self.face(list(reversed(rings[0])), mat, [(0.5, 0.5)] * segs)

    # -- skive med planar UV og valgfri højde-funktion
    def disc(self, c, r, segs, rings, mat, hfn=None, uvscale=1.0):
        c = Vector(c)
        hfn = hfn or (lambda x, y: 0.0)
        center = self.bm.verts.new(c + Vector((0, 0, hfn(0, 0))))
        grid = []
        for k in range(1, rings + 1):
            rr = r * k / rings
            row = []
            for i in range(segs):
                a = i / segs * 2 * math.pi
                x, y = math.cos(a) * rr, math.sin(a) * rr
                row.append(self.bm.verts.new(c + Vector((x, y, hfn(x, y)))))
            grid.append(row)
        uv = lambda v: (0.5 + (v.co.x - c.x) / (2 * r) * uvscale, 0.5 + (v.co.y - c.y) / (2 * r) * uvscale)
        for i in range(segs):
            j = (i + 1) % segs
            vs = [center, grid[0][i], grid[0][j]]
            self.face(vs, mat, [uv(v) for v in vs])
        for k in range(rings - 1):
            for i in range(segs):
                j = (i + 1) % segs
                vs = [grid[k][i], grid[k + 1][i], grid[k + 1][j], grid[k][j]]
                self.face(vs, mat, [uv(v) for v in vs])

    def blob(self, c, radii, mat, subdiv=1, rnd=None, jitter=0.0):
        before = set(self.bm.faces)
        M = Matrix.Translation(Vector(c)) @ Matrix.Diagonal((*radii, 1))
        bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=1.0, matrix=M)
        new = set(self.bm.faces) - before
        if rnd and jitter:
            for v in {v for f in new for v in f.verts}:
                v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * jitter
        for f in new:
            f.material_index = self.mi(mat)
            f.smooth = True
            for l in f.loops:
                d = (l.vert.co - Vector(c)).normalized()
                l[self.uv].uv = (0.5 + math.atan2(d.y, d.x) / 6.283, 0.5 + d.z * 0.5)

    # -- blad med midterribbe-fold og atlas-celle (0-3)
    def leaf(self, base, ldir, n, L, W, mat, cell=0, droop=0.15, fold=0.25, steps=4, curl=0.0):
        base, ldir, n = Vector(base), Vector(ldir).normalized(), Vector(n).normalized()
        side = ldir.cross(n).normalized()
        cu, cv = (cell % 2) * 0.5, (cell // 2) * 0.5
        rows = []
        for s in range(steps + 1):
            t = s / steps
            w = W * (math.sin(math.pi * min(max(t, 0.02), 0.985)) ** 0.75) * 0.5
            mid = base + ldir * L * t - n * droop * L * t * t
            edge = -n * (fold * w + curl * w * t)
            row = []
            for k, sgn in enumerate((-1, 0, 1)):
                p = mid + side * w * sgn + (edge if sgn else Vector())
                row.append((p, (cu + 0.02 + t * 0.46, cv + 0.25 + sgn * (w / W) * 0.48)))
            rows.append(row)
        for back in (False, True):
            off = -n * 0.0012 if back else Vector()
            vs = [[self.bm.verts.new(p + off) for p, _ in r] for r in rows]
            for s in range(steps):
                for k in range(2):
                    quad = [vs[s][k], vs[s][k + 1], vs[s + 1][k + 1], vs[s + 1][k]]
                    uvs = [rows[s][k][1], rows[s][k + 1][1], rows[s + 1][k + 1][1], rows[s + 1][k][1]]
                    if back:
                        quad.reverse(); uvs.reverse()
                    self.face(quad, mat, uvs)

    def finish(self, name, coll):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=0.00002)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(get_icon_mat(m) if m.startswith('icon_') else get_mat(m))
        ca = me.color_attributes.new('Color 1', 'BYTE_COLOR', 'CORNER')
        for d in ca.data:
            d.color = (1, 1, 1, 1)
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        return ob


def rot_y(a):
    return Matrix.Rotation(a, 3, 'Y')


def rot_x(a):
    return Matrix.Rotation(a, 3, 'X')


def rot_z(a):
    return Matrix.Rotation(a, 3, 'Z')


