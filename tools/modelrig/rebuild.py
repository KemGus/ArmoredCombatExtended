"""Write a parsed Source model (srcmodel.load) back out as SMD + QC and compile it."""
import math, os, shutil, struct, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np

STUDIOMDL = r"E:/Programs/Steam/steamapps/common/GarrysMod/bin/studiomdl.exe"


def quat_to_euler(q):
    """xyzw quaternion -> Source RadianEuler (x, y, z), M = Rz(z)*Ry(y)*Rx(x)."""
    x, y, z, w = (float(v) for v in q)
    m00 = 1 - 2 * (y * y + z * z); m10 = 2 * (x * y + w * z); m20 = 2 * (x * z - w * y)
    m21 = 2 * (y * z + w * x); m22 = 1 - 2 * (x * x + y * y)
    m01 = 2 * (x * y - w * z); m11 = 1 - 2 * (x * x + z * z)
    sy = math.hypot(m00, m10)
    if sy > 1e-6:
        return (math.atan2(m21, m22), math.atan2(-m20, sy), math.atan2(m10, m00))
    return (math.atan2(-2 * (y * z - w * x), m11), math.atan2(-m20, sy), 0.0)


def f(v):
    return "%.6f" % (0.0 if abs(v) < 5e-7 else v)


def write_skeleton(fh, bones, frames):
    fh.write("version 1\nnodes\n")
    for i, b in enumerate(bones):
        fh.write('%d "%s" %d\n' % (i, b[0], b[1]))
    fh.write("end\nskeleton\n")
    for t, poses in enumerate(frames):
        fh.write("time %d\n" % t)
        for i, (p, r) in enumerate(poses):
            fh.write("%d %s %s %s %s %s %s\n" % (i, f(p[0]), f(p[1]), f(p[2]), f(r[0]), f(r[1]), f(r[2])))
    fh.write("end\n")


def bind_frame(bones):
    return [(b[2], b[3]) for b in bones]


def write_ref(path, bones, meshes):
    with open(path, "w", newline="\n") as fh:
        write_skeleton(fh, bones, [bind_frame(bones)])
        fh.write("triangles\n")
        for me in meshes:
            pos, nrm, uv, bone, wt = me["pos"], me["nrm"], me["uv"], me["bone"], me["weight"]
            for tri in me["tris"]:
                fh.write(me["material"] + "\n")
                for vi in tri:
                    links = [(int(bone[vi][k]), float(wt[vi][k])) for k in range(len(wt[vi])) if wt[vi][k] > 1e-6]
                    p, n = pos[vi], nrm[vi]
                    fh.write("0 %s %s %s %s %s %s %s %s %d %s\n" % (
                        f(p[0]), f(p[1]), f(p[2]), f(n[0]), f(n[1]), f(n[2]), f(uv[vi][0]), f(1 - uv[vi][1]),
                        len(links), " ".join("%d %s" % (b, f(w)) for b, w in links)))
        fh.write("end\n")


def write_anim(path, bones, anim):
    frames = []
    n = max(1, anim["frames"])
    for t in range(n):
        poses = []
        for b in bones:
            tr = anim["tracks"].get(b[0])
            if tr is not None and len(tr):
                k = tr[min(t, len(tr) - 1)]
                poses.append((k["pos"], quat_to_euler(k["rot"])))
            else:
                poses.append((b[2], b[3]))
        frames.append(poses)
    with open(path, "w", newline="\n") as fh:
        write_skeleton(fh, bones, frames)


def write_qc(path, m, modelname, smd_names, extra_attach=()):
    raw = m["raw"]
    hdr = m["mdl"].header
    L = []
    L.append('$modelname "%s"' % modelname)
    L.append("$origin 0 0 0 -90")
    for cd in m["cdmaterials"]:
        L.append('$cdmaterials "%s"' % cd)
    L.append('$surfaceprop "%s"' % hdr.surface_prop)
    ip = hdr.illumination_position
    # studiomdl rotates $illumposition by its default +90 deg Z even under
    # "$origin ... -90", so pre-rotate it by -90 to round-trip.
    L.append("$illumposition %s %s %s" % (f(ip[1]), f(-ip[0]), f(ip[2])))
    for bp, names in zip(m["bodyparts"], smd_names):
        L.append('$bodygroup "%s"\n{' % bp["name"])
        for nm in names:
            L.append('\tstudio "%s"' % nm if nm else "\tblank")
        L.append("}")
    bones = m["bones"]
    for name, pb, mat in list(m["attachments"]) + list(extra_attach):
        rot = np.degrees(quat_to_euler(_mat_quat(mat[:, :3])))
        L.append('$attachment "%s" "%s" %s %s %s rotate %s %s %s' % (
            name, bones[pb][0], f(mat[0, 3]), f(mat[1, 3]), f(mat[2, 3]), f(rot[0]), f(rot[1]), f(rot[2])))
    for setname, boxes in m["hitboxes"]:
        L.append('$hboxset "%s"' % setname)
        for b, g, mn, mx in boxes:
            L.append('$hbox %d "%s" %s %s %s %s %s %s' % (g, bones[b][0], *(f(v) for v in mn), *(f(v) for v in mx)))
    for s in m["sequences"]:
        an = next(a for a in m["anims"] if a["name"] == s["anims"][0])
        L.append('$sequence "%s" "%s.smd" fps %g fadein %g fadeout %g' % (
            s["name"], an["name"].lstrip("@"), an["fps"], round(s["fadein"], 4), round(s["fadeout"], 4)))
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")


def _mat_quat(r):
    t = r[0, 0] + r[1, 1] + r[2, 2]
    if t > 0:
        s = math.sqrt(t + 1) * 2
        return ((r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, s / 4)
    i = int(np.argmax([r[0, 0], r[1, 1], r[2, 2]]))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = math.sqrt(1 + r[i, i] - r[j, j] - r[k, k]) * 2
    q = [0, 0, 0, 0]
    q[i] = s / 4; q[j] = (r[j, i] + r[i, j]) / s; q[k] = (r[k, i] + r[i, k]) / s; q[3] = (r[k, j] - r[j, k]) / s
    return q


def write_all(m, srcdir, modelname, bones=None, extra_attach=()):
    """Writes reference + animation SMDs and the QC. `bones` overrides m['bones']
    (meshes must then carry matching bone ids)."""
    bones = bones or m["bones"]
    os.makedirs(srcdir, exist_ok=True)
    smd_names = []
    for bp in m["bodyparts"]:
        names = []
        for md in bp["models"]:
            if not md["meshes"]:
                names.append(None)
                continue
            nm = md["name"] if md["name"].lower().endswith(".smd") else md["name"] + ".smd"
            write_ref(os.path.join(srcdir, nm), bones, md["meshes"])
            names.append(nm)
        smd_names.append(names)
    for a in m["anims"]:
        write_anim(os.path.join(srcdir, a["name"].lstrip("@") + ".smd"), bones, a)
    mm = dict(m); mm["bones"] = bones
    write_qc(os.path.join(srcdir, "model.qc"), mm, modelname, smd_names, extra_attach)
    return os.path.join(srcdir, "model.qc")


def compile_qc(qc, gamedir):
    os.makedirs(gamedir, exist_ok=True)
    gi = os.path.join(gamedir, "gameinfo.txt")
    if not os.path.exists(gi):
        with open(gi, "w") as fh:
            fh.write('"GameInfo"\n{\n\tgame "rb"\n\tFileSystem\n\t{\n\t\tSteamAppId 4000\n\t\tSearchPaths\n\t\t{\n\t\t\tgame |gameinfo_path|.\n\t\t}\n\t}\n}\n')
    r = subprocess.run([STUDIOMDL, "-game", gamedir, "-nop4", "-verbose", qc], capture_output=True, text=True, timeout=600)
    return r.returncode, r.stdout + r.stderr


def patch_phy(src_phy, dst_phy, mdl_path):
    """Copies the original .phy, rewriting its header checksum to match the new MDL."""
    ck = struct.unpack_from("<i", open(mdl_path, "rb").read(), 8)[0]
    data = bytearray(open(src_phy, "rb").read())
    struct.pack_into("<i", data, 12, ck)
    open(dst_phy, "wb").write(data)
