"""Check the compiled source set and the actual FetchContent dependency revisions.

After reviewing a libultraship update, pass --record to pin what this build fetched.
"""

import datetime
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
build = Path(sys.argv[1]).resolve(strict=True)


def head(checkout):
    return subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()


commands = json.loads((build / "compile_commands.json").read_text())
sources = [entry["file"] for entry in commands]
for required in ("/fast/backends/gfx_metal.cpp", "/fast/backends/gfx_metal_shader.cpp",
                 "/ship/Context.cpp", "/ship/resource/ResourceManager.cpp"):
    if not any(path.endswith(required) for path in sources):
        raise SystemExit(f"error: Required libultraship source was not compiled: {required}")
for path in sources:
    if "/scripting/" in path or "/tinycc" in path:
        raise SystemExit(f"error: Runtime scripting entered the simulator build: {path}")
manifest_path = root / "upstream/libultraship-simulator.json"
manifest = json.loads(manifest_path.read_text())
pinned = json.loads((root / "upstream/lighthouse-baseline.json").read_text())["sources"]["libultraship"]["revision"]
if "--record" in sys.argv[2:]:
    previous = {dependency["name"]: dependency for dependency in manifest["dependencies"]}
    recorded = []
    for checkout in sorted((build / "_deps").glob("*-src")):
        if not (checkout / ".git").exists():
            continue
        name, revision = checkout.name.removesuffix("-src"), head(checkout)
        url = subprocess.check_output(["git", "-C", str(checkout), "remote", "get-url", "origin"], text=True).strip()
        old = previous.get(name, {})
        recorded.append({"name": name, "repository": url.removeprefix("https://github.com/").removesuffix(".git"),
                         "upstream_ref": old["upstream_ref"] if old.get("revision") == revision else revision,
                         "revision": revision})
    manifest.update(recorded_on=datetime.date.today().isoformat(), libultraship_revision=pinned, dependencies=recorded)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Recorded {len(recorded)} dependency pins for libultraship {pinned[:12]}; review and commit {manifest_path.name}.")
if manifest["libultraship_revision"] != pinned:
    raise SystemExit("error: libultraship changed since its dependency pins were recorded. Review the dependency "
                     "changes, then rerun scripts/check-shipwright-metal.sh with --record-dependencies.")
for dependency in manifest["dependencies"]:
    actual = head(build / "_deps" / (dependency["name"] + "-src"))
    if actual != dependency["revision"]:
        raise SystemExit(f"error: Dependency revision mismatch: {dependency['name']} is {actual}, "
                         f"pinned {dependency['revision']}")
print(f"Verified {len(commands)} compiled sources and {len(manifest['dependencies'])} dependency pins.")
