# Enemy motion: minimum remaining acceptance

## Finding

No new common renderer failure was established in this bounded review. All 30 enemy IDs have a runtime mapping for idle, walk, anticipate, execute, recover, hit, and resolve; the R366 ledger correctly leaves every unit below accepted-complete animation status. Existing state maps and forced-state renders are useful asset/render references, but they do not prove an ordinary encounter naturally traverses those states.

I visually sampled the six preserved R145 battle videos at three points each (minions at PTS 2/6/10 s; bosses at 3/12/21 s). The party and target remain in the field; these samples show no gross cropping, overlap, or disappearance. They are sparse, and no sampled PTS is asserted to match a particular event. The three derived contact sheets are in `derived_r001/` (879,040 bytes total). R145 receipts separately contain per-event and per-frame scene observations for six R01 enemies, but every receipt says `videoJoin: NOT_ESTABLISHED_OCR_REQUIRED`; the video is not yet a pixel-level visual join to those scene frames.

The R366/R368 correction matters: the ten later evidence rows are eight battle-result stills, one ordinary E_R05_01 video, and one B_R05_B challenge replay. They are not ten ordinary videos. The E_R05_01 clip has an approximate HUD-to-event alignment for three telegraph/hit cycles and a bounded resolve observation. The eight stills corroborate event/cue-root occurrence and terminal presentation only. The challenge replay is separate from an ordinary campaign battle.

## Per-state acceptance still needed

| State/transition | Existing evidence | Minimum acceptance for each unit |
|---|---|---|
| Idle | Mapped for 30; R083 sampled poses; actual R145 idle snapshots for six R01 actors | In an ordinary fight, actor stays visible between events, keeps a stable ground/flight anchor, and does not jump, clip, or change frame unexpectedly. |
| Walk/arrival | Mapped for 30; R145 `battle_arrival` requests for six actors; R083 poses | Record the natural arrival/approach window continuously enough to see the locomotion loop and its exit to idle. For stationary arena staging, verify the authored walk motion itself rather than demanding position travel. |
| Anticipate → execute | R145 ties scene-frame transition requests to event sequence for six actors; R337 shows three approximate ordinary E_R05_01 cycles; eight other stills have matching event/cue roots | Same actor and combat root must connect the actual telegraph to visible anticipate, then execute. Check a readable cue/pose distinction before impact, at phone scale. |
| Hit | R145 has incoming-damage transitions for six actors; R337 has three approximate hit windows; eight other stills/logs show event/cue evidence | Count only nonlethal damage to that actor. Confirm a visible hit reaction after that event, without body disappearance or a pose being overwritten by duplicate requests. |
| Recover | R083 forced samples only; R145 actually observed recover for E_R01_01 and E_R01_04, but it was unobserved for E_R01_02, E_R01_03, B_R01_A, and B_R01_B because those fights reached resolve first | Let a target survive long enough after its attack/hit. Verify recover completes and returns to idle; if the ordinary encounter kills it first, record `UNOBSERVED`, not a defect. |
| Resolve | R145 records lethal resolve for six actors; R337 approximates the result/fade; eight stills show terminal resolve snapshots | A lethal event must start the correct resolve presentation, keep the actor visible through the configured duration, then clear it cleanly at result. Check the actual interval, not just terminal alpha/state metadata. |

R083 coverage is broad but bounded: 30/30 old QA-isolated actor clips requested seven states and were visually sampled in the R366 review set (the initial three plus nine plus eighteen). The dense 18-actor review reports no gross clipping/overlap, while noting smaller silhouettes for E_R03_01 and E_R05_01..04, and a static-sample hit-contrast concern for B_R01_B. That B_R01_B concern is specific enough to prioritize, but is not yet a confirmed live defect because those frames came from requested-state capture rather than a synchronized natural hit.

## Safest next validation batch

Reuse the already-built event/render recorder and normal-development battle timing trace; do not regenerate art or force states. First close the B_R01_B hit-contrast concern and the four R145 recover gaps using existing R145 video/trace offline where a defensible visual join can be made. If video-to-scene timing cannot be joined from the preserved run, record that limitation and do one ordinary, naturally reached encounter capture for the affected actor(s), with no seed/clock/gear injection.

For any new capture, bind one run ID, process ID, save key, encounter ID, app/resource hashes, and scene generation. The event record must include actor, event sequence/root action, scene frame/time, and requested/observed state; the screen recording must share a monotonic/wall-clock anchor. Preserve a 1-fps battle overview and extract 10-fps windows from roughly one second before telegraph through hit/recovery (and lethal resolve). Keep untriggered states `UNOBSERVED`; do not infer them from source maps, queued callbacks, or end-state snapshots. Reuse a single real encounter wherever multiple target actors naturally appear. No change to timing, combat values, approved art, or save state is required for this validation.

After the focused R01 gaps, extend the same exact event/render join only to units without any ordinary battle clip, batching by their real encounter routes. R366 names 20 rows without a newer ordinary screenshot/video/replay; six of these have separate R145 QA-isolated event/render traces, leaving 14 that have only the R083 state-audit evidence. Do not label the remaining 14 complete from the mapped states. Formal artwork adoption remains a separate Human decision; technical natural-motion review is still actionable locally.

## Pins and scope

- R366 per-unit ledger SHA-256: `0b7963a968411f8ff618f2f39beea7abc6ddcbc6704d6cdd42b914bc5bdd8306`.
- R083 30-actor run SHA-256: `f9c922bc2a98361369dfb30f33703471df121a5aa0e48a71522072170afbd06e`; it explicitly describes old QA-isolated requested-state captures.
- R145 six-encounter run SHA-256: `bbff4bc5d167f1209579978cfeae1634dbf4e5ba16a9f637aa42690ef0ba6770`; 5,024 frame rows and 254 event rows across six encounters; raw capture still requires offline/visual review.
- R368 ordinary event/render review SHA-256: `d64234d250640076933cc901fa693b895191082fc0f4ebe0c6ec6dc0ff5af4ce`.
- Current source hashes: `EnemyMotion.swift` `d2491abb24d0fdefee34c8c375266787ec83de34c43603be9535e9eed12baa48`; `LivingScene.swift` `3520f93057a3434be001e3b343e8aa895c399a9b1522e379689b6ec4a37cfd86`; `BattlePlayback.swift` `112dcff156070e83e15d346d2f48e5b13ea89e94d9ecf01e48121fff9ccbbf45`; `BattleTimingTraceR319.swift` `a8e8cc1b18613ca4c5bfec40544d535b6d4f6a8835f621db0595bf2bc09e1774`.

No source, save, or simulator was changed. The R145 stills/contact sheets in `derived_r001/` are review-only reductions, not new runtime captures or approval evidence.
