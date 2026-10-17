"""P1 locked check: every top-level chunk of the original file must appear, byte-identical
(line endings and trailing whitespace ignored), in exactly one of the new files.

usage: python check_moves.py <original.lua> <new1.lua> [<new2.lua> ...] [--allow <name> ...]
Exit 0 = pass. --allow names a function whose body was deliberately changed (must be justified
in the implementer's report); it is reported but not failed.
"""
import re, sys

HEAD = re.compile(r'^(local\s+function|function)\s+([\w.:]+)')

def chunks(path):
    lines = [l.rstrip() for l in open(path, encoding='utf-8', errors='replace').read().replace('\r\n', '\n').split('\n')]
    funcs, loose, i = {}, [], 0
    while i < len(lines):
        m = HEAD.match(lines[i])
        if m:
            j = i
            while j < len(lines) and lines[j] != 'end' and not (j == i and lines[j].endswith(' end')):
                j += 1
            funcs.setdefault(m.group(2), []).append('\n'.join(lines[i:j + 1]))
            i = j + 1
            continue
        s = lines[i].strip()
        if s and not s.startswith('--'):
            loose.append(s)
        i += 1
    return funcs, loose

args = sys.argv[1:]
allow = set()
if '--allow' in args:
    k = args.index('--allow'); allow = set(args[k + 1:]); args = args[:k]
orig, new = args[0], args[1:]
of, ol = chunks(orig)
nf, nl = {}, []
for p in new:
    f, l = chunks(p)
    for k, v in f.items():
        nf.setdefault(k, []).extend(v)
    nl += l

bad = 0
for name, bodies in of.items():
    got = nf.get(name, [])
    for b in bodies:
        if b in got:
            got.remove(b)
        elif name in allow:
            print('ALLOWED CHANGE', name)
        else:
            print('MISSING OR CHANGED', name); bad += 1
for name, bodies in nf.items():
    for b in bodies:
        if name not in of or b not in of[name]:
            if name not in allow:
                print('EXTRA FUNCTION', name); bad += 1
rest = list(nl)
for s in ol:
    if s in rest:
        rest.remove(s)
    else:
        print('MISSING TOP-LEVEL LINE', s); bad += 1
for s in rest:
    print('NEW TOP-LEVEL LINE (review):', s)
print('functions:', sum(len(v) for v in of.values()), 'checked,', bad, 'problems')
sys.exit(1 if bad else 0)
