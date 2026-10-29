#!/usr/bin/env bash
# Build native tvOS code only. No ROM or player data is read by this script.
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Xcode on macOS is required.' >&2; exit 2; }
runtime_root=$(cd "$(dirname "$0")/.." && pwd)
runtime_ship="$runtime_root/build/upstream/Shipwright"
runtime_torch="$runtime_root/build/upstream/Torch"
runtime_lus="$runtime_root/build/upstream/libultraship"
[[ $(git -C "$runtime_torch" rev-parse HEAD) == 2ab12fe9660aec04e02ee89fe81baed304a1a1d6 &&
   -z $(git -C "$runtime_torch" status --porcelain) ]] || { echo 'Use the clean pinned Torch checkout.' >&2; exit 2; }
python3 "$runtime_root/scripts/prepare-shipwright-metal.py" "$runtime_lus"
python3 "$runtime_root/scripts/prepare-shipwright-game.py" "$runtime_ship"
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
        cmake -S "$runtime_root/experiments/shipwright/simulator-game" -B "$runtime_build" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_SYSTEM_NAME=tvOS \
            -DCMAKE_OSX_SYSROOT="$runtime_platform" -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_FIND_ROOT_PATH="$runtime_sdk_path" \
            -DRECOMPTV_BUILD_RUNTIME_FRAMEWORK=ON \
            -DRECOMPTV_LUS_SOURCE="$runtime_root/build/shipwright-metal/source" \
            -DRECOMPTV_SHIPWRIGHT_SOURCE="$runtime_root/build/shipwright-game/source" \
            -DRECOMPTV_TORCH_SOURCE="$runtime_torch"
        cmake --build "$runtime_build" --target RecompTVShipwright --parallel 6
        runtime_framework="$runtime_build/NativecadeRuntime.framework"
        lipo "$runtime_framework/NativecadeRuntime" -verify_arch arm64
        otool -L "$runtime_framework/NativecadeRuntime" > "$runtime_build/dependencies.txt"
        if grep -Eq '(AppKit|Cocoa|OpenGL|OpenGLES)\.framework' "$runtime_build/dependencies.txt"; then
            echo 'An unsupported graphics framework entered the runtime.' >&2; exit 1
        fi
        "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil" \
            "$runtime_framework/NativecadeRuntime" -o "$runtime_build/NativecadeRuntime.framework.dSYM"
    done
done
python3 "$runtime_root/scripts/package-nativecade-runtime.py"
