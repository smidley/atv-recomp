#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 3 ]]; then
    echo 'Usage: bash scripts/check-shipwright-game.sh SHIPWRIGHT_CHECKOUT TORCH_CHECKOUT LIBULTRASHIP_CHECKOUT' >&2
    exit 2
fi
[[ $(uname -s) == Darwin ]] || { echo 'This experiment requires a Mac.' >&2; exit 2; }
game_root=$(cd "$(dirname "$0")/.." && pwd)
game_ship=$(cd "$1" && pwd)
game_torch=$(cd "$2" && pwd)
game_lus=$(cd "$3" && pwd)
game_sdk="$(xcode-select -p)/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator.sdk"
game_build="$game_root/build/shipwright-game/simulator-arm64"
game_torch_pin=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["sources"]["torch"]["revision"])' \
    "$game_root/upstream/shipwright-baseline.json")
[[ $(git -C "$game_torch" rev-parse HEAD) == "$game_torch_pin" ]] || {
    echo 'Wrong Torch revision.' >&2; exit 2;
}
[[ -z $(git -C "$game_torch" status --porcelain) ]] || {
    echo 'Torch checkout has local changes.' >&2; exit 2;
}
python3 "$game_root/scripts/prepare-shipwright-metal.py" "$game_lus"
python3 "$game_root/scripts/prepare-shipwright-game.py" "$game_ship"
cmake -S "$game_root/experiments/shipwright/simulator-game" -B "$game_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=tvOS \
    -DCMAKE_OSX_SYSROOT=appletvsimulator -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_FIND_ROOT_PATH="$game_sdk" \
    -DRECOMPTV_LUS_SOURCE="$game_root/build/shipwright-metal/source" \
    -DRECOMPTV_SHIPWRIGHT_SOURCE="$game_root/build/shipwright-game/source" \
    -DRECOMPTV_TORCH_SOURCE="$game_torch"
cmake --build "$game_build" --target RecompTVShipwright --parallel 6
game_binary="$game_build/RecompTVShipwright.app/RecompTVShipwright"
lipo "$game_binary" -verify_arch arm64
otool -L "$game_binary" > "$game_build/dependencies.txt"
if grep -Eq '(AppKit|Cocoa|OpenGL|OpenGLES)\.framework' "$game_build/dependencies.txt"; then
    echo 'Desktop/OpenGL framework leaked into the simulator game.' >&2
    exit 1
fi
echo "Built simulator experiment: $game_build/RecompTVShipwright.app"
echo 'Supply locally prepared assets before installation; see docs/SHIPWRIGHT_SIMULATOR_GAME.md.'
