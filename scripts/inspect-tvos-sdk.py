"""Expose the exact SDK availability declarations in CI, including the jobs API."""

import os
from pathlib import Path
import re
import subprocess

sdk = Path(subprocess.check_output(
    ["xcrun", "--sdk", "appletvsimulator", "--show-sdk-path"], text=True).strip())
frameworks = sdk / "System/Library/Frameworks"
queries = [
    ("QuartzCore.framework/Headers/CAMetalLayer.h", "displaySyncEnabled"),
    ("Metal.framework/Headers/MTLDevice.h", "MTLCopyAllDevices(void)"),
    ("Metal.framework/Headers/MTLResource.h", "MTLStorageModeManaged"),
]
declarations = []
for path, symbol in queries:
    lines = (frameworks / path).read_text().splitlines()
    hits = [i for i, line in enumerate(lines) if symbol in line and not line.strip().startswith(('*', '//'))]
    if not hits:
        raise SystemExit(f"Could not locate SDK declaration: {symbol}")
    start = hits[0]
    declaration = re.sub(r"\s+", " ", " ".join(lines[start:start + 3])).strip()
    declarations.append(declaration[:280])
    print(f"{path}: {declaration}")
if os.environ.get("GITHUB_OUTPUT"):
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("declarations=" + " | ".join(declarations) + "\n")
