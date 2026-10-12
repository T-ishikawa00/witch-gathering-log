#!/usr/bin/env python3
"""Narrow source-contract regression for the enemy_cast_start presentation path.

This guards the exact integration seam that previously dropped the tell before
EffectCueCoordinator could start its planned cue. It is not a runtime render test.
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "native/WitchApp/LivingScene.swift"
EFFECTS = ROOT / "native/WitchApp/BattleEffects.swift"
COORDINATOR = ROOT / "native/WitchApp/EffectCueCoordinator.swift"


class EnemyCastStartDispatchTests(unittest.TestCase):
    def test_enemy_cast_start_reaches_tell_dispatch_and_impact_hold_contract(self):
        scene = SCENE.read_text()
        effects = EFFECTS.read_text()
        coordinator = COORDINATOR.read_text()

        present = scene.split("func present(_ event:CombatEvent)", 1)[1].split(
            "private func statusLabel", 1
        )[0]
        tell_condition = re.search(r"if\s+([^\{]+)\{", present)
        self.assertIsNotNone(tell_condition, "present() tell branch missing")
        self.assertIn('event.kind=="enemy_cast_start"', tell_condition.group(1))

        self.assertIn('"enemy_cast_start"', effects)
        self.assertIn("binding.telegraphKinds.contains(event.kind)", coordinator)
        self.assertIn("effectCues.hold(node,for:plan)", scene)
        self.assertIn("effectCues.pendingNode(for:plan.key)", scene)
        self.assertIn("effectCues.clearPending(plan.key)", scene)
        self.assertIn("BattleEffects.playImpact(id:plan.effectID,on:node)", scene)

    def test_mist_guard_uses_armor_event_and_enemy_owned_visual_target(self):
        effects = EFFECTS.read_text()
        scene = SCENE.read_text()
        self.assertIn('"ACT_E_R02_02": direct("ACT_E_R02_02_mist_guard", ["enemy_armor"])', effects)
        self.assertIn('let visualTargetIDs = event.kind == "enemy_armor" ? [event.sourceID] : [event.targetID]', scene)


if __name__ == "__main__":
    unittest.main(verbosity=2)
