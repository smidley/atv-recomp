"""Copy a clean pinned libultraship checkout, then apply the tvOS experiment patch."""

import json
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/prepare-shipwright-metal.py LIBULTRASHIP_CHECKOUT")
    root = Path(__file__).resolve().parent.parent
    source = Path(sys.argv[1]).resolve(strict=True)
    pin = json.loads((root / "upstream/shipwright-baseline.json").read_text())["sources"]["libultraship"]["revision"]

    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()

    if Path(git("rev-parse", "--show-toplevel")).resolve() != source or git("rev-parse", "HEAD") != pin:
        raise SystemExit(f"Incorrect upstream libultraship checkout; expected {pin}")
    if git("status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"):
        raise SystemExit("Upstream libultraship checkout has local changes")
    relative = Path("build/shipwright-metal/source")
    destination = root / relative
    if destination == source or source in destination.parents or destination in source.parents:
        raise SystemExit("The generated source directory must be outside the upstream checkout")
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".git"), dirs_exist_ok=True)
    command = ["git", "-C", str(root), "apply", f"--directory={relative}"]
    for name in ("tvos.patch", "rendering.patch"):
        patch = root / "experiments/shipwright/metal" / name
        subprocess.run([*command, "--check", str(patch)], check=True)
        subprocess.run([*command, str(patch)], check=True)
    print(f"Prepared pinned libultraship sources in {destination}")


if __name__ == "__main__":
    main()
