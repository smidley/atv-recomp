"""Package upstream support files and extraction definitions, never a game ROM."""
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
source = root / "build/upstream/Lighthouse"
pin = json.loads((root / "upstream/lighthouse-baseline.json").read_text())
revision = pin["sources"]["lighthouse"]["revision"]
if subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() != revision:
    raise SystemExit("Use the pinned Lighthouse source.")
output = root / "build/nativecade-runtime/NativecadeGame/Lighthouse"
output.mkdir(parents=True, exist_ok=True)
# Upstream packs port/ with libultraship's shaders as lighthouse.o2r. The shaders come from the
# shared Metal backend, including its tvOS fixes.
files = {path.relative_to(source / "port").as_posix(): path for path in (source / "port").rglob("*") if path.is_file()}
shaders = root / "build/shipwright-metal/source/src/fast/shaders"
files.update({"shaders/" + path.relative_to(shaders).as_posix(): path
              for path in shaders.rglob("*") if path.is_file()})
with zipfile.ZipFile(output / "lighthouse.o2r", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name, path in sorted(files.items()):
        if path.suffix.lower() in {".z64", ".n64", ".v64", ".romdata", ".sav"}:
            raise SystemExit("Refusing to package private game data.")
        archive.write(path, name)
with zipfile.ZipFile(output / "lighthouse.o2r") as archive:
    assert archive.testzip() is None
# Torch reads config.yml and the extraction definitions it names. Lighthouse plays every
# retail release (USA 1.0 and 1.1, Europe, Japan), so all of them are shipped.
definitions = output / "assets"
if definitions.exists():
    shutil.rmtree(definitions)
shutil.copytree(source / "assets", definitions)
shutil.copy2(source / "config.yml", output / "config.yml")
(output / "Upstream.txt").write_text(
    f"Lighthouse {pin['release']} by HarbourMasters\nhttps://github.com/HarbourMasters/Lighthouse\n"
    + revision + "\nShared runtime dependencies and notices: ../ThirdPartyNotices.txt\n"
    "No Banjo-Kazooie ROM or extracted bk.o2r is included.\n")
print(f"Prepared Lighthouse support files: {output}")
