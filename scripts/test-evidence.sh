#!/bin/sh
set -eu

task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build=$(mktemp -d "${TMPDIR:-/tmp}/recomptv-evidence.XXXXXX")
trap 'rm -rf "$task_build"' EXIT HUP INT TERM

"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete \
    "$task_root/RecompTV/Diagnostics/FrameEvidence.swift" \
    "$task_root/Tests/FrameEvidenceTests.swift" -o "$task_build/evidence-tests"
"$task_build/evidence-tests"
