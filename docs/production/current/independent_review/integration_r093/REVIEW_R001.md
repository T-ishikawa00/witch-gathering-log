# R093/R094 integration review R001

## Scope and pin check

Read-only review of the frozen compile input `native/build/source_R093_compile_r002` and integration records in `recovery_r022/integration_r093_notice_luna_grounding_r001`. `INTEGRATION_R004.json` lists 140 source inputs. I rehashed all 140 flattened build inputs: 139 match the integration map directly; `PursuitNoticeRenderObserverR092.swift` matches the separately recorded `COMPILE_FIX_R002.json` after-SHA `d0cae7d5…e0b5761` instead of the pre-fix hash. The build receipt reports `SIMULATOR_BUILD_PASS` (140 sources, 1,914 resources, per Root's build readback). No simulator run or native UI acceptance was part of this review.

## Findings

No blocking logic defect found in the reviewed paths.

- Wardrobe preview is local-only: `WardrobePreviewSelectionR094` holds only optional ID/kind and applies them to a copied appearance dictionary. It has no snapshot or dispatch access. The current catalog candidates are all for `C_WITCH`, matching the `C_WITCH`/`WITCH_WEAPON` override keys. The picker derives eligible actors from the catalog; it prefers a still-eligible explicit choice, then the selected actor, then the first eligible actor. Changing actor clears preview.
- Applying/resetting appearance clears the preview only through the success callback; dispatch failure leaves it available. The separate ownership and selection commands are sequential, so ownership may persist if selection later fails. This is disclosed in the code comment as separately durable; the UI labels these appearances as production-validation candidates, not sale items. Do not present the ownership command as a purchase flow.
- R094 furniture staging is keyed to the exact `FURN_DESK_BOTANICAL` ID, avoiding the prior broad “any furniture” condition. LUNA reading and AIRA desk placement use the same exact predicate.
- R092 observer creation requires isolated QA mode, its dedicated argument, and a nonempty save key. Sampling occurs after actions and notice reflow, and records node state rather than claiming pixel visibility. It records cue/removal roots, rejects post-cue scene-generation changes, and only reports the capture window complete after removal plus a later empty sample. The compile correction narrows the observer's scene argument to `LivingScene`, which is required by its geometry readback.
- The R088 LUNA frame is behind both isolated QA flags. It subdivides the existing last execute-frame 100 ms budget into 34 ms + 33 ms midpoint + 33 ms bridge; ordinary playback and R050-only playback keep their old timing. Body, book, and palm-mask updates are applied together on one SpriteKit action sequence. The bridge adds only its own foreground palm/finger shapes and retains the shared cleanup path. This establishes source-level gating/timing, not visual acceptance; the app has not received a native visual run in this review.

## Boundary

The build proves compile/resource integration only. It does not establish wardrobe interaction or the bridge's readability/hand contact in a rendered battle. The candidate appearance “use” button calls `setCosmetic(... owned: true)` before selection when unowned; this is acceptable only while the explicit test-candidate wording and non-sale boundary remain in place.
