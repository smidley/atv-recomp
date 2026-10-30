#!/usr/bin/env bash
set -euo pipefail
saves_root=$(cd "$(dirname "$0")/.." && pwd)
saves_build="$saves_root/build/save-tests"
mkdir -p "$saves_build"
clang++ -std=c++20 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -DRECOMPTV_SAVE_TEST_MAIN \
    "$saves_root/experiments/shipwright/simulator-game/AppleTVSaveStore.mm" \
    "$saves_root/experiments/shipwright/simulator-game/SaveStoreTests.mm" \
    -Wl,-sectcreate,__TEXT,__info_plist,"$saves_root/experiments/shipwright/simulator-game/SaveTestInfo.plist" \
    -framework Foundation -framework Security -lz -o "$saves_build/save-tests"
saves_port=$(mktemp "$saves_build/port.XXXXXX")
python3 "$saves_root/experiments/shipwright/simulator-game/save_test_server.py" "$saves_port" &
saves_server=$!
trap 'kill "$saves_server" 2>/dev/null || true; wait "$saves_server" 2>/dev/null || true; rm -f "$saves_port"' EXIT
for ((attempt=0;attempt<300;attempt++)); do
    [[ -s "$saves_port" ]] && break
    if ! kill -0 "$saves_server" 2>/dev/null; then
        wait "$saves_server" || true
        printf '%s\n' 'Save fixture exited before it was ready.' >&2
        exit 1
    fi
    sleep 0.1
done
if [[ ! -s "$saves_port" ]]; then
    printf '%s\n' 'Save fixture did not become ready within 30 seconds.' >&2
    exit 1
fi
saves_endpoint="http://127.0.0.1:$(cat "$saves_port")"
# Fail at fixture startup rather than reporting a client regression for an unavailable server.
curl --fail --silent --show-error --noproxy '*' "$saves_endpoint/stats" >/dev/null
"$saves_build/save-tests" "$saves_endpoint"
