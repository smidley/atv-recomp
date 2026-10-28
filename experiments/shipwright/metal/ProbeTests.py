"""Host tests for evidence classification and the ROM-free shader archive."""

import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


runner = module("render_runner", ROOT / "scripts/run-shipwright-render-probe.py")
packer = module("shader_packer", Path(__file__).with_name("pack-probe-shaders.py"))


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.report = {"schema_version": 1, "run_id": "fresh", "status": "passed", "metal_device": "fixture",
                       "width": 1920, "height": 1080, "completed_frames": 6, "verified_cycles": 3, "destroyed_renderers": 3,
                       "rgba5551_samples": [[color] * 5 + [0] * 4 for color in (0xF801, 0x07C1, 0x003F)]}

    def test_complete_evidence(self):
        self.assertEqual(runner.validate_report(self.report, "fresh"), "passed")
        for samples in self.report["rgba5551_samples"]:
            samples[5:] = [1] * 4
        self.assertEqual(runner.validate_report(self.report, "fresh"), "passed")

    def test_old_process_is_rejected(self):
        with self.assertRaises(ValueError):
            runner.validate_report(self.report, "different-launch")

    def test_incomplete_gpu_or_teardown_evidence(self):
        for key in ("completed_frames", "verified_cycles", "destroyed_renderers"):
            with self.subTest(key=key):
                report = copy.deepcopy(self.report)
                report[key] -= 1
                with self.assertRaises(ValueError):
                    runner.validate_report(report, "fresh")

    def test_missing_gpu_or_dimensions(self):
        for key, value in (("metal_device", ""), ("width", 0), ("height", True)):
            with self.subTest(key=key):
                report = copy.deepcopy(self.report)
                report[key] = value
                with self.assertRaises(ValueError):
                    runner.validate_report(report, "fresh")

    def test_unavailable_is_not_a_pass(self):
        self.assertEqual(runner.validate_report({"schema_version": 1, "run_id": "fresh", "status": "unavailable"}, "fresh"), "unavailable")

    def test_stale_pixels_rejected_even_with_complete_counters(self):
        self.report["rgba5551_samples"][2] = self.report["rgba5551_samples"][1]
        with self.assertRaises(ValueError):
            runner.validate_report(self.report, "fresh")

    def test_failure_remains_failure(self):
        self.report["status"] = "failed"
        self.assertEqual(runner.validate_report(self.report, "fresh"), "failed")

    def test_unknown_schema_or_state_rejected(self):
        for key, value in (("schema_version", 2), ("status", "success")):
            with self.subTest(key=key):
                report = copy.deepcopy(self.report)
                report[key] = value
                with self.assertRaises(ValueError):
                    runner.validate_report(report, "fresh")

    def test_shader_archive_is_deterministic_and_contains_no_other_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "src/fast/shaders/metal/default.shader.metal"
            template.parent.mkdir(parents=True)
            template.write_bytes(b"synthetic shader template")
            (root / "LICENSE").write_bytes(b"synthetic license fixture")
            (root / "unrelated.rom").write_bytes(b"must not enter archive")
            first, second = root / "one.o2r", root / "two.o2r"
            packer.pack(root, first)
            packer.pack(root, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(set(archive.namelist()), {"shaders/metal/default.shader.metal", "LICENSE.libultraship.txt"})
                self.assertEqual(archive.read("shaders/metal/default.shader.metal"), template.read_bytes() + b"\0")


if __name__ == "__main__":
    unittest.main()
