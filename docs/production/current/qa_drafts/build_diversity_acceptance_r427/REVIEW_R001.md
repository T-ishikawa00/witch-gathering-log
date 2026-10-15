# R427 build-diversity acceptance review

**Status: local evidence is partial; no production defect is established by these records.**

Stage 3 asks for poison, barrier, counter, healing and follow-up builds; for proof that direct attack is not the only successful answer; and for outcome evidence covering wins, time, safety, resource needs and multiple solutions. The current engine exposes a paired, no-reward loadout preview that returns `CombatResult` (win, ticks, enemy/party HP and event trace) while checking that both loadouts use existing owned items and identical occupied slots (`GameEngine.swift`, lines 177–240).

The strongest local result already rebuts “direct is the only solution”: on CH_R02_01, direct and poison arms each won all three fixed seeds. The poison arm was tied twice and three ticks faster once; party HP loss was 20/22/25 versus 20/22/29. Both Q0 weapons had +3 catalog attack and no upgrade dust invested. Their natural latent rolls differ, and the source save is an R368 30-day simulated cohort, so the result is descriptive rather than an isolated causal estimate or a human-playtest result.

The other families have bounded but mixed outcome evidence. R359 membrane previews won with both builds and prevented 249–267 damage over 23–26 paired active hits, at a 4–5 tick cost. R377 barrier previews all won and added barrier/absorb/reflect, but saved one aggregate party HP per seed and changed no clear time. Smith counter showed 12 vs 8 damage in one seed; the event did not occur in the other two. Chase damage was 2 vs 1 on four paired attacks per seed, with one seed one tick faster. The R377 AF_HEAL test did not observe the candidate heal on CH_R02_01 and failed. R394 separately observed AF_HEAL 42 vs AF_WARD 39 on CH_R05_03, but both arms won in 29 ticks. R402’s Q4 poison projection was 916 bp against Q3’s 656 bp, yet both arms won in 9 ticks with the same party HP loss on all three seeds.

R371’s 15/15 tests verify authored challenge mechanics in `MECHANISM_ONLY` fixtures; they do not verify earned-build viability for all 15 challenges. R384 is a collection projection, not a battle comparison. R387 must not be treated as an aggregate pass: the selected Swift log records R376 pass, R377 fail and one R384 projection pass, while the adjacent resume receipt says no tests started. The older R387 candidate receipt separately records seven passes and three failures.

The remaining concrete local gap is traceability of **resource requirements**: the comparison reports identify owned UUIDs and upgrade investment, but they do not join every tested build to its acquisition/recipe receipt, required materials and unlock gate in the same acceptance record. Most outcome rows are no-reward previews of the virtual R368 cohort, not persisted alternate-build challenge transactions. A small follow-up can reconcile two existing comparisons (direct/poison and barrier/control) to their saved acquisition or recipe routes and costs, retaining the already-recorded per-seed wins, ticks, party HP and events. Only if the persisted command path itself needs verification, use separate copies of one pinned save and one seed for `.resolveChallenge`, then check `lastCombatResult`; because the source challenge is already cleared, label that as a synthetic-copy transaction check with no first-clear reward claim.

No Core or balance change is justified by this evidence. Formal balance, fun, purchase value and release approval remain separate decisions.

## Fixed source and evidence pins

- Acceptance: `03_ACCEPTANCE_AND_BLOCKERS.md` SHA-256 `5c26036c…d674012c`, Stage 3 line 6.
- Current engine: `GameEngine.swift` SHA-256 `c50d7418…45347b65`; timeline simulator `R6TimelineSimulator.swift` SHA-256 `2385aa9b…c813bc37`.
- Full evidence paths, exact hashes, outcomes and limits are in `REVIEW_R001.json`.
