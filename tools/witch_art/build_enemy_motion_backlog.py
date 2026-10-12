#!/usr/bin/env python3
"""Build a source-linked motion gap ledger for the 30 Witch enemy kits."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
OUT = ROOT / "docs/production/current/art"
EXPECTED_STATES = ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"]

# Morphology/motion families are planning hypotheses based on the canonical name.
# The details that affect identity, timing, or gameplay remain subject to art review.
FAMILIES = {
    "ACT_E_R01_01": ("quadruped_ground", "Four-beat walk cycle; weight shift and tusk-led charge."),
    "ACT_E_R01_02": ("arachnid_ground", "Alternating articulated leg gait; web/silk action; body stays ground-registered."),
    "ACT_E_R01_03": ("winged_insect_ground", "Insect gait with wing/leaf-blade follow-through."),
    "ACT_E_R01_04": ("roller_armored", "Leg/roll transition; roll only where canonical action permits."),
    "ACT_B_R01_A": ("large_quadruped_ground", "Heavy planted gait; root/tusk charge and long recovery."),
    "ACT_B_R01_B": ("rooted_plant_boss", "Rooted trunk sway and branch/root articulation; do not imply ordinary walking."),
    "ACT_E_R02_01": ("spore_body_ground_or_hover", "Soft sac breathing/float and spore release; ground mode remains to verify."),
    "ACT_E_R02_02": ("reptile_ground", "Low quadruped gait, torso undulation, lizard lunge."),
    "ACT_E_R02_03": ("aquatic_hover_tentacle", "Bell pulse and two independent tentacle waves; map walk to drift/swim only if approved."),
    "ACT_E_R02_04": ("flying_moth", "Wingbeat and hover/flight cycle; preserve powder/wing silhouette."),
    "ACT_B_R02_A": ("walking_mushroom_boss", "Heavy two-leg weight transfer plus cap/spore telegraph."),
    "ACT_B_R02_B": ("large_reptile_ground", "Four-beat gait, torso/tail follow-through, lizard boss lunge."),
    "ACT_E_R03_01": ("crustacean_ground", "Alternating many-leg gait; shell weight/side shift."),
    "ACT_E_R03_02": ("flying_bat", "Wingbeat and inverted/hover transitions if supported by source design."),
    "ACT_E_R03_03": ("construct_ground", "Chunky jointed steps and tool/arm action."),
    "ACT_E_R03_04": ("reptile_ground", "Low four-beat gait and tail counterbalance."),
    "ACT_B_R03_A": ("multiarm_construct_boss", "Existing five-state arm rig; needs walk and resolve; hammer reach must not be mistaken for foot contact."),
    "ACT_B_R03_B": ("large_construct_boss", "Heavy biped gait, mass shift, mining/forge action."),
    "ACT_E_R04_01": ("wolf_quadruped_ground", "Four-beat gait, shoulder/neck lead and tail balance."),
    "ACT_E_R04_02": ("flying_owl", "Wingbeat/glide and grounded settle; eye/head tracking."),
    "ACT_E_R04_03": ("roller_armored", "Leg/roll transition; shell remains aligned to ground."),
    "ACT_E_R04_04": ("construct_ground", "Jointed scraping steps and tool/arm motion."),
    "ACT_B_R04_A": ("large_horned_quadruped", "Planted quadruped gait; horn-led warning/charge and recovery."),
    "ACT_B_R04_B": ("large_dragon_ground_winged", "Four-part source supports neck/head, two wings, fused body/legs/tail; breathe/wing motion possible, independent leg walk is not."),
    "ACT_E_R05_01": ("floating_spirit_object", "Hover, page/cover flutter, readable tilt rather than foot gait."),
    "ACT_E_R05_02": ("armored_guardian_ground", "Planted guard stance, jointed steps, shield/body turn."),
    "ACT_E_R05_03": ("floating_familiar", "Bottle bob, hover/drift, liquid/glow motion only where existing source supports it."),
    "ACT_E_R05_04": ("flower_beast_ground", "Quadruped/plant weight shifts and petal/head follow-through."),
    "ACT_B_R05_A": ("pruning_construct_boss", "Machine gait, articulated tool arms, ring/pruning telegraph."),
    "ACT_B_R05_B": ("large_deer_quadruped", "Four-beat deer gait, antler balance, rooted landing/recovery."),
}


def main() -> None:
    index = json.loads((ART / "runtime_index.json").read_text())
    manifest = json.loads((ART / "asset_manifest_r002.json").read_text())
    catalog = {}
    csv_path = ROOT / "docs/design/sources/all_regions_r4/Witch_AllRegions_ArtSpec_R4_20261009/data/work_packages_R4.csv"
    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if row.get("type") == "enemy_actor_kit":
                catalog[row["asset_id"]] = row
    files_by_id: dict[str, list[dict]] = {}
    for record in manifest["files"]:
        files_by_id.setdefault(record["asset_id"], []).append(record)

    actors = []
    for actor_id, entry in index["entries"].items():
        if entry.get("kind") != "enemy_actor_kit":
            continue
        row = catalog.get(actor_id, {})
        source = None
        selected = entry.get("selectedPNG")
        if selected:
            exact = [r for r in files_by_id.get(actor_id, []) if r.get("bundle_relative_path") == selected]
            source = exact[0].get("source_path") if exact else None
        if actor_id == "ACT_B_R04_B":
            source = "/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/representatives/ACT_B_R04_B/parts_pilot_r005/parts_atlas.png"

        clips = entry.get("clips") or {}
        present = sorted(k for k in clips if k in EXPECTED_STATES)
        complete_states = [s for s in EXPECTED_STATES if s in present]
        missing = [s for s in EXPECTED_STATES if s not in present]
        family, motion_note = FAMILIES.get(actor_id, ("unclassified", "Requires source-spec review."))
        actors.append({
            "asset_id": actor_id,
            "region_id": row.get("region_id", actor_id.split("_")[2]),
            "display_name": row.get("description", "").split(" 本体")[0],
            "original_source_path": source,
            "bundle_still_path": selected,
            "current_index_status": entry.get("status"),
            "clip_states_present_in_index": present,
            "required_states": EXPECTED_STATES,
            "states_missing_from_index": missing,
            "motion_family_hypothesis": family,
            "motion_type_note": motion_note,
            "motion_type_basis": "Name/art-spec morphology planning inference; validate against canonical actor spec before authorship.",
            "authored_natural_motion_complete": False,
            "review": "HUMAN_ADOPTION_PENDING"
        })

    # Treat only established source clip actors as the three baseline exceptions.
    # Spider's nine poses remain candidates until they have natural transitions.
    baseline = {"ACT_E_R01_01", "ACT_E_R02_03", "ACT_B_R03_A"}
    remaining = [a for a in actors if a["asset_id"] not in baseline]
    payload = {
        "schema": "witch.enemy_motion_gap_ledger.v1",
        "source_index": "native/Art/runtime_index.json",
        "source_catalog": str(csv_path.relative_to(ROOT)),
        "required_state_contract": EXPECTED_STATES,
        "status": "PARTIAL; all states require authored natural motion, runtime integration, and Human art adoption",
        "counts": {
            "enemy_kits": len(actors),
            "established_clip_baseline_exceptions": len(baseline),
            "remaining_motion_production_targets": len(remaining),
            "remaining_with_any_index_clip": sum(bool(a["clip_states_present_in_index"]) for a in remaining),
            "remaining_with_all_seven_states": sum(not a["states_missing_from_index"] for a in remaining)
        },
        "state_semantics": {
            "idle": "Species-specific breathing, blink, hover, or planted sway; avoid a frozen still.",
            "walk": "Locomotion for grounded species; flight/swim/hover/roll/rooted shuffle must be defined per canonical form, not forced into a foot cycle.",
            "anticipate": "Readable pre-action body cue before hit/effect resolution.",
            "execute": "Species-specific authored action motion.",
            "recover": "Visible recoil, landing, or return to balance.",
            "hit": "Readable impact reaction that preserves anchor and identity.",
            "resolve": "Outcome/defeat/reward reaction; still pose or mirrored hit frame is insufficient."
        },
        "actors": actors,
        "remaining_motion_targets": remaining
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "enemy_motion_gap_ledger_r001.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")

    lines = [
        "# Enemy motion production backlog R001",
        "",
        "This is an evidence-linked worklist, not an acceptance or adoption report. A static image, pose sheet, or incomplete clip set does not satisfy an animation state. `walk` is a movement concept adapted to each species (flight, swim, roll, rooted motion) where a foot cycle would be wrong.",
        "",
        f"Observed in runtime index: {len(actors)} enemy kits; {len(remaining)} remaining production targets after separating boar, jellyfish, and hammerman source-clip baselines. The spider's nine generated poses remain in the backlog pending natural transitions and screen review.",
        "",
        "Required state contract: `idle`, `walk`, `anticipate`, `execute`, `recover`, `hit`, `resolve`. Existing partial states are listed as evidence only and do not mark motion complete.",
        "",
        "|ID|正本名|原画/部位正本|現在のindex状態|不足state|motion family hypothesis|",
        "|---|---|---|---|---|---|"
    ]
    for a in remaining:
        path = a["original_source_path"] or "UNKNOWN"
        lines.append("|`{}`|{}|`{}`|{}|{}|{}|".format(
            a["asset_id"], a["display_name"], path, a["current_index_status"],
            ", ".join(a["states_missing_from_index"]) or "none in index; quality/integration still unverified",
            a["motion_family_hypothesis"]
        ))
    lines += [
        "",
        "Motion-family notes are explicit planning inferences from the canonical names and art package, not approved animation design. Recheck the actor-specific regional spec before drawing poses. Source path and clip evidence live in the JSON ledger. The top priority R01 six are the four ordinary enemies plus both bosses; do not stop at the spider sample.",
        "",
        "`authored_natural_motion_complete` remains false for every entry until continuous motion, state transitions, a stable anchor, runtime playback, and visual review are evidenced. Human art adoption remains pending."
    ]
    (OUT / "enemy_motion_gap_ledger_r001.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
