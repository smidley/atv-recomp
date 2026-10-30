"""Package upstream support files and extraction definitions, never a game ROM."""
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
source = root / "build/upstream/Starship"
pin = json.loads((root / "upstream/starship-baseline.json").read_text())
if subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() != pin["sources"]["starship"]["revision"]:
    raise SystemExit("Use the pinned Starship source.")
output = root / "build/nativecade-runtime/NativecadeGame/Starship"
output.mkdir(parents=True, exist_ok=True)
# Upstream packs port/ as starship.o2r. Its shaders are replaced with the shared Metal
# backend's definitions, including tvOS fixes.
files = {path.relative_to(source / "port").as_posix(): path
         for path in (source / "port").rglob("*") if path.is_file() and "shaders" not in path.parts}
shaders = root / "build/shipwright-metal/source/src/fast/shaders"
files.update({"shaders/" + path.relative_to(shaders).as_posix(): path
              for path in shaders.rglob("*") if path.is_file()})
with zipfile.ZipFile(output / "starship.o2r", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name, path in sorted(files.items()):
        if path.suffix.lower() in {".z64", ".n64", ".v64", ".romdata", ".sav"}:
            raise SystemExit("Refusing to package private game data.")
        archive.write(path, name)
with zipfile.ZipFile(output / "starship.o2r") as archive:
    assert archive.testzip() is None
# Torch reads config.yml and the extraction definitions it names. Only the US
# releases are supported, so only their definitions are shipped.
definitions = output / "assets/yaml/us"
if definitions.exists():
    shutil.rmtree(definitions)
shutil.copytree(source / "assets/yaml/us", definitions)
shutil.copy2(source / "config.yml", output / "config.yml")
(output / "Upstream.txt").write_text(
    f"Starship {pin['release']} by HarbourMasters\nhttps://github.com/HarbourMasters/Starship\n"
    + pin["sources"]["starship"]["revision"] + "\nShared runtime dependencies and notices: ../ThirdPartyNotices.txt\n"
    "No Star Fox 64 ROM or extracted sf64.o2r is included.\n")
print(f"Prepared Starship support files: {output}")
