#!/usr/bin/env python3
"""Source-contract checks for the isolated synthetic effect-budget QA runner.

These tests validate guard rails and dispatch relationships only; they are not
Simulator rendering evidence and do not execute GameEngine commands.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
QA = (ROOT / "native/WitchApp/EffectBudgetRegressionQA.swift").read_text()
SCENE = (ROOT / "native/WitchApp/LivingScene.swift").read_text()
COORDINATOR = (ROOT / "native/WitchApp/EffectCueCoordinator.swift").read_text()


class EffectBudgetQAContractTests(unittest.TestCase):
    def test_qa_runner_requires_isolated_mode_explicit_flag_and_save_key(self):
        self.assertIn('args.contains("--qa-isolated")', QA)
        self.assertIn('args.contains("--qa-effect-budget-regression")', QA)
        self.assertIn('rawKey=args.first(where:{$0.hasPrefix("--qa-save-key=")})', QA)
        self.assertIn('saveURL.lastPathComponent.hasPrefix("qa-")', QA)

    def test_qa_runner_uses_synthetic_events_without_engine_dispatch(self):
        self.assertIn("SYNTHETIC_COMBAT_EVENTS_NO_ENGINE_DISPATCH_NO_REWARDS_NOT_NATURAL_BATTLE", QA)
        self.assertIn("scene.prepareCombatEffects", QA)
        self.assertIn("scene.present", QA)
        self.assertNotIn("engine.dispatch", QA)
        self.assertIn('"saveBytesUnchanged"', QA)
        self.assertIn('"revisionUnchanged"', QA)

    def test_tool_combo_cancellable_plan_requires_same_root_interrupt_to_enemy(self):
        gate = COORDINATOR.split("let isInterruptedToolCast", 1)[1].split("let impactKind", 1)[0]
        self.assertIn('actor == "ACT_E_R03_03"', gate)
        self.assertIn('$0.kind == "cast_interrupt"', gate)
        self.assertIn("$0.rootActionID == root", gate)
        self.assertIn("$0.targetID == tell.sourceID", gate)
        self.assertIn("sourceID:event.targetID", SCENE)

    def test_duplicate_is_checked_before_node_creation_or_transient_preemption(self):
        body = SCENE.split("private func startEffectCue", 1)[1].split("private func presentCombatEffect", 1)[0]
        self.assertLess(body.index("effectCues.emitted.contains"), body.index("BattleEffects.makeNode"))
        self.assertLess(body.index("BattleEffects.makeNode"), body.index("preempted_for_cue"))

    def test_armor_reuse_is_same_event_and_emissions_record_target_and_placement(self):
        body = SCENE.split("private func presentCombatEffect", 1)[1].split("func finishCombatEffects", 1)[0]
        self.assertIn('event.kind == "enemy_armor"', body)
        self.assertIn('"effectEventKind"] as? String)==event.kind', body)
        self.assertIn('"coalesced:"+event.kind', body)
        self.assertIn('targets:targets,placement:placement', body)
        self.assertIn('"capacity_suppressed:"+event.kind', body)
        self.assertIn('"cue_placement"', SCENE)
        self.assertIn('"impact_placement"', SCENE)

    def test_synthetic_qa_covers_five_casts_reverse_interrupt_duplicate_and_cap(self):
        for marker in (
            '"tool_combo_two_impacts_three_cancels"',
            '"cancelledCueTargetsRemainOriginalVictim"',
            '"enemy_to_party_interrupt_does_not_cancel"',
            '"unmatched_tell_without_impact_or_interrupt_stays_effect_free"',
            '"expired_duplicate_at_capacity_does_not_evict"',
            '"two_held_cues_suppress_third_with_trace"',
            '"armor_three_roots_coalesce"',
        ):
            self.assertIn(marker, QA)

    def test_synthetic_runner_requires_current_cases_for_overall_pass(self):
        self.assertIn('"allCasesPass":cases.count==36', QA)
        self.assertIn('"r02_magic_support_arc_recipient_path"', QA)
        self.assertIn('"r05_light_transfer_recipient_path"', QA)
        self.assertIn('"r02_magic_support_arc_missing_recipient_no_fallback"', QA)
        self.assertIn('"unrelated_effect_placement_unchanged"', QA)
        self.assertIn('unmatchedTrace.contains{($0["step"] as? String)=="unplanned_tell:enemy_telegraph"}', QA)
        self.assertIn('($0["targetIDs"] as? String)=="ERNA"', QA)
        self.assertIn('C_WITCH → ERNA', QA)
        self.assertIn('"transfer_notice_lifetime_pause_and_expiry"', QA)
        self.assertIn('"transfer_notice_cancelled_cue_never_arrives"', QA)

    def test_support_notices_are_impact_only_geometry_checked_and_scene_pausable(self):
        for marker in (
            'TransferPathGeometry.noticeNodeName',
            'TransferPathGeometry.noticeAnchorNodeName',
            'TransferPathGeometry.noticeLifetime',
            '"supportLabelAppearsOnlyAtImpact"',
            '"supportLabelTextAndSingleInstance"',
            '"supportLabelUprightAnd34By20"',
            '"supportLabelSixPointBelowRecipientBounds"',
            'scene.isPaused=true',
            'scene.isPaused=false',
            '"heldCueCancelledBySameRootInterrupt"',
            '"cancelledEffectParentRemoved"',
            '"noSupportImpactWasPresented"',
        ):
            self.assertIn(marker, QA)
        self.assertIn('"transfer_notice_lifetime_pause_and_expiry"', (ROOT / "tools/witch_review/run_effect_budget_regression.py").read_text())
        self.assertIn('"transfer_notice_cancelled_cue_never_arrives"', (ROOT / "tools/witch_review/run_effect_budget_regression.py").read_text())

    def test_transfer_path_cases_check_real_converted_children_and_bounded_arrival(self):
        for marker in (
            'pathChildPoint(r02Effect,TransferPathGeometry.startNodeName)',
            'pathChildPoint(r02Effect,TransferPathGeometry.endNodeName)',
            'pathChildPoint(r05Effect,TransferPathGeometry.startNodeName)',
            'pathChildPoint(r05Effect,TransferPathGeometry.endNodeName)',
            'arrivalAccentOnlyAtImpactAndSevenPointRadius',
            'transferPathChildrenCleanedAfterFinish',
            'unknownDegenerateAndNonfiniteInputsAreSideEffectFree',
            'r02_magic_support_arc_missing_recipient_no_fallback',
            'unrelated_effect_placement_unchanged',
        ):
            self.assertIn(marker, QA)
        self.assertIn('child.convert(.zero,to:scene)', QA)

    def test_runner_pins_transfer_geometry_source(self):
        self.assertIn('"TransferPathGeometry"', (ROOT / "tools/witch_review/run_effect_budget_regression.py").read_text())
        self.assertIn('"r02_magic_support_arc_recipient_path"', (ROOT / "tools/witch_review/run_effect_budget_regression.py").read_text())

    def test_suppressed_notice_fixture_holds_two_future_impact_cues_without_applying_hits(self):
        source=(ROOT / "native/WitchApp/EffectBudgetRegressionQA.swift").read_text()
        case=source.split('for reason in ["cast_interrupt","enemy_magnet_target_lost"]',1)[1].split("let finalState=state",1)[0]
        self.assertIn('event("enemy_hit","E_R01_01","C_SMITH",1,root+":block1",43_800)',case)
        self.assertIn('event("enemy_hit","E_R02_01","C_WITCH",1,root+":block2",43_800)',case)
        self.assertIn('scene.present(blockers[0]);scene.present(blockers[2])',case)
        self.assertNotIn('scene.present(blockers[1])',case)
        self.assertIn('blockerHeldRoots==Set([root+":block1",root+":block2"])',case)
        self.assertIn('"blockerHPUnchangedBeforeMark":blockerHPUnchanged',case)

    def test_suppressed_magnet_notices_are_root_scoped_and_terminal_checked(self):
        for reason in ("cast_interrupt", "enemy_magnet_target_lost"):
            self.assertIn('"magnet_suppressed_cancel_"+reason', QA)
        block = QA.split('for reason in ["cast_interrupt","enemy_magnet_target_lost"] {', 1)[1]
        block = block.split('let finalState=state', 1)[0]
        self.assertIn('"differentRootTerminalDoesNotRemoveNotice"', block)
        self.assertIn('"sameRootTerminalRemovesNoticeImmediately"', block)
        self.assertIn('"noImpactOrHitApplied"', block)
        self.assertIn('"HPUnchanged"', block)


if __name__ == "__main__":
    unittest.main(verbosity=2)
