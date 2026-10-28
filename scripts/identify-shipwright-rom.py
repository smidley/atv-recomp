#!/usr/bin/env python3
"""Identify a local N64 dump against pinned Shipwright hashes; never write ROM data."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

REFERENCE = Path(__file__).resolve().parent.parent / "upstream/shipwright-supported-roms.json"
BYTE_ORDERS = {b"\x80\x37\x12\x40": "z64", b"\x37\x80\x40\x12": "v64", b"\x40\x12\x37\x80": "n64"}


def load_revisions(path=REFERENCE):
    rows = json.loads(Path(path).read_text())
    if not isinstance(rows, list) or not rows:
        raise ValueError("The pinned ROM reference must be a nonempty list")
    revisions = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("name"), str) or not row["name"].strip():
            raise ValueError("Invalid ROM revision name")
        digest = row.get("sha1")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{40}", digest) or digest in revisions:
            raise ValueError("Invalid or duplicate ROM reference hash")
        revisions[digest] = row["name"]
    return revisions


def canonical_bytes(block, byte_order):
    """Return big-endian N64 bytes, swapping pairs or words as required."""
    if len(block) % 4:
        raise ValueError("N64 data must contain complete four-byte words")
    if byte_order == "z64":
        return block
    if byte_order not in ("v64", "n64"):
        raise ValueError("Unknown N64 byte order")
    width = 2 if byte_order == "v64" else 4
    result = bytearray(len(block))
    for offset in range(width):
        result[offset::width] = block[width - 1 - offset::width]
    return result


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def identify_rom(path, revisions, chunk_size=1024 * 1024):
    if chunk_size <= 0 or chunk_size % 4:
        raise ValueError("Read size must be a positive multiple of four")
    # SHA-1 is upstream's compatibility identifier, not an authenticity check.
    sha1 = hashlib.sha1(usedforsecurity=False)
    sha256 = hashlib.sha256()
    total = 0
    # Nonblocking open lets us reject a FIFO/device before a read can wait on it.
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0)
    with os.fdopen(os.open(path, flags), "rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode):
            raise ValueError("Select a regular, uncompressed ROM file")
        if before.st_size < 64 or before.st_size % 4:
            raise ValueError("Incomplete N64 header or truncated four-byte word")
        byte_order = BYTE_ORDERS.get(source.read(4))
        if byte_order is None:
            raise ValueError("Unrecognized N64 header; archives and asset packs are not ROM dumps")
        source.seek(0)
        while True:
            block = source.read(chunk_size)
            if not block:
                break
            canonical = canonical_bytes(block, byte_order)
            sha1.update(canonical)
            sha256.update(canonical)
            total += len(block)
        if total != before.st_size or fingerprint(before) != fingerprint(os.fstat(source.fileno())):
            raise ValueError("ROM changed during validation; retry with a stable local copy")
    digest = sha1.hexdigest()
    revision = revisions.get(digest)
    return {
        "status": "recognized" if revision else "unsupported_revision",
        "runtime_id": "shipwright" if revision else None,
        "revision": revision,
        "input_byte_order": byte_order,
        "canonical_byte_order": "z64",
        "size_bytes": total,
        "sha1": digest,
        "sha256": sha256.hexdigest(),
        "launchable": False,
        "runtime_status": "not_integrated",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom", type=Path, help="Local uncompressed ROM; its extension is not used for identification")
    args = parser.parse_args()
    try:
        result = identify_rom(args.rom, load_revisions())
    except (OSError, ValueError) as error:
        print(json.dumps({"status": "validation_error", "error": str(error), "launchable": False}, indent=2))
        return 2
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "recognized" else 1


if __name__ == "__main__":
    sys.exit(main())
