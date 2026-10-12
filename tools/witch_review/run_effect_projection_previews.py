#!/usr/bin/env python3
"""Run isolated effect previews on one supplied Simulator; keep preview separate from campaign battles."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import pathlib
import signal
import subprocess
import time
import uuid
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUNDLE_ID = "local.witch.autonomous.r1"
PARTY_ALIASES = {
    "C_WITCH": "ERNA",
    "C_APPRENTICE": "LUNA",
    "C_SMITH": "AIRA",
    "C_FAMILIAR": "NOIR",
}
CASES = {
    "E02_MAGIC_SUPPORT": ("multi", "R02", "ACT_E_R02_04_support_arc"),
    "E04_FOLLOWUP": ("multi", "R04", "ACT_E_R04_01_pursuit"),
    "E03_PINCER_FRONT": ("multi", "R03", "ACT_E_R03_01_pincer_guard"),
    "E03_PINCER_BEHIND": ("multi", "R03", "ACT_E_R03_01_pincer_guard"),
    "B02_MIRROR": ("mechanic", "R02", "ACT_B_R02_B_mirror_bolt"),
    "B05_DEER": ("mechanic", "R05", "ACT_B_R05_B_seed_wave"),
    "E05_TRANSFER": ("mechanic", "R05", "ACT_E_R05_03_light_transfer"),
    "E05_GUARD": ("mechanic", "R05", "ACT_E_R05_02_guard_attack"),
    "E05_POISON": ("mechanic", "R05", "ACT_E_R05_04_heal_toxin"),
    "E03_MAGNET": ("mechanic", "R03", "ACT_E_R03_04_magnet_pullcue"),
    "E03_MAGNET_INTERRUPT": ("mechanic", "R03", "ACT_E_R03_04_magnet_pullcue"),
}

# R4 scene map, independent of the app's receipt claims.
AREA_SUFFIX = {
    "E02_MAGIC_SUPPORT": "03", "E04_FOLLOWUP": "01",
    "E03_PINCER_FRONT": "01", "E03_PINCER_BEHIND": "01",
    "B02_MIRROR": "04", "B05_DEER": "04", "E05_TRANSFER": "03",
    "E05_GUARD": "01", "E05_POISON": "03", "E03_MAGNET": "03",
    "E03_MAGNET_INTERRUPT": "03",
}


def current_background_matches(case_id: str, art: dict[str, Any], region: str) -> bool:
    states = art.get("states", {})
    area = art.get("areaBackground")
    if area is None:
        # Legacy reports precede R015 area routing; keep their old evidence rule.
        return states.get(f"background_BG_{region}_FIELD") is True
    if not isinstance(area, dict):
        return False
    suffix = AREA_SUFFIX[case_id]
    expected_id = (f"BG_{region}_FIELD" if suffix == "01" else
                   f"BG_{region}_BOSS" if suffix == "04" else f"VAR_A_{region}_{suffix}")
    return (area.get("regionID") == region
            and area.get("areaID") == f"A_{region}_{suffix}"
            and area.get("sceneID") == f"SCN_A_{region}_{suffix}"
            and area.get("renderedBackgroundID") == expected_id
            and not area.get("fallbackReason")
            and states.get("background_" + expected_id) is True)


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(path: pathlib.Path) -> str:
    return sha_bytes(path.read_bytes())


def parse_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text())


def parse_receipt(path: pathlib.Path, started: float, timeout: float) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if path.exists() and path.stat().st_mtime > started:
                outer = parse_json(path)
                date = outer.get("date")
                if not isinstance(date, str) or not date:
                    raise ValueError("receipt has no timestamp")
                raw = outer.get("value")
                inner = json.loads(raw) if isinstance(raw, str) else raw
                if not isinstance(inner, dict):
                    raise ValueError("receipt value is not an object")
                return {"envelope": outer, "value": inner}
        except (OSError, ValueError, TypeError):
            pass
        time.sleep(0.2)
    raise TimeoutError(f"No fresh, parseable receipt at {path}")


def canonical(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: canonical(v) for k, v in sorted(value.items())}
    if isinstance(value, list):
        return [canonical(v) for v in value]
    return value


def canonical_snapshot(value: Any) -> Any:
    """Normalize only snapshot fields modeled as Sets by WitchGameCore."""
    if not isinstance(value, dict):
        return canonical(value)
    normalized = dict(value)
    for key in ("unlockedRegionIDs", "completedEncounterIDs", "completedResearchIDs",
                "ownedCosmeticIDs", "ownedFurnitureIDs", "placedFurnitureIDs",
                "partyActorIDs", "pendingPurchaseIDs"):
        if isinstance(normalized.get(key), list):
            normalized[key] = sorted(normalized[key])
    return canonical(normalized)


def display_id(raw: str) -> str:
    return PARTY_ALIASES.get(raw, raw if raw.startswith("ACT_") else "ACT_" + raw)


def trace_rows(report: dict[str, Any]) -> list[dict[str, Any]]:
    if report.get("scope", "").startswith("R6_TIMELINE"):
        art = report.get("artAudit", {})
    else:
        raw_art = report.get("battleArtReceipt", "")
        try:
            art = json.loads(raw_art) if isinstance(raw_art, str) else raw_art
        except (ValueError, TypeError):
            art = {}
    effects = art.get("effects", {}) if isinstance(art, dict) else {}
    rows = effects.get("cueTrace", []) if isinstance(effects, dict) else []
    return rows if isinstance(rows, list) else []


def report_events(report: dict[str, Any]) -> list[dict[str, Any]]:
    candidates: list[Any] = []
    result = report.get("result")
    if isinstance(result, dict):
        candidates.extend(result.get("events", []))
    candidates.extend(report.get("events", []))
    candidates.extend(report.get("relevantEvents", []))
    out: list[dict[str, Any]] = []
    seen: dict[tuple[Any, ...], dict[str, Any]] = {}
    for event in candidates:
        if not isinstance(event, dict):
            continue
        # Reports repeat the same Core event in full and compact projections.
        # Which array carries diagnostics differs across report schemas. Keep
        # the complete non-conflicting evidence instead of discarding it when
        # a compact representation happens to be encountered first.
        key = tuple(event.get(k) for k in ("kind", "sourceID", "targetID", "amount", "rootActionID", "timestampMs"))
        if key not in seen:
            merged = dict(event)
            seen[key] = merged
            out.append(merged)
        else:
            merged = seen[key]
            for field, value in event.items():
                if value is None:
                    continue
                if merged.get(field) is None:
                    merged[field] = value
                elif merged[field] != value:
                    raise ValueError(f"Conflicting event projections for {key!r}: {field}")
    return out


def placement_rows(trace: list[dict[str, Any]], effect: str, root: str | None = None) -> list[dict[str, Any]]:
    return [r for r in trace if r.get("effectID") == effect
            and (root is None or r.get("rootActionID") == root)
            and r.get("step") in {"cue_placement", "impact_placement", "direct_full:enemy_armor",
                                  "coalesced:enemy_armor", "direct_full:enemy_guard_absorb",
                                  "coalesced:enemy_guard_absorb", "direct_full:enemy_guard_stance",
                                  "direct_full:dot_applied", "coalesced:dot_applied",
                                  "direct_full:enemy_reflect_projectile", "coalesced:enemy_reflect_projectile",
                                  "direct_full:enemy_reflect_stance", "coalesced:enemy_reflect_stance"}]


def exact_targets(row: dict[str, Any]) -> set[str]:
    value = row.get("targetIDs", "")
    if isinstance(value, list):
        return set(value)
    if isinstance(value, str):
        return {p for p in value.split(",") if p}
    return set()


def actor_is_loaded(art: dict[str, Any], raw_id: str) -> bool:
    display = display_id(raw_id)
    states = art.get("states", {})
    actors = art.get("actorIDs", [])
    geometry = art.get("geometry", {})
    node = geometry.get(display, {}) if isinstance(geometry, dict) else {}
    width, height = node.get("width"), node.get("height")
    finite_positive = lambda v: type(v) in (int, float) and math.isfinite(v) and v > 0
    return (isinstance(states, dict) and states.get(display + ":battle_entry_walk") is True
            and display in actors
            and states.get("load_" + display) is not False
            and finite_positive(width) and finite_positive(height))


def require_pair(trace: list[dict[str, Any]], effect: str, root: str, target_ids: set[str]) -> bool:
    rows = placement_rows(trace, effect, root)
    if len(rows) != 2:
        return False
    by_step = {row.get("step"): row for row in rows}
    return set(by_step) == {"cue_placement", "impact_placement"} and all(exact_targets(row) == target_ids for row in rows)


def require_direct(trace: list[dict[str, Any]], effect: str, root: str, steps: set[str], target_ids: set[str]) -> bool:
    rows = [r for r in trace if r.get("effectID") == effect and r.get("rootActionID") == root and r.get("step") in steps]
    return len(rows) == 1 and exact_targets(rows[0]) == target_ids


def _trace_events_for(trace: list[dict[str, Any]], effect: str, root: str) -> list[dict[str, Any]]:
    steps = {"cue_placement", "impact_placement", "impact_advance",
             "cue_cancel:enemy_magnet_target_lost", "cue_cancel:cast_interrupt",
             "capacity_suppressed:cue", "missing_target:cue", "missing_target:impact"}
    return [r for r in trace if r.get("effectID") == effect and r.get("rootActionID") == root
            and r.get("step") in steps]

def assert_magnet_contract(case_id: str, events: list[dict[str, Any]], trace: list[dict[str, Any]],
                           effect: str, report: dict[str, Any]) -> dict[str, bool]:
    """Independent strict projection assertions; does not infer Core contract from art trace."""
    terminal_censored_value = report.get("terminalCensoredRoots", [])
    terminal_censored_roots = set(terminal_censored_value) if isinstance(terminal_censored_value, list) else set()
    party = {"C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"}
    params = report.get("candidateMagnetParameters", {})
    params_ok = isinstance(params, dict) and params.get("markWindowMs") == 800 and params.get("strikeWindupMs") == 1_200 and params.get("strikeCoefficientBP") == 12_500
    horizon = report.get("fixtureMaxDurationMs")
    elapsed = report.get("elapsedWholeSeconds")
    horizon_ok = type(horizon) is int and horizon == 12_000 and type(elapsed) is int and elapsed * 1_000 >= horizon
    party_hp = report.get("remainingPartyHP", {})
    enemy_hp = report.get("remainingEnemyHP", {})
    hp_maps_ok = isinstance(party_hp, dict) and isinstance(enemy_hp, dict)
    marks = [e for e in events if e.get("kind") == "enemy_magnet_mark" and e.get("sourceID") == "E_R03_04"]
    all_marks_well_formed = bool(marks) and all(isinstance(e.get("rootActionID"), str) and e.get("rootActionID")
        and e.get("targetID") in party for e in marks)
    roots = {e.get("rootActionID") for e in marks if isinstance(e.get("rootActionID"), str) and e.get("rootActionID")}
    exact_mark_cues = True
    exact_impacts = True
    correct_cancellations = True
    terminal_handling = True
    no_unmarked_effect = True
    no_capacity_loss = True
    timing_matches = params_ok
    hit_diagnostics_valid = True
    censor_roots_valid = True
    typed_interrupt_roots = {e.get("rootActionID") for e in events if e.get("kind") == "cast_interrupt"
                             and e.get("targetID") == "E_R03_04" and e.get("sourceID") in party}
    for root in roots:
        root_marks = [e for e in marks if e.get("rootActionID") == root]
        if len(root_marks) != 1:
            exact_mark_cues = False
            continue
        marked = root_marks[0]["targetID"]
        marked_alias = display_id(marked)
        mark_time = root_marks[0].get("timestampMs")
        if type(mark_time) is not int or mark_time < 0 or root_marks[0].get("amount") != 800:
            timing_matches = False
        hit_rows = [e for e in events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "E_R03_04" and e.get("rootActionID") == root]
        lost_rows = [e for e in events if e.get("kind") == "enemy_magnet_target_lost" and e.get("sourceID") == "E_R03_04" and e.get("rootActionID") == root]
        interrupt_rows = [e for e in events if e.get("kind") == "cast_interrupt" and e.get("rootActionID") == root
                          and e.get("targetID") == "E_R03_04" and e.get("sourceID") in party]
        heavy_tells = [e for e in events if e.get("kind") == "telegraph_heavy" and e.get("sourceID") == "E_R03_04" and e.get("rootActionID") == root]
        cue = [r for r in trace if r.get("effectID") == effect and r.get("rootActionID") == root and r.get("step") == "cue_placement"]
        hold = [r for r in trace if r.get("effectID") == effect and r.get("rootActionID") == root and r.get("step") == "cue_hold:enemy_magnet_mark"]
        cancels = [r for r in trace if r.get("effectID") == effect and r.get("rootActionID") == root and
                   r.get("step") in {"cue_cancel:enemy_magnet_target_lost", "cue_cancel:cast_interrupt"}]
        if len(cue) != 1 or len(hold) != 1 or cue[0].get("sourceID") != "E_R03_04" or exact_targets(cue[0]) != {marked_alias}:
            exact_mark_cues = False
        else:
            # Require finite coordinates so a matching label cannot mask an unplaced sprite.
            for k in ("placement.impactX", "placement.impactY"):
                try: value = float(cue[0].get(k, "nan"))
                except (TypeError, ValueError): value = float("nan")
                if not math.isfinite(value): exact_mark_cues = False
        if len(hit_rows) > 1:
            exact_impacts = False
        tell_before_deadline = (type(mark_time) is int and any(
            type(e.get("timestampMs")) is int and e["timestampMs"] <= mark_time + 800 for e in lost_rows + interrupt_rows))
        if heavy_tells:
            if len(heavy_tells) != 1 or heavy_tells[0].get("targetID") != marked or type(heavy_tells[0].get("timestampMs")) is not int or heavy_tells[0]["timestampMs"] != mark_time + 800:
                timing_matches = False
        elif not (lost_rows or interrupt_rows or (root in terminal_censored_roots and params_ok and horizon_ok
                                                 and type(mark_time) is int and mark_time + 800 > horizon)) or (lost_rows or interrupt_rows) and not tell_before_deadline:
            timing_matches = False
        if hit_rows:
            hit = hit_rows[0]
            diagnostic = hit.get("diagnostics")
            if (hit.get("sourceID") != "E_R03_04" or hit.get("targetID") not in party
                    or not isinstance(diagnostic, dict)
                    or diagnostic.get("candidateMagnetCoefficientBP") != 12_500):
                hit_diagnostics_valid = False
            impacts = [r for r in trace if r.get("effectID") == effect and r.get("rootActionID") == root and r.get("step") == "impact_placement"]
            if len(impacts) != 1 or exact_targets(impacts[0]) != {display_id(hit["targetID"])} or impacts[0].get("sourceID") != "E_R03_04":
                exact_impacts = False
            if type(hit.get("timestampMs")) is not int or hit["timestampMs"] != mark_time + 2_000:
                timing_matches = False
            if lost_rows or interrupt_rows or cancels:
                terminal_handling = False
        else:
            terminal = bool(lost_rows or interrupt_rows or root in terminal_censored_roots)
            if not terminal: terminal_handling = False
            if lost_rows and (not all(e.get("targetID") == marked for e in lost_rows)
                              or not any(r.get("step") == "cue_cancel:enemy_magnet_target_lost" and r.get("sourceID") == "E_R03_04" for r in cancels)):
                correct_cancellations = False
            if interrupt_rows and not any(r.get("step") == "cue_cancel:cast_interrupt" and r.get("sourceID") == "E_R03_04" for r in cancels):
                correct_cancellations = False
            if root in terminal_censored_roots:
                target_alive = hp_maps_ok and type(party_hp.get(marked)) is int and party_hp[marked] > 0
                enemy_alive = hp_maps_ok and type(enemy_hp.get("E_R03_04")) is int and enemy_hp["E_R03_04"] > 0
                horizon_censored = params_ok and horizon_ok and type(mark_time) is int and mark_time + 2_000 > horizon
                if lost_rows or interrupt_rows or not target_alive or not enemy_alive or not horizon_censored:
                    censor_roots_valid = False
            if any(r.get("step") == "impact_placement" or r.get("step") == "impact_advance" for r in _trace_events_for(trace,effect,root)):
                exact_impacts = False
        if any(r.get("step") == "capacity_suppressed:cue" for r in _trace_events_for(trace,effect,root)):
            no_capacity_loss = False
    # Validate every explicit censor independently, including the negative case
    # where a trace both reports censoring and later contains a hit/loss/interrupt.
    for censored_root in terminal_censored_roots:
        censored_marks = [e for e in marks if e.get("rootActionID") == censored_root]
        valid_mark = len(censored_marks) == 1 and type(censored_marks[0].get("timestampMs")) is int
        target = censored_marks[0].get("targetID") if valid_mark else None
        mark_time = censored_marks[0].get("timestampMs") if valid_mark else None
        no_terminal_event = not any(
            e.get("rootActionID") == censored_root
            and ((e.get("kind") == "enemy_hit" and e.get("sourceID") == "E_R03_04")
                 or (e.get("kind") == "enemy_magnet_target_lost" and e.get("sourceID") == "E_R03_04")
                 or (e.get("kind") == "cast_interrupt" and e.get("targetID") == "E_R03_04" and e.get("sourceID") in party))
            for e in events)
        valid_horizon = params_ok and horizon_ok and type(mark_time) is int and mark_time + 2_000 > horizon
        valid_hp = (hp_maps_ok and type(party_hp.get(target)) is int and party_hp[target] > 0
                    and type(enemy_hp.get("E_R03_04")) is int and enemy_hp["E_R03_04"] > 0)
        if not (valid_mark and no_terminal_event and valid_horizon and valid_hp):
            censor_roots_valid = False

    # The two cases have distinct expectations. An interrupted run must actually contain a typed, same-root enemy interrupt.
    typed_interrupt = case_id != "E03_MAGNET_INTERRUPT" or any(
        e.get("kind") == "cast_interrupt" and e.get("targetID") == "E_R03_04"
        and e.get("sourceID") in party and e.get("rootActionID") in roots for e in events)
    # This diagnostic intentionally has no effectID. Detect it by source + step,
    # in both cases; effectID-based filtering would silently miss the regression.
    no_unmarked_effect = not any(r.get("sourceID") == "E_R03_04"
                                 and r.get("step") == "unmarked_magnet_hit" for r in trace)
    # No extra cue or impact root may be smuggled into apparent coverage.
    marked_roots = roots
    effect_rows = [r for r in trace if r.get("effectID") == effect and r.get("step") in {"cue_placement", "impact_placement"}]
    exact_trace_roots = all(r.get("rootActionID") in marked_roots for r in effect_rows)
    return {
        "magnetMarkEventSourceRootAndPartyTarget": all_marks_well_formed,
        "eachMarkHasExactLockedTargetCue": exact_mark_cues,
        "hitImpactMatchesActualHitRecipient": exact_impacts,
        "lossOrInterruptCancelsWithoutImpact": correct_cancellations and terminal_handling,
        "interruptIsTypedSameRootAndTargetsEnemy": typed_interrupt,
        "noGenericHeavyInventsMagnetEffect": no_unmarked_effect,
        "noMagnetCueSuppressedByCapacity": no_capacity_loss,
        "candidateTimingMatches800Plus1200": timing_matches,
        "actualMagnetHitsCarry12500CandidateDiagnostic": hit_diagnostics_valid,
        "explicitCensorHasHorizonAndAliveProof": censor_roots_valid and terminal_censored_roots.issubset(roots),
        "noExtraEffectRoot": exact_trace_roots,
    }

def assess_case(case_id: str, report: dict[str, Any], region: str, effect: str,
                initial_sha: str, after_save: bytes, readback: dict[str, Any], hp_envelope: dict[str, Any] | None) -> dict[str, bool]:
    events = report_events(report)
    trace = trace_rows(report)
    effects = report.get("artAudit", {}).get("effects", {}) if isinstance(report.get("artAudit"), dict) else {}
    if not effects:
        raw_art = report.get("battleArtReceipt", "")
        try:
            effects = json.loads(raw_art).get("effects", {})
        except (ValueError, TypeError):
            effects = {}
    checks: dict[str, bool] = {
        "previewStatus": report.get("status") in {"NO_REWARD_SIMULATION_PREVIEW_PASS", "NO_REWARD_SIMULATION_PREVIEW_PASS"},
        "unapprovedPreviewScope": "PREVIEW" in str(report.get("scope", "")).upper()
            and "NO_ENGINE" in str(report.get("scope", "")).upper() or report.get("scope") == "NO_REWARD_SIMULATION_PREVIEW",
        "revisionUnchanged": report.get("revisionBefore") == report.get("revisionAfter"),
        "reportedSaveBytesUnchanged": report.get("saveBytesUnchanged", report.get("snapshotFileBytesUnchanged")) is True,
        "reportedSaveHashMatches": report.get("saveSHA256Before", report.get("snapshotFileSHA256Before"))
            == report.get("saveSHA256After", report.get("snapshotFileSHA256After"))
            == initial_sha == sha_bytes(after_save),
        "readbackLoadedSameSave": readback.get("loadedExistingSave") is True,
        "readbackHashMatchesSave": readback.get("saveFileSHA256") == sha_bytes(after_save),
        "readbackRevisionMatches": readback.get("revision") == report.get("revisionBefore"),
        "hpReceiptFresh": hp_envelope is not None and hp_envelope.get("kind") == "presentation_hp",
        "hpParity": report.get("hpMismatchesEmpty") is True if "hpMismatchesEmpty" in report
            else report.get("hpPresentationMismatchesAfterFinish") == {},
        "effectCapCombat": type(effects.get("peakCombat")) is int and 0 <= effects["peakCombat"] <= 2
            and effects.get("activeCombat") == 0,
        "effectCapEnvironment": type(effects.get("peakEnvironment")) is int and 0 <= effects["peakEnvironment"] <= 2,
        "fixtureRegion": region in report.get("fixtureRegionIDs", []) if "fixtureRegionIDs" in report
            else report.get("mechanicCase") is not None,
        "actorLoad": True,
        "eventContract": False,
        "targetedRenderCoverage": False,
    }
    if case_id in {"E02_MAGIC_SUPPORT", "E04_FOLLOWUP", "E03_PINCER_FRONT", "E03_PINCER_BEHIND"}:
        contracts = report.get("contractAssertions", {})
        arts = report.get("artAssertions", {})
        checks["eventContract"] = bool(contracts) and all(v is True for v in contracts.values())
        checks["targetedRenderCoverage"] = bool(arts) and all(v is True for v in arts.values())
        IDs = report.get("fixtureEnemyIDs", [])
        regions = report.get("fixtureRegionIDs", [])
        checks["fixtureRegion"] = regions == [region]
        checks["currentAreaBackground"] = current_background_matches(case_id, report.get("artAudit", {}), region)
        state_map = report.get("artAudit", {}).get("states", {})
        checks["actorLoad"] = bool(IDs) and all(actor_is_loaded(report.get("artAudit", {}), eid) for eid in IDs)
        # Independently check precise placement roots and display targets.
        exact = True
        if case_id == "E02_MAGIC_SUPPORT":
            support = [e for e in events if e.get("kind") == "enemy_magic_support" and e.get("sourceID") == "E_R02_04"]
            exact = len(support) == 1 and support[0].get("targetID") == "E_R02_03" and support[0].get("amount") == 1_500 \
                and support[0].get("timestampMs") == 2_500 and bool(support[0].get("rootActionID")) \
                and require_pair(trace, effect, support[0]["rootActionID"], {"ACT_E_R02_03"})
        elif case_id == "E04_FOLLOWUP":
            hits = [e for e in events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "E_R04_01"]
            marks = [e for e in events if e.get("kind") == "enemy_followup" and e.get("sourceID") == "E_R04_01"]
            exact = len(hits) == len(marks) == 1 and hits[0].get("targetID") == marks[0].get("targetID") \
                and hits[0].get("rootActionID") == marks[0].get("rootActionID") \
                and require_pair(trace, effect, hits[0]["rootActionID"], {display_id(hits[0]["targetID"])})
        elif case_id == "E03_PINCER_FRONT":
            armor = [e for e in events if e.get("kind") == "enemy_armor" and e.get("sourceID") == "E_R03_01" and e.get("amount", 0) > 0]
            roots = {e.get("rootActionID") for e in armor}
            exact = bool(roots) and all(require_direct(trace, effect, root,
                {"direct_full:enemy_armor", "coalesced:enemy_armor"}, {"ACT_E_R03_01"}) for root in roots)
        else:
            hits = [e for e in events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "E_R03_01"]
            roots = {e.get("rootActionID") for e in hits}
            exact = bool(roots) and all(
                require_pair(trace, effect, root, {display_id(e["targetID"]) for e in hits if e.get("rootActionID") == root})
                for root in roots)
        checks["targetedRenderCoverage"] = checks["targetedRenderCoverage"] and exact
    elif case_id in {"E03_MAGNET", "E03_MAGNET_INTERRUPT"}:
        raw_art = report.get("battleArtReceipt", "")
        try: art = json.loads(raw_art) if isinstance(raw_art, str) else raw_art
        except (ValueError, TypeError): art = {}
        art = art if isinstance(art, dict) else {}
        effect_stats = art.get("effects", {}) if isinstance(art.get("effects"), dict) else {}
        checks["eventContract"] = report.get("contractMatches") is True
        magnet = assert_magnet_contract(case_id, events, trace, effect, report)
        checks.update(magnet)
        if case_id == "E03_MAGNET":
            ordinary_hits = [e for e in events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "E_R03_04"]
            ordinary_interrupts = [e for e in events if e.get("kind") == "cast_interrupt" and e.get("targetID") == "E_R03_04" and e.get("sourceID") in {"C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"}]
            checks["ordinaryCaseHasRealHitAndNoTypedInterrupt"] = bool(ordinary_hits) and not ordinary_interrupts and all(
                e.get("diagnostics", {}).get("candidateMagnetCoefficientBP") == 12_500 for e in ordinary_hits)
        checks["targetedRenderCoverage"] = bool(magnet) and all(magnet.values())
        checks["actorLoad"] = actor_is_loaded(art, "E_R03_04")
        checks["effectPeakAndCleanup"] = type(effect_stats.get("peakCombat")) is int and effect_stats.get("peakCombat") <= 2 and effect_stats.get("activeCombat") == 0
        checks["regionR03Loaded"] = current_background_matches(case_id, art, region)
        return checks
    else:
        raw_art = report.get("battleArtReceipt", "")
        try:
            art = json.loads(raw_art)
        except (ValueError, TypeError):
            art = {}
        states = art.get("states", {}) if isinstance(art, dict) else {}
        # Legacy preview reports did not serialize region metadata; the scene's bundled background load is the direct evidence.
        checks["fixtureRegion"] = current_background_matches(case_id, art, region)
        case_events = events
        exact = True
        if case_id == "E05_TRANSFER":
            deliveries = [e for e in case_events if e.get("kind") == "enemy_light_transfer" and e.get("sourceID") == "E_R05_03"]
            roots = {e.get("rootActionID") for e in deliveries}
            exact = len(deliveries) == 2 and all(e.get("targetID") == "E_R05_02" and e.get("amount") == 1_500 for e in deliveries) \
                and bool(roots) and all(require_pair(trace, effect, root, {"ACT_E_R05_02"}) for root in roots)
        elif case_id == "E05_GUARD":
            stance = [e for e in case_events if e.get("kind") == "enemy_guard_stance" and e.get("sourceID") == "E_R05_02"]
            absorbs = [e for e in case_events if e.get("kind") == "enemy_guard_absorb" and e.get("sourceID") == "E_R05_02" and e.get("amount", 0) > 0]
            roots = {e.get("rootActionID") for e in absorbs}
            exact = bool(stance) and all(e.get("targetID") == "E_R05_02" and e.get("amount") == 2_500 for e in stance) \
                and bool(roots) and all(require_direct(trace, effect, root,
                    {"direct_full:enemy_guard_absorb", "coalesced:enemy_guard_absorb"}, {"ACT_E_R05_02"}) for root in roots)
        elif case_id == "E05_POISON":
            hits = [e for e in case_events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "E_R05_04"]
            dots = [e for e in case_events if e.get("kind") == "dot_applied" and e.get("sourceID") == "E_R05_04"]
            regen = [e for e in case_events if e.get("kind") == "enemy_regen" and e.get("sourceID") == "E_R05_04" and e.get("amount", 0) > 0]
            root_hits = {e.get("rootActionID") for e in hits}
            healing = any(r.get("step") == "healing_feedback:enemy_regen" and r.get("sourceID") == "E_R05_04" for r in trace)
            exact = bool(hits and dots and regen and root_hits) and all(e.get("amount") == 3 for e in dots) \
                and all(e.get("rootActionID") in root_hits for e in dots + regen) \
                and all(e.get("targetID") == "E_R05_04" for e in regen) and healing \
                and all(require_pair(trace, effect, e["rootActionID"], {display_id(e["targetID"])}) for e in hits)
        elif case_id == "B02_MIRROR":
            hits = [e for e in case_events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "B_R02_B"]
            reflects = [e for e in case_events if e.get("kind") == "enemy_reflect_projectile" and e.get("sourceID") == "B_R02_B" and e.get("amount", 0) > 0]
            stances = [e for e in case_events if e.get("kind") == "enemy_reflect_stance" and e.get("sourceID") == "B_R02_B"]
            hit_roots = {e.get("rootActionID") for e in hits}
            reflect_roots = {e.get("rootActionID") for e in reflects}
            hit_ok = bool(hit_roots) and all(require_pair(trace, effect, root,
                {display_id(e["targetID"]) for e in hits if e.get("rootActionID") == root}) for root in hit_roots)
            reflect_ok = bool(reflect_roots) and all(require_direct(trace, effect, root,
                {"direct_full:enemy_reflect_projectile", "coalesced:enemy_reflect_projectile"},
                {display_id(e["targetID"]) for e in reflects if e.get("rootActionID") == root}) for root in reflect_roots)
            stance_ok = bool(stances) and all(require_direct(trace, effect, e.get("rootActionID"),
                {"direct_full:enemy_reflect_stance", "coalesced:enemy_reflect_stance"}, {"ACT_B_R02_B"}) for e in stances)
            exact = hit_ok and reflect_ok and stance_ok
        elif case_id == "B05_DEER":
            hits = [e for e in case_events if e.get("kind") == "enemy_hit" and e.get("sourceID") == "B_R05_B"]
            dots = [e for e in case_events if e.get("kind") == "dot_applied" and e.get("sourceID") == "B_R05_B"]
            hit_roots = {e.get("rootActionID") for e in hits}
            dot_roots = {e.get("rootActionID") for e in dots}
            hit_ok = bool(hit_roots) and all(require_pair(trace, effect, root,
                {display_id(e["targetID"]) for e in hits if e.get("rootActionID") == root}) for root in hit_roots)
            dot_ok = bool(dot_roots) and all(require_direct(trace, effect, root,
                {"direct_full:dot_applied", "coalesced:dot_applied"},
                {display_id(e["targetID"]) for e in dots if e.get("rootActionID") == root}) for root in dot_roots)
            exact = hit_ok and dot_ok and all(e.get("amount") == 3 for e in dots)
        checks["eventContract"] = report.get("contractMatches") is True
        checks["targetedRenderCoverage"] = exact
        states = art.get("states", {}) if isinstance(art, dict) else {}
        enemy = {"B02_MIRROR": "B_R02_B", "B05_DEER": "B_R05_B",
                 "E05_TRANSFER": "E_R05_03", "E05_GUARD": "E_R05_02", "E05_POISON": "E_R05_04", "E03_MAGNET": "E_R03_04", "E03_MAGNET_INTERRUPT": "E_R03_04"}[case_id]
        checks["actorLoad"] = actor_is_loaded(art, enemy)
    return checks


def start_video(device: str, path: pathlib.Path, log_path: pathlib.Path) -> subprocess.Popen:
    log = log_path.open("wb")
    proc = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(path)],
                            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    proc._qa_log = log  # type: ignore[attr-defined]
    time.sleep(0.5)
    return proc


def stop_video(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGINT)
    try:
        proc.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
    log = getattr(proc, "_qa_log", None)
    if log:
        log.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Explicit dedicated Simulator UDID")
    parser.add_argument("--app", required=True, type=pathlib.Path, help="Frozen .app bundle")
    parser.add_argument("--output", required=True, type=pathlib.Path, help="New evidence directory; must not exist")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--video", action="store_true", help="Record each preview from launch through report completion")
    parser.add_argument("--only", action="append", choices=sorted(CASES), help="Run selected case(s); use --only E03_MAGNET --only E03_MAGNET_INTERRUPT for magnet checks")
    args = parser.parse_args()
    app, out = args.app.resolve(), args.output.resolve()
    if out.exists():
        raise SystemExit(f"Refusing to overwrite evidence: {out}")
    receipt_path = app.parent / "BUILD_RECEIPT.json"
    receipt = parse_json(receipt_path)
    if receipt.get("status") != "SIMULATOR_BUILD_PASS" or receipt.get("bundle") != str(app):
        raise SystemExit("Frozen Simulator BUILD_RECEIPT is absent, failed, or names another bundle")
    if receipt.get("png_decode_validation") != "PASS" or receipt.get("source_stability") != "PASS":
        raise SystemExit("Build receipt lacks PNG decode/source stability PASS")
    exe = app / "WitchGathering"
    exe_sha = sha_file(exe)
    if exe_sha != receipt.get("executable_sha256"):
        raise SystemExit("Executable hash does not match frozen BUILD_RECEIPT")
    source_rows: dict[str, str] = {}
    for relative, expected in receipt.get("source_sha256", {}).items():
        source = ROOT / relative
        if not source.is_file() or sha_file(source) != expected:
            raise SystemExit(f"Current source differs from frozen build receipt: {relative}")
        source_rows[relative] = expected

    selected = args.only or list(CASES)
    if len(set(selected)) != len(selected):
        raise SystemExit("Duplicate preview case requested")
    out.mkdir(parents=True)
    run_data: dict[str, Any] = {
        "schema": "effect_projection_previews_r014_r003",
        "status": "RUNNING",
        "scope": "SIMULATOR_READ_ONLY_R6_PREVIEW_NOT_COMMITTED_CAMPAIGN",
        "humanApproved": False,
        "canonicalMechanicsApproved": False,
        "device": args.device,
        "app": str(app),
        "buildReceipt": str(receipt_path),
        "buildReceiptSHA256": sha_file(receipt_path),
        "executableSHA256": exe_sha,
        "sourceSHA256": source_rows,
        "cases": [],
    }
    (out / "RUN.json").write_text(json.dumps(run_data, ensure_ascii=False, indent=2) + "\n")
    run("xcrun", "simctl", "install", args.device, str(app))
    support = pathlib.Path(run("xcrun", "simctl", "get_app_container", args.device, BUNDLE_ID, "data")) \
        / "Library/Application Support/Witch03to05R1"

    for case_id in selected:
        kind, region, expected_effect = CASES[case_id]
        case_dir = out / case_id
        case_dir.mkdir()
        key = "r12p-" + hashlib.sha256((str(out) + case_id + uuid.uuid4().hex).encode()).hexdigest()[:20]
        save = support / f"qa-{key}-save.json"
        readback_path = support / "last_qa_save_readback.json"

        # Make and verify a persisted isolated save before any preview starts. This
        # provides an external byte baseline and keeps the preview invocation read-only.
        setup_started = time.time()
        run("xcrun", "simctl", "launch", "--terminate-running-process", args.device, BUNDLE_ID,
            "--qa-isolated", "--qa-fixture=challenge", "--qa-persist-fixture", "--qa-save-key=" + key,
            "--qa-readback-save", "--screen=探索")
        setup_receipt = parse_receipt(readback_path, setup_started, args.timeout)
        if setup_receipt["value"].get("loadedExistingSave") is not False:
            raise RuntimeError(f"Fixture setup did not prove a new isolated save for {case_id}")
        if not save.is_file():
            raise RuntimeError(f"Fixture setup did not persist expected save file for {case_id}")
        initial_save = save.read_bytes()
        initial_sha = sha_bytes(initial_save)
        initial_snapshot = parse_json(save).get("snapshot")
        (case_dir / "fixture_setup_readback.json").write_bytes(readback_path.read_bytes())
        (case_dir / "save_before_preview.json").write_bytes(initial_save)
        setup_started_at = setup_receipt["envelope"].get("date")

        receipt_name = "last_effect_multi_preview.json" if kind == "multi" else "last_effect_mechanic_preview.json"
        preview_path = support / receipt_name
        old_preview_mtime = preview_path.stat().st_mtime if preview_path.exists() else 0
        hp_path = support / "last_presentation_hp.json"
        old_hp_mtime = hp_path.stat().st_mtime if hp_path.exists() else 0
        preview_started = time.time()
        video_proc = None
        if args.video:
            video_proc = start_video(args.device, case_dir / "preview.mp4", case_dir / "video.log")
        flag = "--qa-effect-multi-preview=" if kind == "multi" else "--qa-effect-mechanic-preview="
        launch_output = run("xcrun", "simctl", "launch", "--terminate-running-process", args.device, BUNDLE_ID,
                            "--qa-isolated", "--qa-save-key=" + key, flag + case_id, "--screen=探索")
        try:
            preview_receipt = parse_receipt(preview_path, preview_started, args.timeout)
        finally:
            if video_proc:
                stop_video(video_proc)
        hp_receipt = parse_receipt(hp_path, preview_started, args.timeout)
        preview = preview_receipt["value"]
        after_preview = save.read_bytes()
        (case_dir / "raw_preview_report.json").write_text(json.dumps(preview, ensure_ascii=False, indent=2) + "\n")
        (case_dir / "preview_receipt_envelope.json").write_bytes(preview_path.read_bytes())
        (case_dir / "presentation_hp_receipt.json").write_bytes(hp_path.read_bytes())
        (case_dir / "save_after_preview.json").write_bytes(after_preview)
        run("xcrun", "simctl", "io", args.device, "screenshot", str(case_dir / "after_preview.png"))

        restart_started = time.time()
        restart_output = run("xcrun", "simctl", "launch", "--terminate-running-process", args.device, BUNDLE_ID,
                             "--qa-isolated", "--qa-save-key=" + key, "--qa-readback-save", "--screen=探索")
        readback_receipt = parse_receipt(readback_path, restart_started, 45)
        readback = readback_receipt["value"]
        after_restart = save.read_bytes()
        (case_dir / "restart_readback_receipt.json").write_bytes(readback_path.read_bytes())
        (case_dir / "save_after_restart.json").write_bytes(after_restart)
        run("xcrun", "simctl", "io", args.device, "screenshot", str(case_dir / "after_restart.png"))

        checks = assess_case(case_id, preview, region, expected_effect, initial_sha, after_preview, readback,
                             hp_receipt["envelope"])
        checks["setupSnapshotWasActuallySaved"] = isinstance(initial_snapshot, dict)
        checks["previewExternalSaveEqualsSetup"] = initial_save == after_preview
        checks["restartSaveBytesEqualsSetup"] = initial_save == after_restart
        checks["restartSnapshotMatchesSavedSnapshot"] = canonical_snapshot(readback.get("snapshot")) == canonical_snapshot(parse_json(save).get("snapshot"))
        checks["setupRevisionEqualsPreviewRevision"] = readback.get("revision") == preview.get("revisionBefore")
        checks["previewReceiptFreshAfterLaunch"] = preview_receipt["envelope"].get("date") is not None and preview_path.stat().st_mtime > old_preview_mtime
        checks["hpReceiptFreshAfterLaunch"] = hp_path.stat().st_mtime > max(preview_started, old_hp_mtime)
        if kind == "mechanic":
            art_string = preview.get("battleArtReceipt", "")
            art = json.loads(art_string) if isinstance(art_string, str) else {}
        else:
            art = preview.get("artAudit", {})
        checks["sceneBackgroundMatchesFixtureRegion"] = current_background_matches(case_id, art, region)

        video_path = case_dir / "preview.mp4"
        row = {
            "caseID": case_id,
            "kind": kind,
            "expectedRegion": region,
            "expectedEffectID": expected_effect,
            "saveKey": key,
            "setupReadbackDate": setup_started_at,
            "previewStartedEpoch": preview_started,
            "previewReceiptDate": preview_receipt["envelope"].get("date"),
            "launchOutput": launch_output,
            "restartOutput": restart_output,
            "previewStatus": preview.get("status"),
            "checks": checks,
            "passed": all(v is True for v in checks.values()),
            "previewReportSHA256": sha_file(case_dir / "raw_preview_report.json"),
            "saveBeforeSHA256": initial_sha,
            "saveAfterPreviewSHA256": sha_bytes(after_preview),
            "saveAfterRestartSHA256": sha_bytes(after_restart),
            "videoSHA256": sha_file(video_path) if video_path.exists() else None,
        }
        run_data["cases"].append(row)
        run_data["status"] = "RUNNING"
        (out / "RUN.json").write_text(json.dumps(run_data, ensure_ascii=False, indent=2) + "\n")
        if not row["passed"]:
            run_data["status"] = "FAILED_CASES_CONTINUED"
            (out / "RUN.json").write_text(json.dumps(run_data, ensure_ascii=False, indent=2) + "\n")
            print(json.dumps({"status": "FAILED_CASE_CONTINUING", "case": case_id,
                              "failedChecks": [k for k,v in checks.items() if not v]}, indent=2))

    pincer = {row["caseID"]: row for row in run_data["cases"] if row["caseID"].startswith("E03_PINCER_")}
    if len(pincer) == 2:
        front = parse_json(out / "E03_PINCER_FRONT" / "raw_preview_report.json").get("result", {}).get("events", [])
        behind = parse_json(out / "E03_PINCER_BEHIND" / "raw_preview_report.json").get("result", {}).get("events", [])
        direct = lambda events: {(e.get("sourceID"), e.get("rootActionID"), e.get("timestampMs")): e.get("amount")
                                 for e in events if e.get("kind") == "direct" and e.get("targetID") == "E_R03_01"}
        fd, bd = direct(front), direct(behind)
        armor_roots = {e.get("rootActionID") for e in front if e.get("kind") == "enemy_armor" and e.get("sourceID") == "E_R03_01" and e.get("amount", 0) > 0}
        paired = set(fd) == set(bd) and bool(fd) and all(
            (fd[k] < bd[k]) if k[1] in armor_roots else (fd[k] == bd[k]) for k in fd)
        run_data["pincerPairedCaseCheck"] = {"sameDirectSchedule": set(fd) == set(bd), "frontArmorRootsReduceOnlyTheirDirectHits": paired,
                                             "frontDirectRootCount": len(fd), "frontArmorRootCount": len(armor_roots)}
        if not paired:
            run_data["status"] = "FAILED_PINCER_PAIR_COMPARISON"
            (out / "RUN.json").write_text(json.dumps(run_data, ensure_ascii=False, indent=2) + "\n")
            return 1
    all_passed = all(row["passed"] for row in run_data["cases"])
    run_data["status"] = "CAPTURED_ALL_ASSERTIONS_PASS_PREVIEW_ONLY" if all_passed else "CAPTURED_WITH_FAILED_ASSERTIONS"
    run_data["summary"] = ("All case checks passed; results are read-only R6 previews, not committed campaign fights or approved mechanics."
                            if all_passed else "All selected cases captured; failed assertions are preserved. Results are read-only previews, not committed campaign fights or approved mechanics.")
    (out / "RUN.json").write_text(json.dumps(run_data, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"status": run_data["status"], "cases": len(run_data["cases"]), "output": str(out)}, indent=2))
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
