#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo 'Usage: bash scripts/check-runtime-core.sh host|simulator RUNTIME_CHECKOUT [arm64|x86_64]' >&2
    exit 2
fi

probe_target=$1
probe_source=$(cd "$2" && pwd)
probe_arch=${3:-$(uname -m)}
probe_root=$(cd "$(dirname "$0")/.." && pwd)

case "$probe_target" in
    host) [[ $# -eq 2 ]] || { echo 'Host mode uses the native architecture.' >&2; exit 2; } ;;
    simulator)
        [[ $(uname -s) == Darwin ]] || { echo 'Simulator compilation requires macOS and Xcode.' >&2; exit 2; }
        [[ $probe_arch == arm64 || $probe_arch == x86_64 ]] || { echo 'Use arm64 or x86_64.' >&2; exit 2; }
        ;;
    *) echo 'Choose host or simulator.' >&2; exit 2 ;;
esac

python3 "$probe_root/scripts/verify-runtime-source.py" "$probe_source"
probe_build="$probe_root/build/runtime-core/$probe_target-$probe_arch"
probe_options=(-DRECOMPTV_RUNTIME_SOURCE="$probe_source" -DCMAKE_BUILD_TYPE=Debug)
if [[ $probe_target == simulator ]]; then
    probe_options+=(
        -DCMAKE_SYSTEM_NAME=tvOS
        -DCMAKE_OSX_SYSROOT=appletvsimulator
        -DCMAKE_OSX_ARCHITECTURES="$probe_arch"
        -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    )
fi

run_probe() {
    cmake -S "$probe_root/experiments/runtime-core" -B "$probe_build" \
        -G 'Unix Makefiles' "${probe_options[@]}" || return $?
    cmake --build "$probe_build" --target runtime_callbacks --parallel 2 || return $?
    if [[ $probe_target == host ]]; then
        ctest --test-dir "$probe_build" --output-on-failure || return $?
    else
        echo "tvOS Simulator $probe_arch: core archive compiled and callback executable linked; execution not attempted."
    fi
}

probe_log=$(mktemp)
trap 'rm -f "$probe_log"' EXIT
set +e
run_probe 2>&1 | tee "$probe_log"
probe_status=${PIPESTATUS[0]}
set -e

# Keep the first compiler failure readable through GitHub's job-step API.
if [[ $probe_status -ne 0 && -n ${GITHUB_OUTPUT:-} ]]; then
    python3 - "$probe_log" <<'PY'
import os
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
errors = [line.strip() for line in lines if "error:" in line or "CMake Error" in line]
message = " | ".join(errors[:3]) or "Runtime probe failed; see build output"
with open(os.environ["GITHUB_OUTPUT"], "a") as output:
    output.write("diagnostic=" + message[:900].replace("\r", " ") + "\n")
PY
fi
exit "$probe_status"
