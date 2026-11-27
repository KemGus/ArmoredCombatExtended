"""Skins compiled models at several length scales into OBJs + a camera json for render.py.
usage: python gen_vis.py <batchdir> <visdir> rel.mdl ..."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from srcmodel import load
from skin import skin, write_obj

batch, vis = sys.argv[1], sys.argv[2]
reg = json.load(open(os.path.join(batch, "registry.json")))
os.makedirs(vis, exist_ok=True)
cams, objs = {}, []
for rel in sys.argv[3:]:
    r = reg["models/" + rel]
    J, T = r["joint"], r["tubeend"]
    mdl = os.path.join(batch, "game", "models", rel)
    m = load(mdl)
    zero = [0] * len(m["bodyparts"])
    rich = [int(np.argmax([sum(len(me["pos"]) for me in md["meshes"]) for md in bp["models"]])) for bp in m["bodyparts"]]
    stem = rel[:-4].replace("/", "_")
    runs = []
    for gname, groups in (("g0", zero), ("gx", rich)):
        if gname == "gx" and groups == zero:
            continue
        for ls in (0.75, 1.0, 1.4):
            _, parts = skin(mdl, ls, J, T, groups)
            base = "%s_%s_ls%.2f" % (stem, gname, ls)
            path = os.path.join(vis, base + ".obj")
            write_obj(path, parts)
            objs.append(path)
            runs.append((base, ls, np.vstack([p for _, p in parts])))
    allp = np.vstack([p for _, _, p in runs])
    lo, hi = allp.min(0), allp.max(0)
    k = max(hi[1] - lo[1], hi[2] - lo[2]) / 30.0
    for base, ls, p in runs:
        cams[base] = {"cx": float((lo[0] + hi[0]) / 2), "ortho": float((hi[0] - lo[0]) * 1.08),
                      "jx": J, "mx": T + (ls - 1) * (T - J), "k": float(k), "cz": float((lo[2] + hi[2]) / 2)}
json.dump(cams, open(os.path.join(vis, "cams.json"), "w"), indent=1)
open(os.path.join(vis, "objs.txt"), "w").write("\n".join(objs) + "\n")
print(len(objs), "objs")
