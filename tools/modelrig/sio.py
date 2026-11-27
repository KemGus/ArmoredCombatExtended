# Load SourceIO's pure-python library without Blender (skip the addon __init__).
import sys, types, os
_CANDIDATES = [
	r"C:\Users\dyer0\AppData\Roaming\Blender Foundation\Blender\5.2\scripts\addons\SourceIO",
	r"C:\Users\dyer0\AppData\Local\Temp\sio_repo",
	os.environ.get("SOURCEIO_PATH", ""),
]
ADDON = next((p for p in _CANDIDATES if p and os.path.isdir(os.path.join(p, "library"))), None)
assert ADDON, "SourceIO checkout not found - clone https://github.com/REDxEYE/SourceIO or set SOURCEIO_PATH"
pkg = types.ModuleType("SourceIO"); pkg.__path__ = [ADDON]; sys.modules["SourceIO"] = pkg
