"""Compares two models loaded with srcmodel: header, bones, attachments, hitboxes,
anims, and per-bodypart geometry (position-sorted vertex sets)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from srcmodel import load


def geo(md):
    rows = []
    for me in md["meshes"]:
        rows.append(np.hstack([me["pos"], me["nrm"], me["uv"]]))
    if not rows:
        return np.zeros((0, 8)), 0
    a = np.vstack(rows)
    a = a[np.lexsort(np.round(a, 3).T[::-1])]
    return a, sum(len(me["tris"]) for me in md["meshes"])


def main(pa, pb, bone_map=True):
    A, B = load(pa), load(pb)
    ha, hb = A["mdl"].header, B["mdl"].header
    for k in ("flags", "contents", "mass", "surface_prop", "illumination_position", "hull_min", "hull_max",
              "view_bbox_min", "view_bbox_max", "eye_position", "key_value_size"):
        va, vb = getattr(ha, k), getattr(hb, k)
        print("%-22s %s | %s" % (k, va, vb))
    print("bones A", [(b[0], b[1], np.round(b[2], 4).tolist(), np.round(b[3], 4).tolist()) for b in A["bones"]])
    print("bones B", [(b[0], b[1], np.round(b[2], 4).tolist(), np.round(b[3], 4).tolist()) for b in B["bones"]])
    print("att A", [(a[0], a[1], np.round(a[2], 4).tolist()) for a in A["attachments"]])
    print("att B", [(a[0], a[1], np.round(a[2], 4).tolist()) for a in B["attachments"]])
    print("hb A", A["hitboxes"]); print("hb B", B["hitboxes"])
    print("seq A", A["sequences"]); print("seq B", B["sequences"])
    for aa, ab in zip(A["anims"], B["anims"]):
        print("anim", aa["name"], aa["fps"], aa["frames"], "|", ab["name"], ab["fps"], ab["frames"])
        for bn, tr in aa["tracks"].items():
            tb = ab["tracks"].get(bn)
            if tb is None:
                print("   missing track", bn); continue
            dp = np.abs(tr["pos"] - tb["pos"]).max() if len(tb) == len(tr) else "len %d vs %d" % (len(tr), len(tb))
            dq = np.abs(np.abs((tr["rot"] * tb["rot"]).sum(1)) - 1).max() if len(tb) == len(tr) else "-"
            print("   ", bn, "dpos", dp, "drot", dq)
        extra = set(ab["tracks"]) - set(aa["tracks"])
        if extra:
            print("   extra tracks in B", extra)
    for bpa, bpb in zip(A["bodyparts"], B["bodyparts"]):
        for ma, mb in zip(bpa["models"], bpb["models"]):
            ga, ta = geo(ma); gb, tb = geo(mb)
            if len(ga) != len(gb):
                print("GEO", bpa["name"], ma["name"], mb["name"], "verts", len(ga), len(gb), "tris", ta, tb)
                continue
            d = np.abs(ga - gb).max(0) if len(ga) else np.zeros(8)
            print("GEO %-15s %-22s v %5d t %5d  dpos %.4f dnrm %.4f duv %.5f" % (
                bpa["name"], ma["name"], len(ga), ta, d[:3].max(), d[3:6].max(), d[6:].max()))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
