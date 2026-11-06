import Foundation
#if canImport(UIKit) && canImport(AVFoundation)
import AVFoundation
import Combine
import os
import UIKit
#endif

/// Short, locally synthesized candidate effects. No external recordings or network assets.
enum WitchSoundEffect: String, CaseIterable, Sendable {
    case uiSelect, gather, craft, equip, attack, hit, victory, defeat
}

struct WitchAudioDiagnostics: Codable, Sendable, Equatable {
    var playRequests = 0
    var playStarted = 0
    var mutedSuppressed = 0
    var rateLimited = 0
    var voiceLimitDropped = 0
    var stoppedVoices = 0
    var inactiveStops = 0
    var interruptionStops = 0
    var activeVoices = 0
    var isMuted = false
    var volume: Float = 0.65
    var settingsReloadMatched: Bool?
    var qaProbePassed: Bool?
    var activeResumes = 0
    var lastInactiveStoppedVoices: Int?
    var lastError: String?
}

/// Deterministic mono PCM generator shared by the app player and the offline QA exporter.
enum WitchAudioDSP {
    private struct Partial {
        let startHz: Double
        let endHz: Double
        let gain: Double
        let noise: Bool
    }

    private struct Program {
        let duration: Double
        let partials: [Partial]
        let decay: Double
    }

    private static let programs: [WitchSoundEffect: Program] = [
        .uiSelect: Program(duration: 0.105, partials: [Partial(startHz: 880, endHz: 740, gain: 0.55, noise: false)], decay: 4.5),
        .gather: Program(duration: 0.19, partials: [Partial(startHz: 740, endHz: 980, gain: 0.32, noise: false), Partial(startHz: 0, endHz: 0, gain: 0.12, noise: true)], decay: 3.5),
        .craft: Program(duration: 0.34, partials: [Partial(startHz: 523.25, endHz: 523.25, gain: 0.28, noise: false), Partial(startHz: 659.25, endHz: 659.25, gain: 0.24, noise: false), Partial(startHz: 783.99, endHz: 783.99, gain: 0.20, noise: false)], decay: 2.6),
        .equip: Program(duration: 0.22, partials: [Partial(startHz: 659.25, endHz: 880, gain: 0.32, noise: false), Partial(startHz: 1318.5, endHz: 1174.7, gain: 0.13, noise: false)], decay: 4.2),
        .attack: Program(duration: 0.17, partials: [Partial(startHz: 260, endHz: 105, gain: 0.30, noise: false), Partial(startHz: 0, endHz: 0, gain: 0.22, noise: true)], decay: 5.5),
        .hit: Program(duration: 0.115, partials: [Partial(startHz: 125, endHz: 54, gain: 0.38, noise: false), Partial(startHz: 0, endHz: 0, gain: 0.22, noise: true)], decay: 6.0),
        .victory: Program(duration: 0.43, partials: [Partial(startHz: 523.25, endHz: 523.25, gain: 0.24, noise: false), Partial(startHz: 659.25, endHz: 659.25, gain: 0.24, noise: false), Partial(startHz: 783.99, endHz: 783.99, gain: 0.22, noise: false), Partial(startHz: 1046.5, endHz: 1046.5, gain: 0.18, noise: false)], decay: 2.2),
        .defeat: Program(duration: 0.42, partials: [Partial(startHz: 392, endHz: 293.66, gain: 0.28, noise: false), Partial(startHz: 293.66, endHz: 220, gain: 0.22, noise: false), Partial(startHz: 196, endHz: 146.83, gain: 0.15, noise: false)], decay: 2.8)
    ]

    static let sampleRate = 24_000
    static let peakLimit = 0.72

    static func renderWAV(_ effect: WitchSoundEffect) -> Data {
        let program = programs[effect]!
        let count = Int((program.duration * Double(sampleRate)).rounded(.up))
        var samples = [Int16](repeating: 0, count: count)
        var random: UInt32 = 0x6D2B79F5
        for i in 0..<count {
            let t = Double(i) / Double(count)
            let seconds = Double(i) / Double(sampleRate)
            let attack = min(1, t * 35)
            let release = min(1, (1 - t) * 8)
            let envelope = attack * release * exp(-program.decay * t)
            var value = 0.0
            for partial in program.partials {
                if partial.noise {
                    random = random &* 1_664_525 &+ 1_013_904_223
                    let white = Double(Int32(bitPattern: random)) / Double(Int32.max)
                    value += white * partial.gain
                } else {
                    let phase = 2 * Double.pi * (partial.startHz * seconds + (partial.endHz - partial.startHz) * seconds * seconds / (2 * program.duration))
                    value += sin(phase) * partial.gain
                }
            }
            let normalized = max(-peakLimit, min(peakLimit, value * envelope))
            samples[i] = Int16((normalized * Double(Int16.max)).rounded())
        }

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8)); data.appendLE(UInt32(36 + samples.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); data.appendLE(UInt32(16))
        data.appendLE(UInt16(1)); data.appendLE(UInt16(1)); data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * 2)); data.appendLE(UInt16(2)); data.appendLE(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); data.appendLE(UInt32(samples.count * 2))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    static func measuredPeak(_ wav: Data) -> Double {
        guard wav.count > 44 else { return 0 }
        var peak: Int32 = 0
        for offset in stride(from: 44, to: wav.count - 1, by: 2) {
            let raw = UInt16(wav[offset]) | (UInt16(wav[offset + 1]) << 8)
            let sample = Int32(Int16(bitPattern: raw))
            peak = max(peak, abs(sample))
        }
        return Double(peak) / Double(Int16.max)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

/// App-facing short-effect player. Ambient session respects iPhone Silent mode;
/// interruptions and app deactivation stop voices instead of resuming stale effects.
#if canImport(UIKit) && canImport(AVFoundation)
@MainActor
final class WitchAudioCoordinator: ObservableObject {
    static let shared = WitchAudioCoordinator()
    private static let qaLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.witch.autonomous.r1", category: "AudioQA")

    @Published private(set) var isMuted: Bool
    @Published private(set) var volume: Float
    @Published private(set) var diagnostics = WitchAudioDiagnostics()

    private let defaults: UserDefaults
    private let maxVoices = 6
    private let rateLimit: TimeInterval = 0.065
    private let perVoiceMaximumGain: Float = 0.12
    private var players: [AVAudioPlayer] = []
    private var lastPlayedAt: [WitchSoundEffect: TimeInterval] = [:]
    private let wavs: [WitchSoundEffect: Data]
    private var observers: [NSObjectProtocol] = []

    init(defaults suppliedDefaults: UserDefaults? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        let isQA = arguments.contains("--qa-isolated")
        let suiteArgument = arguments.first(where: { $0.hasPrefix("--qa-audio-suite=") }).map { String($0.dropFirst("--qa-audio-suite=".count)) }
        let saveKeyArgument = arguments.first(where: { $0.hasPrefix("--qa-save-key=") }).map { String($0.dropFirst("--qa-save-key=".count)) }
        let rawSuiteToken = suiteArgument ?? saveKeyArgument
        let suiteToken = rawSuiteToken.map { String($0.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(64)) }
        let qaSuiteName = "WitchAudioQA-" + ((suiteToken?.isEmpty == false) ? suiteToken! : UUID().uuidString)
        let defaults = suppliedDefaults ?? (isQA ? UserDefaults(suiteName: qaSuiteName)! : .standard)
        self.defaults = defaults
        self.isMuted = defaults.object(forKey: "witch.audio.muted") as? Bool ?? false
        let savedVolume = (defaults.object(forKey: "witch.audio.volume") as? NSNumber)?.floatValue ?? 0.65
        self.volume = Self.sanitizeVolume(savedVolume)
        self.wavs = Dictionary(uniqueKeysWithValues: WitchSoundEffect.allCases.map { ($0, WitchAudioDSP.renderWAV($0)) })
        self.diagnostics.isMuted = self.isMuted
        self.diagnostics.volume = self.volume
        configureAmbientSession()
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopAll(reason: "inactive") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.diagnostics.activeResumes += 1
                self.logDiagnosticsIfEnabled()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            guard let kind = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: kind) == .began else { return }
            Task { @MainActor in self?.stopAll(reason: "interruption") }
        })
        applyQASettingsOverridesIfRequested()
        logDiagnosticsIfEnabled()
        startQALifecycleProbeIfRequested()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        defaults.set(muted, forKey: "witch.audio.muted")
        diagnostics.isMuted = muted
        if muted { stopAll(reason: "muted") }
        logDiagnosticsIfEnabled()
    }

    func setVolume(_ newValue: Float) {
        volume = Self.sanitizeVolume(newValue)
        defaults.set(volume, forKey: "witch.audio.volume")
        for player in players { player.volume = outputVolume }
        diagnostics.volume = volume
        logDiagnosticsIfEnabled()
    }

    func play(_ effect: WitchSoundEffect, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        diagnostics.playRequests += 1
        guard !isMuted, volume > 0 else { diagnostics.mutedSuppressed += 1; logDiagnosticsIfEnabled(); return }
        guard time.isFinite else { diagnostics.lastError = "ignored nonfinite playback timestamp"; logDiagnosticsIfEnabled(); return }
        players.removeAll { !$0.isPlaying }
        diagnostics.activeVoices = players.count
        if let previous = lastPlayedAt[effect], time - previous >= 0, time - previous < rateLimit {
            diagnostics.rateLimited += 1; logDiagnosticsIfEnabled(); return
        }
        guard players.count < maxVoices else { diagnostics.voiceLimitDropped += 1; logDiagnosticsIfEnabled(); return }
        guard let wav = wavs[effect] else { diagnostics.lastError = "missing synthesized WAV: \(effect.rawValue)"; logDiagnosticsIfEnabled(); return }
        guard let player = try? AVAudioPlayer(data: wav) else { diagnostics.lastError = "AVAudioPlayer rejected synthesized WAV: \(effect.rawValue)"; logDiagnosticsIfEnabled(); return }
        lastPlayedAt[effect] = time
        player.volume = outputVolume
        player.prepareToPlay()
        if player.play() {
            players.append(player); diagnostics.playStarted += 1; diagnostics.activeVoices = players.count
        } else { diagnostics.lastError = "AVAudioPlayer.play returned false: \(effect.rawValue)" }
        logDiagnosticsIfEnabled()
    }

    /// Optional GameModel hook: call only after a command receipt succeeds.
    func playAfterSuccessfulCommand(_ command: GameCommand, result: String) {
        switch command {
        case .startExpedition, .startExpeditionAt, .setGatherTarget, .setGatherTargetAt:
            play(.uiSelect)
        case .gather:
            play(.gather)
        case .craftRecipe, .evolveGear:
            play(.craft)
        case .equip:
            play(.equip)
        default:
            break
        }
    }

    func stopAll(reason: String = "manual") {
        let stoppedNow = players.count
        diagnostics.stoppedVoices += stoppedNow
        players.forEach { $0.stop() }
        players.removeAll(keepingCapacity: true)
        lastPlayedAt.removeAll(keepingCapacity: true)
        diagnostics.activeVoices = 0
        if reason == "inactive" {
            diagnostics.inactiveStops += 1
            diagnostics.lastInactiveStoppedVoices = stoppedNow
        }
        if reason == "interruption" { diagnostics.interruptionStops += 1 }
        logDiagnosticsIfEnabled()
    }

    /// Six aligned voices at this ceiling and the synth's 0.72 peak sum to at most 0.5184.
    private var outputVolume: Float { min(perVoiceMaximumGain, volume * perVoiceMaximumGain) }

    static func sanitizeVolume(_ value: Float) -> Float {
        guard value.isFinite else { return 0.65 }
        return min(1, max(0, value))
    }

    /// Tests can drive the real stop branch without synthesizing OS events. Production
    /// app code must rely on UIApplication/AVAudioSession notifications instead.
    func stopForQATest(reason: String) {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"),
              ["inactive", "interruption"].contains(reason) else { return }
        stopAll(reason: reason)
    }

    private func applyQASettingsOverridesIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated") else { return }
        if let value = arguments.first(where: { $0.hasPrefix("--qa-audio-set-muted=") })?.split(separator: "=", maxSplits: 1).last,
           value == "true" || value == "false" {
            setMuted(value == "true")
        }
        if let raw = arguments.first(where: { $0.hasPrefix("--qa-audio-set-volume=") })?.split(separator: "=", maxSplits: 1).last,
           let value = Float(raw), value.isFinite {
            setVolume(value)
        }
    }

    /// Starts one short voice so a Simulator operator can background/resume the app
    /// and inspect the real UIApplication lifecycle notifications.
    private func startQALifecycleProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"),
              ProcessInfo.processInfo.arguments.contains("--qa-audio-lifecycle") else { return }
        Task { @MainActor in
            self.play(.victory)
            try? await Task.sleep(for: .seconds(5))
            self.logDiagnosticsIfEnabled()
        }
    }

    /// Opt-in simulator probe. It plays only when launched with --qa-isolated
    /// --qa-audio-probe; UserDefaults is redirected to the QA suite in that mode.
    func runQASmokeProbeIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated"), arguments.contains("--qa-audio-probe") else { return }
        diagnostics.lastError = nil
        let startedBeforeProbe = diagnostics.playStarted
        let mutedBeforeProbe = diagnostics.mutedSuppressed
        let rateLimitedBeforeProbe = diagnostics.rateLimited
        let dropsBeforeProbe = diagnostics.voiceLimitDropped
        setMuted(true)
        play(.uiSelect, at: 100)
        let muteWorked = diagnostics.mutedSuppressed == mutedBeforeProbe + 1 && diagnostics.playStarted == startedBeforeProbe
        setMuted(false)
        setVolume(.nan)
        let nanSanitized = volume.isFinite && volume >= 0 && volume <= 1
        setVolume(1)
        play(.uiSelect, at: 1_000)
        play(.uiSelect, at: 1_000.02)
        let rateLimitWorked = diagnostics.rateLimited == rateLimitedBeforeProbe + 1
        stopAll(reason: "qaProbeReset")
        for (index, effect) in WitchSoundEffect.allCases.enumerated() {
            play(effect, at: 2_000 + Double(index) * 0.1)
        }
        let concurrencyWorked = diagnostics.activeVoices == maxVoices && diagnostics.voiceLimitDropped == dropsBeforeProbe + 2
        let interruptionStopsBeforeProbe = diagnostics.interruptionStops
        stopAll(reason: "interruption")
        let interruptionStopWorked = diagnostics.interruptionStops == interruptionStopsBeforeProbe + 1 && diagnostics.activeVoices == 0
        let reloaded = WitchAudioCoordinator(defaults: defaults)
        let settingsReloaded = reloaded.isMuted == isMuted && reloaded.volume == volume
        diagnostics.settingsReloadMatched = settingsReloaded
        diagnostics.qaProbePassed = muteWorked && nanSanitized && rateLimitWorked && concurrencyWorked && interruptionStopWorked && settingsReloaded
        if diagnostics.qaProbePassed == false {
            diagnostics.lastError = "QA assertion failed: mute=\(muteWorked), sanitize=\(nanSanitized), rate=\(rateLimitWorked), voices=\(concurrencyWorked), interruption=\(interruptionStopWorked), settings=\(settingsReloaded)"
        }
        logDiagnosticsIfEnabled()
    }

    private func logDiagnosticsIfEnabled() {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"),
              ProcessInfo.processInfo.arguments.contains("--qa-audio-diagnostics") else { return }
        if let data = try? JSONEncoder().encode(diagnostics), let line = String(data: data, encoding: .utf8) {
            Self.qaLogger.notice("WITCH_AUDIO_QA \(line, privacy: .public)")
        }
    }

    private func configureAmbientSession() {
        let session = AVAudioSession.sharedInstance()
        do { try session.setCategory(.ambient, mode: .default, options: []) }
        catch { diagnostics.lastError = "AVAudioSession category setup failed: \(error.localizedDescription)"; logDiagnosticsIfEnabled() }
    }
}
#endif
