# Ped-animationer der passer til maskinernes prop-animationer (freemode-skelet, Blender 5 + Sollumz).
# Køres efter cfbuild.py (deler globals):
#   exec(open('cfbuild.py').read()); exec(open('pedanim.py').read())
#   build_ped_anims(); export_ped_ycd(<_blender/ycd>)
#
# Metode: peden stilles foran maskinen. Pr. frame regnes maskindelens position ud fra de samme funktioner som
# prop-animationen (fx håndtagets bane), og en analytisk 2-knogle-IK lægger hænderne dér. Ben-IK holder fødderne
# plantet, når kroppen bøjer sig. Resultatet bages til keyframes på freemode-skelettet.
import bpy, math
from mathutils import Vector, Matrix, Quaternion

PED = 'mp_m_freemode_01'
PED_DICT = 'm1_cf_ped'
HIP = 1.0            # ped-entityens origo ligger ca. 1 m over gulvet
TABLE_H = 0.9        # sedeltælleren står på et arbejdsbord (m1_cf_table)

SIDES = ('L', 'R')
FINGERS = [('0', 0.45), ('1', 1.0), ('2', 1.0), ('3', 1.0), ('4', 1.0)]   # finger, curl-vægt (tommel mindre)
KEY_BONES = (['SKEL_ROOT', 'SKEL_Pelvis', 'SKEL_Spine_Root', 'SKEL_Spine0', 'SKEL_Spine1', 'SKEL_Spine2', 'SKEL_Spine3',
              'SKEL_Neck_1', 'SKEL_Head']
             + [f'SKEL_{s}_{b}' for s in SIDES for b in ('Clavicle', 'UpperArm', 'Forearm', 'Hand', 'Thigh', 'Calf', 'Foot', 'Toe0')]
             + [f'SKEL_{s}_Finger{f}{j}' for s in SIDES for f, _ in FINGERS for j in range(3)])


def lerpk(keys, t):
    """keys = [(t, værdi)] med blød overgang. Værdi kan være float eller tuple/Vector."""
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            k = smooth(t0, t1, t)
            if isinstance(v0, (tuple, list, Vector)):
                return Vector(v0).lerp(Vector(v1), k)
            return v0 + (v1 - v0) * k
    v = keys[-1][1]
    return Vector(v) if isinstance(v, (tuple, list, Vector)) else v


# ---------------------------------------------------------------- pose-hjælpere (armature-rum)
class Poser:
    def __init__(self, arm):
        self.arm = arm
        self.pb = arm.pose.bones
        self.inv = arm.matrix_world.inverted()
        self.reset()
        # håndens akser i knoglens lokalrum (fra hvilestilling): fingerretning og håndfladens normal
        self.hand_axes = {}
        for s in SIDES:
            h = self.pb[f'SKEL_{s}_Hand']
            M = h.matrix.to_3x3()
            f = (self.pb[f'SKEL_{s}_Finger20'].head - h.head).normalized()
            body = Vector((-1.0 if s == 'R' else 1.0, 0, 0)) * (1 if self._right_x() else -1)
            pn = (body - f * body.dot(f)).normalized()         # i A-pose vender håndfladen ind mod kroppen
            self.hand_axes[s] = (M.inverted() @ f, M.inverted() @ pn)
        self.rest_feet = {s: (self.pb[f'SKEL_{s}_Foot'].head.copy(), self.pb[f'SKEL_{s}_Foot'].matrix.copy()) for s in SIDES}
        self.len = {}
        for s in SIDES:
            for a, b, c in (('UpperArm', 'Forearm', 'Hand'), ('Thigh', 'Calf', 'Foot')):
                S, E, W = (self.pb[f'SKEL_{s}_{x}'].head for x in (a, b, c))
                self.len[(s, a)] = ((E - S).length, (W - E).length)

    def _right_x(self):
        return self.pb['SKEL_R_UpperArm'].head.x > 0

    def upd(self):
        bpy.context.view_layer.update()

    def reset(self):
        for p in self.pb:
            p.rotation_mode = 'QUATERNION'
            p.location = (0, 0, 0)
            p.rotation_quaternion = (1, 0, 0, 0)
            p.scale = (1, 1, 1)
        self.pb['SKEL_ROOT'].rotation_quaternion = (0, 0, 0, 1)     # 180° om Z: peden vender +Y (som i vanilla-clips)
        self.upd()

    def local(self, world_pt):
        return self.inv @ Vector(world_pt)

    def rotate(self, name, R, about=None):
        p = self.pb[name]
        M = p.matrix.copy()
        c = M.translation if about is None else about
        R4 = R.to_4x4() if len(R) == 3 else R
        p.matrix = Matrix.Translation(c) @ R4 @ Matrix.Translation(-c) @ M
        self.upd()

    def move_root(self, delta):
        p = self.pb['SKEL_ROOT']
        p.matrix = Matrix.Translation(Vector(delta)) @ p.matrix
        self.upd()

    def aim(self, name, cur_dir, want_dir, about):
        q = cur_dir.normalized().rotation_difference(want_dir.normalized())
        self.rotate(name, q.to_matrix(), about)

    def two_bone(self, s, a, b, c, target, pole):
        """Analytisk 2-knogle-IK: S (a) -> E (b) -> W (c) så W rammer target, albue/knæ mod pole."""
        A, B, C = (f'SKEL_{s}_{x}' for x in (a, b, c))
        L1, L2 = self.len[(s, a)]
        S = self.pb[A].head.copy()
        T = Vector(target)
        d = T - S
        dist = max(min(d.length, (L1 + L2) * 0.999), abs(L1 - L2) * 1.001)
        dn = d.normalized()
        x = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
        h = math.sqrt(max(L1 * L1 - x * x, 0.0))
        pv = Vector(pole) - S
        pv = (pv - dn * pv.dot(dn)).normalized()
        E_new = S + dn * x + pv * h
        self.aim(A, self.pb[B].head - S, E_new - S, S)
        E = self.pb[B].head.copy()
        self.aim(B, self.pb[C].head - E, S + dn * dist - E, E)

    def orient_hand(self, s, fdir, palm):
        h = self.pb[f'SKEL_{s}_Hand']
        fl, pl = self.hand_axes[s]
        M = h.matrix.to_3x3()
        f_cur, p_cur = (M @ fl).normalized(), (M @ pl).normalized()
        fdir = Vector(fdir).normalized()
        palm = Vector(palm)
        palm = (palm - fdir * palm.dot(fdir)).normalized()
        Bc = Matrix((f_cur, p_cur, f_cur.cross(p_cur))).transposed()
        Bt = Matrix((fdir, palm, fdir.cross(palm))).transposed()
        self.rotate(f'SKEL_{s}_Hand', Bt @ Bc.inverted())

    def curl(self, s, amount, spread=0.0):
        h = self.pb[f'SKEL_{s}_Hand']
        fl, pl = self.hand_axes[s]
        M = h.matrix.to_3x3()
        f, pn = (M @ fl).normalized(), (M @ pl).normalized()
        axis = f.cross(pn).normalized()
        for fi, w in FINGERS:
            for j in range(3):
                ang = amount * w * (0.55 if j == 0 else 0.75)
                if fi == '0':
                    ang *= 0.7
                self.rotate(f'SKEL_{s}_Finger{fi}{j}', Matrix.Rotation(ang, 3, axis))

    def plant_feet(self):
        for s in SIDES:
            pos, mat = self.rest_feet[s]
            knee_pole = self.pb[f'SKEL_{s}_Calf'].head + Vector((0, 0.6, 0))
            self.two_bone(s, 'Thigh', 'Calf', 'Foot', pos, knee_pole)
            f = self.pb[f'SKEL_{s}_Foot']
            m = mat.copy()
            m.translation = f.head
            f.matrix = m
            self.upd()

    def spine(self, lean=0.0, yaw=0.0, side=0.0):
        """lean > 0 = fremover (rad, fordelt på rygsøjlen), yaw = drej, side = sidebøjning."""
        for n, w in (('SKEL_Spine0', 0.15), ('SKEL_Spine1', 0.3), ('SKEL_Spine2', 0.3), ('SKEL_Spine3', 0.25)):
            R = (Matrix.Rotation(yaw * w, 3, 'Z') @ Matrix.Rotation(-lean * w, 3, 'X') @ Matrix.Rotation(side * w, 3, 'Y'))
            self.rotate(n, R)

    def shrug(self, s, up):
        self.rotate(f'SKEL_{s}_Clavicle', Matrix.Rotation((up if s == 'L' else -up), 3, 'Y'))

    def look(self, target):
        for n, w in (('SKEL_Neck_1', 0.45), ('SKEL_Head', 1.0)):
            hd = self.pb['SKEL_Head']
            fwd = (hd.matrix.to_3x3() @ self._head_fwd).normalized()
            want = (Vector(target) - hd.head).normalized()
            q = fwd.rotation_difference(want)
            ax, ang = q.to_axis_angle()
            self.rotate(n, Matrix.Rotation(ang * w * (0.5 if n == 'SKEL_Neck_1' else 0.6), 3, ax))

    def key(self, frame):
        for n in KEY_BONES:
            p = self.pb.get(n)
            if not p:
                continue
            p.keyframe_insert('rotation_quaternion', frame=frame)
            if n == 'SKEL_ROOT':
                p.keyframe_insert('location', frame=frame)


def _init_head_fwd(P):
    hd = P.pb['SKEL_Head']
    P._head_fwd = hd.matrix.to_3x3().inverted() @ Vector((0, 1, 0))


# ---------------------------------------------------------------- scener
def machine_world(name):
    return bpy.data.objects[name].matrix_world


def place_ped(arm, machine, offset, yaw_deg, base_z=0.0):
    bpy.context.view_layer.update()
    M = machine_world(machine)
    p = M @ Vector((offset[0], offset[1], 0.0))
    arm.location = (p.x, p.y, M.translation.z + base_z + HIP)
    arm.rotation_mode = 'XYZ'
    arm.rotation_euler = (0, 0, M.to_euler().z + math.radians(yaw_deg))
    bpy.context.view_layer.update()


def mw(machine, local, base_z=0.0):
    """Maskine-lokalt punkt -> verden (base_z = hvor maskinen står over gulvet)."""
    return machine_world(machine) @ Vector((local[0], local[1], local[2]))


def mdir(machine, v):
    return (machine_world(machine).to_3x3() @ Vector(v)).normalized()


# --- skæremaskine: to hænder på håndtaget, træk ned i takt med kniven (2.5 s, samme som cutter_cut)
CUT = dict(machine='m1_cf_cutter_loaded', offset=(0.19, -0.8), yaw=0, frames=60)


def pose_cut(P, t):
    m = CUT['machine']
    down = smooth(0.12, 0.38, t) * (1 - smooth(0.56, 0.8, t))
    ang = math.radians(36) * down
    piv = Vector((0.4, -0.02, 1.2))
    Rl = Matrix.Rotation(ang, 3, 'X')
    P.move_root(P.inv.to_3x3() @ Vector((0, 0.03 * down, -0.09 * down)))
    P.spine(lean=math.radians(6) + math.radians(20) * down, yaw=0.0)
    P.plant_feet()
    for s, x in (('R', 0.28), ('L', 0.1)):
        g = piv + Rl @ (Vector((x, -0.48, 1.32)) - piv)
        fdir = Rl @ Vector((0, 0.55, -0.85))            # fingrene griber ned og frem over stangen
        palm = Rl @ Vector((0, 0.3, -1.0))
        wrist = g - fdir.normalized() * 0.075 + Rl @ Vector((0, -0.01, 0.03))
        P.shrug(s, math.radians(4) * (1 - down))
        elbow = P.local(mw(m, (x + (0.35 if s == 'R' else -0.35), -0.9, 1.0)))
        P.two_bone(s, 'UpperArm', 'Forearm', 'Hand', P.local(mw(m, wrist)), elbow)
        P.orient_hand(s, P.inv.to_3x3() @ mdir(m, fdir), P.inv.to_3x3() @ mdir(m, palm))
        P.curl(s, 1.25)
    P.look(P.local(mw(m, (0.0, -0.1, 0.9))))


# --- sedeltæller (står på bord): venstre hånd holder bunken i tragten, højre retter op i lommen (2 s = 2 tælle-loops)
COUNT = dict(machine='m1_cf_counter_run', offset=(0.0, -0.55), yaw=0, frames=48, base=TABLE_H)


def pose_count(P, t):
    m = COUNT['machine']
    P.spine(lean=math.radians(14), yaw=math.radians(-3))
    P.plant_feet()
    tap = 0.004 * math.sin(t * 2 * math.pi * 4)
    lpos = Vector((-0.085, 0.085 + tap, 0.2))
    P.two_bone('L', 'UpperArm', 'Forearm', 'Hand', P.local(mw(m, lpos)), P.local(mw(m, (-0.5, -0.5, -0.2))))
    P.orient_hand('L', P.inv.to_3x3() @ mdir(m, (0.35, 0.5, 0.6)), P.inv.to_3x3() @ mdir(m, (0.7, 0.4, -0.5)))
    P.curl('L', 0.35)
    rpos = lerpk([(0.0, (0.1, -0.05, 0.12)), (0.35, (0.1, -0.05, 0.12)), (0.55, (0.02, -0.2, 0.06)),
                  (0.75, (0.0, -0.17, 0.045)), (0.9, (0.1, -0.05, 0.12)), (1.0, (0.1, -0.05, 0.12))], t)
    P.two_bone('R', 'UpperArm', 'Forearm', 'Hand', P.local(mw(m, rpos)), P.local(mw(m, (0.6, -0.5, -0.2))))
    P.orient_hand('R', P.inv.to_3x3() @ mdir(m, (-0.2, 1.0, -0.35)), P.inv.to_3x3() @ mdir(m, (0, 0.1, -1)))
    P.curl('R', lerpk([(0.0, 0.25), (0.55, 0.25), (0.7, 0.7), (0.85, 0.25), (1.0, 0.25)], t))
    P.look(P.local(mw(m, lerpk([(0.0, (0, -0.06, 0.16)), (0.45, (0, -0.06, 0.16)), (0.6, (0, -0.15, 0.03)),
                                (0.85, (0, -0.15, 0.03)), (1.0, (0, -0.06, 0.16))], t))))


# --- trykpresse, indføring (står ved bagenden): retter papirstakken til og skubber den frem (2 s)
FEED = dict(machine='m1_cf_press_off', offset=(0.0, 1.12), yaw=180, frames=48)


def pose_feed(P, t):
    m = FEED['machine']
    P.spine(lean=math.radians(22), yaw=math.radians(2) * math.sin(t * 2 * math.pi))
    P.plant_feet()
    push = lerpk([(0.0, 0.0), (0.3, -0.035), (0.5, -0.035), (0.75, 0.0), (1.0, 0.0)], t)
    jog = 0.01 * math.sin(t * 2 * math.pi * 3) * smooth(0.5, 0.6, t) * (1 - smooth(0.85, 1.0, t))
    feed = Matrix.Rotation(math.radians(-12), 3, 'X')
    for s, x in (('R', -0.12), ('L', 0.12)):      # peden vender -Y i maskinens rum, så højre = -X
        top = Vector((0, 0.5, 1.008)) + feed @ Vector((x * 1.25, 0.12 + push + jog, 0.085))
        P.two_bone(s, 'UpperArm', 'Forearm', 'Hand', P.local(mw(m, top + Vector((0, 0.06, 0.02)))),
                   P.local(mw(m, (x * 4, 1.4, 1.0))))
        P.orient_hand(s, P.inv.to_3x3() @ mdir(m, (-x * 1.5, -1.0, -0.25)), P.inv.to_3x3() @ mdir(m, (0, -0.15, -1)))
        P.curl(s, 0.3)
    P.look(P.local(mw(m, (0.0, 0.3, 1.0))))


# --- trykpresse, udtag (står foran): bøjer sig ned, tager bunken fra bakken og løfter den op (4 s, ét forløb)
TAKE = dict(machine='m1_cf_press_done', offset=(0.0, -1.02), yaw=0, frames=96)


def pose_take(P, t):
    m = TAKE['machine']
    bend = lerpk([(0.0, 0.2), (0.25, 1.0), (0.55, 1.0), (0.8, 0.35), (1.0, 0.2)], t)
    P.move_root(P.inv.to_3x3() @ Vector((0, -0.04 * bend, -0.12 * bend)))
    P.spine(lean=math.radians(38) * bend)
    P.plant_feet()
    lift = lerpk([(0.0, 0.0), (0.45, 0.0), (0.8, 1.0), (1.0, 1.0)], t)
    reach = lerpk([(0.0, 0.0), (0.25, 1.0), (1.0, 1.0)], t)
    for s, x in (('R', 0.17), ('L', -0.17)):
        grab = Vector((x, -0.46, 0.69))
        held = Vector((x * 0.9, -0.78, 1.12))
        rest = Vector((x * 1.6, -0.9, 0.85))
        p = rest.lerp(grab, reach).lerp(held, lift)
        P.two_bone(s, 'UpperArm', 'Forearm', 'Hand', P.local(mw(m, p)), P.local(mw(m, (x * 4, -1.0, 0.7))))
        side = -1 if x > 0 else 1
        P.orient_hand(s, P.inv.to_3x3() @ mdir(m, (0, 0.55, -0.8)), P.inv.to_3x3() @ mdir(m, (side, 0, 0)))
        P.curl(s, 0.2 + 0.7 * smooth(0.25, 0.4, t))
    P.look(P.local(mw(m, Vector((0, -0.46, 0.7)).lerp(Vector((0, -0.7, 1.2)), lift))))


# --- tørresnor: rækker op, sætter et ark i klemmen og glatter det ud (3 s)
HANG = dict(machine='m1_cf_dryline_dry', offset=(0.0, -0.42), yaw=0, frames=72)


def pose_hang(P, t):
    m = HANG['machine']
    up = lerpk([(0.0, 0.0), (0.25, 1.0), (0.7, 1.0), (0.9, 0.0), (1.0, 0.0)], t)
    slide = lerpk([(0.0, 0.0), (0.3, 0.0), (0.6, 0.18), (1.0, 0.18)], t)
    P.spine(lean=-math.radians(4) * up, side=math.radians(3) * math.sin(t * 2 * math.pi))
    P.plant_feet()
    for s, x in (('R', 0.11), ('L', -0.11)):
        hi = Vector((x + slide - 0.09, -0.03, 1.58))
        lo = Vector((x * 1.3 - 0.05, -0.25, 1.12))
        p = lo.lerp(hi, up)
        P.shrug(s, math.radians(12) * up)
        P.two_bone(s, 'UpperArm', 'Forearm', 'Hand', P.local(mw(m, p)), P.local(mw(m, (x * 6, -0.6, 0.9))))
        P.orient_hand(s, P.inv.to_3x3() @ mdir(m, Vector((0, 0.35, 1.0)).lerp(Vector((0, 1.0, 0.1)), 1 - up)),
                      P.inv.to_3x3() @ mdir(m, (0, 1.0, 0)))
        P.curl(s, 0.55)
    P.look(P.local(mw(m, Vector((slide, 0, 1.05)).lerp(Vector((slide, 0, 1.55)), up))))


PED_CLIPS = [
    # clip,        opsætning, pose-funktion
    ('cut',        CUT,   pose_cut),
    ('count',      COUNT, pose_count),
    ('press_feed', FEED,  pose_feed),
    ('press_take', TAKE,  pose_take),
    ('hang',       HANG,  pose_hang),
]


def _place_counter_on_table():
    """Preview: sedeltælleren står oven på bordet."""
    tbl, cnt = bpy.data.objects['m1_cf_table'], bpy.data.objects['m1_cf_counter_run']
    cnt.location = tbl.location + Vector((0.25, -0.05, TABLE_H))
    bpy.context.view_layer.update()


def pose_frame(clip, t):
    arm = bpy.data.objects[PED]
    for name, cfg, fn in PED_CLIPS:
        if name == clip:
            place_ped(arm, cfg['machine'], cfg['offset'], cfg['yaw'], -cfg.get('base', 0.0))
            P = Poser(arm)
            _init_head_fwd(P)
            fn(P, t)
            return P


def build_ped_anims(only=None):
    arm = bpy.data.objects[PED]
    _place_counter_on_table()
    for o in arm.children:
        o.hide_viewport = True             # hurtigere depsgraph under bagning
    acts = {}
    try:
        for name, cfg, fn in PED_CLIPS:
            if only and name not in only:
                continue
            old = bpy.data.actions.get('ped_' + name)
            if old:
                bpy.data.actions.remove(old)
            arm.animation_data_create()
            act = bpy.data.actions.new('ped_' + name)
            act.use_fake_user = True
            arm.animation_data.action = act
            place_ped(arm, cfg['machine'], cfg['offset'], cfg['yaw'], -cfg.get('base', 0.0))
            P = Poser(arm)
            _init_head_fwd(P)
            for f in range(cfg['frames'] + 1):
                P.reset()
                fn(P, f / cfg['frames'])
                P.key(f)
            for fc in _fcurves(act):
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'
            arm.animation_data.action = None
            acts[name] = act
        Poser(arm).reset()
    finally:
        for o in arm.children:
            o.hide_viewport = o.name == 'SKEL_ROOT'
    return list(acts)


def build_ped_clipdict():
    old = bpy.data.objects.get(PED_DICT)
    if old:
        for ob in list(old.children_recursive) + [old]:
            bpy.data.objects.remove(ob, do_unlink=True)
    arm = bpy.data.objects[PED]
    cd, clips, anims = _ycdi.create_clip_dictionary_template(PED_DICT)
    for name, cfg, fn in PED_CLIPS:
        act = bpy.data.actions['ped_' + name]
        a = _ycdi.create_anim_obj(SollumType.ANIMATION)
        a.name = name + '_anim'
        a.parent = anims
        ap = a.animation_properties
        ap.hash = 'm1_cf_ped_' + name
        ap.target_id_type = 'ARMATURE'
        ap.target_id = arm.data
        ap.action = act
        c = _ycdi.create_anim_obj(SollumType.CLIP)
        c.name = name
        c.parent = clips
        cp = c.clip_properties
        cp.hash = name
        cp.name = name
        cp.duration = cfg['frames'] / FPS
        ca = cp.animations.add()
        ca.animation = a
        ca.start_frame = 0
        ca.end_frame = cfg['frames']
    return cd


def export_ped_ycd(ycd_xml_dir):
    build_ped_clipdict()
    exp = import_module(SZ + '.ycd.ycdexport')
    path = os.path.join(ycd_xml_dir, PED_DICT + '.ycd.xml')
    ok = exp.export_ycd(bpy.data.objects[PED_DICT], path)
    return ok and path
