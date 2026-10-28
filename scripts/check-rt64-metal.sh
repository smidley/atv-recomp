#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! ($1 == arm64 || $1 == x86_64) ]]; then
    echo 'Usage: bash scripts/check-rt64-metal.sh arm64|x86_64 RT64_CHECKOUT' >&2
    exit 2
fi
[[ $(uname -s) == Darwin ]] || { echo 'This experiment requires macOS and Xcode.' >&2; exit 2; }
probe_arch=$1
probe_source=$(cd "$2" && pwd)
probe_root=$(cd "$(dirname "$0")/.." && pwd)
probe_build="$probe_root/build/rt64-metal/simulator-$probe_arch"

python3 "$probe_root/scripts/prepare-rt64-metal.py" "$probe_source"
cmake -S "$probe_root/experiments/rt64-metal" -B "$probe_build" \
    -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Debug \
    -DRECOMPTV_RT64_SOURCE="$probe_source" \
    -DRECOMPTV_RT64_PATCHED="$probe_root/build/rt64-metal/source" \
    -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT=appletvsimulator \
    -DCMAKE_OSX_ARCHITECTURES="$probe_arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
cmake --build "$probe_build" --target rt64_metal_link --parallel 2

# A successful archive alone can hide unresolved desktop dependencies. Require
# the executable link, then inspect its actual framework dependencies.
IFS= read -r probe_binary < "$probe_build/link-probe-path.txt"
[[ -f "$probe_binary" ]] || { echo "error: Linked fixture is missing: $probe_binary" >&2; exit 1; }
otool -L "$probe_binary" > "$probe_build/dependencies.txt"
cat "$probe_build/dependencies.txt"
if grep -q 'AppKit.framework\|SDL' "$probe_build/dependencies.txt"; then
    echo 'error: Desktop framework leaked into the tvOS renderer link.' >&2
    exit 1
fi
echo "RT64 Metal backend compiled and linked for tvOS Simulator $probe_arch; execution not attempted."
