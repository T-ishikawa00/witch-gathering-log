#!/usr/bin/env python3
"""Adversarial contract probes for effect_encounter_audit.py.

These tests intentionally express what an audit must reject. A failing test
means the runner currently admits malformed evidence; do not weaken the test
to match implementation behavior.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = ROOT / "tools/witch_native/effect_encounter_audit.py"
RUNNER_SHA256_AT_AUTHORING = "78392f7fe5fa84aacd4e0820593aeb151db52ee7ca99d6df0e1cdcf70d180794"
REVIEWED_AT = "2026-10-11T01:06:40+09:00"

spec = importlib.util.spec_from_file_location("effect_encounter_audit", RUNNER_PATH)
assert spec and spec.loader
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def valid_direct_case():
    action = {
        "mode": "direct", "root": "enemy:E_R02_02:1", "source": "E_R02_02",
        "effect": "ACT_E_R02_02_mist_guard", "targets": ["ERNA"],
        "impactKinds": ["enemy_armor"],
    }
    trace = [{
        "rootActionID": action["root"], "sourceID": action["source"],
        "effectID": action["effect"], "step": "direct_full:enemy_armor",
        "targetIDs": "ERNA", "placement.x": "0.5", "placement.y": "0.4",
    }]
    counts = {action["effect"]: 1}
    return action, trace, counts


class EffectEncounterAuditContractTests(unittest.TestCase):
    def test_empty_expected_actions_are_not_coverage(self):
        result = audit.validate_cue_trace([], [], {}, 0, 0)
        self.assertFalse(result["passed"], "empty expected actions must not be reported as cue coverage")

    def test_boolean_capacity_values_are_rejected(self):
        action, trace, counts = valid_direct_case()
        for peak, active in [(True, 0), (1, False)]:
            with self.subTest(peak=peak, active=active):
                result = audit.validate_cue_trace([action], trace, counts, peak, active)
                self.assertFalse(result["passed"], "bool must not satisfy numeric capacity evidence")

    def test_delivered_trace_requires_placement_coordinates(self):
        action, trace, counts = valid_direct_case()
        trace[0].pop("placement.x")
        trace[0].pop("placement.y")
        result = audit.validate_cue_trace([action], trace, counts, 1, 0)
        self.assertFalse(result["passed"], "delivered visual cue without measured placement must fail")

    def test_suppressed_direct_event_still_requires_correct_target(self):
        action, _, _ = valid_direct_case()
        trace = [{
            "rootActionID": action["root"], "sourceID": action["source"],
            "effectID": action["effect"], "step": "capacity_suppressed:enemy_armor",
            "targetIDs": "NOIR",
        }]
        result = audit.validate_cue_trace([action], trace, {}, 2, 0)
        self.assertFalse(result["passed"], "suppression must not bless a wrong recipient")

    def test_missing_and_extra_counters_are_rejected(self):
        action, trace, counts = valid_direct_case()
        missing = audit.validate_cue_trace([action], trace, {}, 1, 0)
        self.assertFalse(missing["passed"], "missing counter must not pass")
        extra = audit.validate_cue_trace([action], trace, {**counts, "ACT_UNEXPECTED": 1}, 1, 0)
        self.assertFalse(extra["passed"], "unmatched extra counter must not pass")

    def test_wrong_root_interrupt_does_not_cancel_expected_tell(self):
        source = "E_R03_03"
        events = [
            {"kind": "enemy_telegraph", "sourceID": source, "targetID": "C_WITCH", "rootActionID": "enemy:E_R03_03:1"},
            {"kind": "cast_interrupt", "sourceID": "C_WITCH", "targetID": source, "rootActionID": "other-root"},
        ]
        actions = audit.expected_visual_actions(source, events)
        self.assertEqual(actions, [], "a cancellation from a different root cannot authorize a cue")
        self.assertFalse(audit.validate_cue_trace(actions, [], {}, 0, 0)["passed"])

    def test_defeat_reward_contract_accepts_zero_delta(self):
        before = {"materials": {"moss": 4}, "currency": {"coin": 13}}
        after = {"materials": {"moss": 4}, "currency": {"coin": 13}}
        result = audit.compare_reward(before, after, {"boss": False}, won=False)
        self.assertTrue(result["materialsMatch"] and result["currencyMatch"])

    def test_build_receipt_rejects_changed_pinned_binding_source(self):
        source = ROOT / "native/WitchApp/BattleEffects.swift"
        current_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "WitchGathering.app"
            app.mkdir()
            exe = app / "WitchGathering"
            exe.write_bytes(b"audit-probe-executable")
            receipt = {
                "status": "SIMULATOR_BUILD_PASS", "bundle": str(app.resolve()),
                "executable_sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
                "source_sha256": {"native/WitchApp/BattleEffects.swift": "0" * 64},
            }
            (app.parent / "BUILD_RECEIPT.json").write_text(json.dumps(receipt))
            with self.assertRaises(ValueError):
                audit.assert_build(app.resolve())

    def test_build_receipt_missing_scene_source_hash_is_a_gap(self):
        """Desired contract: app identity must include all cue-routing sources."""
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "WitchGathering.app"
            app.mkdir()
            exe = app / "WitchGathering"
            exe.write_bytes(b"audit-probe-executable")
            receipt = {
                "status": "SIMULATOR_BUILD_PASS", "bundle": str(app.resolve()),
                "executable_sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
                "source_sha256": {
                    "native/WitchApp/BattleEffects.swift": audit.sha_file(ROOT / "native/WitchApp/BattleEffects.swift")
                },
            }
            (app.parent / "BUILD_RECEIPT.json").write_text(json.dumps(receipt))
            try:
                audit.assert_build(app.resolve())
            except ValueError:
                rejected = True
            else:
                rejected = False
            self.assertTrue(rejected, "receipt lacking EffectCueCoordinator/LivingScene hashes must be rejected")


if __name__ == "__main__":
    print(json.dumps({"runner": str(RUNNER_PATH), "runnerSHA256AtAuthoring": RUNNER_SHA256_AT_AUTHORING,
                      "reviewedAt": REVIEWED_AT}, ensure_ascii=False))
    unittest.main(verbosity=2)
