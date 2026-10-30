"""Offline tests for the game version files and the update helpers in upstream.py."""

import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import upstream  # noqa: E402


class UpstreamTests(unittest.TestCase):
    def setUp(self):
        self.games = upstream.load_games(ROOT)

    def test_each_tracked_game_names_its_own_repository(self):
        self.assertEqual(set(self.games), {"shipwright", "spaghettikart", "starship"})
        self.assertEqual(upstream.game_source(self.games["shipwright"])[1]["repository"], "HarbourMasters/Shipwright")
        self.assertEqual(upstream.game_source(self.games["spaghettikart"])[1]["repository"], "HarbourMasters/SpaghettiKart")

    def test_checkouts_list_each_tvos_source_once(self):
        pins = upstream.checkouts(self.games)
        self.assertEqual(sorted(pin.path.name for pin in pins), ["Shipwright", "SpaghettiKart", "Starship", "Torch", "libultraship"])
        for pin in pins:
            self.assertRegex(pin.revision, r"^[0-9a-f]{40}$")
            self.assertEqual(pin.path.parent, ROOT / "build/upstream")

    def test_update_takes_libraries_from_the_new_release(self):
        game = copy.deepcopy(self.games["shipwright"])
        updated = upstream.update_pins(game, "9.4.0", "a" * 40, {"libultraship": "b" * 40, "torch": "c" * 40}, "2026-11-02")
        sources = updated["sources"]
        self.assertEqual((updated["release"], updated["recorded_on"]), ("9.4.0", "2026-11-02"))
        self.assertEqual([sources[k]["revision"] for k in ("shipwright", "libultraship", "torch")], ["a" * 40, "b" * 40, "c" * 40])
        self.assertEqual(updated["rom_reference"], game["rom_reference"])
        self.assertEqual(game["release"], self.games["shipwright"]["release"], "the input must stay unchanged")

    def test_update_rejects_a_release_without_a_shared_library(self):
        with self.assertRaisesRegex(SystemExit, "torch"):
            upstream.update_pins(self.games["shipwright"], "9.4.0", "a" * 40, {"libultraship": "b" * 40}, "2026-11-02")

    def test_rom_reference_follows_the_new_list(self):
        data = json.dumps([{"name": "A", "sha1": "1" * 40}, {"name": "B", "sha1": "2" * 40}]).encode()
        reference = upstream.refreshed_rom_reference(self.games["shipwright"]["rom_reference"], data, "d" * 40)
        self.assertEqual(reference["file_sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(reference["upstream_entry_count"], 2)
        self.assertIn("/blob/" + "d" * 40 + "/docs/supportedHashes.json", reference["source"])

    def test_release_issue_only_for_a_different_release(self):
        game = self.games["shipwright"]
        self.assertIsNone(upstream.release_issue("shipwright", game, game["release"]))
        title, body = upstream.release_issue("shipwright", game, "9.4.0")
        self.assertEqual(title, "Update Shipwright to 9.4.0")
        self.assertIn(f"https://github.com/HarbourMasters/Shipwright/compare/{game['sources']['shipwright']['revision']}...9.4.0", body)
        self.assertIn("python3 scripts/upstream.py update shipwright 9.4.0", body)


if __name__ == "__main__":
    unittest.main()
