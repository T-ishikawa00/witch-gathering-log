# Simulator Audio QA R001

Authority: automated technical QA for the unapproved local DSP audio overlay. This is Simulator evidence only; it does not establish Human listening quality, physical iPhone Silent-switch behavior, or release readiness.

## Build and run

- Frozen current-source project: `native/WitchGatheringQA_20261010T161529.xcodeproj`, source manifest `native/qa_source_20261010T161529/SOURCE_SHA256.json`.
- `xcodebuild` Simulator build succeeded for bundle `local.witch.autonomous.r1`; the full build log is in [`xcodebuild_161529.log`](simulator_qa_r001/xcodebuild_161529.log).
- Installed and operated only on `Witch 03to05 R1 QA` Simulator, UDID `9A067715-7CF3-40D3-9064-38423223959B`. A8 StoreKit, 1D art/video, and F843 UI-test Simulators were not touched.
- The app source includes the startup call to `runQASmokeProbeIfRequested()`; the coordinator itself gates the action on `--qa-isolated --qa-audio-probe`.

## Automated probe

`tools/witch_audio_qa/run_simulator_probe.sh 9A067715-7CF3-40D3-9064-38423223959B local.witch.autonomous.r1 audio-probe-r004` returned `PASS`. Unified Logging recorded `qaProbePassed=true`, `settingsReloadMatched=true`, `mutedSuppressed=1`, `rateLimited=1`, `activeVoices=6`, `voiceLimitDropped=2`, and the guarded shared interruption-stop branch cleared all voices. The probe was repeated after the logger was changed from stdout-only to Unified Logging so the runner could capture a machine-readable result. See [`audio_probe_diagnostics.log`](simulator_qa_r001/audio_probe_diagnostics.log).

## Mute and volume persistence across process death

With a fresh QA-only key `audio-persist-r002`, the app launched with `--qa-audio-set-muted=true --qa-audio-set-volume=0.37`, then `simctl terminate` killed the process. A new process launched with the same key and without overrides. Its startup diagnostic read `isMuted=true` and `volume=0.37`, confirming both preferences survive process relaunch in the isolated suite. See [`settings_before_terminate.log`](simulator_qa_r001/settings_before_terminate.log) and [`settings_after_relaunch.log`](simulator_qa_r001/settings_after_relaunch.log). The preferences were kept out of `UserDefaults.standard`.

The app settings screen also exposes the mute toggle and volume slider (`audio_mute`, `audio_volume`). Independent accessibility test `testAudioControlsAndMutePersistence` passed in reviewer batch R007; see [`r007_large_all.xcresult`](../independent_review/accessibility_audit_r001/r007_large_all.xcresult) and [`xcodebuild_r007_large_all.log`](../independent_review/accessibility_audit_r001/xcodebuild_r007_large_all.log). That UI test exercises mute persistence. The CLI-isolated process test above verifies persistence of both mute and volume values.

## Background and resume

A QA-only lifecycle launch played one 0.43-second victory effect. The Simulator opened Apple Settings without changing any setting, returning to the game afterward. For process `93042`, diagnostics recorded `inactiveStops=1`, `lastInactiveStoppedVoices=1`, and `activeVoices=0` when the app resigned active; after return, `activeResumes` advanced from 1 to 2. See [`background_resume_diagnostics.log`](simulator_qa_r001/background_resume_diagnostics.log). The audio was stopped instead of resumed as stale playback.

This validates app deactivation and reactivation on Simulator. The automated probe called the QA-only interruption stop hook and verified it drains the six active voices. The Simulator run did not inject or validate a real AVAudioSession interruption notification; that remains an explicit test boundary.

## Gain bound and remaining review

The DSP QA measured peak <=0.72, each player is capped at gain 0.12, and simultaneous voices are capped at six. The conservative aligned sum is `6 × 0.12 × 0.72 = 0.5184` full scale. This supports no digital PCM clipping within the app gain calculation; it does not characterize simulator speaker output or human perception.

Human listening, physical device playback, hardware Silent switch, real headphone routing, and interruption delivery are not tested. No audio preferences or OS audio settings were changed outside this isolated QA suite.
