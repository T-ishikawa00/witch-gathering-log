# R407 residual temporal acceptance matrix

## Evidence boundary

R308 records exact runtime keys for all 159 baseline units, but those keys do not pass visual or temporal acceptance. For the 30 enemies, R366 sampled forced states for 27 actors at phone scale; its reviews report no gross clipping but do not prove event timing. The R377/R391 real-battle traces add state observations, while their clips are only about eight seconds and do not have a verified event-to-video join. The findings below keep those three kinds of evidence separate.

## Enemy coverage

R377 gives actual R01 battle trace coverage for E_R01_01–04. The state snapshots include all seven states for E_R01_01 and E_R01_04; E_R01_02 and E_R01_03 lack recover. The four associated enemy clips are roughly eight seconds each, with no trace-frame join.

R391 captured 19 synthetic-challenge encounters, with a raw case20 trace for B_R04_B rejected by a composite-root-texture validator. Among the 19 accepted-by-capture cases, observed-state gaps are: B_R01_A execute/recover; B_R01_B recover; E_R02_01, E_R02_02, E_R02_04 execute/recover; E_R03_02 and E_R03_04 execute/recover; E_R03_03 recover; B_R03_A recover; B_R03_B execute/recover; E_R04_01 recover; E_R04_02 execute/recover; E_R04_04 execute/recover; B_R04_A recover. The raw B_R04_B trace has all seven states but was not accepted by the runner. R391 videos run 7.90–8.07 seconds and have no OCR-confirmed state marker join.

R366 forced-state sheets cover 27/30 enemies. They record no gross cropping or overlap; one unconfirmed contrast concern is B_R01_B, whose telegraph and hit stills remain similarly upright. Size watches for E_R03_01, E_R05_01–04, B_R03_A, B_R05_A are not confirmed failures.

## Allies, effects, and the pending seven

R377 full-party trace has six pose states for each ally; AIRA also has hit, while ERNA, LUNA, and NOIR lack a visual hit sample. R391 actual-damage target rows include all four allies, but these are passive actor snapshots, not proof that a visible hit pose rendered.

R308 maps all 10 ENV/FX entries (five ambient + five combat VFX) into effect_kit entries. The 24–56 indexed PNG references per entry hash-match historical bundle references; all ten remain PARTIAL, with no current per-ID event-to-pixel review.

R407 is built as `enemyart.r407` (executable SHA `766d27ea64d4baef7ab247eb2f585ce301ea04309ba49d2be7e1ba2961f84d54`; 235 source entries, 1,922 resources). Root’s pending capture list is B_R04_B and the six R05 encounters. No R407 capture result is included here.

## Recommended capture order

1. Finish the seven registered R407 battles with full-battle video through resolution, ≤60 seconds/≤180 MB each, ≤2 GB aggregate. Require the marker to be readable in pixels/OCR and tied to the same case trace; scene-node `markerVisible` alone is not enough. B_R04_B is especially valuable because the old raw trace showed all seven states but failed a composite-texture validator, and an area attack can exercise all four party hit poses.

2. If those captures do not close state gaps, target only the 16 enemy IDs listed in the JSON whose prior actual traces lacked execute and/or recover. At the measured R391 storage rate, a 60-second full-clip hard cap for 16 is 2.88 GB; expected size is about 2.1 GB. Recheck free storage before starting and split the batch if needed. Never force a pose; if the state is not naturally reached, mark it unobserved.

3. Review ambient and combat effects separately across five regions. One actual region clip can cover both categories in that region only if an environment ID and triggered FX ID are visible and temporally joined. A single sample does not clear the three ambient subgroups or all 48/56 FX references.

## Judgment

No concrete enemy art defect is proven by the reviewed temporal evidence. R391’s state gaps and the absent pixel-level joins are verification gaps; B_R01_B has a targeted but unconfirmed readability concern. The next technically useful work is the already-prepared R407 full-battle batch, followed only by targeted missing-state captures. Final art adoption remains separate from technical visual review.
