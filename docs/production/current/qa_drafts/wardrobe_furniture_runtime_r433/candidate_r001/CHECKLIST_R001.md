# R433 — bounded wardrobe and furniture UI check

## Scope and fixed baseline

Use the R420 Release app and the R421 fresh ordinary-UI save at revision 13 as read-only baseline. The saved snapshot has four party actors, `ownedCosmeticIDs=[]`, empty selected-cosmetic and selected-weapon-appearance maps, and `ownedFurnitureIDs=[]` / `placedFurnitureIDs=[]`. Save SHA-256: `07252129426c3d68b9617c2569f1a6c79c16f86968ed6a6841a1aa472150cab6`.

R420 was built with `STANDARD_PLAY_R169` and R421 launched its app without QA arguments. This enables the local R128/R130 candidate catalog in standard-play mode. These remain unapproved local candidates, not released or for-sale products. Do not call the six visible rows “four approved wardrobe products”: the four character items are ERNA travel outfit, LUNA mantle, AIRA apron, and NOIR neck ornament; the two ERNA staff rows are separate weapon appearances.

## Minimal no-grant sequence

1. Record the initial save revision/hash and the current app/data identity from the already-running R420 session. Do not relaunch into a different namespace or alter time.
2. From Home, open `仲間` → `試着` (`WardrobeView`). Confirm the actor picker and the expected item rows are present. Record the visible labels and accessibility IDs for each row: `appearance_<id>`, `preview_appearance_<id>`, and `use_appearance_<id>`.
3. Preview, without applying, ERNA’s `ERNA_TRAVEL`, `STAFF_BRANCH`, then `STAFF_MOON`. Capture each same-actor/same-camera preview; confirm switching staff changes only the preview and that “標準の武器外観に戻す” restores the saved appearance. The two staff options are visually distinct assets with separate anchors in `LivingScene`; previewing them does not establish applied-state persistence.
4. Use the actor picker to preview LUNA’s `LUNA_MANTLE_CANDIDATE_R128` and NOIR’s `NOIR_NECKWEAR_MOSS_R001`; capture the portrait and the selected row label. For NOIR, specifically check whether the green ornament is attached at the neck rather than near the forepaw. For LUNA, verify the mantle layer is visible on the torso/shoulder. Do not tap “この見た目を使う.”
5. Preview AIRA’s `AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130` and confirm the apron is visibly on the torso. Do not tap “この見た目を使う.”
6. Close the wardrobe without applying anything, then open Home → `模様替え`. Confirm the preview says the desk is stored and inspect `place_desk` plus the free-claim control. Since the save does not own `FURN_DESK_BOTANICAL`, the place button should be disabled and “無料の研究机を受け取る” visible. Do not claim it or place it. Close the preview and cold-reopen the same app/data only if the owning operator has already authorized that lifecycle; verify baseline save bytes/revision remain exact.

## Stop conditions and what this can establish

Stop if an expected row is absent, a candidate gate is not active, or previewing changes save bytes/revision. Do not use QA flags, direct commands, save edits, grants, clock changes, a replacement save, or purchase flows.

This sequence checks catalog exposure and transient preview rendering only. It cannot establish that an appearance can be applied or persists, that any candidate is available to ordinary players, or that wardrobe art appears in Home/field/battle after selection. It also cannot show the desk placed with LUNA reading: that requires claiming the free starter furniture and then placing it. The R279 placement/cold-reopen proof used another save/build; do not transfer that result to R420. To test those states later, obtain separate authorization for normal UI ownership/apply actions and account for the resulting save mutations.
