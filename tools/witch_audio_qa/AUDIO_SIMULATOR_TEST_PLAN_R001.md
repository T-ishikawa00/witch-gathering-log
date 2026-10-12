# Audio Simulator QA Plan R001

Authority: `UNAPPROVED_TEST_OVERLAY`. Run only on an isolated Simulator installation; this plan does not change device audio routing, iOS settings, or production preferences.

## Automated probe

The app's QA-only startup path should call `WitchAudioCoordinator.shared.runQASmokeProbeIfRequested()` after the coordinator is initialized. The invocation is inert unless launch arguments contain both `--qa-isolated` and `--qa-audio-probe`. With `--qa-audio-diagnostics`, it prints JSON lines prefixed `WITCH_AUDIO_QA`.

```sh
tools/witch_audio_qa/run_simulator_probe.sh <booted-simulator-udid> <app-bundle-id> audio-probe-r001
```

The runner launches with `--qa-isolated --qa-save-key=audio-probe-r001`; the audio coordinator uses that stable, sanitized key to select a dedicated `UserDefaults` suite. Neither `UserDefaults.standard` nor the real user's settings are accessed in QA mode. The automated probe checks:

- mute suppresses a playback request without starting a player;
- a non-finite volume input is sanitized to a finite value in `0...1`;
- two same-effect requests 20 ms apart trigger repeat suppression;
- eight distinct effects offered in one burst retain six voices and count two drops;
- a new coordinator using the same defaults suite reads the persisted mute and volume values.

A fresh `--qa-save-key` should be used for each clean probe. For persistence across app relaunches, launch twice with the same explicit key and omit `--qa-audio-probe` on the second launch; startup diagnostics show the loaded values. The smoke probe intentionally writes `muted=false` and `volume=1` in its QA suite, so do not use that run to verify preservation of manually chosen values.

## Lifecycle checks

1. Set mute and volume using the app's audio controls in isolated QA mode. Relaunch with the same `--qa-save-key` and diagnostics enabled. Verify `isMuted` and `volume` match the prior values.
2. Start several short effects, background the app by opening Simulator's app switcher or another app, and inspect diagnostics. Expect `inactiveStops` to increase and `activeVoices` to become zero. Do not change Settings or audio routes.
3. While QA-isolated, call `stopForQATest(reason: "interruption")` through a test-only control if OS interruption delivery is unavailable. Verify `interruptionStops` increases and no stale sound resumes.
4. Optionally inspect silent-mode behavior on a physical iPhone with the Human-operated ringer switch. The Simulator cannot establish hardware silent-switch behavior; `.ambient` is the implementation choice that requests Silent-mode respect.
5. Listen at low and maximum settings on device, headphones and speaker and record clipping, harshness, audibility and fatigue. Automated peak arithmetic is not a substitute for listening.

## Gain and concurrency bound

The offline WAV QA measures every generated waveform peak at or below `0.72` full scale. The player caps each voice at `0.12` and permits at most six simultaneous players. Even if six voices are perfectly phase-aligned, the conservative linear peak sum is `6 × 0.12 × 0.72 = 0.5184`, leaving at least `0.4816` full-scale headroom before device/system processing. This establishes no digital PCM clipping at the app's gain bound; it does not prove speaker output quality or account for downstream OS/audio hardware processing.

## Remaining limits

The QA-only settings override and lifecycle trigger are diagnostic test hooks, not product controls. No real AVAudioSession interruption was injected. Human listening and physical-device interruption/Silent-switch checks remain pending.

## Executed on 9A Simulator (2026-10-10)

Build `WitchGatheringQA_20261010T161529` passed. The opt-in smoke probe passed on `Witch 03to05 R1 QA` (9A): mute suppression, repeat limiting, six-voice cap, two dropped extras and settings reload all matched. Separate QA-only launch overrides `--qa-audio-set-muted=true --qa-audio-set-volume=0.37` were followed by process termination and relaunch with the same `--qa-save-key`; startup diagnostics read back `true` and `0.37`. A background/resume run played one victory effect, opened Settings without changing settings, then foregrounded the game; diagnostics showed one inactive stop with one voice stopped and a second active-resume notification. The shared stop branch for a synthetic interruption also passed in the probe; no real AVAudioSession interruption was injected. Raw evidence and limitations are recorded in `docs/production/current/audio/SIMULATOR_AUDIO_QA_R001.md`.

The QA settings override and lifecycle trigger accept arguments only in `--qa-isolated` mode. They are test hooks, not product controls. Product mute/volume controls were separately exercised by accessibility test `testAudioControlsAndMutePersistence` in the R007 reviewer suite.
