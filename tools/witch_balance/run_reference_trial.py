"""Run the unmodified Endgame R1/R6-B affix lab on a fresh seed range.

This deliberately does not claim evolved-weapon or research-mechanic coverage.
The output folder must not already exist.
"""
from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
from dataclasses import asdict

HERE = Path(__file__).resolve().parent
ENDGAME = HERE / "reference/endgame_r1/Witch_G2_Collection_Endgame_Monetization_R1_20261010"
import sys
sys.path.insert(0, str(ENDGAME / "tools"))
from lab import BUILD_NAMES, bosses, fight, party  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--count", type=int, default=64)
    ap.add_argument("--seed-start", type=int, default=910000)
    args = ap.parse_args()
    if args.count <= 0:
        ap.error("count must be positive")
    args.output.mkdir(parents=True, exist_ok=False)
    inputs = {
        "builds": {name: [asdict(p) for p in party(name)] for name in BUILD_NAMES},
        "bosses": bosses(),
        "seed_start": args.seed_start,
        "count": args.count,
        "scope": "conditional Lv60/R5 basic-weapon affix lab; excludes evolved cores/research/awakening",
        "source": "unmodified Endgame R1 lab.py and imported R6-B FinalBattleR6",
    }
    (args.output / "INPUTS.json").write_text(json.dumps(inputs, ensure_ascii=False, indent=2))
    rows = []
    summaries = []
    for scenario, enemy in bosses().items():
        for build in BUILD_NAMES:
            trials = []
            for seed in range(args.seed_start, args.seed_start + args.count):
                result = fight(build, enemy, seed)
                row = {
                    "scenario": scenario, "build": build, "seed": seed,
                    "outcome": result["outcome"], "elapsed_ms": result["elapsed_ms"],
                    "boss_remaining_hp": result["boss_remaining_hp"],
                    "remaining_party_hp": sum(result["party_remaining_hp"].values()),
                    "metrics": result["metrics"],
                }
                rows.append(row)
                trials.append(row)
            wins = [row for row in trials if row["outcome"] == "VICTORY"]
            summaries.append({
                "scenario": scenario, "build": build, "wins": len(wins), "n": len(trials),
                "median_win_seconds": statistics.median(r["elapsed_ms"] / 1000 for r in wins) if wins else None,
                "median_remaining_party_hp": statistics.median(r["remaining_party_hp"] for r in trials) / 10000,
                "damage_dot_share_mean": statistics.mean(
                    r["metrics"].get("damage_dot", 0) / max(1, sum(v for k, v in r["metrics"].items() if k.startswith("damage_")))
                    for r in trials
                ),
                "counter_count_mean": statistics.mean(r["metrics"].get("reaction_counter", 0) for r in trials),
            })
    (args.output / "BATTLE_ROWS.json").write_text(json.dumps(rows, ensure_ascii=False))
    (args.output / "SUMMARY.json").write_text(json.dumps(summaries, ensure_ascii=False, indent=2))
    print(json.dumps(summaries, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
