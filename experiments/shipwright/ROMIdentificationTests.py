"""Synthetic bytes only: these checks do not contain or validate a real game ROM."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/identify-shipwright-rom.py"
spec = importlib.util.spec_from_file_location("rom_identifier", SCRIPT)
rom = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rom)


class ROMIdentificationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "misleading-name.zip"
        self.data = bytes.fromhex("80371240") + bytes(range(256)) * 4097
        self.sha1 = hashlib.sha1(self.data, usedforsecurity=False).hexdigest()
        # This private fixture allowlist is never used by the CLI or shipped reference.
        self.revisions = {self.sha1: "Synthetic fixture"}

    def check_variant(self, data, expected_order):
        self.path.write_bytes(data)
        result = rom.identify_rom(self.path, self.revisions)
        self.assertEqual(result["status"], "recognized")
        self.assertEqual(result["input_byte_order"], expected_order)
        self.assertEqual(result["sha1"], self.sha1)
        self.assertEqual(result["sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(result["size_bytes"], len(self.data))
        self.assertFalse(result["launchable"])
        self.assertEqual(self.path.read_bytes(), data, "validation must not rewrite the user's file")

    def test_big_endian_and_misleading_extension(self):
        self.check_variant(self.data, "z64")

    def test_byte_swapped_across_read_boundary(self):
        words = struct.unpack(">" + "H" * (len(self.data) // 2), self.data)
        self.check_variant(struct.pack("<" + "H" * len(words), *words), "v64")

    def test_word_swapped_across_read_boundary(self):
        words = struct.unpack(">" + "I" * (len(self.data) // 4), self.data)
        self.check_variant(struct.pack("<" + "I" * len(words), *words), "n64")

    def test_literal_byte_order_examples(self):
        canonical = bytes.fromhex("8037124001020304")
        self.assertEqual(rom.canonical_bytes(bytes.fromhex("3780401202010403"), "v64"), canonical)
        self.assertEqual(rom.canonical_bytes(bytes.fromhex("4012378004030201"), "n64"), canonical)

    def test_modified_data_is_unsupported(self):
        self.path.write_bytes(self.data[:-1] + bytes([self.data[-1] ^ 1]))
        result = rom.identify_rom(self.path, self.revisions)
        self.assertEqual(result["status"], "unsupported_revision")
        self.assertIsNone(result["runtime_id"])
        self.assertFalse(result["launchable"])

    def test_invalid_header_and_truncation(self):
        for data in (b"", b"PK\x03\x04" + bytes(60), self.data[:63], self.data[:-1]):
            with self.subTest(size=len(data)):
                self.path.write_bytes(data)
                with self.assertRaises(ValueError):
                    rom.identify_rom(self.path, self.revisions)

    def test_changed_file_is_rejected(self):
        self.path.write_bytes(self.data)
        before = self.path.stat()
        after = SimpleNamespace(**{key: getattr(before, key) for key in
                                  ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")})
        after.st_mtime_ns += 1
        with patch.object(rom.os, "fstat", side_effect=[before, after]):
            with self.assertRaisesRegex(ValueError, "changed"):
                rom.identify_rom(self.path, self.revisions)

    def test_pinned_reference_is_intact(self):
        baseline = json.loads((ROOT / "upstream/shipwright-baseline.json").read_text())
        reference = baseline["rom_reference"]
        data = rom.REFERENCE.read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), reference["file_sha256"])
        self.assertEqual(len(rom.load_revisions()), 19)
        self.assertNotIn(self.sha1, rom.load_revisions())

    def test_duplicate_reference_hash_is_rejected(self):
        row = {"name": "Fixture", "sha1": self.sha1}
        self.path.write_text(json.dumps([row, row]))
        with self.assertRaises(ValueError):
            rom.load_revisions(self.path)

    def test_cli_uses_real_reference_and_exit_codes(self):
        self.path.write_bytes(self.data)
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["status"], "unsupported_revision")
        self.path.unlink()
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["status"], "validation_error")

    @unittest.skipUnless(hasattr(os, "mkfifo"), "FIFO check requires POSIX")
    def test_cli_rejects_fifo_without_waiting_for_a_writer(self):
        os.mkfifo(self.path)
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.path)],
                                capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["status"], "validation_error")


if __name__ == "__main__":
    unittest.main()
