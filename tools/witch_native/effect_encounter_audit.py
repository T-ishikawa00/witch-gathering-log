#!/usr/bin/env python3
"""Audit real isolated encounter playback, bound effects, rewards, and save reopen.

This is a local Simulator QA runner. The challenge fixture is explicit test data;
the report is not progression, balance, art, or Human approval evidence.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any

BUNDLE = "local.witch.autonomous.r1"
DEFAULT_DEVICE = "9A067715-7CF3-40D3-9064-38423223959B"
TELL_KINDS = {"enemy_telegraph", "telegraph_heavy", "telegraph_aoe", "enemy_cast_start"}
ACTOR_TO_DISPLAY = {"C_WITCH": "ERNA", "C_APPRENTICE": "LUNA", "C_SMITH": "AIRA", "C_FAMILIAR": "NOIR"}
DEFENSE_EVENT_KINDS = {"enemy_armor", "enemy_guard_absorb"}
SELF_OR_SCALAR_STATUS_KINDS = {
    "enemy_rest", "enemy_scale_opening", "enemy_ring_opening", "enemy_vent",
    "enemy_heat_store", "enemy_heat_release", "enemy_seed_pressure",
    "enemy_ultimate_release", "enemy_regen", "enemy_guard_stance",
    "enemy_reflect_stance", "enemy_shell_close",
}
ROOT = Path(__file__).resolve().parents[2]
PINNED_SOURCES = (
    "native/WitchApp/BattleEffects.swift",
    "native/WitchApp/EffectCueCoordinator.swift",
    "native/WitchApp/LivingScene.swift",
    "native/WitchApp/BattlePlayback.swift",
    "native/WitchApp/App.swift",
    "native/WitchApp/QASaveReadback.swift",
    "native/WitchGameCore/Sources/WitchGameCore/Domain.swift",
    "native/WitchGameCore/Sources/WitchGameCore/GameEngine.swift",
    "native/WitchGameCore/Sources/WitchGameCore/CandidateCombatOverlay.swift",
    "native/WitchGameCore/Sources/WitchGameCore/R6TimelineSimulator.swift",
    "native/WitchGameCore/Sources/WitchGameCore/SaveRepository.swift",
)

# Kept in sync with BattleEffects.bindings. The build receipt pins that source
# file's SHA so a changed binding table cannot silently reuse this expectation.
ATTACK = ("enemy_hit",)
DIRECT: dict[str, tuple[str, ...]] = {
    "E_R01_04": ("enemy_armor",),
    "E_R02_02": ("enemy_armor",),
    "E_R02_03": ("enemy_reflect_projectile",),
    "E_R05_02": ("enemy_guard_stance", "enemy_guard_absorb"),
    "E_R05_03": ("enemy_light_transfer",),
}
BINDINGS: dict[str, tuple[str, tuple[str, ...], tuple[str, ...]]] = {
    "E_R01_01": ("ACT_E_R01_01_charge", ATTACK, tuple(sorted(TELL_KINDS))),
    "E_R01_02": ("ACT_E_R01_02_silk", ATTACK, tuple(sorted(TELL_KINDS))),
    "E_R01_03": ("ACT_E_R01_03_double_leaf", ATTACK, tuple(sorted(TELL_KINDS))),
    "E_R01_04": ("ACT_E_R01_04_shell", DIRECT["E_R01_04"], ()),
    "B_R01_A": ("ACT_B_R01_A_heavy_charge", ATTACK, tuple(sorted(TELL_KINDS))),
    "B_R01_B": ("ACT_B_R01_B_branch", ATTACK, tuple(sorted(TELL_KINDS))),
    "E_R02_01": ("ACT_E_R02_01_spore", ATTACK, tuple(sorted(TELL_KINDS))),
    "E_R02_02": ("ACT_E_R02_02_mist_guard", DIRECT["E_R02_02"], ()),
    "E_R02_03": ("ACT_E_R02_03_return_mote", DIRECT["E_R02_03"], ()),
    "E_R02_04": ("ACT_E_R02_04_support_arc", ("enemy_magic_support",), ("enemy_telegraph",)),
    "B_R02_A": ("ACT_B_R02_A_drowse_spore", ("enemy_hit", "party_drowse", "enemy_rest"), tuple(sorted(TELL_KINDS))),
    "B_R02_B": ("ACT_B_R02_B_mirror_bolt", ("enemy_hit", "enemy_armor", "enemy_reflect_stance", "enemy_reflect_projectile", "enemy_scale_opening"), tuple(sorted(TELL_KINDS))),
    "E_R03_01": ("ACT_E_R03_01_pincer_guard", ("enemy_hit", "enemy_armor"), tuple(sorted(TELL_KINDS))),
    "E_R03_02": ("ACT_E_R03_02_resonance", ("cast_interrupt",), tuple(sorted(TELL_KINDS))),
    "E_R03_03": ("ACT_E_R03_03_tool_combo", ATTACK, tuple(sorted(TELL_KINDS))),
    "E_R03_04": ("ACT_E_R03_04_magnet_pullcue", ATTACK, ("enemy_magnet_mark", "telegraph_heavy")),
    "B_R03_A": ("ACT_B_R03_A_three_hammer", ("enemy_hit", "enemy_rest"), tuple(sorted(TELL_KINDS))),
    "B_R03_B": ("ACT_B_R03_B_heat_floor", ("enemy_hit", "enemy_vent", "enemy_heat_store", "enemy_heat_release"), tuple(sorted(TELL_KINDS))),
    "E_R04_01": ("ACT_E_R04_01_pursuit", ATTACK, tuple(sorted(TELL_KINDS))),
    "E_R04_02": ("ACT_E_R04_02_wing_gust", ("party_cast_slow",), tuple(sorted(TELL_KINDS))),
    "E_R04_03": ("ACT_E_R04_03_hex_guard", ("enemy_shell_close", "enemy_armor"), ()),
    "E_R04_04": ("ACT_E_R04_04_tool_arcs", ATTACK, tuple(sorted(TELL_KINDS))),
    "B_R04_A": ("ACT_B_R04_A_snow_charge", ATTACK, tuple(sorted(TELL_KINDS))),
    "B_R04_B": ("ACT_B_R04_B_breath_fan", ("enemy_hit", "enemy_cold_wave", "party_frost_slow", "enemy_breath_inhale", "enemy_breath_release"), tuple(sorted(TELL_KINDS))),
    "E_R05_01": ("ACT_E_R05_01_unbind", ("enemy_hit", "support_duration_reduced"), tuple(sorted(TELL_KINDS))),
    "E_R05_02": ("ACT_E_R05_02_guard_attack", DIRECT["E_R05_02"], ()),
    "E_R05_03": ("ACT_E_R05_03_light_transfer", DIRECT["E_R05_03"], ("enemy_telegraph",)),
    "E_R05_04": ("ACT_E_R05_04_heal_toxin", ("enemy_hit", "dot_applied", "enemy_regen"), tuple(sorted(TELL_KINDS))),
    "B_R05_A": ("ACT_B_R05_A_pruning_ring", ("enemy_hit", "enemy_ring_opening", "enemy_ring_sweep"), tuple(sorted(TELL_KINDS))),
    "B_R05_B": ("ACT_B_R05_B_seed_wave", ("enemy_hit", "enemy_seed_pressure", "dot_applied", "enemy_guard_stance", "enemy_guard_absorb", "enemy_ultimate_release"), tuple(sorted(TELL_KINDS))),
}


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_json(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return sha_bytes(encoded)


def sha_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text())


def snapshot_from(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("snapshot is not an object")
    return value.get("snapshot", value)


SET_FIELDS = {
    "unlockedRegionIDs", "completedResearchIDs", "ownedCosmeticIDs", "ownedFurnitureIDs",
    "placedFurnitureIDs", "pendingPurchaseIDs", "completedEncounterIDs", "localStoreKitQAOwnedProductIDs",
}


def canonical_snapshot(value: dict[str, Any]) -> dict[str, Any]:
    """Normalize JSON array order for Codable Set fields; preserve ordered arrays."""
    result = dict(value)
    for key in SET_FIELDS:
        if isinstance(result.get(key), list):
            result[key] = sorted(result[key])
    return result


def actor_for_source(source: str) -> str | None:
    if source.startswith(("E_R", "B_R")):
        return "ACT_" + source
    return None


def display_id(raw: str) -> str:
    if raw in ACTOR_TO_DISPLAY:
        return ACTOR_TO_DISPLAY[raw]
    if raw.startswith(("E_R", "B_R")):
        return "ACT_" + raw
    return raw


def is_effective_bound_event(event: dict[str, Any], kinds: tuple[str, ...] | list[str] | set[str]) -> bool:
    if event.get("kind") not in kinds:
        return False
    if event.get("kind") in DEFENSE_EVENT_KINDS:
        amount = event.get("amount")
        return isinstance(amount, int) and not isinstance(amount, bool) and amount > 0
    return True


def expected_visual_actions(enemy_id: str, events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Derive targets from event semantics, not the renderer's current projection.

    An actual hit owns an attack cue for that root. Same-root self/status events
    are recorded as semantic-only and cannot add targets or advance that cue.
    Without a hit, positive defense prevention projects onto its source; other
    concrete recipients are collected, then self is the fallback.
    """
    binding = BINDINGS.get(enemy_id)
    if not binding or not binding[0]:
        return []
    effect, impacts, tells = binding
    source = enemy_id
    source_events = [e for e in events if e.get("sourceID") == source]
    groups: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for event in source_events:
        root = event.get("rootActionID") or f"tick:{event.get('timestampMs', int(event.get('tick', 0)) * 1000)}"
        groups[root].append(event)
    result: list[dict[str, Any]] = []
    for root, group in groups.items():
        relevant = [e for e in group if is_effective_bound_event(e, impacts)]
        tell_events = [e for e in group if e.get("kind") in tells]
        interrupted = any(e.get("kind") == "cast_interrupt" and e.get("targetID") == source
                          and e.get("rootActionID") == root for e in events)
        hits = [e for e in relevant if e.get("kind") == "enemy_hit"]
        defenses = [e for e in relevant if e.get("kind") in DEFENSE_EVENT_KINDS]
        if enemy_id == "E_R03_04":
            marks = [e for e in group if e.get("kind") == "enemy_magnet_mark"]
            if marks:
                mark = marks[0]
                lost = any(e.get("kind") == "enemy_magnet_target_lost" for e in group)
                result.append({"mode": "planned", "root": root, "source": source,
                    "effect": effect,
                    "cueTargets": [display_id(str(mark.get("targetID", "")))],
                    "targets": list(dict.fromkeys(display_id(str(e.get("targetID", ""))) for e in hits)),
                    "impactKinds": ["enemy_hit"] if hits else [], "semanticOnlyKinds": [],
                    "requiredCancellation": "enemy_magnet_target_lost" if lost else "cast_interrupt" if interrupted else None})
            continue
        if hits:
            presentation_events = hits
        elif defenses:
            presentation_events = defenses
        else:
            presentation_events = [e for e in relevant if e.get("kind") not in SELF_OR_SCALAR_STATUS_KINDS]
            if not presentation_events and relevant:
                # A status-only root can still have source-anchored art.
                presentation_events = relevant
        if tell_events and (presentation_events or (enemy_id == "E_R03_03" and interrupted)):
            tell = tell_events[0]
            chosen_effect = effect
            if enemy_id == "B_R01_B":
                chosen_effect = "ACT_B_R01_B_root_floor" if tell.get("kind") == "telegraph_aoe" else "ACT_B_R01_B_branch"
            if defenses and not hits:
                targets = [display_id(source)]
            else:
                targets = list(dict.fromkeys(display_id(str(e.get("targetID", ""))) for e in presentation_events
                                             if e.get("targetID") not in ("", "party", root)))
            if not targets and not presentation_events:
                targets = [display_id(str(tell.get("targetID", "")))]
            result.append({"mode": "planned", "root": root, "source": source,
                           "effect": chosen_effect, "targets": targets,
                           "impactKinds": sorted({str(e.get("kind")) for e in presentation_events}),
                           "semanticOnlyKinds": sorted({str(e.get("kind")) for e in relevant
                                                         if e not in presentation_events})})
        elif presentation_events:
            # The renderer coalesces one direct presentation per action root/source.
            event = presentation_events[0]
            if defenses:
                targets = [display_id(source)]
            else:
                targets = list(dict.fromkeys(display_id(str(e.get("targetID", ""))) for e in presentation_events
                                             if e.get("targetID") not in ("", "party", root)))
            if not targets:
                targets = [display_id(source)]
            result.append({"mode": "direct", "root": root, "source": source,
                           "effect": effect, "targets": targets,
                           "impactKinds": sorted({str(e.get("kind")) for e in presentation_events}),
                           "semanticOnlyKinds": sorted({str(e.get("kind")) for e in relevant
                                                         if e not in presentation_events})})
    return result


def validate_cue_trace(actions: list[dict[str, Any]], trace: list[dict[str, Any]],
                       effect_counts: dict[str, Any], peak: Any, active: Any) -> dict[str, Any]:
    errors: list[str] = []
    by_identity: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for row in trace:
        by_identity[(row.get("rootActionID", ""), row.get("sourceID", ""))].append(row)
    matched: list[dict[str, Any]] = []
    rendered_count = suppressed_count = deduped_count = target_verified_count = 0

    def has_placement(row: dict[str, Any], phase: str) -> bool:
        pairs = [(f"placement.{phase}X", f"placement.{phase}Y"), ("placement.x", "placement.y")]
        for x_key, y_key in pairs:
            try:
                x, y = float(row[x_key]), float(row[y_key])
                if all(map(lambda n: n == n and abs(n) != float("inf"), (x, y))):
                    return True
            except (KeyError, TypeError, ValueError):
                pass
        return False

    def verify_targets(row: dict[str, Any], action: dict[str, Any], *, required: bool) -> bool:
        actual = row.get("targetIDs")
        cue_row = row.get("step") in {"cue_placement", "capacity_suppressed:cue"}
        expected = ",".join(action.get("cueTargets", action["targets"]) if cue_row else action["targets"])
        if actual is None:
            if required:
                errors.append(f"missing target evidence {action['source']} {action['root']} {row.get('step')}")
            return False
        if actual != expected:
            errors.append(f"target mismatch {action['source']} {action['root']}: {actual!r} != {expected!r}")
            return False
        return True

    for action in actions:
        rows = by_identity.get((action["root"], action["source"]), [])
        rows = [r for r in rows if r.get("effectID") == action["effect"]]
        targets = ",".join(action["targets"])
        if action["mode"] == "planned":
            cue = next((r for r in rows if r.get("step") == "cue_placement"), None)
            suppressed = any(str(r.get("step", "")).startswith("capacity_suppressed:cue") for r in rows)
            if cue:
                verified = verify_targets(cue, action, required=True)
                if not has_placement(cue, "cue"):
                    errors.append(f"planned cue missing placement coordinates {action['source']} {action['root']}")
                impact = next((r for r in rows if r.get("step") == "impact_placement"), None)
                canceled = any(str(r.get("step", "")).startswith("cue_cancel:") for r in rows)
                expected_cancel = action.get("requiredCancellation")
                if expected_cancel and (impact or not any(r.get("step") == "cue_cancel:" + expected_cancel for r in rows)):
                    errors.append(f"magnet cancellation mismatch {action['source']} {action['root']}")
                if action["impactKinds"] and not impact and not canceled:
                    errors.append(f"planned cue has no matching impact/cancel {action['source']} {action['root']}")
                if impact:
                    verified = verify_targets(impact, action, required=True) and verified
                    if not has_placement(impact, "impact"):
                        errors.append(f"planned impact missing placement coordinates {action['source']} {action['root']}")
                rendered_count += 1
                target_verified_count += int(verified)
                matched.append({"root": action["root"], "source": action["source"], "effect": action["effect"],
                                "status": "rendered_then_cancelled" if canceled and not impact else "rendered",
                                "rendered": True, "suppressed": False, "targetVerified": verified})
            elif suppressed:
                suppressed_row = next((r for r in rows if str(r.get("step", "")).startswith("capacity_suppressed:cue")), None)
                verified = verify_targets(suppressed_row, action, required=False) if suppressed_row else False
                suppressed_count += 1
                target_verified_count += int(verified)
                matched.append({"root": action["root"], "source": action["source"], "effect": action["effect"],
                                "status": "suppressed", "rendered": False, "suppressed": True,
                                "targetVerified": verified})
            else:
                errors.append(f"missing planned cue {action['source']} {action['root']} {action['effect']}")
        else:
            direct_steps = {f"direct_full:{kind}" for kind in action["impactKinds"]} | {f"coalesced:{kind}" for kind in action["impactKinds"]}
            actual = next((r for r in rows if r.get("step") in direct_steps), None)
            suppressed = any(str(r.get("step", "")).startswith("capacity_suppressed:") for r in rows)
            deduped = any(r.get("step") == "dedupe" for r in rows)
            if actual:
                verified = verify_targets(actual, action, required=True)
                if not has_placement(actual, "impact"):
                    errors.append(f"direct cue missing placement coordinates {action['source']} {action['root']}")
                rendered_count += 1
                target_verified_count += int(verified)
                matched.append({"root": action["root"], "source": action["source"], "effect": action["effect"],
                                "status": "rendered", "rendered": True, "suppressed": False,
                                "targetVerified": verified, "traceStep": actual.get("step")})
            elif suppressed or deduped:
                suppression_row = next((r for r in rows if str(r.get("step", "")).startswith("capacity_suppressed:")), None)
                dedupe_row = next((r for r in rows if r.get("step") == "dedupe"), None)
                evidence = suppression_row or dedupe_row
                verified = verify_targets(evidence, action, required=False) if evidence else False
                if deduped and not suppressed:
                    # Dedupe has no placement/recipient fields; require the rendered
                    # same-root effect that owns the coalesced presentation.
                    owner_rows = [r for r in rows if r.get("step") in direct_steps and has_placement(r, "impact")]
                    verified = any(r.get("targetIDs") == targets for r in owner_rows)
                    if not verified:
                        errors.append(f"dedupe has no same-root rendered target owner {action['source']} {action['root']}")
                    deduped_count += 1
                else:
                    suppressed_count += 1
                target_verified_count += int(verified)
                matched.append({"root": action["root"], "source": action["source"], "effect": action["effect"],
                                "status": "suppressed" if suppressed else "deduped", "rendered": False,
                                "suppressed": bool(suppressed), "targetVerified": verified})
            else:
                errors.append(f"missing direct cue {action['source']} {action['root']} {action['effect']}")
    if isinstance(peak, bool) or not isinstance(peak, (int, float)) or peak < 0 or peak > 2:
        errors.append(f"combat effect peak exceeds cap 2: {peak!r}")
    if isinstance(active, bool) or not isinstance(active, int) or active != 0:
        errors.append(f"combat effect cleanup expected 0 active nodes, got {active!r}")
    # Every incremented effect count must have a corresponding cue/direct/coalesced trace row.
    traced_counts: collections.Counter[str] = collections.Counter()
    for row in trace:
        step = row.get("step", "")
        if step == "cue_placement" or step.startswith(("direct_full:", "coalesced:")):
            traced_counts[row.get("effectID", "")] += 1
    # Environment emitters share the counts dictionary but do not emit combat cueTrace rows.
    # Environment emitters share the counts dictionary but do not emit combat cueTrace rows.
    visual_keys = {key for key in effect_counts if key.startswith("ACT_")} | set(traced_counts)
    count_match: dict[str, bool] = {}
    for effect in sorted(visual_keys):
        value = effect_counts.get(effect)
        valid_integer = isinstance(value, int) and not isinstance(value, bool)
        matches = valid_integer and value == traced_counts[effect]
        count_match[effect] = matches
        if not matches:
            errors.append(f"effect count/trace mismatch or missing count {effect}: count={value!r} trace={traced_counts[effect]}")
    return {"passed": not errors and bool(actions) and rendered_count > 0, "errors": errors, "expectedActions": actions,
            "matchedActions": matched, "renderedActionCount": rendered_count,
            "suppressedActionCount": suppressed_count, "dedupedActionCount": deduped_count,
            "targetVerifiedActionCount": target_verified_count,
            "coverageStatus": "OBSERVED_RENDERED" if rendered_count else "INCONCLUSIVE_NO_RENDERED_ACTION",
            "traceCounts": dict(traced_counts), "countMatches": count_match}


def audit_environment(runtime_index: dict[str, Any], region: str,
                      effects: dict[str, Any], duration_ms: int) -> dict[str, Any]:
    region_ids = sorted(key for key in runtime_index.get("effects", {}) if key.startswith(f"ENV_{region}_"))
    counts = effects.get("counts", {})
    observed = {key: counts.get(key, 0) for key in region_ids}
    count_values_valid = all(isinstance(value, int) and not isinstance(value, bool) and value >= 0
                             for value in observed.values())
    foreign = sorted(key for key in counts if key.startswith("ENV_") and key not in region_ids)
    # updateEnvironment rotates the two active slots every 4 seconds. A complete
    # three-emitter sweep needs enough real scene time; short fights are censored.
    rotation_expected = len(region_ids) == 3 and duration_ms >= 12_000
    rotation_observed = bool(region_ids) and all(observed[key] > 0 for key in region_ids)
    peak = effects.get("peakEnvironment")
    active = effects.get("activeEnvironment")
    return {
        "region": region, "expectedEmitterIDs": region_ids, "counts": observed,
        "observedEmitterIDs": [key for key, count in observed.items() if count > 0],
        "foreignRegionEmitterIDs": foreign,
        "peakEnvironment": peak, "activeEnvironmentAtReceipt": active,
        "countsValid": count_values_valid,
        "peakAtMostTwo": not isinstance(peak, bool) and isinstance(peak, (int, float)) and 0 <= peak <= 2,
        "activeAtMostTwo": not isinstance(active, bool) and isinstance(active, int) and 0 <= active <= 2,
        "rotationWindowSeconds": 4,
        "rotationComplete": rotation_observed if rotation_expected else None,
        "rotationStatus": ("OBSERVED_COMPLETE" if rotation_observed else "EXPECTED_BUT_INCOMPLETE")
            if rotation_expected else "NOT_OBSERVED_SHORT_BATTLE",
    }


def compare_reward(before: dict[str, Any], after: dict[str, Any], enemy: dict[str, Any], won: bool) -> dict[str, Any]:
    expected_materials: dict[str, int] = {}
    expected_currency: dict[str, int] = {"coin": (10 if enemy.get("boss") else 2) if won else 0}
    if won and enemy.get("dropMaterialID"):
        expected_materials[enemy["dropMaterialID"]] = 5 if enemy.get("boss") else 1
    def delta_map(a: dict[str, Any], b: dict[str, Any]) -> dict[str, int]:
        return {key: b.get(key, 0) - a.get(key, 0) for key in set(a) | set(b) if b.get(key, 0) != a.get(key, 0)}
    material_delta = delta_map(before.get("materials", {}), after.get("materials", {}))
    currency_delta = delta_map(before.get("currency", {}), after.get("currency", {}))
    return {"materialDelta": material_delta, "expectedMaterialDelta": expected_materials,
            "currencyDelta": currency_delta, "expectedCurrencyDelta": {k: v for k, v in expected_currency.items() if v},
            "materialsMatch": material_delta == expected_materials,
            "currencyMatch": currency_delta == {k: v for k, v in expected_currency.items() if v}}


def validate_terminal_hp(combat: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    maps = {name: combat.get(name) for name in
            ("initialPartyHP", "remainingPartyHP", "initialEnemyHP", "remainingEnemyHP")}
    for name, value in maps.items():
        if not isinstance(value, dict) or not value:
            errors.append(f"{name} must be a non-empty object")
        elif any(not isinstance(key, str) or not key for key in value):
            errors.append(f"{name} contains an invalid entity key")
        elif any(isinstance(hp, bool) or not isinstance(hp, int) for hp in value.values()):
            errors.append(f"{name} contains a non-integer HP value")
    if not errors:
        ip, rp = maps["initialPartyHP"], maps["remainingPartyHP"]
        ie, re = maps["initialEnemyHP"], maps["remainingEnemyHP"]
        if set(ip) != set(rp): errors.append("party HP keysets differ")
        if set(ie) != set(re): errors.append("enemy HP keysets differ")
        if not ip or not ie: errors.append("party or enemy HP keyset is empty")
        for label, initial, remaining in (("party", ip, rp), ("enemy", ie, re)):
            for entity, max_hp in initial.items():
                value = remaining.get(entity)
                if max_hp <= 0: errors.append(f"{label} initial HP must be positive: {entity}")
                if value is None or value < 0 or value > max_hp:
                    errors.append(f"{label} terminal HP outside [0,initial]: {entity}={value!r}/{max_hp}")
        presentation = combat.get("entityPresentation")
        all_hp_ids = set(ip) | set(ie)
        if not isinstance(presentation, dict):
            errors.append("entityPresentation must be an object")
        elif set(presentation) != all_hp_ids:
            errors.append("entityPresentation IDs do not exactly match initial HP entities")
    return {"passed": not errors, "errors": errors,
            "partyEntityCount": len(maps["initialPartyHP"]) if isinstance(maps["initialPartyHP"], dict) else 0,
            "enemyEntityCount": len(maps["initialEnemyHP"]) if isinstance(maps["initialEnemyHP"], dict) else 0}


def wait_json(path: Path, started_ns: int, timeout: float, predicate) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    last_error: str | None = None
    while time.monotonic() < deadline:
        try:
            if path.exists() and path.stat().st_mtime_ns >= started_ns:
                obj = read_json(path)
                if predicate(obj):
                    return obj
        except (OSError, ValueError, TypeError) as error:
            last_error = repr(error)
        time.sleep(0.25)
    raise TimeoutError(f"fresh receipt timeout: {path}; last={last_error}")


def assert_build(app: Path) -> tuple[Path, dict[str, Any], str, str]:
    receipt_path = app.parent / "BUILD_RECEIPT.json"
    if not receipt_path.is_file():
        raise ValueError(f"build receipt missing: {receipt_path}")
    receipt = read_json(receipt_path)
    if receipt.get("status") != "SIMULATOR_BUILD_PASS" or Path(receipt.get("bundle", "")).resolve() != app:
        raise ValueError("build receipt does not identify this app as SIMULATOR_BUILD_PASS")
    exe = app / "WitchGathering"
    exe_sha = sha_file(exe)
    if receipt.get("executable_sha256") != exe_sha:
        raise ValueError("executable SHA mismatch with build receipt")
    source_hashes = receipt.get("source_sha256", {})
    missing = [path for path in PINNED_SOURCES if not source_hashes.get(path)]
    if missing:
        raise ValueError("build receipt lacks cue/gameplay source pins: " + ", ".join(missing))
    snapshot_value = receipt.get("source_snapshot")
    if not isinstance(snapshot_value, str) or not snapshot_value:
        raise ValueError("build receipt lacks a frozen source snapshot path")
    snapshot_root = Path(snapshot_value)
    if not snapshot_root.is_absolute():
        snapshot_root = (app.parent / snapshot_root).resolve()
    if not snapshot_root.is_dir():
        raise ValueError(f"frozen source snapshot missing: {snapshot_root}")
    changed = []
    for relative in PINNED_SOURCES:
        # build.py's source snapshot is flattened; receipt keys preserve original paths.
        frozen_path = snapshot_root / Path(relative).name
        if not frozen_path.is_file() or sha_file(frozen_path) != source_hashes[relative]:
            changed.append(relative)
    if changed:
        raise ValueError("frozen cue/gameplay sources differ from build receipt: " + ", ".join(changed))
    source_sha = source_hashes["native/WitchApp/BattleEffects.swift"]
    return receipt_path, receipt, exe_sha, source_sha


def run_case(app: Path, out: Path, support: Path, device: str, enemy: dict[str, Any], timeout: int) -> dict[str, Any]:
    eid = enemy["id"]
    case = out / eid
    case.mkdir()
    token = uuid.uuid4().hex[:12]
    key = f"effect-enc-{token}-{eid.lower().replace('_', '-')}"
    save = support / f"qa-{key}-save.json"
    if save.exists():
        raise FileExistsError(f"isolated QA save already exists; refusing reuse: {save}")
    paths = {name: support / filename for name, filename in {
        "battle": "last_battle.json", "art": "last_battle_art.json",
        "hp": "last_presentation_hp.json", "before": "battle_before.json",
    }.items()}
    prior_mtimes = {name: path.stat().st_mtime_ns if path.exists() else 0 for name, path in paths.items()}
    started_ns = time.time_ns()
    launch_output = run("xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE,
                       "--qa-isolated", "--qa-save-key=" + key, "--qa-fixture=challenge",
                       "--qa-encounter=" + eid, "--qa-slow-battle")
    deadline = time.monotonic() + timeout
    receipts: dict[str, dict[str, Any]] = {}
    while time.monotonic() < deadline:
        fresh = True
        for name in ("before", "battle", "hp", "art"):
            path = paths[name]
            try:
                if not path.exists() or path.stat().st_mtime_ns <= max(started_ns, prior_mtimes[name]):
                    fresh = False; break
                data = read_json(path)
                if name in ("battle", "art", "hp") and not isinstance(data.get("value"), str):
                    fresh = False; break
                if name == "battle" and (data.get("kind") != "battle" or eid not in data.get("value", "")):
                    fresh = False; break
                if name == "art" and data.get("kind") != "battle_art":
                    fresh = False; break
                if name == "hp" and data.get("kind") != "presentation_hp":
                    fresh = False; break
                receipts[name] = data
            except (OSError, ValueError, TypeError):
                fresh = False; break
        if fresh:
            break
        time.sleep(0.25)
    if not fresh:
        raise TimeoutError(f"one or more fresh battle/art/HP/before receipts timed out for {eid}")
    time.sleep(0.4)  # allow final save atomic replace to finish after receipt write
    if not save.is_file():
        raise FileNotFoundError(f"battle receipt arrived but isolated save is missing: {save}")
    before_data = paths["before"].read_bytes(); save_data = save.read_bytes()
    before = snapshot_from(json.loads(before_data))
    after = snapshot_from(json.loads(save_data))
    combat = after.get("lastCombatResult") or {}
    if after.get("lastEncounterID") != eid:
        raise ValueError(f"saved lastEncounterID mismatch for {eid}: {after.get('lastEncounterID')}")
    if receipts["battle"].get("revision") != after.get("revision"):
        raise ValueError("battle receipt revision does not match saved snapshot")
    result_events = combat.get("events", [])
    art_value = json.loads(receipts["art"].get("value", "{}"))
    hp_value = json.loads(receipts["hp"].get("value", "{}"))
    runtime_index = read_json(app / "Art" / "runtime_index.json")
    battle_ms = max((int(e.get("timestampMs", int(e.get("tick", 0)) * 1000)) for e in result_events), default=0)
    binding = BINDINGS.get(eid, ("", (), ()))
    raw_bound_events = [event for event in result_events
                        if event.get("sourceID") == eid and is_effective_bound_event(event, binding[1])]
    actions = expected_visual_actions(eid, result_events)
    cue_result = validate_cue_trace(actions,
                                    art_value.get("effects", {}).get("cueTrace", []),
                                    art_value.get("effects", {}).get("counts", {}),
                                    art_value.get("effects", {}).get("peakCombat"),
                                    art_value.get("effects", {}).get("activeCombat"))
    hp_validation = validate_terminal_hp(combat)
    environment_result = audit_environment(runtime_index, str(enemy.get("regionID", "")),
                                           art_value.get("effects", {}), battle_ms)
    rewards = compare_reward(before, after, enemy, bool(combat.get("won")))
    revision_delta = after.get("revision", -1000) - before.get("revision", 0)
    checks = {
        "encounterRecorded": after.get("lastEncounterID") == eid,
        "revisionAdvancedExactlyOne": revision_delta == 1,
        "resultPresentAndHasOutcome": isinstance(combat.get("won"), bool),
        "terminalHPMapsValid": hp_validation["passed"],
        "presentationHPMatches": hp_value == {},
        "rewardsMatchWinOrDefeat": rewards["materialsMatch"] and rewards["currencyMatch"],
        "effectTraceContractValid": not cue_result["errors"] if actions else None,
        "effectRenderedCoverage": (True if cue_result["renderedActionCount"] > 0 else
                                    None if not raw_bound_events or cue_result["suppressedActionCount"] else False)
                                    if binding[0] else None,
        "boundEventObserved": bool(raw_bound_events) if binding[0] and raw_bound_events else None,
        "environmentCapacityAndRegionIsolation": environment_result["countsValid"]
            and environment_result["peakAtMostTwo"]
            and environment_result["activeAtMostTwo"]
            and not environment_result["foreignRegionEmitterIDs"],
    }
    if environment_result["rotationComplete"] is False:
        checks["environmentRotationComplete"] = False
    for name, data in receipts.items():
        (case / f"{name}_receipt.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    (case / "before_save.json").write_bytes(before_data)
    (case / "after_battle_save.json").write_bytes(save_data)
    screenshot = case / "result_screen.png"
    run("xcrun", "simctl", "io", device, "screenshot", str(screenshot))
    # A fresh process reopens exactly this isolated save; no commands are dispatched.
    restart_receipt = support / "last_appearance_art.json"
    readback_receipt = support / "last_qa_save_readback.json"
    old_restart_mtime = restart_receipt.stat().st_mtime_ns if restart_receipt.exists() else 0
    old_readback_mtime = readback_receipt.stat().st_mtime_ns if readback_receipt.exists() else 0
    restart_ns = time.time_ns()
    restart_launch = run("xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE,
                         "--qa-isolated", "--qa-save-key=" + key, "--screen=仲間", "--qa-pose=idle", "--qa-readback-save")
    wait_json(restart_receipt, max(restart_ns, old_restart_mtime), min(timeout, 45),
              lambda row: row.get("kind") == "appearance_art")
    readback_wrapper = wait_json(readback_receipt, max(restart_ns, old_readback_mtime), min(timeout, 45),
                                 lambda row: row.get("kind") == "qa_save_readback")
    reopened_data = save.read_bytes()
    (case / "after_restart_save.json").write_bytes(reopened_data)
    checks["restartBytesUnchanged"] = reopened_data == save_data
    checks["restartSnapshotUnchanged"] = snapshot_from(json.loads(reopened_data)) == after
    readback = json.loads(readback_wrapper.get("value", "{}"))
    checks["readbackReceiptMatchesSameSave"] = (
        readback.get("saveFile") == save.name
        and readback.get("loadedExistingSave") is True
        and readback.get("revision") == after.get("revision")
        and isinstance(readback.get("snapshot"), dict)
        and canonical_snapshot(readback.get("snapshot", {})) == canonical_snapshot(after)
        and readback.get("saveFileSHA256") == sha_bytes(save_data)
        and readback.get("snapshotJSONSHA256") == sha_json(readback.get("snapshot", {}))
    )
    (case / "readback_receipt.json").write_text(json.dumps(readback_wrapper, ensure_ascii=False, indent=2) + "\n")
    false_checks = [name for name, value in checks.items() if value is False]
    inconclusive_checks = [name for name, value in checks.items() if value is None]
    case_status = "FAIL" if false_checks else "INCONCLUSIVE" if inconclusive_checks else "PASS"
    row = {
        "enemyID": eid, "regionID": enemy.get("regionID"), "boss": enemy.get("boss"),
        "saveKey": key, "launchOutput": launch_output, "restartLaunchOutput": restart_launch,
        "outcome": "WIN" if combat.get("won") else "DEFEAT",
        "revisionBefore": before.get("revision"), "revisionAfter": after.get("revision"),
        "revisionDelta": revision_delta, "eventCount": len(result_events),
        "eventKinds": dict(collections.Counter(e.get("kind", "?") for e in result_events)),
        "boundEventCoverage": {"bindingID": binding[0] or None, "expectedEventKinds": list(binding[1]),
                                "observedCount": len(raw_bound_events),
                                "status": "UNBOUND_BY_DESIGN" if not binding[0] else
                                    "OBSERVED" if raw_bound_events else "INCONCLUSIVE_NO_BOUND_EVENT"},
        "saveSHA256BeforeRestart": sha_bytes(save_data), "saveSHA256AfterRestart": sha_bytes(reopened_data),
        "materialAndCurrency": rewards, "presentationHPMismatches": hp_value,
        "battleDurationMs": battle_ms, "environmentAudit": environment_result,
        "cueAudit": cue_result, "terminalHPValidation": hp_validation,
        "resultScreenshotSHA256": sha_file(screenshot), "checks": checks,
        "inconclusiveChecks": inconclusive_checks, "failedChecks": false_checks,
        "status": case_status,
    }
    (case / "case.json").write_text(json.dumps(row, ensure_ascii=False, indent=2) + "\n")
    return row


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Explicit Simulator UDID")
    parser.add_argument("--app", type=Path, required=True, help="Frozen .app path with sibling BUILD_RECEIPT.json")
    parser.add_argument("--output", type=Path, required=True, help="New evidence directory; existing path is refused")
    parser.add_argument("--enemies", nargs="+", help="Optional stable enemy IDs; default is all bundled encounters")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    app, out = args.app.resolve(), args.output.resolve()
    if out.exists():
        raise SystemExit(f"Refusing to overwrite existing evidence directory: {out}")
    if not app.is_dir() or args.timeout < 20:
        raise SystemExit("App must exist and timeout must be at least 20 seconds")
    build_path, build, exe_sha, source_sha = assert_build(app)
    catalog = read_json(app / "catalog_overlay.json")
    enemies_by_id = {row["id"]: row for row in catalog.get("enemies", [])}
    if len(enemies_by_id) != 30:
        raise SystemExit(f"Expected 30 bundled enemy IDs; found {len(enemies_by_id)}")
    ids = args.enemies or [row["id"] for row in catalog["enemies"]]
    if len(set(ids)) != len(ids) or any(eid not in enemies_by_id for eid in ids):
        raise SystemExit("Enemy selection contains a duplicate or ID absent from this app's catalog")
    out.mkdir(parents=True)
    report: dict[str, Any] = {
        "schema": "effect_encounter_audit_r001", "status": "RUNNING",
        "scope": "ISOLATED_SIMULATOR_REAL_GAMEENGINE_BATTLE_PLAYBACK_REWARD_SAVE_REOPEN; UNAPPROVED TEST FIXTURE",
        "humanApproved": False, "device": args.device, "bundleID": BUNDLE,
        "app": str(app), "buildReceipt": str(build_path), "buildReceiptSHA256": sha_file(build_path),
        "executableSHA256": exe_sha, "bindingSourceSHA256": source_sha,
        "runnerPath": str(Path(__file__).resolve()), "runnerSHA256": sha_file(Path(__file__).resolve()),
        "frozenSourceSnapshot": build.get("source_snapshot"),
        "pinnedGameplayAndPresentationSources": {
            path: build.get("source_sha256", {}).get(path) for path in PINNED_SOURCES
        },
        "candidateRewardContractSource": "native/WitchGameCore/Sources/WitchGameCore/GameEngine.swift",
        "candidateRewardExpectations": {"ordinaryWin": {"coin": 2, "dropMaterial": 1},
                                        "bossWin": {"coin": 10, "dropMaterial": 5},
                                        "defeat": {"currency": 0, "materials": 0}},
        "fixture": "challenge QA fixture per encounter; no natural progression evidence",
        "enemyIDs": ids, "cases": [],
    }
    (out / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    run("xcrun", "simctl", "install", args.device, str(app))
    data_container = Path(run("xcrun", "simctl", "get_app_container", args.device, BUNDLE, "data"))
    support = data_container / "Library/Application Support/Witch03to05R1"
    for eid in ids:
        try:
            row = run_case(app, out, support, args.device, enemies_by_id[eid], args.timeout)
        except Exception as error:
            row = {"enemyID": eid, "status": "FAIL", "error": repr(error)}
        report["cases"].append(row)
        report["status"] = "RUNNING"
        (out / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"enemyID": eid, "status": row["status"], "outcome": row.get("outcome"),
                          "checks": row.get("checks"), "error": row.get("error")}, ensure_ascii=False), flush=True)
        if row["status"] == "FAIL":
            report["status"] = "FAILED_CASE_RETAINED"
            break
    else:
        has_inconclusive = any(row.get("status") == "INCONCLUSIVE" for row in report["cases"])
        report["status"] = ("INCONCLUSIVE_SELECTED_CASES" if has_inconclusive else
                            "PASS_ALL_SELECTED_CASES" if len(ids) == 30 else "PASS_SELECTED_CASES")
    report["completedCaseCount"] = len(report["cases"])
    report["passedCaseCount"] = sum(row.get("status") == "PASS" for row in report["cases"])
    report["inconclusiveCaseCount"] = sum(row.get("status") == "INCONCLUSIVE" for row in report["cases"])
    (out / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if report["status"] == "FAILED_CASE_RETAINED":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
