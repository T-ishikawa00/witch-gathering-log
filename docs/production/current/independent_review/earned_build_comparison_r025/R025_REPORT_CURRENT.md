# R025 progression and earned-loadout comparison — current reconciliation

**Status: unapproved test overlay.** This report consolidates preserved 90-day actual-command runs, the frozen R003 reruns, the 48-row earned-loadout matrix, and the day-count correction. No formal balance, growth, or monetization choice is approved.

## Evidence and provenance

The definitive paired active-policy reruns are in [frozen_r003](tier_safe/frozen_r003/FINAL_RUN_NOTE.md). Both used seed 4742, candidate R014, growth 500 BP, and the opt-in `nondecreasing_highest` comparison policy. The exact frozen package contains 4,974 manifest-listed files; manifest SHA-256 is `3d7229ea315a89fd9048369b1bc2789d05f99fa76cf33b7b9c95cc201e8dafba`. Its runner SHA-256 is `000340e9d796bc672b5640267180fc3be6d826c6ea5184c36d336c46f9ad0457`. The package was rehashed after execution. Each run’s [PROVENANCE.json](tier_safe/frozen_r003/free_ward/PROVENANCE.json) records environment, command, package/runner pins, test-log, report, and action-log hashes.

Earlier R025 raw runs under [free_ward](free_ward/) and [free_poison](free_poison/) retain action logs and per-file source hashes, but the full source bytes for their runner revision were not preserved; only its SHA (`4c98a483…`) remains. The raw logs are retained unchanged. Corrected R002 has a separate saved source snapshot and uses runner SHA `81f0edca…`. The older `tier_safe/free_*` directory’s runner SHA `d0597d5e…` is another prior attempt, not corrected R002. R003 removes this ambiguity with a complete fresh package freeze.

## 500 BP full progression outcomes

| Run | Commands | Campaign / challenges | Actual campaign clear | Challenge clear | R05 final campaign receipt | Day-30 final challenge: ticks / party HP after battle | Resource / investment summary |
|---|---:|---|---:|---:|---|---|---|
| Legacy free_ward | 1,418 | 30/30, 15/15; 0 defeats | Day 20 | Day 25 | B_R05_B, 24 ticks | CH_R05_03, 23 ticks / 498 HP | 620 refine dust; 29 enhances, 20 refinements, 12 promotions; 450 free pulls; 0 evolutions |
| Frozen R003 free_ward | 1,409 | 30/30, 15/15; 0 defeats | Day 20 | Day 25 | B_R05_B, 23 ticks | CH_R05_03, 23 ticks / 520 HP | 510 refine dust; 26 enhances, 18 refinements, 9 promotions; 450 free pulls; 0 evolutions |
| Legacy free_poison | 1,424 | 30/30, 15/15; 0 defeats | Day 20 | Day 25 | B_R05_B, 20 ticks | CH_R05_03, 20 ticks / 489 HP | 700 refine dust; 31 enhances, 21 refinements, 15 promotions; 450 free pulls; 0 evolutions |
| Frozen R003 free_poison | 1,416 | 30/30, 15/15; 0 defeats | Day 20 | Day 25 | B_R05_B, 22 ticks | CH_R05_03, 22 ticks / 500 HP | 620 refine dust; 28 enhances, 19 refinements, 13 promotions; 450 free pulls; 0 evolutions |
| Passive control | 731 | 30/30, 15/15; 1 defeat | Day 21 | Day 26 | B_R05_B, 39 ticks | CH_R05_03, 40 ticks / 206 HP | 0 free pulls, no target upgrades; 5 owned gear instances / 5 equipped slots |

Actual clear day comes from the successful `campaign-encounter:B_R05_B` action row and daily save snapshot. Earlier `firstCampaignClearDay` summaries were one day late because they sampled before that day’s combat loop. The raw JSON remains unchanged; the table uses the committed action day.

The corrected selector avoids target-stage downgrades present in the preserved legacy action logs: free_ward equipped G2 on day 1 then G1 on day 3; free_poison equipped P2 on day 3 then P1 on day 18. The frozen R003 selector does not reduce the target stage. It is an analysis-only deterministic policy, not an auto-equip game feature and not proof that a higher stage is always stronger. The standard test-runner default remains `legacy_first`. These are runner selection policies; the app has no automatic weapon-tier selection or auto-equip behavior, and equipment changes still require explicit game commands.

The spending delta is material: the corrected ward trace spent 110 fewer refine dust and issued 9 fewer commands than its legacy trace; corrected poison spent 80 fewer dust and issued 8 fewer commands. Yet the poison R05 boss receipt became two ticks slower (20→22); ward became one tick faster (24→23). These whole-run traces change both selected gear and upgrade spending, so they do not isolate gear-stage combat causality. Both active runs ended with 45 gear instances and 24 equipped slots.

`free_poison` names a poison-target strategy only. Each run’s successful evolution count is zero; neither the old prose nor the strategy label establishes a completed evolution chain.

## 250 vs 500 BP and earned loadouts

A separate 48-row matrix compares the same saved day-30/day-90 inventories and loadouts at both growth settings using actual `.equip` and `.resolveEncounter(B_R05_B, seed: 100049)` dispatch. It has **36 available-and-winning rows and 12 unavailable rows** (18 and 6 at each BP). The unavailable combinations stayed unavailable; no gear was synthesized. The 500 BP value is the current app candidate; 250 BP is a test-only comparator. See [matrix method/results](LOADOUT_GROWTH_SENSITIVITY_R002.md) and the [machine-readable rows](loadout_checks/LOADOUT_MATRIX_R002_GROWTH_SENSITIVITY.json).

On the passive Q0 starter set, the fixed-input B_R05_B probe changed from 86.6 seconds and 20 total survivor HP at 250 BP to 40.2 seconds and 132 HP at 500 BP. For available active ward/poison loadouts, 500 BP shortened this one seeded boss by 1.1–3.2 seconds; all available pairs won at both rates. This is a narrow same-save sensitivity result, not a whole-campaign balance decision. The day-30 snapshot’s last result is challenge `CH_R05_03`, not the campaign boss; campaign action receipts do not retain the boss’s complete HP maps, so this report does not claim a campaign-boss HP delta.

The 250 BP full-run comparison is confounded by investment policy. Passive control unlocked all five regions but finished 28/30 campaign, with 72 repeated defeats at R05_A/B and no challenge attempts. The active ward policy cleared campaign on actual day 20 and all challenges by day 25 with no defeats. At 500 BP, passive cleared on actual day 21 and challenges on day 26 with one campaign defeat. The passive day-30 inventory has exactly `EQ_W_01`, `EQ_A_01`, `EQ_S_01`, `EQ_F_01`, and `EQ_BODY_01`; it is a passive control, not a representative engaged player. See [250 BP run analysis](GROWTH_250_VS_500_R003.md).

## Limits

These are seeded local simulations using actual engine commands and file-backed save reopen checks. Their virtual schedule issues multiple gather-target/settlement actions inside each day; it is not a literal one-login/day observation. One seed, candidate combat/economy values, and one paired R05 boss cannot establish player fun, market fit, Human acceptance, or formal balance. No runtime, catalog, normal save, purchase service, or external system was changed in this analysis batch.

Machine-readable companion: [R025_REPORT_CURRENT.json](R025_REPORT_CURRENT.json).
