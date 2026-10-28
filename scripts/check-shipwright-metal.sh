#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 || ! ($1 == arm64 || $1 == x86_64) ]]; then
    echo 'Usage: bash scripts/check-shipwright-metal.sh arm64|x86_64 LIBULTRASHIP_CHECKOUT' >&2
    exit 2
fi
[[ $(uname -s) == Darwin ]] || { echo 'This build requires macOS and the tvOS SDK.' >&2; exit 2; }
probe_arch=$1
probe_source=$(cd "$2" && pwd)
probe_root=$(cd "$(dirname "$0")/.." && pwd)
probe_build="$probe_root/build/shipwright-metal/simulator-$probe_arch"
python3 "$probe_root/scripts/prepare-shipwright-metal.py" "$probe_source"
cmake -S "$probe_root/experiments/shipwright/metal" -B "$probe_build" \
    -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Debug \
    -DRECOMPTV_LUS_SOURCE="$probe_root/build/shipwright-metal/source" \
    -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT=appletvsimulator \
    -DCMAKE_OSX_ARCHITECTURES="$probe_arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$probe_build" --target shipwright_metal_link --parallel 3
python3 "$probe_root/scripts/verify-shipwright-metal-build.py" "$probe_build"
IFS= read -r probe_binary < "$probe_build/link-probe-path.txt"
lipo -verify_arch "$probe_arch" "$probe_binary"
otool -L "$probe_binary" > "$probe_build/dependencies.txt"
cat "$probe_build/dependencies.txt"
if grep -Eq '(AppKit|Cocoa|OpenGL|OpenGLES)\.framework' "$probe_build/dependencies.txt"; then
    echo 'error: Desktop/OpenGL framework leaked into the tvOS Metal link.' >&2
    exit 1
fi
echo "libultraship services and Metal backend compiled and linked for tvOS Simulator $probe_arch. No GPU execution attempted."
