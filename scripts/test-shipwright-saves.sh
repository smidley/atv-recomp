#!/usr/bin/env bash
set -euo pipefail
saves_root=$(cd "$(dirname "$0")/.." && pwd)
saves_build="$saves_root/build/save-tests"
mkdir -p "$saves_build"
clang++ -std=c++20 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -DRECOMPTV_SAVE_TEST_MAIN \
    "$saves_root/experiments/shipwright/simulator-game/AppleTVSaveStore.mm" \
    "$saves_root/experiments/shipwright/simulator-game/SaveStoreTests.mm" \
    -framework Foundation -framework Security -lz -o "$saves_build/save-tests"
saves_port=$(mktemp "$saves_build/port.XXXXXX")
python3 "$saves_root/experiments/shipwright/simulator-game/save_test_server.py" "$saves_port" &
saves_server=$!
trap 'kill "$saves_server" 2>/dev/null || true; wait "$saves_server" 2>/dev/null || true; rm -f "$saves_port"' EXIT
for ((attempt=0;attempt<50;attempt++)); do
    [[ -s "$saves_port" ]] && break
    sleep 0.1
done
"$saves_build/save-tests" "http://127.0.0.1:$(cat "$saves_port")"
