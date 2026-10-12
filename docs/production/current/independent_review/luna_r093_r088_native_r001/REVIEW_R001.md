# LUNA R088 native control visual review R001

**Disposition: PARTIAL visual continuity evidence; no formal art adoption or naturalness approval.** This review covers only the three normal-control captures for `EQ_A_01`, `EQ_A_02`, and `EQ_A_03` on the same R093 build. It does not cover fault injection, all cast cycles, all devices, or the complete LUNA motion system.

## Evidence checked

The three captures use `native/build/app_R093_compile_r002/WitchGathering.app`, executable SHA-256 `3190724a9cd50be11468d5241956e5ee4da34de997f5c0d8eb3f62f5cc5866ee`, and the shared R093 build receipt. The receipt records 140 runtime sources and 1,914 resources. Exact build, code, and relevant book/motion-resource pins are in [EVIDENCE_R001.json](EVIDENCE_R001.json); the build receipt SHA-256 is `f91908d541ac816d2ac48bb9b66bbcd371ce61fa9994c24ed0dea1ca2ceb8309`.

For each MP4, I decoded with AVAssetReader and ran Vision OCR on the same decoded pixel buffer used to export each selected JPEG. The selected frame joins use the exact `LUNA NNNN` marker, saved observer `sequence`, and marker-visible row; I did not map FFmpeg indices or resample timing labels. The source videos and observer receipts were read-only. The three decoded videos contain 1,574 / 1,589 / 1,578 frames. The observer traces contain 1,402 / 1,402 / 1,409 rows. OCR finds later visible marker values beyond each saved trace tail, so those additional video values are not treated as joined observer rows.

The evidence includes 12 selected marker frames per gear plus legibility contact sheets and hand/book detail sheets:

- [EQ_A_01 contact](eq_a01_contact.jpg) · [hand/book detail](eq_a01_luna_detail.jpg)
- [EQ_A_02 contact](eq_a02_contact.jpg) · [hand/book detail](eq_a02_luna_detail.jpg)
- [EQ_A_03 contact](eq_a03_contact.jpg) · [hand/book detail](eq_a03_luna_detail.jpg)

All three traces report `CAPTURED`, same-save observer keys, marker visible and sequence-matched on every row, body metadata matching the actual texture, and visible textured book and foreground-hand layers on all rows. Each records the 33 ms R050 midpoint followed by the 33 ms R088 bridge before recover F01; total action timing remains bounded by the existing sequence. Full row counts and hashes are listed in the evidence JSON.

## Per-gear visual findings

| Gear | Observed transition | Finding |
|---|---|---|
| `EQ_A_01` | execute F03 → 33 ms midpoint → 33 ms bridge → recover F01 | The ornate brown book remains visible while LUNA moves from the extended cast gesture toward the closer recover pose. No gross body, foot, or book-layer disappearance is visible in the sampled images. In execute, the open hand sits beside the book more than it closes around it; the book can read as lightly floating. **PARTIAL grip readability.** |
| `EQ_A_02` | same ordered bridge | The teal book is distinguishable and persists through the same transition. Its near-palm relation is similarly loose during execute, and the bright cover competes with the hand in small-screen crops. No sampled hard pop or detached body part. **PARTIAL.** |
| `EQ_A_03` | same ordered bridge | The dark green book stays present through execute, bridge, and recover; its lower contrast makes the grip less legible at full-screen battle scale. The hand remains open and close to, rather than clearly wrapped around, the book. No sampled gross layer loss or body/foot displacement. **PARTIAL.** |

The contact sheets show the hand and book changing pose in a coherent sequence, but the evidence does not establish firm physical contact. The book is a separate rendered layer and the foreground palm is an intentional separate layer, so this is a visual-readability concern rather than proof of a missing hand texture or renderer failure. No book duplication was observed.

## Technical status and limits

`EQ_A_02` and `EQ_A_03` raw RUN files remain `CAPTURED_REQUIRES_VISUAL_REVIEW`; their trace and save readback validations pass, with same-save revision 3 and prior JSON preserved. `EQ_A_01` raw RUN remains `FAIL_PRESERVED` because its host wrapper raised `NameError("name 'validate_payload_r006' is not defined")`. Its saved 1,402-row observer trace is `CAPTURED`; the separate same-save semantic/restart sidecar reports pass for the same save key and revision. This review does not rewrite or upgrade the raw RUN status.

The screenshots support continuity and layer-presence only at the selected poses. They do not prove every decoded frame is natural, exact hand-to-cover contact, or the final appearance on other devices. Motion adoption remains unapproved. A useful next review would compare the hand-cover overlap and grip silhouette in a continuous same-build screen recording at normal playback speed, particularly execute F03 into midpoint/bridge, without changing timing or book art first.
