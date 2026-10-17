"""Runs engine_dump.lua on the gmodkit server and copies the JSON out.

usage: python run_engine_dump.py <output.json>
Needs the server up with the engines-p1 profile (python -m gmodkit up engines-p1, run from
E:/GMODDS/gmodkit). Reports the Lua error count the server has logged.
"""
import json, shutil, subprocess, sys, time
from pathlib import Path

KIT = Path("E:/GMODDS/gmodkit")
SCRIPT = Path(__file__).with_name("engine_dump.lua")
DATA = Path("E:/GMODDS/server/garrysmod/data/ace_engine_dump.json")


def kit(*args):
    r = subprocess.run([sys.executable, "-m", "gmodkit", *args], cwd=KIT, capture_output=True, text=True)
    return r.stdout + r.stderr


def main(out):
    kit("lua", "--file", str(SCRIPT))
    for _ in range(120):
        time.sleep(3)
        status = json.loads(kit("lua", "return ENGINE_DUMP_STATUS"))[0]
        if status != "running":
            break
    if status != "done":
        sys.exit("dump did not finish: " + status)
    shutil.copyfile(DATA, out)
    print("saved", out, DATA.stat().st_size, "bytes")
    print(kit("errors").strip().splitlines()[-1])


if __name__ == "__main__":
    main(sys.argv[1])
