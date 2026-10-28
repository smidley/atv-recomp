#!/bin/sh
set -eu

task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build=$(mktemp -d "${TMPDIR:-/tmp}/recomptv-native.XXXXXX")
trap 'rm -rf "$task_build"' EXIT HUP INT TERM

"${CC:-cc}" -std=c17 -Wall -Wextra -Werror -pedantic \
    -I "$task_root/RecompTV/Native" \
    -c "$task_root/Tests/BridgeProbeTests.c" -o "$task_build/tests.o"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -pedantic \
    -c "$task_root/RecompTV/Native/BridgeProbe.cpp" -o "$task_build/probe.o"
"${CXX:-c++}" "$task_build/tests.o" "$task_build/probe.o" -o "$task_build/native-tests"
"$task_build/native-tests"
