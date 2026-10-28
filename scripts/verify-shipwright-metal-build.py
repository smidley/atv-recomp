"""Check the compiled source set and the actual FetchContent dependency revisions."""

import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
build = Path(sys.argv[1]).resolve(strict=True)
commands = json.loads((build / "compile_commands.json").read_text())
sources = [entry["file"] for entry in commands]
for required in ("/fast/backends/gfx_metal.cpp", "/fast/backends/gfx_metal_shader.cpp",
                 "/ship/Context.cpp", "/ship/resource/ResourceManager.cpp"):
    if not any(path.endswith(required) for path in sources):
        raise SystemExit(f"error: Required libultraship source was not compiled: {required}")
for path in sources:
    if "/scripting/" in path or "/tinycc" in path:
        raise SystemExit(f"error: Runtime scripting entered the simulator build: {path}")
manifest = json.loads((root / "upstream/libultraship-simulator.json").read_text())
for dependency in manifest["dependencies"]:
    checkout = build / "_deps" / (dependency["name"] + "-src")
    actual = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if actual != dependency["revision"]:
        raise SystemExit(f"error: Dependency revision mismatch: {dependency['name']}")
print(f"Verified {len(commands)} compiled sources and {len(manifest['dependencies'])} dependency pins.")
