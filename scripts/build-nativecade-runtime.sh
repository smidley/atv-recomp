#!/usr/bin/env bash
# Build native tvOS code only. No ROM or player data is read by this script.
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Xcode on macOS is required.' >&2; exit 2; }
runtime_root=$(cd "$(dirname "$0")/.." && pwd)
runtime_ship="$runtime_root/build/upstream/Shipwright"
runtime_torch="$runtime_root/build/upstream/Torch"
runtime_lus="$runtime_root/build/upstream/libultraship"
python3 "$runtime_root/scripts/upstream.py" fetch
python3 "$runtime_root/scripts/prepare-shipwright-metal.py" "$runtime_lus"
python3 "$runtime_root/scripts/prepare-shipwright-game.py" "$runtime_ship"
python3 "$runtime_root/scripts/prepare-spaghettikart.py"
python3 "$runtime_root/scripts/prepare-starship.py"
python3 "$runtime_root/scripts/prepare-ghostship.py"
python3 "$runtime_root/scripts/prepare-lighthouse.py"
# Shadows of the Empire runs its game code and audio microcode through experiments/n64interp from
# the player's ROM (docs/SOTE.md), so its build reads no ROM either.
python3 "$runtime_root/scripts/prepare-sote.py"
cmake -S "$runtime_root/experiments/sote/host-tools" -B "$runtime_root/build/sote/rt64-host-tools" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DRECOMPTV_SOTE_SOURCE="$runtime_root/build/sote/source"
cmake --build "$runtime_root/build/sote/rt64-host-tools"
# Star Wars Episode I: Racer runs the same way (docs/RACER.md). Its runtime and renderer are other
# versions of SotE's, so it builds as its own project, with shader tools from its own RT64.
python3 "$runtime_root/scripts/prepare-racer.py"
cmake -S "$runtime_root/experiments/sote/host-tools" -B "$runtime_root/build/racer/rt64-host-tools" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DRECOMPTV_RT64_SOURCE="$runtime_root/build/racer/source/rt64"
cmake --build "$runtime_root/build/racer/rt64-host-tools"
# Super Smash Bros. (BattleShip) builds with its own libultraship and Torch forks (docs/BATTLESHIP.md);
# its support files go with the other games' into the app's NativecadeGame folder.
python3 "$runtime_root/scripts/prepare-battleship.py" "$runtime_root/build/nativecade-runtime/NativecadeGame/BattleShip"
for runtime_sdk in "${@:-appletvsimulator appletvos}"; do
    # The default contains both SDKs; explicit arguments can build one at a time.
    for runtime_platform in $runtime_sdk; do
        case "$runtime_platform" in
            appletvos) runtime_platform_folder=AppleTVOS ;;
            appletvsimulator) runtime_platform_folder=AppleTVSimulator ;;
            *) echo 'Supported SDKs: appletvos appletvsimulator' >&2; exit 2 ;;
        esac
        runtime_build="$runtime_root/build/nativecade-runtime/$runtime_platform"
        runtime_sdk_path="$(xcode-select -p)/Platforms/$runtime_platform_folder.platform/Developer/SDKs/$runtime_platform_folder.sdk"
        # CMake caches framework and zlib paths inside the versioned SDK, which an Xcode update replaces.
        runtime_fresh=
        if [[ -f "$runtime_build/CMakeCache.txt" ]] &&
                ! grep -qF "$(xcrun --sdk "$runtime_platform" --show-sdk-path)" "$runtime_build/CMakeCache.txt"; then
            runtime_fresh=--fresh
        fi
        cmake $runtime_fresh -S "$runtime_root/experiments/shipwright/simulator-game" -B "$runtime_build" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_SYSTEM_NAME=tvOS \
            -DCMAKE_OSX_SYSROOT="$runtime_platform" -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_FIND_ROOT_PATH="$runtime_sdk_path" \
            -DRECOMPTV_BUILD_RUNTIME_FRAMEWORK=ON \
            -DRECOMPTV_LUS_SOURCE="$runtime_root/build/shipwright-metal/source" \
            -DRECOMPTV_SHIPWRIGHT_SOURCE="$runtime_root/build/shipwright-game/source" \
            -DRECOMPTV_TORCH_SOURCE="$runtime_torch" \
            -DRECOMPTV_SPAGHETTIKART_SOURCE="$runtime_root/build/spaghettikart/source" \
            -DRECOMPTV_STARSHIP_SOURCE="$runtime_root/build/starship/source" \
            -DRECOMPTV_GHOSTSHIP_SOURCE="$runtime_root/build/ghostship/source" \
            -DRECOMPTV_LIGHTHOUSE_SOURCE="$runtime_root/build/lighthouse/source" \
            -DRECOMPTV_SOTE_SOURCE="$runtime_root/build/sote/source" -DRECOMPTV_SOTE_HOST_TOOLS="$runtime_root/build/sote/rt64-host-tools"
        # Code generated from a ROM (scripts/generate-sote-code.sh) may be compiled into this Mac's
        # simulator builds to compare it with the interpreter, never into an Apple TV build.
        if [[ $runtime_platform == appletvos ]] && grep -q "build/sote/source/generated" "$runtime_build/build.ninja"; then
            echo 'Code generated from a ROM is in the Apple TV build.' >&2; exit 1
        fi
        cmake --build "$runtime_build" --target NativecadeSpaghetti NativecadeStarship NativecadeGhostship \
            NativecadeLighthouse NativecadeSote --parallel "${NATIVECADE_BUILD_JOBS:-4}"
        # Racer takes SDL from the shared runtime this SDK just built.
        cmake $runtime_fresh -S "$runtime_root/experiments/racer" -B "$runtime_build/racer" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_SYSTEM_NAME=tvOS \
            -DCMAKE_OSX_SYSROOT="$runtime_platform" -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_FIND_ROOT_PATH="$runtime_sdk_path" \
            -DRECOMPTV_RACER_SOURCE="$runtime_root/build/racer/source" -DRECOMPTV_RUNTIME_BUILD="$runtime_build" \
            -DRECOMPTV_RACER_HOST_TOOLS="$runtime_root/build/racer/rt64-host-tools"
        cmake --build "$runtime_build/racer" --target NativecadeRacer --parallel "${NATIVECADE_BUILD_JOBS:-4}"
        cmake $runtime_fresh -S "$runtime_root/experiments/battleship" -B "$runtime_build/battleship" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_SYSTEM_NAME=tvOS \
            -DCMAKE_OSX_SYSROOT="$runtime_platform" -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_FIND_ROOT_PATH="$runtime_sdk_path" \
            -DRECOMPTV_BATTLESHIP_SOURCE="$runtime_root/build/battleship/source" -DRECOMPTV_RUNTIME_BUILD="$runtime_build"
        cmake --build "$runtime_build/battleship" --target NativecadeBattleShip --parallel "${NATIVECADE_BUILD_JOBS:-4}"
        for runtime_relative in NativecadeRuntime.framework spaghettikart/NativecadeSpaghetti.framework \
                starship/NativecadeStarship.framework ghostship/NativecadeGhostship.framework \
                lighthouse/NativecadeLighthouse.framework sote/NativecadeSote.framework racer/NativecadeRacer.framework \
                battleship/NativecadeBattleShip.framework; do
        runtime_framework="$runtime_build/$runtime_relative"
        runtime_name=$(basename "$runtime_framework" .framework)
        lipo "$runtime_framework/$runtime_name" -verify_arch arm64
        otool -L "$runtime_framework/$runtime_name" > "$runtime_build/$runtime_name-dependencies.txt"
        if grep -Eq '(AppKit|Cocoa|OpenGL|OpenGLES)\.framework' "$runtime_build/$runtime_name-dependencies.txt"; then
            echo 'An unsupported graphics framework entered the runtime.' >&2; exit 1
        fi
        "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil" \
            "$runtime_framework/$runtime_name" -o "$runtime_framework.dSYM"
        done
    done
done
python3 "$runtime_root/scripts/package-nativecade-runtime.py"
