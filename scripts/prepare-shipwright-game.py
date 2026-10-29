"""Prepare a patched copy of the pinned game without touching its checkout."""

import json
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/prepare-shipwright-game.py SHIPWRIGHT_CHECKOUT")
    root = Path(__file__).resolve().parent.parent
    source = Path(sys.argv[1]).resolve(strict=True)
    pin = json.loads((root / "upstream/shipwright-baseline.json").read_text())["sources"]["shipwright"]["revision"]

    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()

    if Path(git("rev-parse", "--show-toplevel")).resolve() != source or git("rev-parse", "HEAD") != pin:
        raise SystemExit(f"Incorrect upstream Shipwright checkout; expected {pin}")
    if git("status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"):
        raise SystemExit("Upstream Shipwright checkout has local changes")
    relative = Path("build/shipwright-game/source")
    destination = root / relative
    if destination == source or source in destination.parents:
        raise SystemExit("The generated source must be outside the upstream checkout")
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".git"), dirs_exist_ok=True)
    command = ["git", "-C", str(root), "apply", f"--directory={relative}"]
    for name in ("tvos.patch", "performance.patch", "gameplay.patch"):
        patch = root / "experiments/shipwright/simulator-game" / name
        subprocess.run([*command, "--check", str(patch)], check=True)
        subprocess.run([*command, str(patch)], check=True)
    print(f"Prepared simulator game sources in {destination}")


if __name__ == "__main__":
    main()
