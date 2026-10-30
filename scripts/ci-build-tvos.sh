#!/bin/bash
set -euo pipefail

# Simulator builds keep Xcode's ad hoc "Sign to Run Locally" signature: it embeds the
# simulated application identifier that Keychain needs and requires no certificate.
# Device builds stay unsigned in CI.
case "${1:-}" in
    simulator) sdk=appletvsimulator; configuration=Debug; destination='generic/platform=tvOS Simulator'; signing=YES ;;
    device) sdk=appletvos; configuration=Release; destination='generic/platform=tvOS'; signing=NO ;;
    *) echo 'Usage: bash scripts/ci-build-tvos.sh simulator|device' >&2; exit 2 ;;
esac

task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_log=$(mktemp "${TMPDIR:-/tmp}/recomptv-build.XXXXXX")
trap 'rm -f "$task_log"' EXIT

set +e
xcodebuild -project "$task_root/RecompTV.xcodeproj" -scheme RecompTV \
    -configuration "$configuration" -sdk "$sdk" -destination "$destination" \
    -derivedDataPath "$task_root/build/$1" CODE_SIGNING_ALLOWED="$signing" build 2>&1 | tee "$task_log"
task_status=${PIPESTATUS[0]}
set -e

if [ "$task_status" -ne 0 ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
    # A short, single-line diagnostic also appears as the next CI step's name.
    # This makes the first failure readable through the workflow jobs API while
    # preserving the full compiler output and the failing exit code above.
    python3 - "$task_log" "$GITHUB_OUTPUT" <<'PY'
import pathlib
import re
import sys

lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
errors = []
for line in lines:
    if "error:" not in line.lower():
        continue
    line = re.sub(r"^.*?/(?=RecompTV/)", "", line)
    line = " ".join(line.split())
    if line not in errors:
        errors.append(line)
summary = " | ".join(errors[:3]) or "Xcode build failed; see build log"
with open(sys.argv[2], "a") as output:
    output.write("diagnostic=" + summary[:900] + "\n")
PY
fi
exit "$task_status"
