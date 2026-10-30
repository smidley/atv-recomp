#!/usr/bin/env bash
# Generate Shadows of the Empire's game code from the player's own ROM on this Mac.
# The output stays in build/sote/source/generated, which Git ignores; never commit or share it.
# build-nativecade-runtime.sh then compiles it into this Mac's runtime builds (docs/SOTE.md).
set -euo pipefail
[[ $# -eq 1 && -f $1 ]] || { echo 'Usage: scripts/generate-sote-code.sh PATH_TO_USA_REV_2_ROM' >&2; exit 2; }
rom=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
root=$(cd "$(dirname "$0")/.." && pwd)
source="$root/build/sote/source"
python3 "$root/scripts/prepare-sote.py"
# N64Recomp and RSPRecomp run on the Mac; the Python tools decompress the game's boot image.
cmake -S "$root/build/upstream/SotE-Recomp/third_party/N64Recomp" -B "$root/build/sote/host-tools" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/build/sote/host-tools" --target N64RecompCLI RSPRecomp
python3 -m pip install --quiet --target "$root/build/sote/python" -r "$source/tools/requirements.txt"
cd "$source"
# Rejects any ROM but the two dumps SotE-Recomp accepts (SHA-256).
PYTHONPATH="$root/build/sote/python" python3 tools/prepare_recomp_rom.py "$rom"
# N64Recomp splits its output by size, so remove the previous set first.
rm -rf generated/RecompiledFuncs
"$root/build/sote/host-tools/N64Recomp" sote.toml
"$root/build/sote/host-tools/RSPRecomp" config/aspMain.toml
python3 tools/patch_rsp_audio.py
echo "Generated Shadows of the Empire's code in ${source#"$root/"}/generated. Keep it on this Mac."
