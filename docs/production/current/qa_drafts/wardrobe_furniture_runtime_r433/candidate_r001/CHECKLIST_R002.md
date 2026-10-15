# R433 — ordinary wardrobe, staff, and furniture UI check

R002 supersedes the no-mutation execution scope in R001. Root authorized ordinary user-visible selection, free starter-desk claim, placement/store, and reset actions. This is a local development-candidate check; it does not imply formal art/product approval or production availability.

## Baseline

Use the R420 Release app with its existing R421 save at revision 13. Baseline save SHA-256: `07252129426c3d68b9617c2569f1a6c79c16f86968ed6a6841a1aa472150cab6`. It has four party actors and no owned/selected cosmetics or furniture. Keep this same app/data namespace and save. No QA arguments, test fixture, direct engine command, file edit, time change, purchase, or save replacement.

The R420 app was built with `STANDARD_PLAY_R169`; R421 used the ordinary no-argument launch. In that local profile the R128/R130 catalog additions are enabled. The four requested character appearances are ERNA travel outfit, LUNA mantle, AIRA apron, and NOIR neck accessory. `STAFF_BRANCH` and `STAFF_MOON` are two further ERNA weapon appearances. All are unapproved local candidates, not production SKUs.

## One bounded UI sequence

1. Record the baseline app/data identity, save revision/hash, and visible equipped gear. Open Home → `仲間` → `試着`. For each character appearance, preview then tap the row’s `この見た目を使う` button. Keep all four actors selected simultaneously: ERNA / `ERNA_TRAVEL`; LUNA / `LUNA_MANTLE_CANDIDATE_R128`; AIRA / `AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130`; NOIR / `NOIR_NECKWEAR_MOSS_R001`. Verify portrait/actor identity and applied row state. Specifically inspect that the LUNA layer is on the shoulder/torso and the NOIR ornament is at the neck rather than forepaw.
2. On ERNA, preview and apply `STAFF_BRANCH`, then capture home and companion views. Switch to `STAFF_MOON`, confirm the preview silhouette changes, apply it, and capture home and companion again. The currently equipped weapon projection explicitly permits a selected owned weapon appearance to override its mapped staff art; verify that selected ID and visible staff agree. Do not infer a weapon-stat change.
3. From Explore, replay an already-cleared R01 ordinary encounter under the normal UI, first with the four character appearances plus `STAFF_MOON`. Capture the party presentation during battle; confirm the correct actor/item mapping. Return through normal UI, reapply `STAFF_BRANCH`, and replay that same encounter once to capture its battle presentation. These are appearance checks, not combat-balance samples. Stop if ordinary replay is unavailable without an injected encounter.
4. Cold-reopen the same R420 app/data. Read the saved cosmetic ownership and selections through the standard UI/runtime diagnostics already exposed by the app; verify ERNA/LUNA/AIRA/NOIR selections and the chosen staff survive. Compare exact item IDs and confirm gear definitions/stats were not changed by cosmetic selection.
5. Open Home → `模様替え`. Claim the explicitly free starter `FURN_DESK_BOTANICAL` using `無料の研究机を受け取る`, then tap `植物研究の机を置く`. Confirm the room preview shows the desk and LUNA reading; inspect the actual Home scene for the same state. Cold-reopen and confirm placed state persists. Tap `机をしまう`, confirm the room/home preview returns to the stored state, then cold-reopen once more and confirm `owned` remains true while `placed` is false.
6. If reset is included in the same bounded session, use only the visible `標準衣装に戻す` / `標準の武器外観に戻す` buttons and record the resulting selected maps. Do not try to restore the exact revision-13 save: ownership and ordinary battle receipts are expected to remain in the live save.

## UI identifiers and state expectations

- Wardrobe actor picker: `wardrobe_actor_picker`.
- Item cards/actions: `appearance_<appearanceID>`, `preview_appearance_<appearanceID>`, `use_appearance_<appearanceID>`.
- Home shortcut: `home_try_on`; companion portrait route is the `試着` button on the selected companion summary.
- Furniture place/store action: `place_desk`; room state/scene/description: `furniture_room_preview_state_r275`, `furniture_room_preview_scene_r275`, `furniture_room_preview_description_r275`.
- Each appearance apply normally first adds its ID to `ownedCosmeticIDs` through the ordinary UI handler, then dispatches the correct actor-scoped select command. The free desk claim dispatches `setFurniture`; place/store dispatch `placeFurniture`. Expect receipts/revisions and these exact state-field changes. No currency charge is expected.
- Appearance changes must not change `gear`, `equippedGearIDs`, combat stats, research, or currency. Ordinary battles may add receipts and first-clear resources only if any reward remains; record actual deltas rather than assuming zero.
- Furniture placement is independent from appearance selection. The placed desk should affect home presentation and LUNA’s reading pose; storing it should remove both while preserving ownership.

## Acceptance boundary

A pass requires each of the six appearance selections to match the visible actor and item in preview, applied home/companion, and the applicable battle captures; both staff silhouettes must differ and agree with persisted selected IDs. Cold reopen must preserve selections and placed/stored furniture state. Save diffs must be explainable by the listed UI actions only. This does not certify art approval, sale availability, real-device accessibility, or a full campaign/combat balance result. R431’s earlier R130 evidence is useful background but does not substitute for this current R420 visual pass.
