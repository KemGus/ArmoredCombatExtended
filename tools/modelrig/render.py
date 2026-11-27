"""Blender (background) renderer: one side view + joint/muzzle close-ups per OBJ.
usage: blender -b --factory-startup -P render.py -- <texdir> <outdir> <muzzle_x_json> obj..."""
import bpy, sys, os, json, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
texdir, outdir = argv[0], argv[1]
muzzles = json.load(open(argv[2])) if os.path.isfile(argv[2]) else json.loads(argv[2])
objs = argv[3:]
if len(objs) == 1 and objs[0].endswith(".txt"):
    objs = [l.strip() for l in open(objs[0]) if l.strip()]

sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_cavity = True
sh.cavity_type = "BOTH"
sh.show_object_outline = False
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w") if not sc.world else sc.world
sc.display.render_aa = "16"
sc.view_settings.view_transform = "Standard"

mats = {}


def mat(name):
    if name in mats:
        return mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    png = os.path.join(texdir, name + ".png")
    if os.path.exists(png):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(png)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.nodes.active = tex
    mats[name] = m
    return m


def look(cam, target):
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def shot(path, loc, target, ortho=None, res=(1600, 1000), lens=50):
    cd = bpy.data.cameras.new("c")
    if ortho:
        cd.type = "ORTHO"; cd.ortho_scale = ortho
    else:
        cd.lens = lens
    cd.clip_end = 5000
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    cam.location = Vector(loc)
    look(cam, target)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


for path in objs:
    for o in list(sc.objects):
        bpy.data.objects.remove(o)
    bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z")
    for o in sc.objects:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat(o.name.split(".")[0]))
            for p in o.data.polygons:
                p.use_smooth = True
    base = os.path.splitext(os.path.basename(path))[0]
    c = muzzles.get(base, 240)
    if not isinstance(c, dict):  # legacy: muzzle x only, 120mm framing
        c = {"cx": 130, "ortho": 460, "jx": 25, "mx": c, "k": 1, "cz": 0}
    k, cz = c["k"], c["cz"]
    shot(os.path.join(outdir, base + "_side.png"), (c["cx"], -4000, cz), (c["cx"], 0, cz), ortho=c["ortho"], res=(1800, 360))
    shot(os.path.join(outdir, base + "_joint.png"), (c["jx"] - 50 * k, -95 * k, cz + 45 * k), (c["jx"], 0, cz), res=(1000, 700), lens=40)
    shot(os.path.join(outdir, base + "_muzzle.png"), (c["mx"] - 70 * k, -70 * k, cz + 40 * k), (c["mx"] - 10 * k, 0, cz), res=(1000, 700), lens=40)
