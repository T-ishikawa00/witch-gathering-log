#!/usr/bin/env python3
"""Unit probes for the independent R012 event-to-target expectation contract."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("effect_encounter_audit", ROOT / "tools/witch_native/effect_encounter_audit.py")
assert SPEC and SPEC.loader
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


def event(kind: str, source: str, target: str, root: str, amount: int = 1) -> dict:
    return {"kind": kind, "sourceID": source, "targetID": target, "rootActionID": root, "amount": amount}


class R012EventProjectionTests(unittest.TestCase):
    def test_poison_wave_aggregates_every_actual_dot_recipient(self):
        source, root = "B_R05_B", "enemy:B_R05_B:1"
        events = [event("enemy_telegraph", source, "party", root)]
        events += [event("dot_applied", source, actor, root, 3) for actor in
                   ("C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH")]
        events += [event("enemy_seed_pressure", source, "party", root, 3)]
        action, = AUDIT.expected_visual_actions(source, events)
        self.assertEqual(action["targets"], ["ERNA", "NOIR", "LUNA", "AIRA"])
        self.assertEqual(action["impactKinds"], ["dot_applied"])
        self.assertEqual(action["semanticOnlyKinds"], ["enemy_seed_pressure"])

    def test_actual_party_hit_excludes_same_root_self_opening(self):
        source, root = "B_R02_B", "enemy:B_R02_B:2"
        events = [event("enemy_telegraph", source, "party", root),
                  event("enemy_hit", source, "C_SMITH", root, 42),
                  event("enemy_scale_opening", source, source, root, 3500)]
        action, = AUDIT.expected_visual_actions(source, events)
        self.assertEqual(action["targets"], ["AIRA"])
        self.assertEqual(action["impactKinds"], ["enemy_hit"])
        self.assertEqual(action["semanticOnlyKinds"], ["enemy_scale_opening"])

    def test_multi_hit_boss_rest_does_not_leak_self_into_party_targets(self):
        source, root = "B_R03_A", "enemy:B_R03_A:2"
        events = [event("enemy_telegraph", source, "C_SMITH", root),
                  event("enemy_hit", source, "C_SMITH", root, 9),
                  event("enemy_hit", source, "C_SMITH", root, 9),
                  event("enemy_rest", source, source, root, 3500)]
        action, = AUDIT.expected_visual_actions(source, events)
        self.assertEqual(action["targets"], ["AIRA"])
        self.assertEqual(action["impactKinds"], ["enemy_hit"])
        self.assertEqual(action["semanticOnlyKinds"], ["enemy_rest"])

    def test_heat_release_self_event_does_not_pollute_aoe_hit_recipients(self):
        source, root = "B_R03_B", "enemy:B_R03_B:3"
        events = [event("telegraph_aoe", source, "party", root)]
        events += [event("enemy_hit", source, actor, root, 40) for actor in
                   ("C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH")]
        events += [event("enemy_heat_release", source, source, root)]
        action, = AUDIT.expected_visual_actions(source, events)
        self.assertEqual(action["targets"], ["ERNA", "NOIR", "LUNA", "AIRA"])
        self.assertEqual(action["impactKinds"], ["enemy_hit"])
        self.assertEqual(action["semanticOnlyKinds"], ["enemy_heat_release"])

    def test_regen_and_dots_do_not_add_self_or_secondary_targets_to_hit_cue(self):
        source, root = "E_R05_04", "enemy:E_R05_04:1"
        events = [event("enemy_telegraph", source, "C_SMITH", root),
                  event("enemy_hit", source, "C_SMITH", root, 22)]
        events += [event("dot_applied", source, actor, root, 3) for actor in
                   ("C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH")]
        events += [event("enemy_regen", source, source, root, 7)]
        action, = AUDIT.expected_visual_actions(source, events)
        self.assertEqual(action["targets"], ["AIRA"])
        self.assertEqual(action["impactKinds"], ["enemy_hit"])
        self.assertEqual(action["semanticOnlyKinds"], ["dot_applied", "enemy_regen"])

    def test_defense_projects_on_source_and_ignores_zero_amount(self):
        source, root = "E_R01_04", "C_WITCH:basic:1"
        positive = event("enemy_armor", source, "C_WITCH", root, 12)
        action, = AUDIT.expected_visual_actions(source, [positive])
        self.assertEqual(action["targets"], ["ACT_E_R01_04"])
        self.assertEqual(action["impactKinds"], ["enemy_armor"])
        self.assertEqual(AUDIT.expected_visual_actions(source, [event("enemy_armor", source, "C_WITCH", root, 0)]), [])
        self.assertFalse(AUDIT.is_effective_bound_event(event("enemy_guard_absorb", source, "C_WITCH", root, 0), ("enemy_guard_absorb",)))

    def test_status_only_root_falls_back_to_source(self):
        source, root = "B_R03_B", "enemy:B_R03_B:1"
        action, = AUDIT.expected_visual_actions(source, [event("enemy_vent", source, source, root, 3500)])
        self.assertEqual(action["targets"], ["ACT_B_R03_B"])
        self.assertEqual(action["impactKinds"], ["enemy_vent"])


    def test_magnet_cover_requires_different_cue_and_hit_targets(self):
        source, root = "E_R03_04", "magnet:covered"
        events = [event("enemy_magnet_mark", source, "C_WITCH", root, 800),
                  event("telegraph_heavy", source, "C_WITCH", root),
                  event("enemy_hit", source, "C_SMITH", root, 25)]
        actions = AUDIT.expected_visual_actions(source, events)
        effect = "ACT_E_R03_04_magnet_pullcue"
        def row(step, target):
            return {"step":step, "rootActionID":root,"sourceID":source,"effectID":effect,"targetIDs":target,
                    "placement.cueX":"10","placement.cueY":"20","placement.impactX":"30","placement.impactY":"40"}
        cue, hit = row("cue_placement", "ERNA"), row("impact_placement", "AIRA")
        self.assertTrue(AUDIT.validate_cue_trace(actions,[cue,hit],{effect:1},1,0)["passed"])
        for wrong in ([row("cue_placement","AIRA"),hit], [cue,row("impact_placement","ERNA")]):
            self.assertFalse(AUDIT.validate_cue_trace(actions,wrong,{effect:1},1,0)["passed"])

    def test_magnet_lost_target_cannot_pass_with_an_impact_or_wrong_cancel(self):
        source, root = "E_R03_04", "magnet:lost"
        effect = "ACT_E_R03_04_magnet_pullcue"
        events = [event("enemy_magnet_mark",source,"C_WITCH",root,800),event("enemy_magnet_target_lost",source,"C_WITCH",root,0)]
        actions = AUDIT.expected_visual_actions(source,events)
        cue = {"step":"cue_placement","rootActionID":root,"sourceID":source,"effectID":effect,
               "targetIDs":"ERNA","placement.cueX":"10","placement.cueY":"20"}
        cancel = {"step":"cue_cancel:enemy_magnet_target_lost","rootActionID":root,"sourceID":source,"effectID":effect}
        self.assertTrue(AUDIT.validate_cue_trace(actions,[cue,cancel],{effect:1},1,0)["passed"])
        self.assertFalse(AUDIT.validate_cue_trace(actions,[cue,{**cancel,"step":"cue_cancel:cast_interrupt"}],{effect:1},1,0)["passed"])
        self.assertFalse(AUDIT.validate_cue_trace(actions,[cue],{effect:1},1,0)["passed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
