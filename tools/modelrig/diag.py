"""Muzzle attachment world pos + largest Body islands (span, centre, radius, bones)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from srcmodel import load
from rerig import bone_world, weld_islands

ROOT = r"E:/GMODDS/deps/clean/ace/models"
for rel in sys.argv[1:]:
    m = load(os.path.join(ROOT, rel))
    names = [b[0] for b in m["bones"]]
    W = bone_world(m["bones"])
    print("==", rel)
    for n, pb, mat in m["attachments"]:
        R, t = W[pb]
        print("   att %s on %s world %s" % (n, names[pb], np.round(R @ mat[:, 3] + t, 2)))
    for bi, (n, b) in enumerate(zip(names, m["bones"])):
        print("   bone %-14s world t %s" % (n, np.round(W[bi][1], 2)))
    body = m["bodyparts"][0]["models"][0]["meshes"]
    labs = weld_islands(body)
    rows = []
    for me, lab in zip(body, labs):
        for i in np.unique(lab):
            s = lab == i
            p = me["pos"][s]
            bones = sorted(set(names[b] for b, w in zip(me["bone"][s].ravel(), me["weight"][s].ravel()) if w > 0))
            rows.append((np.ptp(p[:, 0]), p[:, 0].min(), p[:, 0].max(), p[:, 1].mean(), p[:, 2].mean(),
                         np.hypot(p[:, 1] - p[:, 1].mean(), p[:, 2] - p[:, 2].mean()).max(), s.sum(), bones, me["material"]))
    rows.sort(key=lambda r: -r[0])
    allp = np.vstack([me["pos"] for me in body])
    print("   body bbox", np.round(allp.min(0), 1), np.round(allp.max(0), 1))
    for r in rows[:10]:
        print("   isl span %6.1f x %7.1f..%7.1f yz (%6.1f %6.1f) r %5.1f n%-5d %s %s" % r)
