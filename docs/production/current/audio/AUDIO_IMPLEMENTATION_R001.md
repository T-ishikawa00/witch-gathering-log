# 『魔女の採集帳』Audio Implementation R001

**Authority:** `UNAPPROVED_TEST_OVERLAY`. The DSP tones, effects balance, volume default, and event assignments are implementation candidates. Human listening and adoption are pending.

## Inventory result

The established project checkout and its in-project ZIP archives were inventoried read-only for WAV, AIFF, CAF, MP3, M4A, OGG, AAC, and FLAC files. The result was **0 direct audio files and 0 audio entries in project ZIPs** before this candidate set. See [AUDIO_ASSET_INVENTORY_R001.md](AUDIO_ASSET_INVENTORY_R001.md) for exact scope and rerun script. This is not a scan of all macOS storage or all Downloads content. No audio asset or playback source existed before this candidate implementation was added. No third-party audio was downloaded or reused. R4 art direction contains per-region *sound ideas* (for example, dry leaves and stream in R01) and explicitly treats those as proposals; the older vertical-slice brief asks for a forest BGM direction plus short gathering/magic/impact effects while allowing full music production later. These texts are not recorded audio or evidence of an approved soundtrack.

## Candidate assets and runtime

`native/WitchApp/WitchAudioCoordinator.swift` contains both the deterministic local PCM synthesizer and the iOS `WitchAudioCoordinator`. The synthesizer emits eight short mono PCM WAV previews in [`native/AudioCandidates/dsp_sfx_r001`](../../../../native/AudioCandidates/dsp_sfx_r001): UI selection, gathering, crafting, equipping, attack, hit, victory, and defeat. Runtime playback generates these WAVs in memory, so the app does not depend on resource-bundle inclusion for audio files.

The coordinator uses `AVAudioPlayer` with the iOS `.ambient` session category, which requests Silent-switch respect. It persists mute and volume preferences in `UserDefaults`, sanitizes non-finite volume to 0.65 and clamps finite values to 0...1, caps active voices at six, rate-limits repeats, and stops sounds on app deactivation or audio-session interruption. In QA mode it isolates preferences to a named `WitchAudioQA-*` suite derived from `--qa-audio-suite=` or `--qa-save-key=`; without either key it uses a random suite. It never resumes stale sounds. There is no BGM or voice content.

The app-level success hook is `playAfterSuccessfulCommand(_:result:)`: call it after `GameEngine.dispatch` returns successfully. It maps region/target selection, gathering, crafting/evolution, and equipping. For `LivingScene` event playback, call `play(.attack)` for outgoing damage events (`direct`, `smith_hammer`, `poison_seed`, `chase`, `counter`, `reflect`), `play(.hit)` for incoming damage (`enemy_hit`, `dot_tick`, `poison_tick`), with victory/defeat played at the end of `LivingScene` battle playback. Do not map `poison_burst` as another hit because it annotates direct damage. Offline gathering should play `.gather` only after `claimOffline` succeeds with a nonempty result.

## Integration and QA boundary

`WitchAudioCoordinator.swift` is included in the generated iOS app source set. The app calls the command-success hook, connects battle attack/hit/result sounds, and exposes mute/volume controls. Startup invokes the QA-only smoke probe, which remains inert unless both `--qa-isolated` and `--qa-audio-probe` are present. Simulator probe, background/resume, and isolated persistence evidence is in [SIMULATOR_AUDIO_QA_R001.md](SIMULATOR_AUDIO_QA_R001.md).

## Automated QA

- Offline Swift DSP runner: `swiftc native/WitchApp/WitchAudioCoordinator.swift tools/witch_audio_qa/AudioDSPQAMain.swift -o /tmp/witch-audio-dsp-qa && /tmp/witch-audio-dsp-qa native/AudioCandidates/dsp_sfx_r001` → `PASS`, eight distinct RIFF/PCM candidates.
- Every preview is mono, 16-bit, 24 kHz, 0.105–0.43 seconds, with measured sample peak 0.365–0.720 (limit 0.72).
- iOS Simulator SDK typecheck succeeded for the coordinator plus all Swift core sources using `swiftc -typecheck -sdk <iphonesimulator SDK> -target arm64-apple-ios17.0-simulator ...`.
- The Simulator audio probe, background/resume stop behavior, and QA-only mute/volume persistence after process relaunch passed on 9A. See [SIMULATOR_AUDIO_QA_R001.md](SIMULATOR_AUDIO_QA_R001.md). These checks do not establish physical Silent-switch behavior, interruption delivery, device output quality, or Human sound-quality acceptance.

- QA diagnostic coverage now includes request/start counts, active voices, mute suppression, rate limiting, max-voice drops, stop reasons, persisted-setting readback, and last error. Six simultaneous sources at the bounded gain sum to at most 0.5184 full-scale under perfectly aligned peaks, based on measured DSP peak <=0.72 and per-voice gain <=0.12.
