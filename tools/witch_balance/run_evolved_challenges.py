"""Trial three named research scenarios with an unapproved R6-B gear overlay."""
from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import replace
from functools import partial
import json
from pathlib import Path
import statistics
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ENDGAME = HERE / "reference/endgame_r1/Witch_G2_Collection_Endgame_Monetization_R1_20261010"
sys.path.insert(0, str(ENDGAME / "tools"))
import lab  # noqa: E402
from evolved_overlay import EvolvedOverlayBattle  # noqa: E402


def encounter(challenge: str) -> dict:
    base = {"level": 60, "hp": 135000, "power": 1250, "defense": 500,
            "dot_resist_bp": 0, "first_telegraph_ms": 1200, "time_limit_ms": 150000}
    def action(id, coefficient, windup, offsets, recovery, rest, aoe=False, heavy=False):
        return {"id": id, "coefficient_bp": coefficient, "windup_ms": windup,
                "hit_offsets_ms": offsets, "recovery_ms": recovery, "rest_ms": rest,
                "aoe": aoe, "heavy": heavy}
    if challenge == "CH_R01_03":
        return {**base, "id": "TRIAL_CH_R01_03", "name": "古樹の脈動・固定候補",
                "power": 1450,
                "actions": [action("ROOT_COMBO", 18000, 1400, [0, 400, 800], 900, 900, False, True),
                            action("BRANCH_SWEEP", 8000, 1700, [0], 1200, 2200, True)]}
    if challenge == "CH_R02_02":
        return {**base, "id": "TRIAL_CH_R02_02", "name": "水鏡のゆらぎ・固定候補",
                "hp": 165000, "power": 1050, "defense": 550, "overlay_phase": True,
                "actions": [action("MIRROR_PULSE", 8500, 1300, [0], 900, 1800, True)]}
    if challenge == "CH_R03_01":
        return {**base, "id": "TRIAL_CH_R03_01", "name": "連槌の検分・固定候補",
                "actions": [action("HAMMER_MULTI", 5200, 1200, [0, 350, 700], 800, 1700, False, True),
                            action("HAMMER_NEW_ROOT", 9500, 900, [0], 700, 2500, False, True)]}
    raise ValueError(challenge)


BUILD_GEAR = {
    "DIRECT": {"base": "BURST", "items": {}},
    "TOXIN_CHASE": {"base": "BALANCED", "items": {"C_WITCH": "EQ_W_P2", "C_FAMILIAR": "EQ_F_03"}},
    "WARD_HEAL_COUNTER": {"base": "BALANCED", "items": {"C_WITCH": "EQ_W_G2", "C_APPRENTICE": "EQ_A_03", "C_SMITH": "EQ_S_03"}},
    "COUNTER_ONLY": {"base": "BALANCED", "items": {"C_SMITH": "EQ_S_02"}},
    "HEAL_ONLY": {"base": "BALANCED", "items": {"C_APPRENTICE": "EQ_A_03"}},
    "CHASE_ONLY": {"base": "BALANCED", "items": {"C_FAMILIAR": "EQ_F_03"}},
}


def party_for(build_name: str):
    spec = BUILD_GEAR[build_name]
    rows = []
    for p in lab.party(spec["base"]):
        target = spec["items"].get(p.actor_id)
        items = tuple(replace(it, template_id=target) if target and lab.g.GEAR[it.template_id]["slot"] == "weapon" else it
                      for it in p.items)
        rows.append(replace(p, items=items))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--seed-start", type=int, default=930000)
    ap.add_argument("--count", type=int, default=32)
    args = ap.parse_args()
    if args.count <= 0:
        ap.error("count must be positive")
    args.output.mkdir(parents=True, exist_ok=False)
    challenges = ("CH_R01_03", "CH_R02_02", "CH_R03_01")
    input_record = {"seed_start": args.seed_start, "seed_count": args.count,
                    "builds": BUILD_GEAR, "challenges": [encounter(c) for c in challenges],
                    "rarity_model": "H1_RECOMMENDED test candidate",
                    "combat_fixed_point_scale": 10000,
                    "enemy_identity_status": "trial fixture; does not claim canonical enemy source values or ID",
                    "unlock_gate": "G_R05_B test fixture; no progression or research reward applied",
                    "overlay": "EVOLVED_RULES_TRIAL_R1", "official_status": "UNAPPROVED"}
    (args.output / "INPUTS.json").write_text(json.dumps(input_record, ensure_ascii=False, indent=2))
    rows, summaries, golden = [], [], {}
    h1patch = partial(lab.old.RarityRules, multipliers=lab.old.MODELS["H1_RECOMMENDED"])
    for challenge in challenges:
        enemy = encounter(challenge)
        for build in BUILD_GEAR:
            results = []
            for seed in range(args.seed_start, args.seed_start + args.count):
                with patch.object(lab.precision_rules, "PrecisionRules", h1patch):
                    battle = EvolvedOverlayBattle(party_for(build), enemy, seed, record=(seed == args.seed_start))
                    out = battle.run()
                metrics = dict(out["metrics"])
                row = {"challenge_id": challenge, "build": build, "seed": seed,
                       "outcome": out["outcome"], "elapsed_ms": out["elapsed_ms"],
                       "party_hp_remaining": sum(out["party_remaining_hp"].values()),
                       "boss_hp_remaining": out["boss_remaining_hp"], "metrics": metrics}
                rows.append(row); results.append(row)
                if seed == args.seed_start:
                    golden[f"{challenge}_{build}"] = out
            wins = [r for r in results if r["outcome"] == "VICTORY"]
            keys = ("damage_basic", "damage_active", "damage_counter", "damage_chase", "damage_reflect",
                    "damage_dot", "received_hp", "barrier_absorbed", "effective_heal", "evolved_heal_barrier",
                    "evolved_pressure_gain", "evolved_pressure_consumed_stacks", "evolved_poison_burst",
                    "evolved_reflect_trigger", "evolved_cover_barrier", "evolved_mark_duration")
            summaries.append({"challenge_id": challenge, "build": build,
                              "wins": len(wins), "n": len(results),
                              "median_win_seconds": statistics.median(r["elapsed_ms"] / 1000 for r in wins) if wins else None,
                              "median_party_hp_remaining": statistics.median(r["party_hp_remaining"] for r in results) / 10000,
                              "metric_means": {key: statistics.mean(r["metrics"].get(key, 0) for r in results) /
                                               (10000 if key.startswith("damage_") or key in ("received_hp", "barrier_absorbed", "effective_heal", "evolved_heal_barrier") else 1)
                                               for key in keys}})
    (args.output / "BATTLE_ROWS.json").write_text(json.dumps(rows, ensure_ascii=False))
    (args.output / "SUMMARY.json").write_text(json.dumps(summaries, ensure_ascii=False, indent=2))
    (args.output / "GOLDEN_FIRST_SEED.json").write_text(json.dumps(golden, ensure_ascii=False, indent=2))
    print(json.dumps(summaries, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
