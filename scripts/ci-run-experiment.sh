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
import re
import sys
log = re.sub(r"\x1b\[[0-9;]*m", "", Path(sys.argv[1]).read_text(errors="replace"))
lines = log.splitlines()
errors = []
for index, line in enumerate(lines):
    if re.search(r"error:|cmake error(?:\s|$)|^FAILED:", line, re.IGNORECASE):
        # CMake puts the explanation on the following lines. Its ordinary
        # negative capability probes ('-- ... - Failed') are not build errors.
        context = lines[index:index + 4] if "cmake error" in line.lower() else [line]
        errors.append(" ".join(part.strip() for part in context if part.strip()))
if not errors:
    errors = [line.strip() for line in lines if not line.startswith("-- ") and
              any(word in line.lower() for word in ("failed", "incorrect upstream", "local changes"))]
message = " | ".join(errors[:3]) or " | ".join(line.strip() for line in lines[-5:] if line.strip())
message = message or "Experiment failed; see step output"
with open(os.environ["GITHUB_OUTPUT"], "a") as output:
    output.write("diagnostic=" + message[:900].replace("\r", " ") + "\n")
PY
fi
exit "$probe_status"
