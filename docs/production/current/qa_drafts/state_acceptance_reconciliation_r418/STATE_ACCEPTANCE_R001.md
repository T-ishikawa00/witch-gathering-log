# State acceptance reconciliation: R418

**Status:** local technical state review remains partial; this is not a Human-art decision.

## Counts grounded in recorded actual encounter traces

- Enemy IDs: 30/30 have trace coverage. Seven-state union: 11/30. Missing execute and recover: 9/30; missing recover only: 10/30. All 30 have idle, walk, anticipate, hit, and resolve in the capture union.
- Four allies: state categories are present across R377 traces and R407 marker-matched hit frames; no state is wholly missing for any ally. Sparse samples do not establish continuous quality.
- All 30 enemies also have existing R083 forced-state clips. Those are suitable for pose appearance checks, not proof of naturally dispatched transitions.

## Exact remaining per-enemy gaps

| Actor | Missing actual-event trace states | Existing capture sources |
|---|---|---|
| ACT_B_R01_A | execute, recover | R391 |
| ACT_B_R01_B | recover | R391 |
| ACT_B_R02_A | none | R391 |
| ACT_B_R02_B | none | R391 |
| ACT_B_R03_A | recover | R391 |
| ACT_B_R03_B | execute, recover | R391 |
| ACT_B_R04_A | recover | R391 |
| ACT_B_R04_B | recover | R407 |
| ACT_B_R05_A | none | R407, R411A |
| ACT_B_R05_B | recover | R411B, R418 |
| ACT_E_R01_01 | none | R377 |
| ACT_E_R01_02 | recover | R377 |
| ACT_E_R01_03 | recover | R377 |
| ACT_E_R01_04 | none | R377 |
| ACT_E_R02_01 | execute, recover | R391 |
| ACT_E_R02_02 | execute, recover | R391 |
| ACT_E_R02_03 | none | R391 |
| ACT_E_R02_04 | execute, recover | R391 |
| ACT_E_R03_01 | none | R391 |
| ACT_E_R03_02 | execute, recover | R391 |
| ACT_E_R03_03 | recover | R391 |
| ACT_E_R03_04 | execute, recover | R391 |
| ACT_E_R04_01 | recover | R391 |
| ACT_E_R04_02 | execute, recover | R391 |
| ACT_E_R04_03 | none | R391 |
| ACT_E_R04_04 | execute, recover | R391 |
| ACT_E_R05_01 | none | R407 |
| ACT_E_R05_02 | recover | R407 |
| ACT_E_R05_03 | none | R407 |
| ACT_E_R05_04 | none | R407 |

There are 9 actors missing both execute and recover, 10 missing recover only, and 11/30 with all seven state names observed in actual encounter traces. The full per-actor table contains trace manifest and video paths, forced clip path, and source state arrays. These are event/render observations, not 30 complete visual passes.

R418 corrects the concrete B_R05_B execute interruption for three sampled attacks (18/16/17 frames) and shows terminal resolve. Recover remains unobserved on that actor. R391’s raw capture batch stays failed-retained; its offline review sampled cases 01–17, not 18–19, and six R05 cases were not launched in that batch.

## Smallest local closeout

Run only the 19 actor/state gaps once each through actual engine-dispatched challenge encounters, with fresh QA keys and no forced poses or combat-value edits. Join event → actor/action root/generation → visible state-frame rows; check a beginning/middle/end phone-scale sample for bounds, disappearance, crop, identity and weapon visibility. If a state is not naturally reached in its one attempt, record that condition rather than treating a forced R083 clip as event proof. Reuse all existing clips and the four-ally evidence. Do not redraw any asset unless this targeted review shows a reproducible rendering defect.

Canonical R008 and checkpoint R082 were not edited. R082 and R008 list R418 as pending; this report adds the later R418 evidence without rewriting either record.
