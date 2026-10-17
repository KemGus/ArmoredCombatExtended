#!/usr/bin/env python3
"""Inventory every engine definition in ACE, ACF-Extra and ACF Customs.

Writes model_inventory.json and model_inventory.md into docs/engines/research/.

Rules:
- Engine calls: ACE.DefineEngine / ACF_DefineEngine / ACF_DefineEngineold /
  ACF_DefineEngineMaker with a literal string id and a literal table.
  ACE.DefineEngineHeater calls are not engines and are ignored.
- Layout and cylinders are guessed only from id, name and model path tokens.
  layout_source is "name" when a token matched, otherwise null.
- The .mdl is looked up in the addon root first, then the base game.
  MDL header (little-endian): hull_min @104, hull_max @116,
  view_bbmin @128, view_bbmax @140, all in inches.
- Model clashes compare only addon-owned .mdl files (not base game).
- Missing or non-literal values are left null, never estimated.
"""
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "research"))
BASE = "E:/Programs/Steam/steamapps/common/GarrysMod/garrysmod"

ADDONS = [
    ("ACE", "E:/GMODDS/ace-worktrees/mobility"),
    ("ACF-Extra", "E:/GMODDS/research/extra"),
    ("ACF Customs", "E:/GMODDS/research/cm"),
]

# Same line shape as the shell grep used for the cross-check.
GREP_PAT = r'^\s*(ACE\.|ACF_)DefineEngine(old|Maker)?\s*\(\s*"'
CALL_RE = re.compile(
    r'(?:ACE\.|ACF_)DefineEngine(old|Maker)?\s*\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*\{'
)
REQUIRED = ["name", "model", "category", "fuel", "enginetype",
            "weight", "torque", "idlerpm", "limitrpm"]
NUM_RE = re.compile(r'^-?\d+(\.\d+)?([eE][-+]?\d+)?$')
KEY_RE = re.compile(r'([A-Za-z_]\w*)\s*=(?!=)')
# Layout tokens: V/VR/I/B/X/W/R<n>, Single[n], Wankel. R only for radial 3/5/7/9.
TOK_RE = re.compile(
    r'(?<![A-Za-z])(?:(VR|V|I|B|X|W|R)(\d{1,2})(?!\d)|(single)(\d)?(?!\d)|(wankel))',
    re.I,
)


def strip_line_comment(line):
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != '\\'):
            in_str = not in_str
        elif not in_str and line.startswith('--', i):
            return line[:i]
        i += 1
    return line


def strip_comments(text):
    # Block comments: keep the newline count so line numbers stay correct.
    text = re.sub(r'--\[(=*)\[.*?\]\1\]',
                  lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    return '\n'.join(strip_line_comment(l) for l in text.split('\n'))


def skip_string(text, i):
    j = i + 1
    while j < len(text):
        if text[j] == '\\':
            j += 2
            continue
        if text[j] == '"':
            return j + 1
        j += 1
    return len(text)


def find_close_brace(text, open_idx):
    depth = 0
    i = open_idx
    while i < len(text):
        c = text[i]
        if c == '"':
            i = skip_string(text, i)
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def parse_table(body):
    """Top-level key = value pairs of a Lua table body."""
    fields = {}
    i = 0
    n = len(body)
    depth = 0
    while i < n:
        c = body[i]
        if c == '"':
            i = skip_string(body, i)
            continue
        if c == '{':
            depth += 1
            i += 1
            continue
        if c == '}':
            depth -= 1
            i += 1
            continue
        if depth == 0 and (c.isalpha() or c == '_') and (
                i == 0 or not (body[i - 1].isalnum() or body[i - 1] == '_')):
            m = KEY_RE.match(body, i)
            if m:
                key = m.group(1)
                j = m.end()
                while j < n and body[j] in ' \t\r\n':
                    j += 1
                if j < n and body[j] == '"':
                    k = skip_string(body, j)
                    fields[key] = ('str', body[j + 1:k - 1])
                    i = k
                    continue
                if j < n and body[j] == '{':
                    k = find_close_brace(body, j)
                    fields[key] = ('table', None)
                    i = (k + 1) if k != -1 else n
                    continue
                k = j
                while k < n and body[k] not in ',\n':
                    k += 1
                raw = body[j:k].strip()
                if NUM_RE.match(raw):
                    fields[key] = ('num', float(raw))
                else:
                    fields[key] = ('raw', raw)
                i = k
                continue
        i += 1
    return fields


def fval(fields, key):
    t = fields.get(key)
    if t and t[0] in ('str', 'num'):
        return t[1]
    return None


def guess_layout(entry):
    for field in ("id", "name", "model"):
        s = entry.get(field) or ""
        for m in TOK_RE.finditer(s):
            if m.group(1):
                fam = m.group(1).upper()
                n = int(m.group(2))
                if fam == 'R' and n not in (3, 5, 7, 9):
                    continue
                return {"layout": fam, "cylinders": n, "layout_source": "name",
                        "layout_token": m.group(0), "layout_field": field}
            if m.group(3):
                n = int(m.group(4)) if m.group(4) else 1
                return {"layout": "Single", "cylinders": n, "layout_source": "name",
                        "layout_token": m.group(0), "layout_field": field}
            if m.group(5):
                return {"layout": "Wankel", "cylinders": None, "layout_source": "name",
                        "layout_token": m.group(0), "layout_field": field}
    return {"layout": None, "cylinders": None, "layout_source": None,
            "layout_token": None, "layout_field": None}


def describe_mdl(path, src):
    with open(path, 'rb') as f:
        data = f.read()
    info = {"model_exists": True, "model_source": src, "mdl_path": path,
            "mdl_size": len(data), "mdl_md5": hashlib.md5(data).hexdigest(),
            "hull_min": None, "hull_max": None, "view_bbmin": None,
            "view_bbmax": None, "size_mm": None, "mdl_error": None}
    if len(data) < 152:
        info["mdl_error"] = "file shorter than 152 bytes"
        return info
    if data[0:4] != b'IDST':
        info["mdl_error"] = "bad magic %r" % data[0:4]
    hmin = struct.unpack_from('<3f', data, 104)
    hmax = struct.unpack_from('<3f', data, 116)
    vmin = struct.unpack_from('<3f', data, 128)
    vmax = struct.unpack_from('<3f', data, 140)
    info["hull_min"] = [round(v, 4) for v in hmin]
    info["hull_max"] = [round(v, 4) for v in hmax]
    info["view_bbmin"] = [round(v, 4) for v in vmin]
    info["view_bbmax"] = [round(v, 4) for v in vmax]
    info["size_mm"] = [round((b - a) * 25.4, 2) for a, b in zip(hmin, hmax)]
    return info


MISSING_MDL = {"model_exists": False, "model_source": None, "mdl_path": None,
               "mdl_size": None, "mdl_md5": None, "hull_min": None, "hull_max": None,
               "view_bbmin": None, "view_bbmax": None, "size_mm": None,
               "mdl_error": None}


def resolve_model(addon_root, model, cache):
    key = (addon_root, model)
    if key in cache:
        return cache[key]
    rel = model.replace('\\', '/').lstrip('/')
    info = None
    for root, src in ((addon_root, 'addon'), (BASE, 'base')):
        p = os.path.join(root, rel)
        if os.path.isfile(p):
            info = describe_mdl(p, src)
            break
    if info is None:
        info = dict(MISSING_MDL)
    cache[key] = info
    return info


def scan_file(addon, root, path):
    rel = os.path.relpath(path, root).replace('\\', '/')
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        clean = strip_comments(f.read())
    engines, unparsed = [], []
    for m in CALL_RE.finditer(clean):
        line = clean.count('\n', 0, m.start()) + 1
        kind = "DefineEngine" + (m.group(1) or "")
        eid = m.group(2)
        open_idx = m.end() - 1
        close = find_close_brace(clean, open_idx)
        base = {"addon": addon, "id": eid, "kind": kind, "file": rel, "line": line}
        if close == -1:
            unparsed.append(dict(base, reason="unterminated table"))
            continue
        fields = parse_table(clean[open_idx + 1:close])
        entry = dict(base)
        for k in ["name", "model", "category", "fuel", "enginetype", "desc", "sound",
                  "weight", "torque", "flywheelmass", "idlerpm", "peakminrpm",
                  "peakmaxrpm", "limitrpm"]:
            entry[k] = fval(fields, k)
        missing = [k for k in REQUIRED if entry.get(k) is None]
        non_literal = [k for k, t in fields.items()
                       if t[0] == 'raw' and k in REQUIRED + ["flywheelmass", "idlerpm"]]
        if missing or non_literal:
            unparsed.append(dict(base, missing=missing, non_literal=non_literal,
                                 reason="required field missing or non-literal"))
        engines.append(entry)
    return engines, unparsed


def count_grep(root):
    try:
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".pat", delete=False,
                                         encoding="utf-8") as pf:
            pf.write(GREP_PAT + "\n")
        try:
            out = subprocess.run(
                ["grep", "-rEh", "-f", pf.name, os.path.join(root, "lua"), "--include=*.lua"],
                capture_output=True, text=True, encoding="utf-8", errors="replace")
        finally:
            os.remove(pf.name)
        if out.returncode not in (0, 1):
            return None, "grep returned %d" % out.returncode
        return len([l for l in out.stdout.split("\n") if l.strip()]), "grep"
    except FileNotFoundError:
        return None, "grep not found"


def grep_only_lines(root, parsed_keys):
    """Lines the grep-style pattern matches that the parser did not turn into an entry."""
    rx = re.compile(GREP_PAT)
    extra = []
    lua_root = os.path.join(root, "lua")
    for dp, _, files in os.walk(lua_root):
        for fn in sorted(files):
            if not fn.endswith(".lua"):
                continue
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, root).replace("\\", "/")
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                for i, line in enumerate(f, 1):
                    if rx.match(line) and (rel, i) not in parsed_keys:
                        extra.append("%s:%d" % (rel, i))
    return extra


def fmt_size(s):
    return "x".join("%.1f" % v for v in s) if s else "-"


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    all_engines, all_unparsed = [], []
    counts = {}
    cache = {}
    grep_info = {}

    for addon, root in ADDONS:
        lua_root = os.path.join(root, "lua")
        addon_engines, addon_unparsed = [], []
        for dp, _, files in os.walk(lua_root):
            for fn in sorted(files):
                if not fn.endswith(".lua"):
                    continue
                e, u = scan_file(addon, root, os.path.join(dp, fn))
                addon_engines += e
                addon_unparsed += u
        for e in addon_engines:
            e.update(guess_layout(e))
            mdl = resolve_model(root, e["model"], cache) if e.get("model") else dict(MISSING_MDL)
            e.update(mdl)
            e["model_path_norm"] = (e["model"] or "").replace('\\', '/').lower() or None
        gcount, gnote = count_grep(root)
        grep_info[addon] = {"grep_line_matches": gcount, "grep_note": gnote}
        all_engines += addon_engines
        all_unparsed += addon_unparsed

    # Per-addon counts
    for addon, root in ADDONS:
        es = [e for e in all_engines if e["addon"] == addon]
        models = {e["model_path_norm"] for e in es if e["model_path_norm"]}
        owned = {e["model_path_norm"] for e in es if e.get("model_source") == "addon"}
        base_only = {e["model_path_norm"] for e in es if e.get("model_source") == "base"}
        missing = {e["model_path_norm"] for e in es
                   if e["model_path_norm"] and not e.get("model_exists")}
        counts[addon] = {
            "parser_engines": len(es),
            "grep_line_matches": grep_info[addon]["grep_line_matches"],
            "grep_note": grep_info[addon]["grep_note"],
            "unparsed": len([u for u in all_unparsed if u["addon"] == addon]),
            "layout_guessed": len([e for e in es if e["layout_source"]]),
            "layout_null": len([e for e in es if not e["layout_source"]]),
            "models_unique": len(models),
            "models_addon_owned": len(owned),
            "models_base_only": len(base_only),
            "models_missing": len(missing),
        }

    # Model clashes (addon-owned files only)
    owned_md5 = defaultdict(lambda: defaultdict(set))
    for e in all_engines:
        if e.get("model_source") == "addon":
            owned_md5[e["model_path_norm"]][e["addon"]].add(e["mdl_md5"])
    model_clashes, model_shared_identical = [], []
    for mp in sorted(owned_md5):
        per = owned_md5[mp]
        if len(per) < 2:
            continue
        all_md5 = set().union(*per.values())
        rec = {"model": mp,
               "addons": {a: sorted(v) for a, v in per.items()}}
        if len(all_md5) > 1:
            model_clashes.append(rec)
        else:
            model_shared_identical.append(rec)

    # Engine id clashes across addons, and within-addon duplicates
    by_id = defaultdict(lambda: defaultdict(list))
    for e in all_engines:
        by_id[e["id"]][e["addon"]].append(e)
    id_clashes = []
    dup_within = []
    for eid in sorted(by_id):
        per = by_id[eid]
        if len(per) > 1:
            id_clashes.append({"id": eid, "addons": sorted(per.keys()),
                               "names": {a: [x.get("name") for x in v] for a, v in per.items()}})
        for a, v in per.items():
            if len(v) > 1:
                dup_within.append({"id": eid, "addon": a, "count": len(v)})

    result = {
        "sources": [{"addon": a, "root": r} for a, r in ADDONS],
        "base_game": BASE,
        "counts": counts,
        "engine_count_total": len(all_engines),
        "unparsed_total": len(all_unparsed),
        "model_clashes": model_clashes,
        "model_shared_identical": model_shared_identical,
        "id_clashes": id_clashes,
        "duplicate_ids_within_addon": dup_within,
        "unparsed": all_unparsed,
        "engines": all_engines,
    }
    json_path = os.path.join(OUT_DIR, "model_inventory.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=1, ensure_ascii=False)

    md = []
    md.append("# Engine model inventory\n")
    md.append("Sources: ACE, ACF-Extra, ACF Customs (see model_inventory.json for paths).\n")
    md.append("## Counts per addon\n")
    md.append("| addon | parser defs | grep defs (line match) | unparsed | layout guessed | layout null | models unique | owned mdl | base-only mdl | missing mdl |")
    md.append("|---|---|---|---|---|---|---|---|---|---|")
    for addon, _ in ADDONS:
        c = counts[addon]
        md.append("| %s | %d | %s | %d | %d | %d | %d | %d | %d | %d |" % (
            addon, c["parser_engines"], c["grep_line_matches"], c["unparsed"],
            c["layout_guessed"], c["layout_null"], c["models_unique"],
            c["models_addon_owned"], c["models_base_only"], c["models_missing"]))
    md.append("")
    md.append("Grep-only lines (matched by the line pattern, not parsed as an engine; "
              "normally commented-out code):\n")
    for addon, root in ADDONS:
        keys = {(e["file"], e["line"]) for e in all_engines if e["addon"] == addon}
        extra = grep_only_lines(root, keys)
        md.append("- %s: %s" % (addon, ", ".join(extra) if extra else "none"))
    md.append("")
    md.append("Base game root %s: no loose models/ folder found, so base-game lookups returned nothing; "
              "missing counts are addon-only.\n" % BASE)
    md.append("Grep note: " + "; ".join("%s: %s" % (a, counts[a]["grep_note"]) for a, _ in ADDONS) + "\n")
    md.append("## Model clashes (same path, different md5, addon-owned)\n")
    if not model_clashes:
        md.append("None.\n")
    for c in model_clashes:
        md.append("- `%s`: %s" % (c["model"], "; ".join(
            "%s=%s" % (a, ",".join(m[:8] for m in v)) for a, v in c["addons"].items())))
    md.append("")
    md.append("Same path, same md5 in more than one addon: %d\n" % len(model_shared_identical))
    md.append("## Engine id clashes across addons\n")
    if not id_clashes:
        md.append("None.\n")
    for c in id_clashes:
        md.append("- `%s`: %s" % (c["id"], ", ".join(c["addons"])))
    md.append("")
    md.append("Duplicate ids within one addon: %d\n" % len(dup_within))
    md.append("## Unparsed (%d)\n" % len(all_unparsed))
    for u in all_unparsed:
        md.append("- %s `%s` %s:%d - %s missing=%s non_literal=%s" % (
            u["addon"], u["id"], u["file"], u["line"], u["reason"],
            u.get("missing", []), u.get("non_literal", [])))
    md.append("")
    md.append("## Engines\n")
    md.append("| id | addon | layout | cyl | model | size_mm (x y z) |")
    md.append("|---|---|---|---|---|---|")
    for e in all_engines:
        md.append("| %s | %s | %s | %s | %s | %s |" % (
            e["id"], e["addon"], e["layout"] or "-",
            "-" if e["cylinders"] is None else e["cylinders"],
            e["model"] or "-", fmt_size(e["size_mm"])))
    md_path = os.path.join(OUT_DIR, "model_inventory.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")

    print(json.dumps({"counts": counts, "engine_total": len(all_engines),
                      "unparsed": len(all_unparsed),
                      "model_clashes": len(model_clashes),
                      "id_clashes": len(id_clashes)}, indent=1))
    print("wrote", json_path)
    print("wrote", md_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
