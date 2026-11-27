"""Prints rig facts for each gun model: bones, barrel frame, joints, bodyparts, anims."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from srcmodel import load
from rerig import bone_world, find_joints

ROOT = r"E:/GMODDS/deps/clean/ace/models"

for rel in sys.argv[1:]:
    m = load(os.path.join(ROOT, rel))
    bones = m["bones"]
    W = bone_world(bones)
    names = [b[0] for b in bones]
    cand = [i for i, n in enumerate(names) if n.lower().startswith("barrel")]
    print("==", rel)
    print("   bones", [(n, b[1]) for n, b in zip(names, bones)])
    for i in cand:
        R, t = W[i]
        print("   %s world x-axis %s t %s" % (names[i], np.round(R[:, 0], 3), np.round(t, 2)))
    print("   bodyparts", [(bp["name"], [md["name"] for md in bp["models"]]) for bp in m["bodyparts"]])
    print("   atts", [(a[0], names[a[1]]) for a in m["attachments"]], "anims", [a["name"] for a in m["anims"]],
          "seq", [s["name"] for s in m["sequences"]])
    for i in cand:
        try:
            J, T, c, r = find_joints(m, i)
            print("   joints(%s) J %.2f T %.2f center %s rmax %.2f" % (names[i], J, T, np.round(c, 3), r))
        except Exception as e:
            print("   joints(%s) ERR %s" % (names[i], e))
