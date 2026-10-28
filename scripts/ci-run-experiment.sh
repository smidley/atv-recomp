#!/usr/bin/env bash
set -euo pipefail
[[ $# -gt 0 ]] || { echo 'Usage: bash scripts/ci-run-experiment.sh COMMAND [ARG ...]' >&2; exit 2; }
probe_log=$(mktemp)
trap 'rm -f "$probe_log"' EXIT
set +e
"$@" 2>&1 | tee "$probe_log"
probe_status=${PIPESTATUS[0]}
set -e
if [[ $probe_status -ne 0 && -n ${GITHUB_OUTPUT:-} ]]; then
    python3 - "$probe_log" <<'PY'
import os
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text(errors="replace").splitlines()
errors = [line.strip() for line in lines if any(word in line.lower() for word in ("error:", "cmake error", "failed", "incorrect upstream", "local changes"))]
message = " | ".join(errors[:3]) or "Experiment failed; see step output"
with open(os.environ["GITHUB_OUTPUT"], "a") as output:
    output.write("diagnostic=" + message[:900].replace("\r", " ") + "\n")
PY
fi
exit "$probe_status"
