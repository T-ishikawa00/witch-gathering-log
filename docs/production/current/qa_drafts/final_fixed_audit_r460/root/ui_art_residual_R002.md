# R013 UI/art residual check — R462 follow-up

Scope: read-only check of R013 UI-01/ART-01/ART-02 against the fixed-R460 review, R457 recovery reconciliation, and the later R462 inventory-clear runtime evidence. No source, build, save, Simulator, or media changes were made in this review.

## Finding: one current, locally fixable UI defect

R013 says the empty-inventory guidance and clear action were added and asks for a normal-runtime check. R462 (`799b47c3-09fb-4461-a16b-2f754a5278be`) verifies that most of this flow works: the empty state reports 43 owned / 0 shown and offers a clear action; afterward it shows 43 / 43 with quality reset to 「すべて」. But the Japanese IME text remains visible in the search field after clear. The same text appears before and after clearing. This is a concrete screen-state inconsistency, not a save failure.

Evidence: R462 `RUN.json` SHA-256 `70f6aad69924dee2b1bab2d5e9f469ba35671b6b6e25328767b81ceec701e71a`; empty screen SHA `e0eab325423a38fa5378732851cffca31c335a3bd7d8b1fa43aac69b12f1ac99`; cleared screen SHA `c3a00aa8687eb31d264a73e92b43a5aa1ce9b59996cf0b4d7c711afdf29017d3`. Independent screen/save review: `inventory_empty_guidance_r464/independent_runtime_review_r001/REVIEW_R001.md`, SHA-256 `48edc4645a05879e1d35cacd4f53b2e3e83834f5581ef293995d4101e44df61c`.

The run records revision 138 and the same `save.json` (`3725e9c13d0e514804d5941d23b7847e12d7c13eb04aac0b3e676b190ae3a3c1`) and `save.json.previous` (`27e965d92ab0d943541a075a599055d37ffd8e4bff501862b00f127846ca3a44`) at all five checkpoints; cold save bytes were exact. The cold screenshot is home, so it does not establish the inventory field’s post-relaunch behavior.

Recommended bounded acceptance after the planned focus/input-generation fix: enter Japanese text with an active or recently committed IME composition; clear; verify the field is visibly empty, the full 43-item list is restored, and new typing works; verify no save revision or gameplay data changed. This is a real local UI follow-up, not a reason to reopen unrelated screens or assets.

## Enemy recovery and naturalness: unresolved evidence, no demonstrated renderer fault

R013 records 17 direct-attack enemy recover routes as unobserved. R457 `RECOVERY_ELIGIBILITY_R002.json` says the retained videos contain zero eligible-but-uninspected recovery intervals: 16 attacks proceed to hit or terminal resolve before a recovery route can be observed; B_R01_A does not render execute; E_R02_04 is a support-role exception. E_R02_01 is the one visually joined recover-to-idle example. The recorded priority/preemption is consistent with the current event flow; an unobserved recovery is not evidence that the animation is missing or broken.

Therefore, these 17 rows are not a concrete local code/art defect and do not justify changing combat priority or staging another forced-state run. They remain unobserved for per-enemy natural-recovery visual acceptance; no existing retained interval can add that evidence. If a naturally eligible uninterrupted recovery is captured later, review it. Do not call all 30 fully accepted, but also do not turn this evidence gap into 17 failures.

## 159 assets and party art

R457 and R460 provide no reproduced high-impact art/rendering defect or identified missing required asset. The 159-row status `PARTIAL_OR_NOT_ACCEPTED` is a conservative per-row acceptance label, not evidence that 159 items are defective or absent. Existing bounded reviews can support scoped technical findings, while individual completion-quality and formal art adoption remain separate. R013 ART-01/ART-02 should retain those boundaries; this review does not upgrade the ledger or require a broad redraw/replay.

## Pins and limits

- R013: `final_acceptance_r360/COMPLETION_REGISTER_R013.json`, SHA-256 `d4f6ed08b34290dad746a0880af653cd42ad173246a2ba21bb4f7f2e11f814f7`.
- R457 eligibility: `completion_priority_r457/RECOVERY_ELIGIBILITY_R002.json`, SHA-256 `fd095cf16dbf160c26fda63444cbd49b37004d35cb410bad0387ef39f1abaab1`.
- R460 fixed-SHA UI/art review: `final_fixed_audit_r460/ui_art/REVIEW_R001.md`, SHA-256 `5d3fcfa5542dddbdcd3d134014c83a0b6708da91dff405e5160f1f873707a75d`.

Conclusion is limited to these records and screenshots. It separates the newly reproduced inventory-field bug from the 17 encounter-limited recovery observations and from Human art adoption.
