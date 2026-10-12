"""Endgame target acquisition by spending persona and login interval.

Conditional snapshot only: post-R05, all gear pools unlocked, no battle/upgrade
choices. The reference sampler is reused without changing source files.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys
import numpy as np

HERE = Path(__file__).resolve().parent
ENDGAME = HERE / "reference/endgame_r1/Witch_G2_Collection_Endgame_Monetization_R1_20261010"
sys.path.insert(0, str(ENDGAME / "tools"))
import lab  # noqa: E402
import collection as ref_collection  # noqa: E402

TARGET = "EQ_W_P2"
PERSONAS = ("FREE_NO_AD", "AD_ONLY", "ONE_OUTFIT", "ONE_SMALL_PURCHASE",
            "VALUE_PACK_ONLY", "VALUE_PLUS_DELIVERY", "REGULAR_100_PER_30D",
            "HIGH_BUDGET_400_PER_30D")
METRICS = ref_collection.METRICS


def run_persona(persona: str, login_hours: int, samples: int, seed: int):
    n_affixes = len(lab.g.eligible_affixes(TARGET))
    natural_rate = ref_collection.natural_prob(TARGET)
    discovered_nat = np.zeros((samples, len(METRICS)), dtype=bool)
    discovered_gacha = np.zeros_like(discovered_nat)
    nat_misses = np.zeros(samples, dtype=int)
    top = np.zeros(samples, dtype=int)
    mid = top.copy()
    forced = np.zeros(samples, dtype=bool)
    natural_rng = np.random.default_rng(seed)
    gacha_rng = np.random.default_rng(seed + 100000)

    def add_natural(count):
        nonlocal discovered_nat, nat_misses
        for _ in range(count):
            qr = natural_rng.integers(0, 10000, samples)
            quality = np.select([qr < 4500, qr < 7500, qr < 9300, qr < 9900], [0, 1, 2, 3], default=4)
            quality = np.where(nat_misses == 99, 4, quality)
            nat_misses = np.where(quality == 4, 0, nat_misses + 1)
            selected = (natural_rng_index[0] % 6 == 0) | (natural_rng.random(samples) < natural_rate)
            flags = ref_collection.affix_flags(natural_rng, samples, n_affixes, quality, "natural") & selected[:, None]
            discovered_nat |= flags
            natural_rng_index[0] += 1

    def add_gacha(count):
        nonlocal discovered_gacha, top, mid, forced
        for _ in range(count):
            quality, selected, top, mid, forced = ref_collection.vector_step(
                top, mid, forced, gacha_rng.integers(0, 10000, samples), gacha_rng.integers(0, 10000, samples))
            flags = ref_collection.affix_flags(gacha_rng, samples, n_affixes, quality, "gacha") & selected[:, None]
            discovered_gacha |= flags

    history = lab.old.personas(90)[persona][0]
    natural_rng_index = [0]
    active_interval_days = login_hours / 24
    last_pulls = 0
    checkpoints = {}
    for day in range(1, 91):
        # 24h sessions credit a full day. A 72h session earns only the R3 48h
        # unattended cap, so 96 gear arrive every third day (32/day average).
        if day % int(active_interval_days) == 0:
            credited_hours = min(login_hours, 48)
            add_natural(int(credited_hours * 2))
        projection = lab.old.plan_projection(history, day)
        desired_pulls = 5 * day + projection["tickets_from_products"]
        add_gacha(desired_pulls - last_pulls)
        last_pulls = desired_pulls
        if day in (30, 90):
            combined = discovered_nat | discovered_gacha
            row = {"persona": persona, "login_interval_hours": login_hours, "day": day,
                   "purchase_yen": projection["spend_jpy"],
                   "purchase_tickets": projection["tickets_from_products"],
                   "total_gacha_draws": desired_pulls,
                   "natural_gear_count": natural_rng_index[0], "samples": samples,
                   "goal_probabilities": {name: float(np.mean(combined[:, j])) for j, name in enumerate(METRICS)},
                   "goal_success_counts": {name: int(np.sum(combined[:, j])) for j, name in enumerate(METRICS)}}
            checkpoints[day] = row
    return list(checkpoints.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--samples", type=int, default=512)
    ap.add_argument("--seed", type=int, default=261120)
    args = ap.parse_args()
    if args.samples <= 0:
        ap.error("samples must be positive")
    args.output.mkdir(parents=True, exist_ok=False)
    rows = []
    for i, persona in enumerate(PERSONAS):
        for login_hours in (24, 72):
            rows.extend(run_persona(persona, login_hours, args.samples, args.seed + i * 10000))
    output = {"status": "UNAPPROVED_ENDGAME_ACQUISITION_PROJECTION",
              "target": TARGET, "samples_per_persona_frequency": args.samples, "seed_start": args.seed,
              "frequencies_hours": [24, 72], "personas": list(PERSONAS), "rows": rows,
              "limitations": ["starts after R05 with all equipment types unlocked", "no combat or gate progression",
                              "no crafting, quality promotion, reforging, inventory decisions, ads, or spend of powder",
                              "purchase schedules are candidate catalog scenarios, not approved products",
                              "72h login settles 48h offline cap every third day; purchased draw entitlements accrue by calendar day"]}
    (args.output / "PERSONA_FREQUENCY_GRID.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(rows, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
