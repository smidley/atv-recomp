"""Package only the pinned open-source Metal template; no game assets or Torch."""

from pathlib import Path
import sys
import zipfile


def pack(source: Path, output: Path):
    output.parent.mkdir(parents=True, exist_ok=True)
    entries = {
        "shaders/metal/default.shader.metal": (source / "src/fast/shaders/metal/default.shader.metal").read_bytes() + b"\0",
        "LICENSE.libultraship.txt": (source / "LICENSE").read_bytes(),
    }
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: pack-probe-shaders.py PINNED_SOURCE OUTPUT.o2r")
    pack(Path(sys.argv[1]), Path(sys.argv[2]))
