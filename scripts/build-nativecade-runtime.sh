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
            -DRECOMPTV_STARSHIP_SOURCE="$runtime_root/build/starship/source"
        cmake --build "$runtime_build" --target NativecadeSpaghetti NativecadeStarship --parallel "${NATIVECADE_BUILD_JOBS:-4}"
        for runtime_relative in NativecadeRuntime.framework spaghettikart/NativecadeSpaghetti.framework \
                starship/NativecadeStarship.framework; do
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
