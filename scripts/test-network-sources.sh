#!/bin/bash
set -euo pipefail
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_log=$(mktemp "${TMPDIR:-/tmp}/recomptv-network-tests.XXXXXX")
trap 'rm -f "$task_log"' EXIT
cmp "$task_root/upstream/shipwright-supported-roms.json" "$task_root/Packages/RecompSources/Sources/RecompSources/Resources/shipwright-supported-roms.json"
set +e
swift test --package-path "$task_root/Packages/RecompSources" 2>&1 | tee "$task_log"
task_status=${PIPESTATUS[0]}
set -e
if [ "$task_status" -ne 0 ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
    python3 - "$task_log" "$GITHUB_OUTPUT" <<'PY'
import pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()
errors=[line.strip() for line in lines if any(term in line for term in ['error:', 'failed', 'Issue recorded', 'Expectation failed'])]
with open(sys.argv[2], 'a') as out:
    out.write('diagnostic=' + ' | '.join(dict.fromkeys(errors))[:1200] + '\n')
PY
fi
exit "$task_status"
