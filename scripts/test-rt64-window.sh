#!/usr/bin/env bash
set -euo pipefail
probe_root=$(cd "$(dirname "$0")/.." && pwd)
probe_build=$(mktemp -d)
trap 'rm -rf "$probe_build"' EXIT
"${CXX:-c++}" -std=c++20 -pthread -Wall -Wextra -Werror -pedantic \
    "$probe_root/experiments/rt64-metal/TVWindow.cpp" \
    "$probe_root/experiments/rt64-metal/WindowStateTests.cpp" \
    -o "$probe_build/window-tests"
"$probe_build/window-tests"
