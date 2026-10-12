"""Mechanic-level assertions for the isolated R6-B evolved gear overlay."""
from __future__ import annotations

from dataclasses import replace
from functools import partial
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "reference/endgame_r1/Witch_G2_Collection_Endgame_Monetization_R1_20261010/tools"))
import lab  # noqa: E402
from evolved_overlay import EvolvedOverlayBattle  # noqa: E402
from run_evolved_challenges import encounter, party_for  # noqa: E402


H1 = partial(lab.old.RarityRules, multipliers=lab.old.MODELS["H1_RECOMMENDED"])


class EvolvedOverlayTests(unittest.TestCase):
    def battle(self, build, challenge="CH_R01_03", seed=930064):
        with patch.object(lab.precision_rules, "PrecisionRules", H1):
            return EvolvedOverlayBattle(party_for(build), encounter(challenge), seed, record=True).run()

    def test_poison_weapon_extends_stack_cap_and_runs_shatter(self):
        result = self.battle("TOXIN_CHASE")
        applies = [x["stacks"] for x in result["log"] if x["kind"] == "poison_apply"]
        self.assertTrue(applies)
        self.assertLessEqual(max(applies), 7)
        self.assertGreater(result["metrics"].get("evolved_poison_burst", 0), 0)

    def test_evolved_ward_replaces_poison_seed_and_reflects_absorption(self):
        result = self.battle("WARD_HEAL_COUNTER")
        self.assertEqual(result["metrics"].get("cast_SK_W_SEED", 0), 0)
        self.assertGreater(result["metrics"].get("cast_SK_A_WARD", 0), 0)
        self.assertGreater(result["metrics"].get("evolved_reflect_trigger", 0), 0)

    def test_effective_heal_creates_only_bounded_barrier(self):
        result = self.battle("HEAL_ONLY")
        self.assertGreater(result["metrics"].get("evolved_heal_barrier", 0), 0)
        self.assertLessEqual(result["metrics"]["evolved_heal_barrier"], result["metrics"].get("effective_heal", 0) // 5)

    def test_pressure_gains_are_per_root_and_capped_before_hammer_consumption(self):
        result = self.battle("COUNTER_ONLY", "CH_R03_01")
        gains = [x["stacks"] for x in result["log"] if x["kind"] == "evolved_effect" and x["effect"] == "pressure_gain"]
        self.assertTrue(gains)
        self.assertLessEqual(max(gains), 3)
        self.assertGreater(result["metrics"].get("evolved_pressure_consumed_stacks", 0), 0)
        counter_roots = [x["root"] for x in result["log"] if x["kind"] == "damage" and x["kind_damage"] == "counter"]
        self.assertEqual(len(counter_roots), len(set(counter_roots)))

    def test_research_overlay_keeps_multiple_clear_roles_and_auto_only(self):
        result = self.battle("WARD_HEAL_COUNTER")
        self.assertEqual(result["outcome"], "VICTORY")
        self.assertGreater(result["metrics"].get("evolved_cover_barrier", 0), 0)
        self.assertIn("ai_planning_order", result)
        self.assertNotIn("player_tactic", result)

    def test_chase_and_mark_have_effect_telemetry(self):
        result = self.battle("CHASE_ONLY")
        self.assertGreater(result["metrics"].get("damage_chase", 0), 0)
        self.assertGreater(result["metrics"].get("evolved_mark_duration", 0), 0)
        timestamps = [x["t_ms"] for x in result["log"] if x["kind"] == "damage" and x["kind_damage"] == "chase"]
        self.assertTrue(all(b - a >= 1500 for a, b in zip(timestamps, timestamps[1:])))


if __name__ == "__main__":
    unittest.main(verbosity=2)
