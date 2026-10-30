"""Package upstream support files and extraction definitions, never a game ROM."""
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
source = root / "build/upstream/Ghostship"
pin = json.loads((root / "upstream/ghostship-baseline.json").read_text())
revision = pin["sources"]["ghostship"]["revision"]
if subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() != revision:
    raise SystemExit("Use the pinned Ghostship source.")
output = root / "build/nativecade-runtime/NativecadeGame/Ghostship"
output.mkdir(parents=True, exist_ok=True)
# Upstream packs port/ as ghostship.o2r. Its shaders are replaced with the shared Metal
# backend's definitions, including tvOS fixes.
files = {path.relative_to(source / "port").as_posix(): path
         for path in (source / "port").rglob("*") if path.is_file() and "shaders" not in path.parts}
shaders = root / "build/shipwright-metal/source/src/fast/shaders"
files.update({"shaders/" + path.relative_to(shaders).as_posix(): path
              for path in shaders.rglob("*") if path.is_file()})
with zipfile.ZipFile(output / "ghostship.o2r", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name, path in sorted(files.items()):
        if path.suffix.lower() in {".z64", ".n64", ".v64", ".romdata", ".sav"}:
            raise SystemExit("Refusing to package private game data.")
        archive.write(path, name)
with zipfile.ZipFile(output / "ghostship.o2r") as archive:
    assert archive.testzip() is None
# Torch reads config.yml and the extraction definitions it names. Ghostship's game code is
# built for the US release, so only its definitions are shipped. The shared renderer reads
# fixed-point matrices, so they are extracted without GBI_FLOATS.
definitions = output / "assets/ymls/us"
if definitions.exists():
    shutil.rmtree(definitions)
shutil.copytree(source / "assets/ymls/us", definitions)
config = (source / "config.yml").read_text()
assert config.count("gbi_floats: true") == 2
(output / "config.yml").write_text(config.replace("gbi_floats: true", "gbi_floats: false"))
(output / "Upstream.txt").write_text(
    f"Ghostship {pin['release']} by HarbourMasters\nhttps://github.com/HarbourMasters/Ghostship\n"
    + revision + "\nShared runtime dependencies and notices: ../ThirdPartyNotices.txt\n"
    "No Super Mario 64 ROM or extracted sm64.o2r is included.\n")
print(f"Prepared Ghostship support files: {output}")
