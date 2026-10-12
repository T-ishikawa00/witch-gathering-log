# R092 native pursuit-notice visual review

**Result: partial visual acceptance.** The notice is readable and appears to clear after the hit in both captures. Its spatial association to the named recipient remains ambiguous, so the evidence does not support an overall visual PASS or formal adoption.

The R002 image joins are suitable for frame-level review: they export the exact AVAssetReader pixel buffer used for the OCR marker and report 45/45 joined rows on 9A and 46/46 on F843, with no missing sequences or marker regressions. R001 JPEG exports are explicitly invalidated for exact joins because the ffmpeg frame-index transfer was offset; this review does not use them.

The selected active frames show a dark, gold-edged chip reading “追撃 / アイラ.” It is legible at the displayed size. AIRA is the red-haired hammer wielder (`C_SMITH` → `アイラ` in `App.swift`) and the combat trace identifies `targetID=AIRA`. However, the chip is low beside the pink-haired foreground character and NOIR, while the gold target ring is around AIRA higher in the formation. The trace corroborates this ambiguity: `actualLayoutSafe=false`, `requiredLeaderPresent=false`, and `actualCollisionIDs` includes party nodes. Keep the result **readable but spatially ambiguous**; a clearer leader/connector or a safe position adjacent to AIRA is a bounded follow-up.

In the first selected post-removal source frames (9A frame 604; F843 frame 573), the notice is absent. Later selected frames also remain clear. This is visual confirmation at sampled frames, not a claim about every intermediate frame. The trace itself still reports `visualPixelsEvaluated=false` and `PENDING_ORIGINAL_PTS_VIDEO_REVIEW`.

Both raw capture receipts report the R04 challenge won, same-save restart bytes, exact prior JSON restoration, and stopped owned process. These were QA-argument challenge launches, not UI-click evidence. The cyan “詠唱遅延” label and `R92` marker are QA overlays and do not count as normal player-facing UI. No source, build, simulator, or raw capture files were modified.

## Evidence

- 9A: [RUN](../../recovery_r022/integration_r093_notice_luna_grounding_r001/notice_capture_r001/R04_9A_r001/RUN.json), [trace](../../recovery_r022/integration_r093_notice_luna_grounding_r001/notice_capture_r001/R04_9A_r001/NOTICE_TRACE.json), [same-buffer join](../../recovery_r022/integration_r093_notice_luna_grounding_r001/notice_capture_r001/R04_9A_r001/root_marker_review_r002/JOIN_R002.json). Video SHA-256: `c61b79761d155b2e742cc33a19a98d63c390e667e7db398ec34427aef6be03e9`.
- F843: [RUN](../../recovery_r022/integration_r093_notice_luna_grounding_r001/notice_capture_r001/R04_F843_r001/RUN.json), [trace](../../recovery_r022/integration_r093_notice_luna_grounding_r001/notice_capture_r001/R04_F843_r001/NOTICE_TRACE.json), [same-buffer join](../../recovery_r022/integration_r093_notice_luna_grounding_r001/notice_capture_r001/R04_F843_r001/root_marker_review_r002/JOIN_R002.json). Video SHA-256: `4e75b8c2662395cdacb292bd8948a43fda55f09268bc7a1b08e7fa8e7b9ce2d1`.
- Shared build receipt: [BUILD_RECEIPT_R002.json](../../recovery_r022/integration_r093_notice_luna_grounding_r001/BUILD_RECEIPT_R002.json), SHA-256 `f91908d541ac816d2ac48bb9b66bbcd371ce61fa9994c24ed0dea1ca2ceb8309`.
- Exact visual samples: `post_event_frames_r001/R04_9A_r001/frame_604.jpg` and `post_event_frames_r001/R04_F843_r001/frame_573.jpg`; full frame hashes and all selected active samples are recorded in [REVIEW.json](REVIEW.json).
