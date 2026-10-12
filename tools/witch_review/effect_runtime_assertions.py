"""Assertions for effect runtime captures; these evaluate receipts, not visuals.

The simulator runner calls this after a battle has been committed and the art
receipt has been read back. The analyzer never dispatches game commands.
"""
from __future__ import annotations

from typing import Any


def decoded_art(art_receipt: dict[str, Any] | None) -> dict[str, Any]:
    value = (art_receipt or {}).get("value")
    if isinstance(value, str):
        import json
        try:
            value = json.loads(value)
        except Exception:
            return {}
    return value if isinstance(value, dict) else {}


def _placement_complete(row: dict[str, Any]) -> bool:
    required = {
        "targetIDs", "placement.sourceAnchor", "placement.targetAnchor",
        "placement.cueX", "placement.cueY", "placement.impactX",
        "placement.impactY", "placement.rotation", "placement.scaleX",
    }
    return required.issubset(row)


def analyze_armor(events: list[dict[str, Any]], art: dict[str, Any],
                  save_equal: bool, hp_mismatches: Any) -> dict[str, Any]:
    expected = [e for e in events if e.get("kind") == "enemy_armor" and e.get("sourceID") == "E_R02_02" and int(e.get("amount", 0)) > 0]
    wanted_roots = {e.get("rootActionID") for e in expected if e.get("rootActionID")}
    effect = art.get("effects", {}) if isinstance(art, dict) else {}
    trace = effect.get("cueTrace", [])
    visual = [row for row in trace if row.get("step") in ("direct_full:enemy_armor", "coalesced:enemy_armor")]
    by_root: dict[str, list[dict[str, Any]]] = {}
    for row in visual:
        by_root.setdefault(row.get("rootActionID", ""), []).append(row)
    all_roots_recorded_once = set(by_root) == wanted_roots and all(len(rows) == 1 for rows in by_root.values())
    every_enemy_targeted = all(
        [part for part in row.get("targetIDs", "").split(",") if part] == ["ACT_E_R02_02"]
        for row in visual
    ) and bool(visual)
    placements_complete = all(_placement_complete(row) for row in visual)
    peak = int(effect.get("peakCombat", -1))
    active = int(effect.get("activeCombat", -1))
    hp_empty = hp_mismatches == {} or hp_mismatches == "{}"
    checks = {
        "every_positive_armor_root_has_one_visual": all_roots_recorded_once,
        "every_visual_targets_defending_enemy": every_enemy_targeted,
        "every_visual_has_source_target_placement": placements_complete,
        "combat_effect_peak_at_most_two": 0 <= peak <= 2,
        "combat_effects_cleaned_after_battle": active == 0,
        "presentation_hp_matches_committed_result": hp_empty,
        "save_bytes_stable_after_restart": save_equal,
    }
    return {
        "case": "E_R02_02_armor",
        "status": "PASS" if all(checks.values()) else "FAIL_OR_PARTIAL",
        "eventCount": len(expected),
        "visualCount": len(visual),
        "missingRoots": sorted(wanted_roots - set(by_root)),
        "unexpectedRoots": sorted(set(by_root) - wanted_roots),
        "visualRecords": visual,
        "peakCombat": peak,
        "activeCombatAfterBattle": active,
        "checks": checks,
    }


def analyze_tool_combo(events: list[dict[str, Any]], art: dict[str, Any],
                       save_equal: bool, hp_mismatches: Any) -> dict[str, Any]:
    tells = [e for e in events if e.get("kind") == "enemy_cast_start" and e.get("sourceID") == "E_R03_03"]
    roots = {e.get("rootActionID") for e in tells if e.get("rootActionID")}
    hit_roots = {e.get("rootActionID") for e in events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "E_R03_03"}
    interrupted_roots = {e.get("rootActionID") for e in events if e.get("kind") == "cast_interrupt" and e.get("targetID") == "E_R03_03"}
    hit_roots &= roots
    interrupted_roots &= roots
    effect = art.get("effects", {}) if isinstance(art, dict) else {}
    trace = effect.get("cueTrace", [])
    records: dict[str, list[dict[str, Any]]] = {}
    for row in trace:
        root = row.get("rootActionID", "")
        if root in roots and row.get("sourceID") == "E_R03_03":
            records.setdefault(root, []).append(row)
    hit_contract = all(
        any(r.get("step", "").startswith("cue_hold:") for r in records.get(root, []))
        and any(r.get("step") == "impact_advance" for r in records.get(root, []))
        and not any(r.get("step", "").startswith("cue_cancel:") for r in records.get(root, []))
        for root in hit_roots
    )
    cancel_contract = all(
        any(r.get("step", "").startswith("cue_hold:") for r in records.get(root, []))
        and any(r.get("step") == "cue_cancel:cast_interrupt" for r in records.get(root, []))
        and not any(r.get("step") == "impact_advance" for r in records.get(root, []))
        for root in interrupted_roots
    )
    # Only the R6 party→enemy interrupt form cancels this enemy's tell. The
    # reverse enemy→party form has a party target and must not be in this set.
    reverse_interrupt_roots = {
        e.get("rootActionID") for e in events
        if e.get("kind") == "cast_interrupt" and e.get("sourceID") == "E_R03_03"
        and e.get("targetID", "").startswith("C_")
    }
    no_reverse_cancel = all(
        not any(r.get("step", "").startswith("cue_cancel:") for r in records.get(root, []))
        for root in reverse_interrupt_roots & roots
    )
    peak = int(effect.get("peakCombat", -1))
    active = int(effect.get("activeCombat", -1))
    hp_empty = hp_mismatches == {} or hp_mismatches == "{}"
    checks = {
        "five_expected_enemy_cast_roots": len(roots) == 5,
        "two_hit_roots_advance_to_impact": len(hit_roots) == 2 and hit_contract,
        "three_interrupted_roots_cancel_without_impact": len(interrupted_roots) == 3 and cancel_contract,
        "enemy_to_party_interrupt_does_not_cancel_enemy_tell": no_reverse_cancel,
        "combat_effect_peak_at_most_two": 0 <= peak <= 2,
        "combat_effects_cleaned_after_battle": active == 0,
        "presentation_hp_matches_committed_result": hp_empty,
        "save_bytes_stable_after_restart": save_equal,
    }
    return {
        "case": "E_R03_03_tool_combo",
        "status": "PASS" if all(checks.values()) else "FAIL_OR_PARTIAL",
        "tellRoots": sorted(roots),
        "impactRoots": sorted(hit_roots),
        "interruptedRoots": sorted(interrupted_roots),
        "reverseInterruptRoots": sorted(reverse_interrupt_roots),
        "traceByRoot": records,
        "peakCombat": peak,
        "activeCombatAfterBattle": active,
        "checks": checks,
    }
