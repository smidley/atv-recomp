"""Package upstream support files and extraction definitions, never a game ROM."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
source = root / "build/upstream/SpaghettiKart"
pin = json.loads((root / "upstream/spaghettikart-baseline.json").read_text())
if subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() != pin["sources"]["spaghettikart"]["revision"]:
    raise SystemExit("Use the pinned SpaghettiKart source.")
output = root / "build/nativecade-runtime/NativecadeGame/SpaghettiKart"
output.mkdir(parents=True, exist_ok=True)
files = {path.relative_to(source / "assets").as_posix(): path
         for path in (source / "assets").rglob("*") if path.is_file()}
# Match the shared Metal backend's shader definitions, including tvOS fixes.
shaders = root / "build/shipwright-metal/source/src/fast/shaders"
files.update({"shaders/" + path.relative_to(shaders).as_posix(): path
              for path in shaders.rglob("*") if path.is_file()})
with zipfile.ZipFile(output / "spaghetti.o2r", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name, path in sorted(files.items()):
        if path.suffix.lower() in {".z64", ".n64", ".v64", ".romdata", ".sav"}:
            raise SystemExit("Refusing to package private game data.")
        archive.write(path, name)
with zipfile.ZipFile(output / "spaghetti.o2r") as archive:
    assert archive.testzip() is None
    assert 'name="extended-assets"' in archive.read("mods.toml").decode()
for directory in ("yamls", "meta"):
    target = output / directory
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source / directory, target)
# Newer shared Torch treats 0x80 addresses as virtual segments before the older
# `vram` fallback. Preserve MK64's addresses, with their explicit ROM mapping.
# All three pinned definitions map RAM 0x80000000 to ROM 0x00000c00.
converted = 0
for definition in (output / "yamls").rglob("*.yml"):
    text = definition.read_text()
    match = re.search(r"  vram:\n    addr: (0x[0-9A-Fa-f]+)\n    offset: (0x[0-9A-Fa-f]+)", text)
    if not match:
        continue
    address, offset = (int(value, 0) for value in match.groups())
    assert address >> 24 == 0x80 and offset - (address & 0xffffff) == 0xc00
    assert "  segments:" not in text
    text = text[:match.end()] + "\n  segments:\n    - [0x80, 0xC00]" + text[match.end():]
    definition.write_text(text)
    converted += 1
assert converted == 3, "Review VRAM mappings when updating the pinned game."
(output / "include").mkdir(exist_ok=True)
shutil.copy2(source / "include/defines.h", output / "include/defines.h")
shutil.copy2(source / "config.yml", output / "config.yml")
(output / "Upstream.txt").write_text(
    f"SpaghettiKart {pin['release']} by HarbourMasters\nhttps://github.com/HarbourMasters/SpaghettiKart\n"
    + pin["sources"]["spaghettikart"]["revision"] + "\nShared runtime dependencies and notices: ../ThirdPartyNotices.txt\n"
    "No Mario Kart ROM or extracted mk64.o2r is included.\n")
print(f"Prepared SpaghettiKart support files: {output}")
