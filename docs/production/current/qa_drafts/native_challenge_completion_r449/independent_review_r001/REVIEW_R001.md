# R449 independent semantic review

- **Result:** the saved semantic evidence is internally consistent for this bounded run; it is not release acceptance.
- **Save and cold reopen:** revision 117 → 137; the final pre-cold and post-cold save bytes both hash to `27e965d92ab0d943541a075a599055d37ffd8e4bff501862b00f127846ca3a44`.
- **Challenge outcomes:** all 15 target checkpoints report WIN. For each, the target ID matches `lastEncounterID`; `lastCombatResult.won` is true; save, challenge-sidecar, and challenge-art revisions agree; and the clear marker is present. Fifteen new challenge receipts cover the same target set. Seven clear markers were already present; eight were added.
- **Equipment and history:** gear 40 → 41 and natural acquisition records 30 → 31. The same 19 equipped UUIDs remained equipped and all remained owned. None of the five known historical mock-draw UUIDs was equipped. Gacha pity, mock purchase records, and summon receipts were unchanged; there was no new summon transaction.
- **Observed progression:** each party member gained 405 XP; refine dust rose by 1,644; materials changed by R04G1 +1 and R05G1 +3. These are saved-game changes, not invariant fields.
- **Protection:** closure reports 18 prior protected trees and 1,925 app files, R445 app unchanged, no unexpected support changes/missing/new files, distinct-process cold reopen, and no surviving app PID.
- **Boundary:** the profile already had seven challenge clears and five mock draws. This does not prove a fresh-profile first-clear path, formal design acceptance, or art quality; screenshots were not independently assessed.

See [REVIEW_R001.json](REVIEW_R001.json) for fixed hashes and the per-challenge table.
