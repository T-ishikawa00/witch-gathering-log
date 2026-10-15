# R374 qualitative matrix review

**Disposition:** the closed matrix is internally complete for its declared isolated Core comparison. It is not product adoption, live purchase testing, or evidence of ordinary-player retention.

## Run integrity and scope

`RUN.json` is `COMPLETE_REVIEW_REQUIRED`; all 16 of 16 matrix rows report `PASS`, with one compile invocation, no runner errors, no owned XCTest survivors, and the owned process group absent. The latest case completed at 2902.2 seconds from run origin, within the 6,000-second cap. Each row filtered the same XCTest method once; this is not 16 distinct XCTest methods. The binary is pinned at `d5c3452516da1cebea6ffc0fae1c6fd79b7ed0b6abcf0883ce5849d983fac422`. Every report records equal source digests at start/end, and every daily save hash matches its read-only reopen hash.

All cases use seed 100049, runtime profile `app-candidate-r098-v1-growth-500bp-enhancement-r230-v1-r350-r352-r353-test-v1`, and the R230/R144/R350/R352/R353 candidate configuration. The 30/90 “days” are 24-hour virtual intervals. The policy and product scenarios are explicitly unapproved. Ticket inputs are local synthetic grants with `NO_TRANSACTION_CREATED`; `storeKitInvoked=false` and `networkInvoked=false`. Ad callback/skip commands are local QA routes, not provider views. Cosmetics produce metadata only, with no R098 appearance mapping or game entitlement.

## Outcomes that matter

Every arm reaches the same scripted result: 30 campaign clears, 15 challenge clears, and all five research IDs; first challenge clears are distributed across simulated days 11–15. This demonstrates that this specific action script can traverse those paths under the selected runtime. The script advances a virtual day per iteration and selects frontier, research, recipe, and gear actions, so equal clear timing cannot establish natural-player pacing or purchase acceleration.

The clearest workload difference is in the one-time TICKET200 scenario. It logs 200 synthetic paid-mock draws and peaks at 258 inspection-eligible items and 210 pending gear trials, versus 58 eligible and 10 pending in the free arm. The 12-item daily trial cap reduces that recorded pending queue to five by day 90. This is a concrete inventory-review workload signal under the candidate treatment and planner, not a forecast of player behavior or evidence for an official offer.

At 90 days, the free arm has one unique craft and three unique evolution recipes; TICKET200 has one unique craft and zero evolution recipes at both horizons, while campaign/research results match. Treat this as a descriptive result for one seed and one fixed agent policy. It does not isolate product causality, and it does not show that more tickets necessarily produce more usable progression.

Rewarded-ad and skip arms record 90 callbacks by day 30 and 270 by day 90. The skip arm records the stored local reward without an ad-provider view. The cosmetics-only case creates an external metadata record but no game entitlement or appearance mapping. Neither establishes user value.

Each case previews two loadouts on only `CH_R01_03`, `CH_R03_02`, and `CH_R05_03` (six rows). Those results are not 15 unique mechanic checks, and the selected loadout pair does not isolate a single gear variable. All listed previews win; this is not a causal build-value result.

## Limits

- The runner remains `COMPLETE_REVIEW_REQUIRED`; this review does not promote its status.
- Eight scenario mappings and price labels remain hypothetical and unapproved. No StoreKit, real payment, external network, or real ad provider was used.
- The final natural-gear ledger retains at most 96 acquisition rows by policy; daily snapshots/action records are needed for a longer item-level provenance trace.
- The matrix does not establish launch balance, cosmetic value, purchase causality, all 15 challenge mechanics, or representative human play.

## Evidence pins

- Run JSON SHA-256: `860273ae6557762adb657dd4a4eee9966fb51f124dd2bbf7c36e2800624aad07`
- Runner SHA-256: `0046c6147a65703a5c86423028eff74df0f86d261bc4d0eed626a92925021374`
- Input manifest SHA-256: `da774ac0d079240ed5a96f3ea617da87d43463a4999974d849dc4feb3cf9eb61`
- Executable SHA-256: `d5c3452516da1cebea6ffc0fae1c6fd79b7ed0b6abcf0883ce5849d983fac422`
- Runtime fingerprint: `2ba901274a3b0f90a536b6cf57bd90a9025fc4d0b19ce1dd07b4841d11a8aeec`
