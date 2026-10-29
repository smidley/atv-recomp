#!/usr/bin/env bash
set -euo pipefail
perf_root=$(cd "$(dirname "$0")/.." && pwd)
perf_build="$perf_root/build/performance-tests"
mkdir -p "$perf_build"
clang++ -std=c++20 -Wall -Wextra -Werror \
    "$perf_root/experiments/shipwright/simulator-game/PerformanceSettingsTests.cpp" \
    -o "$perf_build/performance-settings-tests"
"$perf_build/performance-settings-tests"
echo 'Performance defaults, preset switching, and custom-setting preservation passed.'
