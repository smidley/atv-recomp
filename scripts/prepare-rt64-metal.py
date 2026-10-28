"""Verify the audit pins, then patch generated copies without changing upstream."""

import json
from pathlib import Path
import shutil
import subprocess
import sys


def verify(source, revision):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()
    if Path(git("rev-parse", "--show-toplevel")).resolve() != source:
        raise SystemExit(f"Expected a separate checkout at {source}")
    if git("rev-parse", "HEAD") != revision:
        raise SystemExit(f"Incorrect upstream revision at {source}; expected {revision}")
    if git("status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"):
        raise SystemExit(f"Upstream checkout has local changes: {source}")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/prepare-rt64-metal.py RT64_CHECKOUT")
    root = Path(__file__).resolve().parent.parent
    source = Path(sys.argv[1]).resolve(strict=True)
    baseline = json.loads((root / "upstream/audit-baseline.json").read_text())
    verify(source, baseline["sources"]["rt64"]["revision"])
    for path in ("src/contrib/xxHash", "src/contrib/spirv-cross", "src/contrib/dxc"):
        pin = next(p for p in baseline["gitlinks"] if p["parent"] == "rt64" and p["path"] == path)
        verify((source / path).resolve(strict=True), pin["revision"])

    relative = Path("build/rt64-metal/source")
    destination = root / relative
    paths = [
        "src/metal/rt64_metal.cpp", "src/metal/rt64_metal.h",
        "src/rhi/rt64_render_interface.h", "src/rhi/rt64_render_interface_types.h",
        "src/rhi/rt64_render_interface_builders.h",
        "src/tools/spirv_cross_msl/spirv_cross_msl.cpp", "LICENSE",
    ]
    for path in paths:
        output = destination / path
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / path, output)
    patch = root / "experiments/rt64-metal/tvos.patch"
    command = ["git", "-C", str(root), "apply", f"--directory={relative}"]
    subprocess.run([*command, "--check", str(patch)], check=True)
    subprocess.run([*command, str(patch)], check=True)
    print(f"Prepared pinned RT64 Metal sources in {destination}")


if __name__ == "__main__":
    main()
