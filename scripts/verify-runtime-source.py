"""Reject a wrong or modified checkout before the isolated runtime experiment."""

import json
from pathlib import Path
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/verify-runtime-source.py RUNTIME_CHECKOUT")
    root = Path(__file__).resolve().parent.parent
    pin = json.loads((root / "upstream/audit-baseline.json").read_text())["sources"]["runtime"]
    source = Path(sys.argv[1]).resolve(strict=True)

    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()

    if Path(git("rev-parse", "--show-toplevel")) != source:
        raise SystemExit("Runtime source must be its own checkout, not a subdirectory of another repo.")
    actual = git("rev-parse", "HEAD")
    if actual != pin["revision"]:
        raise SystemExit(f"Runtime revision mismatch: expected {pin['revision']}, found {actual}")
    if git("status", "--porcelain", "--untracked-files=all"):
        raise SystemExit("Runtime checkout has local changes. Use a clean checkout of the pinned revision.")
    print(f"Verified {pin['repository']} at {actual}")


if __name__ == "__main__":
    main()
