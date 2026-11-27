import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import sio
argv = sys.argv[1:]
from SourceIO.library.models.mdl.v49 import MdlV49
from SourceIO.library.utils import FileBuffer
p = argv[0]
mdl = MdlV49.from_buffer(FileBuffer(p))
h = mdl.header
print("HEADER", {k: getattr(h,k) for k in dir(h) if not k.startswith('_') and not callable(getattr(h,k))})
for b in mdl.bones:
    print("BONE", {k: getattr(b,k) for k in dir(b) if not k.startswith('_') and not callable(getattr(b,k))})
for a in mdl.attachments:
    print("ATT", {k: getattr(a,k) for k in dir(a) if not k.startswith('_') and not callable(getattr(a,k))})
print("MATS", [m.name for m in mdl.materials], mdl.materials_paths)
print("SKINS", [[m.name for m in g] for g in mdl.skin_groups])
for bp in mdl.body_parts:
    print("BODYPART", bp.name, [(m.name, m.vertex_count, m.vertex_offset, len(m.meshes)) for m in bp.models])
for i,ad in enumerate(mdl.anim_descs):
    print("ANIMDESC", {k: getattr(ad,k) for k in dir(ad) if not k.startswith('_') and not callable(getattr(ad,k))})
    a = mdl.animations[i]
    print("  shape", a.shape, a.dtype)
    for f in range(a.shape[0]):
        print("  f", f, [(tuple(round(float(x),3) for x in a[f,b]["pos"]), tuple(round(float(x),3) for x in a[f,b]["rot"])) for b in range(a.shape[1])])
for s in mdl.sequences:
    print("SEQ", {k: getattr(s,k) for k in dir(s) if not k.startswith('_') and not callable(getattr(s,k))})
for k in ['hitbox_sets','key_values','include_models','surface_prop','bone_controllers','pose_parameters','local_nodes','ik_chains']:
    if hasattr(mdl,k): print("X", k, getattr(mdl,k))
print("ATTRS", [k for k in dir(mdl) if not k.startswith('_')])
