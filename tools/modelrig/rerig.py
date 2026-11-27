"""Re-rigs a parsed gun model so only the tube stretches.

Adds two bones under the recoil ("barrel") bone:
  tube      origin at the breech/tube joint J; stretch-class vertices J < x <= T.
  muzzledev origin at the tube end T; everything at/after the muzzle.
Rigid parts on the tube (bands, evacuators, sleeves) get a constant
barrel/muzzledev blend so they translate with the tube without deforming.

Runtime (Lua): ManipulateBoneScale(tube, (ls,1,1)) and
ManipulateBonePosition(muzzledev, ((ls-1)*(T-J),0,0)).
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np

LONG_FRAC = 0.5     # island at least this fraction of (T-J) long = stretches
TOUCH = 0.5         # short islands closer than this along x form one rigid group
NEAR_FRAC = 0.02    # rigid groups within this fraction of (T-J) of J stay put / of T ride the muzzle


def euler_mat(r):
    x, y, z = r
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def bone_world(bones):
    W = []
    for name, par, pos, rot in bones:
        R, t = euler_mat(rot), np.asarray(pos, float)
        if par >= 0:
            PR, Pt = W[par]
            R, t = PR @ R, PR @ t + Pt
        W.append((R, t))
    return W


def quat_mat(q):
    x, y, z, w = (float(v) for v in q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
                     [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
                     [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)]])


def mat_euler(R):
    """Inverse of euler_mat (M = Rz*Ry*Rx)."""
    sy = math.hypot(R[0, 0], R[1, 0])
    if sy > 1e-6:
        return np.array([math.atan2(R[2, 1], R[2, 2]), math.atan2(-R[2, 0], sy), math.atan2(R[1, 0], R[0, 0])])
    return np.array([math.atan2(-R[1, 2], R[1, 1]), math.atan2(-R[2, 0], sy), 0.0])


def mat4(R, t):
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = t
    return M


def bind_world4(bones):
    return [mat4(R, t) for R, t in bone_world(bones)]


def idle_anim(m):
    seq = next((s for s in m["sequences"] if s["name"].lower() == "idle"), None)
    name = seq["anims"][0] if seq else (m["anims"][0]["name"] if m["anims"] else None)
    return next((a for a in m["anims"] if a["name"] == name), None)


def anim_world4(bones, anim, frame=0, local_override=None):
    """Model-space bone matrices in an animation pose (what the engine skins with).
    local_override(i, L) may modify each bone's parent-local matrix."""
    out = []
    for i, (name, par, pos, rot) in enumerate(bones):
        tr = anim["tracks"].get(name) if anim else None
        if tr is not None and len(tr):
            k = tr[min(frame, len(tr) - 1)]
            L = mat4(quat_mat(k["rot"]), k["pos"])
        else:
            L = mat4(euler_mat(rot), pos)
        if local_override:
            L = local_override(i, L)
        out.append(out[par] @ L if par >= 0 else L)
    return out


def posed(meshes, S):
    """Copies of meshes with positions skinned by per-bone matrices S."""
    res = []
    for me in meshes:
        P = np.hstack([me["pos"], np.ones((len(me["pos"]), 1))])
        out = np.zeros((len(P), 3))
        for k in range(me["bone"].shape[1]):
            w = me["weight"][:, k]
            for b in np.unique(me["bone"][:, k]):
                s = (me["bone"][:, k] == b) & (w > 0)
                if s.any():
                    out[s] += w[s, None] * (P[s] @ S[b].T)[:, :3]
        nme = dict(me); nme["pos"] = out
        res.append(nme)
    return res


def weld_islands(meshes):
    """Island label per vertex across all meshes of one bodypart model."""
    pos = np.vstack([me["pos"] for me in meshes])
    offs = np.cumsum([0] + [len(me["pos"]) for me in meshes])
    tris = np.vstack([me["tris"] + o for me, o in zip(meshes, offs[:-1])])
    _, weld = np.unique(np.round(pos, 3), axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    par = np.arange(weld.max() + 1)

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for t in weld[tris]:
        a = find(t[0]); par[find(t[1])] = a; par[find(t[2])] = a
    root = np.array([find(w) for w in weld])
    _, lab = np.unique(root, return_inverse=True)
    return [lab[offs[i]:offs[i + 1]] for i in range(len(meshes))]


def pure_bone(me, b):
    w = me["weight"]; bn = me["bone"]
    return np.isclose(np.where(bn == b, w, 0).sum(1), 1.0, atol=1e-3)


def find_joints(body, barrel):
    """J = front of everything in Body that is not on the barrel bone or is a
    short barrel-bone island starting behind the tube; T = end of the tube.
    `body` = Body meshes in the idle pose."""
    labs = weld_islands(body)
    best = None
    for me, lab in zip(body, labs):
        pb = pure_bone(me, barrel)
        for i in np.unique(lab):
            sel = (lab == i) & pb
            if sel.sum() < 3:
                continue
            x = me["pos"][sel, 0]
            r = np.hypot(me["pos"][sel, 1], me["pos"][sel, 2])
            span = x.max() - x.min()
            if best is None or span > best[0]:
                best = (span, x.min(), x.max(), me["pos"][sel, 1:].mean(0), r.max())
    _, tmin, T, center, rmax = best
    # J: furthest-forward non-barrel vertex in Body (cradle/mantlet/breech).
    J = -1e9
    for me in body:
        nb = ~pure_bone(me, barrel)
        if nb.any():
            J = max(J, me["pos"][nb, 0].max())
    if J < tmin:  # nothing static reaches the tube: the tube starts at its own rear end
        J = tmin
    return J, T, center, rmax


def classify(meshes, barrel, J, T):
    """Per-mesh lists of per-vertex (kind, w): kind 'keep' | 'stretch' | 'rigid'.
    Only pure barrel-bone vertices are ever re-weighted; island extents come from
    those vertices alone (some tubes are welded to a static ring at the mantlet)."""
    L = T - J
    labs = weld_islands(meshes)
    nisl = max(int(l.max()) for l in labs) + 1 if labs else 0
    xmin = np.full(nisl, np.inf); xmax = np.full(nisl, -np.inf)
    amin = np.full(nisl, np.inf); amax = np.full(nisl, -np.inf)
    for me, lab in zip(meshes, labs):
        pb = pure_bone(me, barrel)
        np.minimum.at(xmin, lab[pb], me["pos"][pb, 0]); np.maximum.at(xmax, lab[pb], me["pos"][pb, 0])
        np.minimum.at(amin, lab, me["pos"][:, 0]); np.maximum.at(amax, lab, me["pos"][:, 0])
    ok = np.isfinite(xmin)
    # muzzle devices some models hang on another bone (semiauto brakes on their own
    # root bones): wholly ahead of the joint and reaching past the tube end
    device = ~ok & (amin > J) & (amax > T + 0.5)
    long_ = ok & ((xmax - xmin) >= LONG_FRAC * L)
    # merge short barrel-bone islands into rigid groups by x overlap/touch
    short = [i for i in range(nisl) if ok[i] and not long_[i]]
    short.sort(key=lambda i: xmin[i])
    groups = []
    for i in short:
        if groups and xmin[i] <= groups[-1][2] + TOUCH:
            g = groups[-1]; g[0].append(i); g[2] = max(g[2], xmax[i])
        else:
            groups.append([[i], xmin[i], xmax[i]])
    anchors = {}
    rigid = []
    for g in groups:
        members, gmin, gmax = g
        if gmax - gmin >= LONG_FRAC * L:  # a chain of touching sleeves/segments: part of the tube
            long_[members] = True
            continue
        rigid.append(g)
        if gmax >= T - NEAR_FRAC * L:
            a = T
        elif gmin <= J + NEAR_FRAC * L:
            a = J
        else:
            a = 0.5 * (gmin + gmax)
        w = min(1.0, max(0.0, (a - J) / L))
        for i in members:
            anchors[i] = (w, gmin, gmax, a)
    out = []
    for me, lab in zip(meshes, labs):
        pb = pure_bone(me, barrel)
        res = []
        for v in range(len(me["pos"])):
            i = lab[v]
            if device[i]:
                res.append(("device", 1.0))
            elif not pb[v]:
                res.append(("keep", 0))
            elif long_[i]:
                res.append(("stretch", 0))
            else:
                res.append(("rigid", anchors[i][0]))
        out.append(res)
    nstretch = int(sum(1 for i in range(nisl) if long_[i]))
    for i in np.nonzero(device)[0]:
        rigid.append([[int(i)], amin[i], amax[i]]); anchors[int(i)] = (1.0, amin[i], amax[i], T)
    return out, rigid, anchors, nstretch


def apply(m, barrel_name="barrel", J=None, T=None, log=print):
    """All geometry decisions are made in the idle pose (model space as rendered:
    +x forward), not the bind pose, which some families store rotated."""
    bones = list(m["bones"])
    names = [b[0] for b in bones]
    barrel = names.index(barrel_name)
    anim = idle_anim(m)
    A = anim_world4(bones, anim)
    B = bind_world4(bones)
    S = [a @ np.linalg.inv(b) for a, b in zip(A, B)]
    J0, T0, center, rmax = find_joints(posed(m["bodyparts"][0]["models"][0]["meshes"], S), barrel)
    J = J0 if J is None else J
    T = T0 if T is None else T
    Ab = A[barrel]; RAb = Ab[:3, :3]
    ib = len(bones); im = ib + 1
    pj = np.array([J, center[0], center[1]]); pt = np.array([T, center[0], center[1]])
    # tube: world-aligned in the idle pose so its local x (the scale axis) is the bore.
    Lt = np.linalg.inv(Ab) @ mat4(np.eye(3), pj)
    # muzzledev: same orientation as the barrel bone, so a translate manipulation
    # means the same thing whether applied in its own or its parent's frame.
    Lm = mat4(np.eye(3), RAb.T @ (pt - Ab[:3, 3]))
    bones.append(("tube", barrel, Lt[:3, 3], mat_euler(Lt[:3, :3])))
    bones.append(("muzzledev", barrel, Lm[:3, 3], np.zeros(3)))
    mdir = RAb.T @ np.array([1.0, 0, 0])
    log("J %.3f T %.3f center %s rmax %.3f mdir %s" % (J, T, np.round(center, 4), rmax, np.round(mdir, 4)))

    mm = dict(m)
    mm["bodyparts"] = []
    for bp in m["bodyparts"]:
        nbp = {"name": bp["name"], "models": []}
        for md in bp["models"]:
            if not md["meshes"]:
                nbp["models"].append(md); continue
            pmeshes = posed(md["meshes"], S)
            cls, groups, anchors, nstretch = classify(pmeshes, barrel, J, T)
            if nstretch:
                log("   %-14s %-22s stretch islands %d" % (bp["name"], md["name"], nstretch))
            for members, gmin, gmax in groups:
                w = anchors[members[0]][0]
                log("   %-14s %-22s rigid x %7.2f..%7.2f n%-3d -> %s" % (
                    bp["name"], md["name"], gmin, gmax, len(members),
                    "stays" if w == 0 else ("muzzle" if w == 1 else "slides w=%.3f" % w)))
            nmeshes = []
            for me, pme, c in zip(md["meshes"], pmeshes, cls):
                bone = me["bone"].copy(); wt = me["weight"].copy()
                pos = me["pos"].copy(); nrm = me["nrm"].copy()
                x = pme["pos"][:, 0]
                iSb = np.linalg.inv(S[barrel])
                for v, (kind, w) in enumerate(c):
                    if kind == "keep":
                        continue
                    if kind == "device":
                        # moves off its own bone: re-bind so the idle pose is unchanged
                        # (barrel, tube and muzzledev all share S[barrel])
                        M = iSb @ S[int(me["bone"][v][0])]
                        pos[v] = (M @ np.append(me["pos"][v], 1))[:3]; nrm[v] = M[:3, :3] @ me["nrm"][v]
                        kind = "rigid"
                    bone[v] = 0; wt[v] = 0
                    if kind == "stretch":
                        bone[v][0] = barrel if x[v] <= J else (ib if x[v] <= T else im); wt[v][0] = 1
                    else:
                        k = 0
                        if w < 1:
                            bone[v][k] = barrel; wt[v][k] = 1 - w; k += 1
                        if w > 0:
                            bone[v][k] = im; wt[v][k] = w
                nme = dict(me); nme["bone"] = bone; nme["weight"] = wt; nme["pos"] = pos; nme["nrm"] = nrm
                nmeshes.append(nme)
            nbp["models"].append({"name": md["name"], "meshes": nmeshes})
        mm["bodyparts"].append(nbp)

    # attachments past the joint ride the tube / muzzle device (the muzzle
    # attachment too when the model hung it on the static bone)
    Anew = {ib: Ab @ Lt, im: Ab @ Lm}
    atts = []
    for name, pb, mat in m["attachments"]:
        Wa = A[pb] @ np.vstack([mat, [0, 0, 0, 1]])
        x = Wa[0, 3]
        if name.lower() == "muzzle" or (x > J and pb == barrel):
            nb = im if (x >= T - 1e-3 or name.lower() == "muzzle") else ib
            mat = (np.linalg.inv(Anew[nb]) @ Wa)[:3]
            log("   attachment %s (%s) -> %s at %s" % (name, names[pb], bones[nb][0], np.round(mat[:, 3], 3)))
            pb = nb
        atts.append((name, pb, mat))
    mm["attachments"] = atts
    mm["bones"] = bones
    # new bones are untracked, so they hold their bind-local pose in every animation
    return mm, {"joint": J, "tubeend": T, "mdir": mdir}
