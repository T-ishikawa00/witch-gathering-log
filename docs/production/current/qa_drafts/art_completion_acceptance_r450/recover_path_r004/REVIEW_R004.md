# E_R02_01 recovery-to-idle visual join (R450 R004)

**Result: scoped visual join confirmed for recovery and return to idle.** I inspected the retained R424 video and event-render trace only. The video was not modified and no capture, build, or Simulator action occurred.

The earlier R424 review already retained two screenshots of the same live battle: marker `E145 00451` at 7.87s maps to trace frame 452 (`recover`), and marker `E145 00461` at 8.05s maps to trace frame 462 (`recover`). I inspected two further frames from the same video: marker `E145 00471` at 8.22s maps to trace frame 472 (`idle`); marker `E145 00482` at 8.40s maps to frame 483 (`idle`). The marker is one less than the observer's `sceneFrame` in these rows, consistently with the retained trace. A third frame at marker `E145 00510` maps to frame 511 (`hit`), showing the next actual action after the idle interval.

Across the four recover/idle samples the marsh enemy remains present on the field and unobscured by the party. The trace supplies the intervening 19 recover rows (frames 452–470), then idle rows 471–508. The paired screenshots establish both sides of the transition, not just state-row presence. This closes the previously unjoined idle-return sample for this one natural E_R02_01 attack. It does not establish continuous-motion naturalness across all 30 enemies or formal art adoption.

## Pins and derived frames

- Original video: `enemy_execute_regression_r424/candidate_r002/capture_r001/enemy_event_traces/case01_E_R02_01/battle_execute_window_upto_20_seconds.mp4`, SHA-256 `4cef77fd35f083c30b94ad76c5adab23b8f9e4cf590609660e244630a1466a43` (29,197,309 bytes).
- Trace: same case's `enemy_event_render_r145_ade42a64-6979-4e85-a87c-d110b39e3b03.json`, SHA-256 `b3e8df6345db2691fa86d7b2f72fe955ff9573f351c58350ce6bea54e728d4dd`.
- Existing recovery samples: `recovery_classification_r002/E_R02_01_recover_video_7p87s.jpg` and `...8p05s.jpg`; hashes `86ed048f43b15a4a3ad8fa362d8b1d652d3ad11bd243f7f38ab0504e38c9cef1` and `f8167cc23238a810f2f9e4a6244b21286a7ff0e3fe5d1874cc10941b11feb4ad`.
- New idle/hit inspection frames (3 PNG, total 3,315,889 bytes):
  - `idle_boundary_8p22.png`, marker 00471 → trace frame 472 idle; SHA-256 `597aff551e377d10db36f479b6a54c3c9486c1cc659c8582404413eb5502b0b7`.
  - `idle_loop_8p40.png`, marker 00482 → trace frame 483 idle; SHA-256 `4f56376e2124b417ec35d57707f69cd0f4b16abd23fb3f4352b0813eb670479c`.
  - `late_idle_8p88.png`, marker 00510 → trace frame 511 hit; SHA-256 `bcea1d679c8b8d55a4d9cb21a2319a597109f1ccd7d2bbd7d26c774eba58df32`.

The trace's `videoJoin` field remains `NOT_ESTABLISHED_OCR_REQUIRED`; this review manually read the visible E145 marker in each cited screenshot and matched it to the trace marker row. The trace is a technical rendering observer and the encounter uses the R424 isolated challenge fixture, so this is not ordinary-progression or all-art approval.
