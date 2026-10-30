"""Create distributable support files exclusively from the pinned open-source trees.

This script deliberately has no ROM path argument and never reads LocalData.
"""
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
release = json.loads((root / "upstream/shipwright-baseline.json").read_text())["release"]
kart_release = json.loads((root / "upstream/spaghettikart-baseline.json").read_text())["release"]
fox_release = json.loads((root / "upstream/starship-baseline.json").read_text())["release"]
mario_release = json.loads((root / "upstream/ghostship-baseline.json").read_text())["release"]
banjo_release = json.loads((root / "upstream/lighthouse-baseline.json").read_text())["release"]
ship = root / "build/upstream/Shipwright"
torch = root / "build/upstream/Torch"
lus = root / "build/upstream/libultraship"
host = root / "build/shipwright-tools"
output = root / "build/nativecade-runtime/NativecadeGame"
stage = root / "build/nativecade-runtime/port-assets"
subprocess.run(["cmake", "-S", str(root / "experiments/shipwright/host-tools"), "-B", str(host),
    "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", f"-DRECOMPTV_SHIPWRIGHT_SOURCE={ship}",
    f"-DRECOMPTV_TORCH_SOURCE={torch}"], check=True)
subprocess.run(["cmake", "--build", str(host), "--target", "soh-o2r-packer", "--parallel", "5"], check=True)
if stage.exists():
    shutil.rmtree(stage)
shutil.copytree(ship / "soh/assets/custom", stage)
shutil.copytree(lus / "src/fast/shaders", stage / "shaders", dirs_exist_ok=True)
output.mkdir(parents=True, exist_ok=True)
subprocess.run([str(host / "soh-o2r-packer"), str(stage), str(output / "soh.o2r"), release], check=True)
with zipfile.ZipFile(output / "soh.o2r") as archive:
    assert archive.testzip() is None, "Port support archive failed its CRC check"
    # One byte, then big-endian major, minor and patch: 9.3.1 is 01 0009 0003 0001.
    expected = bytes([1]) + b"".join(int(part).to_bytes(2, "big") for part in release.split("."))
    assert archive.read("portVersion") == expected, "Incorrect port version"
definitions = output / "yml"
if definitions.exists():
    shutil.rmtree(definitions)
shutil.copytree(ship / "soh/assets/yml", definitions)
notices = [f"Nativecade uses Shipwright {release}, SpaghettiKart {kart_release}, Starship {fox_release}, "
           f"Ghostship {mario_release}, Lighthouse {banjo_release}, Torch and libultraship.\n"
           "https://github.com/HarbourMasters/Shipwright\n"
           "https://github.com/HarbourMasters/SpaghettiKart\n"
           "https://github.com/HarbourMasters/Starship\n"
           "https://github.com/HarbourMasters/Ghostship\n"
           "https://github.com/HarbourMasters/Lighthouse\n"
           "https://github.com/HarbourMasters/Torch\n"
           "https://github.com/HarbourMasters/libultraship\n"
           "https://github.com/JeodC/libultraship\n\n"
           "No game ROMs or extracted game content are included. Import a supported ROM to play.\n"
           "\nNativecade also uses Shadows of the Empire: Recompiled and Star Wars Episode I: Racer, with\n"
           "N64ModernRuntime (GPL-3.0), N64Recomp and RT64.\n"
           "https://github.com/GTTeancum/SotE-Recomp\n"
           "https://github.com/sp00nznet/racer\n"
           "\nSuper Smash Bros. runs through BattleShip, with its own libultraship and Torch.\n"
           "https://github.com/JRickey/BattleShip\n"
           "https://github.com/N64Recomp/N64ModernRuntime\n"
           "https://github.com/N64Recomp/N64Recomp\n"
           "https://github.com/rt64/rt64\n"]
seen = set()
for source in (ship, torch, lus, root / "build/upstream/SpaghettiKart", root / "build/upstream/Starship",
               root / "build/upstream/Ghostship", root / "build/upstream/Lighthouse", root / "build/upstream/SotE-Recomp",
               root / "build/upstream/racer", root / "build/upstream/racer-toolkits", root / "build/upstream/BattleShip",
               host / "_deps", root / "build/nativecade-runtime/appletvsimulator/_deps",
               root / "build/nativecade-runtime/appletvos/_deps"):
    if not source.exists():
        continue
    for path in sorted(source.rglob("*")):
        if not path.is_file() or ".git" in path.parts:
            continue
        # Bundled fonts carry their SIL Open Font License as NAME-OFL.txt (BattleShip's).
        if not path.name.lower().startswith(("license", "licence", "copying", "notice")) and not path.name.endswith("-OFL.txt"):
            continue
        if path.stat().st_size > 300_000:
            continue
        try:
            contents = path.read_text()
        except UnicodeError:
            continue
        if contents in seen:
            continue
        seen.add(contents)
        notices.append(f"\n--- {source.name}/{path.relative_to(source)} ---\n{contents}\n")
(output / "ThirdPartyNotices.txt").write_text("\n".join(notices))
for path in output.rglob("*"):
    if path.is_file() and (path.suffix.lower() in {".z64", ".v64", ".n64", ".rom", ".romdata", ".sav"} or
                           path.name in {"oot.o2r", "oot-mq.o2r", "oot.otr", "oot-mq.otr", "mk64.o2r", "mk64.otr",
                                         "sf64.o2r", "sf64.otr", "sm64.o2r", "sm64.otr",
                                         "bk.o2r", "bk.otr"}):
        raise SystemExit(f"Refusing to distribute private game data: {path}")
print(f"Prepared open-source game support files: {output}")
