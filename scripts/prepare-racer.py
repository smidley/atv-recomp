"""Prepare the pinned Star Wars Episode I: Racer recompilation for tvOS without reading any game ROM.

upstream/racer-baseline.json pins Racer and the runtime, renderer and recompiler forks it builds
with. This copies them to build/racer/source, applies the tvOS changes Racer shares with Shadows of
the Empire (rt64_tvos.py) and its own, and writes the tables experiments/n64interp runs the game's
code with. Racer's own build turns that code into C from the ROM; Nativecade interprets it from
the ROM in memory instead, so nothing here comes from a ROM.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess

import rt64_tvos

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/racer-baseline.json").read_text())
checkouts = {name: root / "build/upstream" / source.get("checkout", source["repository"].split("/")[1])
             for name, source in pin["sources"].items()}


def git(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, text=True).strip()


for name, path in checkouts.items():
    if git(path, "rev-parse", "HEAD") != pin["sources"][name]["revision"]:
        raise SystemExit(f"{path} doesn't match its pin; run scripts/upstream.py fetch.")
    if git(path, "status", "--porcelain"):
        raise SystemExit(f"Preserve {path}'s local edits before preparing a generated copy.")

# Only what the tvOS build compiles. The N64Recomp checkout is read for its lists of the libultra
# functions the runtime replaces; librecomp builds the runtime's own N64Recomp submodule.
for base, table in ((checkouts["rt64"], rt64_tvos.RT64_SUBMODULES),
                    (checkouts["N64ModernRuntime"], rt64_tvos.RUNTIME_SUBMODULES),
                    (checkouts["N64ModernRuntime"] / "N64Recomp", rt64_tvos.N64RECOMP_SUBMODULES)):
    for parent, paths in table.items():
        subprocess.check_call(["git", "submodule", "--quiet", "update", "--init", "--depth", "1", *paths],
                              cwd=base / parent)

destination = root / "build/racer/source"
if destination.exists():
    shutil.rmtree(destination)
(destination / "racer").mkdir(parents=True)
# Clones share the checkouts' blocks until a file changes, and keeping modification times means a
# build only recompiles what the changes below touch.
racer = checkouts["racer"]
for name in ("src", "frontend", "recomp.toml", "symbols.toml", "LICENSE"):
    subprocess.check_call(["cp", "-cRp", str(racer / name), str(destination / "racer" / name)])
for name in ("N64ModernRuntime", "rt64"):
    subprocess.check_call(["cp", "-cRp", str(checkouts[name]), str(destination / name)])
# Git metadata in the copy would point back at the checkouts' submodules.
for marker in destination.rglob(".git"):
    shutil.rmtree(marker) if marker.is_dir() else marker.unlink()

rt64_tvos.adapt(destination / "rt64", destination / "N64ModernRuntime", "RECOMPTV_RACER", "prepare-racer.py")
rt64_tvos.apply(destination / "racer/frontend", rt64_tvos.FRONTEND, "prepare-racer.py")

# Tables for experiments/n64interp, from Racer's configuration and symbol file. Its section table
# (src/section_table.cpp, which its main.cpp registers) also names the functions N64Recomp split off
# at calls into other functions, and tools/post_recomp_patches.py sends two functions to host code.
table = (racer / "src/section_table.cpp").read_text()
base = int(re.search(r"(0x[0-9A-Fa-f]+),\s*// ram_addr", table).group(1), 16)
extras = [f"{name}@{base + int(offset, 16):X}"
          for name, offset in re.findall(r"\{ (\w+), (0x[0-9A-Fa-f]+), 0x[0-9A-Fa-f]+ \}", table)]
patches = (racer / "tools/post_recomp_patches.py").read_text()
redirects = re.findall(r'"(\w+)":\s*"(\w+)"', re.search(r"REDIRECTS = \{(.*?)\n\}", patches, re.S).group(1))
subprocess.check_call(["python3", str(root / "scripts/generate-n64interp.py"), str(destination / "racer/recomp.toml"),
                       str(checkouts["N64Recomp"]), str(destination / "interpreter"),
                       *[f"{name}={target}" for name, target in redirects], *extras])
print(f"Prepared Star Wars Episode I: Racer {pin['release']} in {destination.relative_to(root)}")
