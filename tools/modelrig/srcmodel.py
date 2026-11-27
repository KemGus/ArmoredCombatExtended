"""Read a Source MDL(+VVD+VTX) into plain python/numpy structures via SourceIO's library."""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sio  # noqa: F401  (registers the SourceIO package without Blender)
import numpy as np
from SourceIO.library.models.mdl.v49 import MdlV49
from SourceIO.library.models.vtx import open_vtx
from SourceIO.library.models.vvd import Vvd
from SourceIO.library.utils import FileBuffer


def _strip_group_merge(vtx_mesh):
    idx, verts, off = [], [], 0
    for sg in vtx_mesh.strip_groups:
        idx.append(np.add(sg.indices, off))
        verts.append(sg.vertexes['original_mesh_vertex_index'].reshape(-1).astype(np.uint32))
        off += sum(s.vertex_count for s in sg.strips)
    return np.hstack(idx), np.hstack(verts), off


def _cstr(d, o):
    return d[o:d.index(b'\0', o)].decode('latin-1')


def read_hitboxes(raw):
    # studiohdr: hitbox_set_count/offset at 0xAC/0xB0 (v44+)
    cnt, off = struct.unpack_from('<ii', raw, 0xAC)
    sets = []
    for s in range(cnt):
        so = off + s * 12
        ni, nh, hi = struct.unpack_from('<iii', raw, so)
        boxes = []
        for h in range(nh):
            ho = so + hi + h * 68
            bone, group = struct.unpack_from('<ii', raw, ho)
            mn = struct.unpack_from('<3f', raw, ho + 8)
            mx = struct.unpack_from('<3f', raw, ho + 20)
            boxes.append((bone, group, mn, mx))
        sets.append((_cstr(raw, so + ni), boxes))
    return sets


def load(path):
    base = path[:-4]
    raw = open(path, 'rb').read()
    mdl = MdlV49.from_buffer(FileBuffer(path))
    vvd = Vvd.from_buffer(FileBuffer(base + '.vvd'))
    vtx = open_vtx(FileBuffer(base + '.dx90.vtx'))
    allv = vvd.lod_data[0]
    out = {
        'mdl': mdl, 'raw': raw,
        'bones': [(b.name, b.parent_id, np.array(b.position, float), np.array(b.rotation, float)) for b in mdl.bones],
        'attachments': [(a.name, a.parent_bone, np.array(a.matrix, float).reshape(3, 4)) for a in mdl.attachments],
        'materials': [m.name for m in mdl.materials],
        'cdmaterials': list(mdl.materials_paths),
        'skins': [[m.name for m in g] for g in mdl.skin_groups],
        'hitboxes': read_hitboxes(raw),
        'bodyparts': [],
    }
    for vbp, bp in zip(vtx.body_parts, mdl.body_parts):
        models = []
        for vm, m in zip(vbp.models, bp.models):
            ent = {'name': m.name, 'meshes': []}
            if m.vertex_count:
                mv = allv[m.vertex_offset:m.vertex_offset + m.vertex_count]
                for vmesh, mesh in zip(vm.model_lods[0].meshes, m.meshes):
                    if not vmesh.strip_groups:
                        continue
                    idx, vix, _ = _strip_group_merge(vmesh)
                    v = mv[np.add(vix, mesh.vertex_index_start)]
                    tris = np.asarray(idx, np.int64).reshape(-1, 3)[:, ::-1]  # CCW, as SourceIO/BST
                    ent['meshes'].append({
                        'material': mdl.materials[mesh.material_index].name,
                        'pos': np.array(v['vertex'], float), 'nrm': np.array(v['normal'], float),
                        'uv': np.array(v['uv'], float), 'bone': np.array(v['bone_id'], int),
                        'weight': np.array(v['weight'], float), 'tris': tris,
                    })
            models.append(ent)
        out['bodyparts'].append({'name': bp.name, 'models': models})
    anims = []
    for i, ad in enumerate(mdl.anim_descs):
        anims.append({'name': ad.name, 'fps': ad.fps, 'frames': ad.frame_count,
                      'flags': int(ad.flags), 'tracks': dict(mdl.animations[i])})
    out['anims'] = anims
    seqs = []
    for s in mdl.sequences:
        seqs.append({'name': s.name, 'label': getattr(s, 'label', s.name), 'activity': s.activity_name,
                     'activity_weight': s.activity_weight, 'flags': s.flags,
                     'anims': [mdl.anim_descs[k].name for k in s.anim_desc_indices],
                     'fadein': s.fade_in_time, 'fadeout': s.fade_out_time})
    out['sequences'] = seqs
    return out


if __name__ == '__main__':
    m = load(sys.argv[1])
    for bp in m['bodyparts']:
        for md in bp['models']:
            print(bp['name'], md['name'], [(me['material'], len(me['pos']), len(me['tris'])) for me in md['meshes']])
    for s in m['sequences']:
        print('SEQ', s)
    print('HB', m['hitboxes'])
