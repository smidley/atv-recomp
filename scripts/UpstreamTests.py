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
        self.assertEqual(set(self.games), {"battleship", "ghostship", "lighthouse", "racer", "shipwright", "sote", "spaghettikart", "starship"})
        self.assertEqual(upstream.game_source(self.games["lighthouse"])[1]["repository"], "HarbourMasters/Lighthouse")
        self.assertEqual(upstream.game_source(self.games["shipwright"])[1]["repository"], "HarbourMasters/Shipwright")
        self.assertEqual(upstream.game_source(self.games["spaghettikart"])[1]["repository"], "HarbourMasters/SpaghettiKart")
        self.assertEqual(upstream.game_source(self.games["sote"])[1]["repository"], "GTTeancum/SotE-Recomp")
        self.assertEqual(upstream.game_source(self.games["racer"])[1]["repository"], "sp00nznet/racer")
        self.assertEqual(upstream.game_source(self.games["battleship"])[1]["repository"], "JRickey/BattleShip")

    def test_checkouts_list_each_tvos_source_once(self):
        pins = upstream.checkouts(self.games)
        self.assertEqual(sorted(str(pin.path.relative_to(ROOT / "build/upstream")) for pin in pins),
                         ["BattleShip", "BattleShip/decomp", "BattleShip/libultraship", "BattleShip/torch",
                          "Ghostship", "Lighthouse", "Shipwright", "SotE-Recomp", "SpaghettiKart", "Starship", "Torch",
                          "libultraship", "racer", "racer-toolkits/N64ModernRuntime", "racer-toolkits/N64Recomp",
                          "racer-toolkits/rt64"])
        for pin in pins:
            self.assertRegex(pin.revision, r"^[0-9a-f]{40}$")

    def test_shared_libraries_follow_one_game(self):
        # Build files and prepare scripts read these pins from lighthouse-baseline.json.
        owners = {name: key for key, game in self.games.items()
                  for name, source in game["sources"].items() if "gitlink" in source}
        # BattleShip's own forks of them are its alone (docs/BATTLESHIP.md).
        self.assertEqual(owners, {"libultraship": "lighthouse", "torch": "lighthouse", "battleship-decomp": "battleship",
                                  "battleship-libultraship": "battleship", "battleship-torch": "battleship"})

    def test_update_takes_libraries_from_the_new_release(self):
        game = copy.deepcopy(self.games["lighthouse"])
        updated = upstream.update_pins(game, "1.3.0", "a" * 40, {"libultraship": "b" * 40, "Torch": "c" * 40}, "2026-11-02")
        sources = updated["sources"]
        self.assertEqual((updated["release"], updated["recorded_on"]), ("1.3.0", "2026-11-02"))
        self.assertEqual([sources[k]["revision"] for k in ("lighthouse", "libultraship", "torch")], ["a" * 40, "b" * 40, "c" * 40])
        self.assertEqual(game["release"], self.games["lighthouse"]["release"], "the input must stay unchanged")

    def test_update_leaves_branch_toolkits_alone(self):
        updated = upstream.update_pins(self.games["racer"], "v0.4.0", "a" * 40, {}, "2026-11-02")
        self.assertEqual(updated["sources"]["racer"]["revision"], "a" * 40)
        for name in ("N64ModernRuntime", "rt64", "N64Recomp"):
            self.assertEqual(updated["sources"][name], self.games["racer"]["sources"][name])

    def test_update_rejects_a_release_without_a_shared_library(self):
        with self.assertRaisesRegex(SystemExit, "Torch"):
            upstream.update_pins(self.games["lighthouse"], "1.3.0", "a" * 40, {"libultraship": "b" * 40}, "2026-11-02")

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
