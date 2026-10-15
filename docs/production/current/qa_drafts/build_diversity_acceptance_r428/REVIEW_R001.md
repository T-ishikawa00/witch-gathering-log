# R428 — acquisition, resource, and paired-outcome reconciliation

**Scope:** read-only reconciliation of the saved R376 direct/poison and R377 barrier/control comparisons, using the pinned R368 virtual 30-day cohort. No source edits, build, test, device action, or save mutation occurred.

## Result

The comparison UUIDs exist in the R368 free/no-ad simulated save, and the recorded preview rows show descriptive combat differences. That does not prove ordinary human availability, pure causal effect size, or a durable paired battle. Two UUIDs have no exact acquisition-record join: poison staff `6CA40746-2A06-4374-A92D-F321927D48BE` and barrier staff `68C84620-D911-48E4-983C-15E4EF8F202E`. Day-level summon outputs list those templates, but the draw records contain no UUID, so exact per-instance origin remains **UNKNOWN**.

The exact base control `BC499DA8-3B80-5536-BAFB-5143888B392C` is joined to natural roll 4 in R01, operation `36810000-0001-4001-8000-000000000005`. Smith control `B72CE760-9884-5D4F-8111-8709C8369782` and counter candidate `31292F32-5F63-5F71-84D9-B69BB4FC303A` have report-level natural joins at rolls 79/R01 and 326/R03 respectively. These older records no longer fit in the save’s 96-entry natural-acquisition retention window; the R368 daily report preserves those joins.

## Pair details and outcome rows

R376 compares Witch weapon `EQ_W_01` (Q0, +0, refinement 0, investment dust 0, attack +3) with `EQ_W_P1` under `CH_R02_01`. All six no-reward previews win. For seeds 37601/37602/37603, direct ticks are 9/9/12 and party HP loss is 20/22/29; poison ticks are 9/9/9 and HP loss is 20/22/25. Poison candidate rows contain poison_seed=2, poison_stack=2, and poison_tick=5/5/6. Latent rolls differ, so this is not a pure causal estimate.

R377 compares Witch `EQ_W_01` control with `EQ_W_G2` candidate for `CH_R02_02`. All six archived preview rows win. Candidate/control ticks are 18/17/18 in both arms. Party HP loss is 92/72/87 vs. 93/73/88. Candidate emits one barrier, absorb, and reflect event per seed; controls emit none. Both arms have Q0, +0, investment 0 and equal template attack, but natural latent slots differ. For `CH_R04_02`, the smith counter event occurs once in each arm at seed 37702 and nowhere else, so the rows do not establish candidate-specific counter uplift. For the apprentice-heal pair, neither arm emits `heal` in the three saved rows; the original heal assertion failure is an unobserved result for this fixture, not proof the mechanic is absent.

## Acquisition and crafting alternatives

The R368 daily log shows free-summon results listing `EQ_W_P1` on day 1 and `EQ_W_G2` on day 2, consistent with—but not UUID-bound to—the two items. The cohort records 155 free summon draws, 0 paid draws, only `RC_EQ_F_01` as a crafted recipe, three other evolution recipes, and zero synthetic-grant receipts.

The catalog’s alternative recipe for `EQ_W_P1` is `RC_EQ_W_P1`, parent `EQ_W_01`, cost 16 `M_R02_E1`, 16 `M_R02_G4`, 1 `M_R02_BA`, gate `G_R02_A`. At the R368 final save, those balances are 1/272/1, so this route is short 15 `M_R02_E1`; the recipe is not in the run’s crafted recipe list. `EQ_W_G2` has alternative recipe `RC_EQ_W_G2`, parent `EQ_W_G1`, cost 2 `M_R04_BB`, 28 `M_R05_E3`, 2 `M_R05_BA`, gate `G_R05_A`. Final balances are 5/1/1, short 27 `M_R05_E3` and 1 `M_R05_BA`; this recipe is absent from the crafted/evolved recipe lists. These recipe costs and gates describe alternatives, not the proven acquisition route of either UUID.

## Saved-command and cold-reopen coverage

Core already tests actual dispatch and persistence in general. `GearSwapCombatPreviewR131Tests.testBothUnassignedCandidatesAndActualEquipResolveMatch` checks preview against actual `.equip` then `.resolveChallenge`, but uses in-memory stores. `EquipmentLoadoutsR342Tests` exercises file-backed equip and loadout commands, reopens the save, and checks snapshot and receipt, without resolving a battle in that sequence. `CurrentProfileProgressionE2ERunnerR120Tests` dispatches real challenge commands and reopens a file-backed save after every virtual day, checking snapshot equality. No defect in those transaction paths was identified.

The narrow remaining evidence gap is that the exact R368 pair UUIDs were previewed, not each dispatched into a file-backed challenge resolution and reopened. If durable paired outcomes are needed, the smallest follow-up is one isolated copy per arm: set the exact Witch weapon UUID, dispatch equip and the same challenge/seed, then compare persisted `lastCombatResult`, receipt and cold-reopened snapshot. Do not infer a gacha UUID link where none is recorded.

## R387 receipt caveat

Keep the receipts separate. The candidate-R004 raw Swift log records 10 tests, 7 passed and 3 failed: R376’s runtime fingerprint assertion compared the R230 `f509…` fingerprint against integrated `2ba…`; R377 failed `occupiedSlotSetMismatch`; one R384 catalog-consistency assertion failed. Its outer receipt says `INCOMPLETE_RETAINED` and omits an exit code. Resume-R006 says no tests had started but also records passed/failed test names and contains R376/R377 reports. The archived 6- and 24-row report files are usable as described forecast output, but do not convert these conflicting receipts into a passing batch.

## Evidence pins

All fixed input, source, report, run and log SHA-256 values are recorded in [REVIEW_R001.json](REVIEW_R001.json). Important pins: R368 save `067c4e…e655`; R368 report `232662…d215`; R376 input `13fae7…f33b`; pair ledger `bee234…c4d7`; R376 report `b48eb9…a9f`; R377 report `207cac…c5a`; GameEngine `c50d74…7b65`.
