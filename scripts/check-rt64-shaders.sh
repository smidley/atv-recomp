#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: bash scripts/check-rt64-shaders.sh RT64_CHECKOUT' >&2; exit 2; }
[[ $(uname -s) == Darwin ]] || { echo 'Shader builds require macOS and Xcode.' >&2; exit 2; }
probe_source=$(cd "$1" && pwd)
probe_root=$(cd "$(dirname "$0")/.." && pwd)
probe_build="$probe_root/build/rt64-metal"
python3 "$probe_root/scripts/prepare-rt64-metal.py" "$probe_source"

# The converter is a native Mac program, in a separate CMake cache from tvOS.
cmake -S "$probe_root/experiments/rt64-metal/host-tools" -B "$probe_build/host-tools" \
    -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release \
    -DRECOMPTV_RT64_SOURCE="$probe_source" \
    -DRECOMPTV_RT64_PATCHED="$probe_build/source"
cmake --build "$probe_build/host-tools" --target rt64_spirv_cross_msl --parallel 2

case $(uname -m) in
    arm64) probe_dxc_arch=arm64 ;;
    x86_64) probe_dxc_arch=x64 ;;
    *) echo 'Unsupported Mac host architecture.' >&2; exit 2 ;;
esac
probe_dxc="$probe_source/src/contrib/dxc"
mkdir -p "$probe_build/shaders"
for probe_spec in 'FullScreenVS:VSMain:vs_6_3' 'TextureCopyPS:PSMain:ps_6_3' 'HistogramClearCS:CSMain:cs_6_3'; do
    IFS=: read -r probe_name probe_entry probe_profile <<< "$probe_spec"
    probe_output="$probe_build/shaders/$probe_name"
    probe_dxc_args=(-spirv -fspv-target-env=vulkan1.0 -fvk-use-dx-layout)
    [[ $probe_profile != vs_* ]] || probe_dxc_args+=(-fvk-invert-y)
    env DYLD_LIBRARY_PATH="$probe_dxc/lib/$probe_dxc_arch${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
        "$probe_dxc/bin/$probe_dxc_arch/dxc-macos" \
        "${probe_dxc_args[@]}" \
        -I "$probe_source/src" -E "$probe_entry" -T "$probe_profile" \
        "$probe_source/src/shaders/$probe_name.hlsl" -Fo "$probe_output.spv"
    "$probe_build/host-tools/rt64_spirv_cross_msl" "$probe_output.spv" "$probe_output.metal"
    xcrun --sdk appletvsimulator metal -target air64-apple-tvos17.0-simulator \
        -c "$probe_output.metal" -o "$probe_output.air"
    xcrun --sdk appletvsimulator metallib "$probe_output.air" -o "$probe_output.metallib"
    [[ -s $probe_output.metallib ]]
    echo "Built $probe_name: HLSL -> SPIR-V -> mobile MSL -> tvOS Simulator metallib."
done
