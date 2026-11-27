"""Re-rigs, compiles and checks every scalable gun model.
usage: python batch.py <outroot> [rel.mdl ...]   (default: all of MODELS)
Writes <outroot>/game/models/..., <outroot>/registry.json, <outroot>/report.txt."""
import json, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from scipy.spatial import cKDTree
from srcmodel import load
from rerig import apply, anim_world4, bind_world4, idle_anim, posed
from rebuild import write_all, compile_qc, patch_phy
from skin import pose

CLEAN = r"E:/GMODDS/deps/clean/ace/models"
MODELS = (["tankgun/tankgun_%s.mdl" % c for c in ("37mm", "50mm", "75mm", "85mm", "100mm", "120mm", "140mm", "170mm", "170mmsb")]
          + ["tankgun/tankgun_al_%s.mdl" % c for c in ("50mm", "75mm", "100mm", "120mm", "140mm", "170mm")]
          + ["tankgun/tankgun_short_%s.mdl" % c for c in ("37mm", "50mm", "75mm", "85mm", "100mm", "120mm", "140mm", "170mm")]
          + ["tankgun_new/tankgun_%s.mdl" % c for c in ("50mm", "75mm", "100mm", "120mm", "140mm", "170mm")]
          + ["howitzer/howitzer_%s.mdl" % c for c in ("75mm", "105mm", "122mm", "155mm", "203mm", "240mm", "290mm", "406mm")]
          + ["autocannon/semiautocannon_%s.mdl" % c for c in ("25mm", "37mm", "45mm", "57mm", "76mm")])


def barrel_name(rel):
    return "barrel01" if "semiautocannon" in rel else "barrel"


def skinned(m, S, groups=None):
    """Per bodypart-model list of skinned vertex arrays."""
    out = []
    for bi, bp in enumerate(m["bodyparts"]):
        for mi, md in enumerate(bp["models"]):
            if groups is not None and groups[bi] != mi:
                continue
            ps = [me["pos"] for me in posed(md["meshes"], S)]
            out.append(((bp["name"], md["name"]), np.vstack(ps) if ps else np.zeros((0, 3))))
    return out


def idle_S(m, ls=None, J=None, T=None):
    B = bind_world4(m["bones"])
    A = pose(m["bones"], idle_anim(m), ls, J, T) if ls is not None else anim_world4(m["bones"], idle_anim(m))
    return [a @ np.linalg.inv(b) for a, b in zip(A, B)], A


def sorted_rows(a):
    return a[np.lexsort(np.round(a, 2).T[::-1])]


def check(orig, new, J, T, log):
    """ls=1 must reproduce the original idle pose; welded vertices stay welded at
    other scales; nothing behind the joint moves; the muzzle lands where Lua expects."""
    S0, A0 = idle_S(orig)
    S1, _ = idle_S(new, 1.0, J, T)
    ok = True
    for (k, a), (_, b) in zip(skinned(orig, S0), skinned(new, S1)):
        if not len(a) and not len(b):
            continue
        # symmetric nearest-neighbour distance (studiomdl may merge duplicate vertices)
        d = max(cKDTree(b).query(a)[0].max(), cKDTree(a).query(b)[0].max())
        if d > 0.05:  # anim compression of the new bones costs ~0.03u
            log("   FAIL ls1 %s dpos %.3f" % (k, d)); ok = False
    names = [b[0] for b in orig["bones"]]
    mz = next((a for a in orig["attachments"] if a[0].lower() == "muzzle"), None)
    mz0 = (A0[mz[1]] @ np.vstack([mz[2], [0, 0, 0, 1]]))[:3, 3] if mz else None
    worst = {}
    for ls in (0.5, 0.75, 1.4, 2.0):
        Sl, Al = idle_S(new, ls, J, T)
        for (k, a), (_, b) in zip(skinned(new, S1), skinned(new, Sl)):
            if not len(a):
                continue
            _, inv = np.unique(np.round(a, 2), axis=0, return_inverse=True)
            inv = inv.reshape(-1)
            lo = np.full((inv.max() + 1, 3), np.inf); hi = np.full((inv.max() + 1, 3), -np.inf)
            np.minimum.at(lo, inv, b); np.maximum.at(hi, inv, b)
            crack = (hi - lo).max()
            behind = a[:, 0] <= J - 0.05
            moved = np.abs(a[behind] - b[behind]).max() if behind.any() else 0
            worst[k] = (max(worst.get(k, (0, 0))[0], crack), max(worst.get(k, (0, 0))[1], moved))
        nn = [b[0] for b in new["bones"]]
        nmz = next((a for a in new["attachments"] if a[0].lower() == "muzzle"), None)
        if nmz is not None and mz0 is not None:
            p = (Al[nmz[1]] @ np.vstack([nmz[2], [0, 0, 0, 1]]))[:3, 3]
            want = mz0 + np.array([(ls - 1) * (T - J), 0, 0])
            if np.abs(p - want).max() > 0.05:
                log("   FAIL muzzle ls %.2f at %s want %s (%s)" % (ls, np.round(p, 2), np.round(want, 2), nn[nmz[1]])); ok = False
    for k, (crack, moved) in worst.items():
        if crack > 0.02 or moved > 0.02:
            log("   FAIL %-14s %-24s crack %.3f breech-moved %.3f" % (k[0], k[1], crack, moved)); ok = False
    return ok


def main():
    out = sys.argv[1]
    rels = sys.argv[2:] or MODELS
    reg = {}
    rep = open(os.path.join(out, "report.txt"), "a")

    def log(s):
        print(s); rep.write(s + "\n"); rep.flush()
    game = os.path.join(out, "game")
    for rel in rels:
        log("===== " + rel)
        src = os.path.join(CLEAN, rel)
        orig = load(src)
        mm, info = apply(orig, barrel_name(rel), log=lambda s: log(s) if "slides" not in s else None)
        srcdir = os.path.join(out, "src", rel[:-4])
        if os.path.isdir(srcdir):
            shutil.rmtree(srcdir)
        qc = write_all(mm, srcdir, rel)
        rc, txt = compile_qc(qc, game)
        dst = os.path.join(game, "models", rel)
        if rc != 0 or not os.path.exists(dst):
            log("   COMPILE FAIL rc %d\n%s" % (rc, txt[-2000:])); continue
        for w in [l for l in txt.splitlines() if "WARNING" in l.upper() or "ERROR" in l.upper()][:5]:
            log("   studiomdl: " + w.strip())
        if os.path.exists(src[:-4] + ".phy"):
            patch_phy(src[:-4] + ".phy", dst[:-4] + ".phy", dst)
        new = load(dst)
        good = check(orig, new, info["joint"], info["tubeend"], log)
        log("   %s" % ("OK" if good else "CHECK FAILED"))
        reg["models/" + rel] = {"joint": round(float(info["joint"]), 3), "tubeend": round(float(info["tubeend"]), 3),
                                "mdir": [round(float(v), 4) + 0.0 for v in info["mdir"]], "ok": good}
        old = {}
        rp = os.path.join(out, "registry.json")
        if os.path.exists(rp):
            old = json.load(open(rp))
        old.update(reg)
        json.dump(old, open(rp, "w"), indent=1)


if __name__ == "__main__":
    main()
