# Earned loadout and growth sensitivity R002

Status: `UNAPPROVED_TEST_OVERLAY`. This is a bounded deterministic engineering comparison, not balance approval, player-experience evidence, or formal adoption.

## Method

The runner read six file-backed checkpoints from the R025 90-day actual-command runs: day 30 and day 90 for `passive_control`, `free_ward`, and `free_poison`. It hashed each source file and decoded snapshot, cloned it into an in-memory `SaveRepository`, then used actual `.equip` commands and `.resolveEncounter(enemyID: "B_R05_B", seed: 100049)` under the app candidate composition: R014 combat overlay plus R017 relative growth at 250BP and 500BP. The source saves were re-read byte-for-byte after each pass. The 48-row result is in [LOADOUT_MATRIX_R002_GROWTH_SENSITIVITY.json](LOADOUT_MATRIX_R002_GROWTH_SENSITIVITY.json); the exact test output is in [LOADOUT_TEST_R002_GROWTH_SENSITIVITY.log](LOADOUT_TEST_R002_GROWTH_SENSITIVITY.log).

`passive_control` has only its saved starter loadout available. Both active runs have three of the four alternate loadouts available at both checkpoints; `ward_reflect_heal_cover_chase` is available in free_ward and free_poison, while the other requested variants are unavailable in passive_control because the gear was never earned. The test does not create or grant missing items.

## Results

All available same-save/loadout pairs won the selected R05 boss at both growth settings. The paired change from 250BP to 500BP was:

| Checkpoint/loadout | 250BP elapsed | 500BP elapsed | 500BP minus 250BP | Survivor HP total, 250 → 500 |
|---|---:|---:|---:|---:|
| passive starter Q0 | 86.6 s | 40.2 s | −46.4 s | 20 → 132 |
| free_ward saved gear | 26.6 s | 24.75 s | −1.85 s | 471 → 475 |
| free_ward ward/heal/cover | 26.6 s | 23.4 s | −3.2 s | 471 → 481 |
| free_ward ward/reflect/heal/cover/chase | 26.35 s | 23.4 s | −2.95 s | 493 → 503 |
| free_poison saved gear | 23.5 s | 21.95 s | −1.55 s | 386 → 489 |
| free_poison poison/heal/pressure/chase | 23.5 s | 22.4 s | −1.1 s | 393 → 500 |
| free_poison ward/reflect/heal/cover/chase | 26.35 s | 23.4 s | −2.95 s | 492 → 502 |
| free_poison ward/heal/cover/mark | 26.6 s | 23.4 s | −3.2 s | 471 → 481 |

The day 30 and day 90 results repeat because these runs reached the same level-60 cap and ended with the same equipped weapon templates/qualities/enhancements. The encounter is one enemy and one seed; these results only show sensitivity to the tested candidate growth multiplier. 250BP already cleared every available paired probe. The large starter delta relative to the smaller active-build deltas suggests the growth multiplier has a stronger effect than these loadout substitutions in this capped endgame probe. It does not prove growth dominates across the campaign or other enemy seeds.

## Progression context and data-quality note

The 90-day E2E runs used seed 4742, R014, growth500BP, no paid/ad grants, and a scripted virtual-day schedule. The schedule issues multiple gather-target and settlement commands within a day; it is not a literal one-human-login-per-day model. At day 30, all three strategies had cleared all 30 campaign encounters and all 15 challenges. `passive_control` did so one day later than the two active policies and had one campaign defeat; it intentionally skipped targeted investment and free-summon policy. At day 90, passive_control retained 5 gear instances and 5 equipped slots, while each active run held 45 gear instances and 24 equipped slots. Both active runs reported 450 free summons, 2 crafts, no failed commands, and no campaign/challenge defeats; free_ward recorded 29 enhancements, 20 refinements, 12 quality promotions, while free_poison recorded 31 enhancements, 21 refinements, 15 quality promotions.

The `free_poison` label means the configured policy targeted poison recipes. The saved report records **zero successful evolution commands**. Therefore this run does not evidence an actually completed poison evolution chain, regardless of the prior constraint prose. The poison-equipped loadout rows use only items present in the saved inventory and preserve their recorded Q0/Q2 quality and enhancement state.

The R025 E2E runs are generated from actual engine commands and reopened saves, but use scripted within-day gathers and are not evidence of one-login retention, player preference, or Human playtest. The paired boss probe uses `.resolveEncounter` on an in-memory clone and commits its reward only to that clone. B_R05_B is outside the R014 magnet target. Canonical fixed-point R6 fixtures remain a separate reference and were not modified.

## Reproduction and provenance

- Test: `swift test --filter EarnedLoadoutSnapshotComparisonTests`
- Result: 1 test, 0 failures; 48 rows; catalog SHA-256 `e9ff34b19a48ee53bd497e287750cd3af5817319c9ddb976d9d356cc4fd37245`.
- Comparison test SHA-256: `6a573a96a526ae7bdcdb9323d22650d6bf76b8d0953d6b6067aa12611c435732`.
- E2E runner test SHA-256: `4c98a48391ff14f88ab37866629a31a0081d85a975149033b5c590a2e7eed3d8`.
- Matrix SHA-256: `0e3398bee92b1e214c905ba66ab43e956f4ab68909d810baa823d00309adfe50`.
- Seeds: progression 4742; paired encounter 100049.

The paired test is a focused regression of the analysis harness, not a full package test. No product/runtime source, normal save, or external service was changed.
