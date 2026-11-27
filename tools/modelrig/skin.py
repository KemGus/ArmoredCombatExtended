"""CPU-skins a compiled model (as the engine would, idle pose) with the
tube/muzzledev manipulations for a length scale, and writes an OBJ per
bodygroup selection."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from srcmodel import load
from rerig import anim_world4, bind_world4, idle_anim, posed


def pose(bones, anim, ls, J, T):
    """Model-space 4x4 per bone in the idle pose after the runtime manipulation:
    ManipulateBoneScale(tube, (ls,1,1)), ManipulateBonePosition(muzzledev, mdir*(ls-1)*(T-J))."""
    names = [b[0] for b in bones]
    it, im = names.index("tube"), names.index("muzzledev")
    base = anim_world4(bones, anim)

    def ov(i, L):
        if i == it:
            L = L @ np.diag([ls, 1, 1, 1])
        elif i == im:
            R = base[bones[i][1]][:3, :3]
            L = L.copy(); L[:3, 3] += R.T @ np.array([(ls - 1) * (T - J), 0, 0])
        return L
    return anim_world4(bones, anim, local_override=ov)


def skin(mdl, ls, J, T, groups):
    m = load(mdl)
    bones = m["bones"]
    B = bind_world4(bones)
    cur = pose(bones, idle_anim(m), ls, J, T)
    S = [c @ np.linalg.inv(b) for c, b in zip(cur, B)]
    parts = []
    for bp, sel in zip(m["bodyparts"], groups):
        md = bp["models"][sel]
        for me in posed(md["meshes"], S):
            parts.append((me, me["pos"]))
    return m, parts


def write_obj(path, parts):
    with open(path, "w") as fh:
        off = 1
        for me, pos in parts:
            fh.write("o %s\n" % me["material"])
            for p in pos:
                fh.write("v %.4f %.4f %.4f\n" % tuple(p))
            for uv in me["uv"]:
                fh.write("vt %.5f %.5f\n" % (uv[0], 1 - uv[1]))
            for t in me["tris"]:
                a, b, c = t + off
                fh.write("f %d/%d %d/%d %d/%d\n" % (a, a, b, b, c, c))
            off += len(pos)


if __name__ == "__main__":
    mdl, out, ls, J, T = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
    groups = [int(g) for g in sys.argv[6].split(",")] if len(sys.argv) > 6 else None
    m = load(mdl)
    m, parts = skin(mdl, ls, J, T, groups or [0] * len(m["bodyparts"]))
    write_obj(out, parts)
