# Ikoner til ox_inventory (256 px, gennemsigtig baggrund). Køres efter cfbuild.py (deler dens globals):
#   exec(open('cfbuild.py').read()); exec(open('icons.py').read()); render_icons(<ox_inventory/web/images>)

def _icon_coll():
    coll = bpy.data.collections.get('cf_icons') or bpy.data.collections.new('cf_icons')
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    return coll


def icon_paper(name, coll):
    m = MB()
    ream(m, (0, 0, 0), 0.21, 0.297, 0.05, 'm1f_paper')
    m.box((0, 0, 0.025), (0.214, 0.08, 0.052), 'm1f_band', bevel=0.001)
    return m.finish(name, coll)


def icon_ink(name, coll):
    m = MB()
    cyl_z(m, (0, 0, 0), 0.06, 0.1, 'm1f_steel', 32)
    m.revolve((0, 0, 0.1), [(0.0, 0.006), (0.058, 0.006), (0.061, 0.0), (0.061, -0.0)], 32, 'm1f_steel', planar=True)
    m.revolve((0, 0, 0), [(0.0605, 0.018), (0.0605, 0.082)], 32, 'm1f_inkroll', urep=1.0)
    transformed(m, lambda: m.revolve((0, 0, 0), [(0.0606, 0.04), (0.0606, 0.06)], 32, 'm1f_plate', urep=2.0),
                Matrix.Identity(4))
    return m.finish(name, coll)


def icon_sheet(name, coll, wet):
    m = MB()
    bend = (lambda u, v: 0.012 * math.sin(u * math.pi) + 0.02 * v * v) if wet else (lambda u, v: 0.0)
    if wet:
        sheet_grid(m, (0, 0, 0.0), SHEET_W, SHEET_H, 'm1f_sheet_wet', 6, 6, bend=bend)
    else:
        for i in range(4):
            transformed(m, lambda i=i: sheet_grid(m, (0, 0, i * 0.002), SHEET_W, SHEET_H, 'm1f_sheet', 1, 1),
                        Matrix.Rotation(math.radians((i - 1.5) * 4), 4, 'Z'))
    return m.finish(name, coll)


def icon_bills(name, coll):
    m = MB()
    for i in range(6):
        a = math.radians(-35 + i * 13)
        transformed(m, lambda i=i: sheet_grid(m, (0, BILL_H * 0.5, i * 0.0015), BILL_W, BILL_H, 'm1f_bill', 1, 1),
                    Matrix.Rotation(a, 4, 'Z') @ Matrix.Translation(Vector((0, -0.02, 0))))
    return m.finish(name, coll)


def icon_band(name, coll):
    m = MB()
    for k in range(4):
        transformed(m, lambda k=k: sheet_grid(m, (0, 0, k * 0.0012), 0.2, 0.05, 'm1f_band', 4, 1,
                                              bend=lambda u, v: 0.006 * math.sin(u * math.pi)),
                    Matrix.Rotation(math.radians(-18 + k * 12), 4, 'Z') @ Matrix.Translation(Vector((0, k * 0.012, 0))))
    return m.finish(name, coll)


def icon_bundle(name, coll):
    m = MB()
    for i in range(2):
        transformed(m, lambda: (ream(m, (0, 0, 0), BILL_W, BILL_H, 0.025, 'm1f_bill'),
                                m.box((0, 0, 0.0127), (0.035, BILL_H + 0.002, 0.0265), 'm1f_band', bevel=0.0005, scale=8)),
                    Matrix.Translation(Vector((0.02 * i, 0.012 * i, 0.0255 * i))) @ Matrix.Rotation(math.radians(8 * i), 4, 'Z'))
    return m.finish(name, coll)


def icon_scanner(name, coll):
    m = MB()
    m.box((0, 0, 0.012), (0.16, 0.12, 0.024), 'm1f_plastic', bevel=0.006)
    m.box((0, 0.05, 0.06), (0.16, 0.025, 0.08), 'm1f_plastic', bevel=0.006)
    m.box((0, 0.0, 0.1), (0.16, 0.12, 0.018), 'm1f_plastic_lt', bevel=0.006)
    sheet_grid(m, (0, 0.0, 0.0905), 0.12, 0.012, 'm1f_lcd', 1, 1, double=False)
    sheet_grid(m, (0, -0.015, 0.0245), BILL_W * 0.9, BILL_H * 0.9, 'm1f_bill', 1, 1, double=False)
    transformed(m, lambda: sheet_grid(m, (0, 0, 0), 0.06, 0.025, 'm1f_lcd', 1, 1, double=False),
                Matrix.Translation(Vector((0, -0.0605, 0.1))) @ rot_x(math.radians(90)).to_4x4())
    return m.finish(name, coll)


ICONS = [
    # (item, objekt der renderes, builder - None = brug den eksporterede model)
    ('cf_paper',     'icon_cf_paper',     icon_paper),
    ('cf_ink',       'icon_cf_ink',       icon_ink),
    ('cf_sheet_wet', 'icon_cf_sheet_wet', lambda n, c: icon_sheet(n, c, True)),
    ('cf_sheet',     'icon_cf_sheet',     lambda n, c: icon_sheet(n, c, False)),
    ('cf_bills',     'icon_cf_bills',     icon_bills),
    ('cf_band',      'icon_cf_band',      icon_band),
    ('cf_bundle',    'icon_cf_bundle',    icon_bundle),
    ('cf_scanner',   'icon_cf_scanner',   icon_scanner),
    ('cf_press',     'm1_cf_press_off',   None),
    ('cf_dryline',   'm1_cf_dryline_wet', None),
    ('cf_cutter',    'm1_cf_cutter_empty', None),
    ('cf_counter',   'm1_cf_counter',     None),
    ('cf_table',     'm1_cf_table',       None),
]


def _meshes_of(ob):
    if ob.type == 'MESH':
        return [ob]
    return [c for c in ob.children_recursive if c.type == 'MESH' and not c.name.endswith('.box')
            and c.sollum_type != 'sollumz_bound_composite']


def render_icons(outdir, only=None, size=256):
    coll = _icon_coll()
    sc = bpy.context.scene
    reset_poses()
    targets = []
    for item, obname, fn in ICONS:
        if only and item not in only:
            continue
        ob = bpy.data.objects.get(obname)
        if fn and ob:
            bpy.data.objects.remove(ob, do_unlink=True)
            ob = None
        if not ob:
            ob = fn(obname, coll)
            ob.location = (20, 20, 0)
        targets.append((item, ob))

    cam_data = bpy.data.cameras.get('icon_cam') or bpy.data.cameras.new('icon_cam')
    cam = bpy.data.objects.get('icon_cam') or bpy.data.objects.new('icon_cam', cam_data)
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam_data.type = 'ORTHO'
    old = (sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.render.film_transparent, sc.render.filepath)
    sc.camera = cam
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.film_transparent = True
    view = Vector((-0.75, -1.0, 0.8)).normalized()

    hidden = {}
    for o in bpy.data.objects:
        if o.type == 'MESH':
            hidden[o.name] = o.hide_render
    done = []
    try:
        for item, ob in targets:
            meshes = _meshes_of(ob)
            keep = {m.name for m in meshes}
            for o in bpy.data.objects:
                if o.type == 'MESH':
                    o.hide_render = o.name not in keep
            bpy.context.view_layer.update()
            pts = [m.matrix_world @ Vector(c) for m in meshes for c in m.bound_box]
            lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            center = (lo + hi) / 2
            cam.location = center + view * 10
            cam.rotation_euler = (-view).to_track_quat('-Z', 'Y').to_euler()
            R = cam.rotation_euler.to_matrix()
            right, up = R @ Vector((1, 0, 0)), R @ Vector((0, 1, 0))
            ext = max(max(abs((p - center).dot(right)) for p in pts), max(abs((p - center).dot(up)) for p in pts))
            cam_data.ortho_scale = ext * 2 * 1.1
            cam_data.clip_end = 30
            sc.render.filepath = os.path.join(outdir, f'm1f_{item}.png')
            bpy.ops.render.render(write_still=True)
            done.append(item)
    finally:
        for n, h in hidden.items():
            o = bpy.data.objects.get(n)
            if o:
                o.hide_render = h
        sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.render.film_transparent, sc.render.filepath = old
    return done
