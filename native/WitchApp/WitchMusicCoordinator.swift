#if canImport(UIKit) && canImport(AVFoundation)
import AVFoundation
import Combine
import Foundation
import UIKit

/// Candidate background-music contexts. These tracks are UNAPPROVED_TEST_OVERLAY assets.
enum WitchMusicContext: String, CaseIterable, Codable, Sendable {
    case home
    case field
    case battle

    var resourceName: String { rawValue + "_r001" }
}

struct WitchMusicDiagnostics: Codable, Sendable, Equatable {
    var requestedContext: WitchMusicContext = .home
    var loadedContext: WitchMusicContext?
    var appIsActive = false
    var interruptionBlocked = false
    var isMuted = false
    var volume: Float = 0.5
    var outputGain: Float = 0
    var activePlayerCount = 0
    var currentPlayerIsPlaying = false
    var currentTimeSeconds: TimeInterval?
    var currentDurationSeconds: TimeInterval?
    var currentLoopCount: Int?
    var crossfadeTransitions = 0
    var lastCrossfadeSeconds: TimeInterval = 0
    var lastRetiringCleanupDelaySeconds: TimeInterval?
    var qaCleanupWaitSeconds: TimeInterval?
    var maximumPlayersObserved = 0
    var settingsPersistenceAvailable = true
    var backgroundPauses = 0
    var interruptionPauses = 0
    var interruptionResumesAllowed = 0
    var interruptionResumesDenied = 0
    var mutedPauses = 0
    var zeroVolumePauses = 0
    var sameContextNoops = 0
    var settingsReloadMatched: Bool?
    var qaProbePassed: Bool?
    var lastError: String?
}

struct WitchMusicSnapshot: Codable, Sendable, Equatable {
    var diagnostics: WitchMusicDiagnostics
}

private struct WitchMusicProbeReceipt: Codable {
    var schema = "witch.music.qa-probe.v1"
    var status = "UNAPPROVED_TEST_OVERLAY"
    var timestamp = ISO8601DateFormatter().string(from: Date())
    var settingsSuite: String
    var checks: [String: Bool]
    var initial: WitchMusicSnapshot
    var final: WitchMusicSnapshot
    var errors: [String]
}

private struct WitchMusicDiagnosticRecord: Codable {
    var timestamp = ISO8601DateFormatter().string(from: Date())
    var uptimeSeconds = ProcessInfo.processInfo.systemUptime
    var event: String
    var snapshot: WitchMusicSnapshot
}

private struct WitchMusicDiagnosticJournal: Codable {
    var schema = "witch.music.diagnostics.v1"
    var records: [WitchMusicDiagnosticRecord]
}

/// App-facing looping music. It leaves the shared audio-session category untouched;
/// the existing SFX coordinator configures `.ambient` to respect the Silent switch.
@MainActor
final class WitchMusicCoordinator: ObservableObject {
    static let shared = WitchMusicCoordinator()
    static let maximumGain: Float = 0.17
    static let maximumCrossfade: TimeInterval = 0.35
    private static let settingsMutedKey = "witch.music.muted"
    private static let settingsVolumeKey = "witch.music.volume"

    @Published private(set) var isMuted: Bool
    @Published private(set) var volume: Float
    @Published private(set) var diagnostics = WitchMusicDiagnostics()

    private struct PlayerSlot {
        let id: UUID
        let context: WitchMusicContext
        let player: AVAudioPlayer
    }

    private let defaults: UserDefaults?
    private let bundle: Bundle
    private let resourceURL: (WitchMusicContext) -> URL?
    private var observers: [NSObjectProtocol] = []
    private var diagnosticHistory: [WitchMusicDiagnosticRecord] = []
    private var currentPlayer: PlayerSlot?
    private var retiringPlayers: [PlayerSlot] = []
    private var crossfadeCleanupTask: Task<Void, Never>?
    private var desiredContext: WitchMusicContext = .home
    private var appIsActive: Bool
    private var interruptionIsActive = false
    private var interruptionResumeDenied = false
    private var settingsSuiteName: String

    private var shouldAudiblyPlay: Bool {
        !isMuted && volume > 0 && appIsActive && !interruptionIsActive && !interruptionResumeDenied
    }

    private var effectiveOutputGain: Float {
        min(Self.maximumGain, max(0, volume) * Self.maximumGain)
    }

    init(
        defaults suppliedDefaults: UserDefaults? = nil,
        bundle: Bundle = .main,
        resourceURL suppliedResourceURL: ((WitchMusicContext) -> URL?)? = nil,
        installObservers: Bool = true,
        autoStart: Bool = false
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        let isQA = arguments.contains("--qa-isolated")
        let rawToken = arguments.first(where: { $0.hasPrefix("--qa-audio-suite=") })
            .map { String($0.dropFirst("--qa-audio-suite=".count)) }
            ?? arguments.first(where: { $0.hasPrefix("--qa-save-key=") })
                .map { String($0.dropFirst("--qa-save-key=".count)) }
        let safeToken = rawToken.map { String($0.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(64)) } ?? ""
        let suite = "WitchMusicQA-" + (safeToken.isEmpty ? "isolated" : safeToken)
        self.settingsSuiteName = isQA ? suite : "standard"
        self.defaults = suppliedDefaults ?? (isQA ? UserDefaults(suiteName: suite) : .standard)
        self.bundle = bundle
        self.resourceURL = suppliedResourceURL ?? { context in
            bundle.url(forResource: context.resourceName, withExtension: "wav", subdirectory: "Music")
                ?? bundle.url(forResource: context.resourceName, withExtension: "wav")
        }
        self.isMuted = self.defaults?.object(forKey: Self.settingsMutedKey) as? Bool ?? false
        let savedVolume = (self.defaults?.object(forKey: Self.settingsVolumeKey) as? NSNumber)?.floatValue ?? 0.5
        self.volume = Self.sanitizeVolume(savedVolume)
        self.appIsActive = UIApplication.shared.applicationState == .active
        self.diagnostics.appIsActive = self.appIsActive
        self.diagnostics.isMuted = self.isMuted
        self.diagnostics.volume = self.volume
        self.diagnostics.outputGain = min(Self.maximumGain, self.volume * Self.maximumGain)
        self.diagnostics.settingsPersistenceAvailable = self.defaults != nil
        if self.defaults == nil { self.diagnostics.lastError = "QA UserDefaults suite unavailable; persistence disabled" }

        if installObservers {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDidEnterBackground() }
            })
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDidBecomeActive() }
            })
            observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
                Task { @MainActor in self?.handleInterruptionNotification(note) }
            })
        }
        if autoStart { reconcilePlayback() }
        recordDiagnostic("initialized")
    }

    deinit {
        crossfadeCleanupTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func setContext(_ context: WitchMusicContext) {
        let sameContext = desiredContext == context
        desiredContext = context
        diagnostics.requestedContext = context
        if sameContext, currentPlayer?.context == context {
            diagnostics.sameContextNoops += 1
            reconcilePlayback()
            recordDiagnostic("context_same_\(context.rawValue)")
            return
        }
        reconcilePlayback()
        recordDiagnostic("context_\(context.rawValue)")
    }

    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        defaults?.set(muted, forKey: Self.settingsMutedKey)
        diagnostics.settingsPersistenceAvailable = defaults != nil
        diagnostics.isMuted = muted
        if !muted { interruptionResumeDenied = false }
        if muted { diagnostics.mutedPauses += 1 }
        reconcilePlayback()
        recordDiagnostic("mute_\(muted)")
    }

    func setVolume(_ newValue: Float) {
        let sanitized = Self.sanitizeVolume(newValue)
        let volumeChanged = sanitized != volume
        volume = sanitized
        defaults?.set(sanitized, forKey: Self.settingsVolumeKey)
        diagnostics.settingsPersistenceAvailable = defaults != nil
        diagnostics.volume = sanitized
        diagnostics.outputGain = effectiveOutputGain
        if sanitized == 0 { diagnostics.zeroVolumePauses += 1 }
        if volumeChanged && sanitized > 0 { interruptionResumeDenied = false }
        if let currentPlayer, shouldAudiblyPlay {
            currentPlayer.player.setVolume(effectiveOutputGain, fadeDuration: 0)
        }
        reconcilePlayback()
        recordDiagnostic("volume_changed")
    }

    var snapshot: WitchMusicSnapshot {
        updatePlaybackDiagnostics()
        return WitchMusicSnapshot(diagnostics: diagnostics)
    }

    static func sanitizeVolume(_ value: Float) -> Float {
        guard value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }

    private func reconcilePlayback() {
        diagnostics.isMuted = isMuted
        diagnostics.volume = volume
        diagnostics.outputGain = effectiveOutputGain
        diagnostics.appIsActive = appIsActive
        diagnostics.interruptionBlocked = interruptionIsActive || interruptionResumeDenied
        guard shouldAudiblyPlay else {
            pauseCurrentPlayer()
            stopRetiringPlayers()
            updatePlaybackDiagnostics()
            return
        }
        if let currentPlayer, currentPlayer.context == desiredContext {
            if !currentPlayer.player.isPlaying {
                currentPlayer.player.volume = effectiveOutputGain
                if !currentPlayer.player.play() {
                    diagnostics.lastError = "AVAudioPlayer could not resume \(desiredContext.rawValue)"
                }
            }
            updatePlaybackDiagnostics()
            return
        }
        startTransition(to: desiredContext)
    }

    private func startTransition(to context: WitchMusicContext) {
        crossfadeCleanupTask?.cancel()
        crossfadeCleanupTask = nil
        stopRetiringPlayers()

        guard let url = resourceURL(context) else {
            failTransition("missing music resource: Music/\(context.resourceName).wav")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            guard player.prepareToPlay() else {
                failTransition("AVAudioPlayer prepareToPlay failed: \(url.lastPathComponent)")
                return
            }
            guard player.play() else {
                failTransition("AVAudioPlayer.play returned false: \(url.lastPathComponent)")
                return
            }
            let next = PlayerSlot(id: UUID(), context: context, player: player)
            let previous = currentPlayer
            currentPlayer = next
            diagnostics.lastError = nil
            diagnostics.crossfadeTransitions += 1
            let duration = Self.maximumCrossfade
            diagnostics.lastCrossfadeSeconds = duration
            player.setVolume(effectiveOutputGain, fadeDuration: duration)
            if let previous {
                previous.player.setVolume(0, fadeDuration: duration)
                retiringPlayers = [previous]
                scheduleRetiringCleanup(after: duration, expectedID: previous.id)
            }
            updatePlaybackDiagnostics()
            recordDiagnostic("transition_started_\(context.rawValue)")
        } catch {
            failTransition("music player failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func failTransition(_ message: String) {
        diagnostics.lastError = message
        pauseCurrentPlayer()
        stopRetiringPlayers()
        updatePlaybackDiagnostics()
        recordDiagnostic("transition_failed")
    }

    private func scheduleRetiringCleanup(after duration: TimeInterval, expectedID: UUID) {
        crossfadeCleanupTask?.cancel()
        let requestedAt = ProcessInfo.processInfo.systemUptime
        diagnostics.lastRetiringCleanupDelaySeconds = nil
        crossfadeCleanupTask = Task { @MainActor [weak self] in
            let milliseconds = UInt64((min(Self.maximumCrossfade, duration) + 0.05) * 1_000)
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let expired = self.retiringPlayers.filter { $0.id == expectedID }
            expired.forEach { $0.player.stop() }
            self.retiringPlayers.removeAll { $0.id == expectedID }
            self.crossfadeCleanupTask = nil
            self.diagnostics.lastRetiringCleanupDelaySeconds = ProcessInfo.processInfo.systemUptime - requestedAt
            self.updatePlaybackDiagnostics()
            self.recordDiagnostic("transition_finished")
        }
    }

    private func pauseCurrentPlayer() {
        currentPlayer?.player.pause()
        updatePlaybackDiagnostics()
    }

    private func stopRetiringPlayers() {
        retiringPlayers.forEach { $0.player.stop() }
        retiringPlayers.removeAll(keepingCapacity: true)
    }

    private func updatePlaybackDiagnostics() {
        let all = ([currentPlayer].compactMap { $0 } + retiringPlayers)
        diagnostics.activePlayerCount = all.count
        diagnostics.maximumPlayersObserved = max(diagnostics.maximumPlayersObserved, all.count)
        diagnostics.currentPlayerIsPlaying = currentPlayer?.player.isPlaying ?? false
        diagnostics.loadedContext = currentPlayer?.context
        diagnostics.currentTimeSeconds = currentPlayer?.player.currentTime
        diagnostics.currentDurationSeconds = currentPlayer?.player.duration
        diagnostics.currentLoopCount = currentPlayer?.player.numberOfLoops
        diagnostics.appIsActive = appIsActive
        diagnostics.interruptionBlocked = interruptionIsActive || interruptionResumeDenied
    }

    private func handleDidEnterBackground() {
        appIsActive = false
        diagnostics.backgroundPauses += 1
        pauseCurrentPlayer()
        stopRetiringPlayers()
        crossfadeCleanupTask?.cancel()
        crossfadeCleanupTask = nil
        updatePlaybackDiagnostics()
        recordDiagnostic("backgrounded")
    }

    private func handleDidBecomeActive() {
        appIsActive = true
        reconcilePlayback()
        recordDiagnostic("active")
    }

    private func handleInterruptionNotification(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            handleInterruptionBegan()
        } else if type == .ended {
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let resume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            handleInterruptionEnded(shouldResume: resume)
            recordDiagnostic("interruption_ended_should_resume_\(resume)")
        }
    }

    private func handleInterruptionBegan() {
        interruptionIsActive = true
        pauseCurrentPlayer()
        stopRetiringPlayers()
        crossfadeCleanupTask?.cancel()
        crossfadeCleanupTask = nil
        diagnostics.interruptionPauses += 1
        updatePlaybackDiagnostics()
        recordDiagnostic("interruption_began")
    }

    private func handleInterruptionEnded(shouldResume: Bool) {
        interruptionIsActive = false
        if shouldResume {
            interruptionResumeDenied = false
            diagnostics.interruptionResumesAllowed += 1
            reconcilePlayback()
            recordDiagnostic("interruption_resume_allowed")
        } else {
            interruptionResumeDenied = true
            diagnostics.interruptionResumesDenied += 1
            pauseCurrentPlayer()
            updatePlaybackDiagnostics()
            recordDiagnostic("interruption_resume_denied")
        }
    }

    /// Runs only with `--qa-isolated --qa-music-probe`; tests real AVAudioPlayer
    /// instances and writes a sanitized JSON receipt to Documents.
    func runQAProbeIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-music-probe") else { return }
        let initial = snapshot
        var checks: [String: Bool] = [:]
        var errors: [String] = []
        let oldMuted = isMuted
        let oldVolume = volume
        let oldContext = desiredContext

        setMuted(false); setVolume(0.5)
        for context in WitchMusicContext.allCases {
            setContext(context)
            try? await Task.sleep(for: .milliseconds(120))
            let player = currentPlayer?.player
            let prefix = "track_\(context.rawValue)"
            checks["\(prefix)_loadedPlayingLoopConfigured"] = currentPlayer?.context == context
                && player?.isPlaying == true
                && player?.numberOfLoops == -1
                && (player?.duration ?? 0) > 0
            if let player, player.duration > 0 {
                player.currentTime = max(0, player.duration - 0.12)
                try? await Task.sleep(for: .milliseconds(300))
                checks["\(prefix)_actuallyLoops"] = player.isPlaying && player.currentTime < 0.6
            } else {
                checks["\(prefix)_actuallyLoops"] = false
            }
            checks["\(prefix)_crossfadeAndPlayerLimit"] = diagnostics.lastCrossfadeSeconds <= Self.maximumCrossfade
                && diagnostics.activePlayerCount <= 2
                && diagnostics.maximumPlayersObserved <= 2
        }
        setContext(.home)
        try? await Task.sleep(for: .milliseconds(180))
        let homeID = currentPlayer?.id
        let homeTime = currentPlayer?.player.currentTime
        setContext(.home)
        try? await Task.sleep(for: .milliseconds(80))
        checks["sameContextDidNotRestart"] = homeID == currentPlayer?.id && (currentPlayer?.player.currentTime ?? 0) >= (homeTime ?? 0)

        setContext(.field)
        try? await Task.sleep(for: .milliseconds(90))
        checks["fieldCrossfadeBounded"] = diagnostics.lastCrossfadeSeconds <= Self.maximumCrossfade && diagnostics.activePlayerCount <= 2
        setContext(.battle); setContext(.home)
        checks["rapidChangesStayAtTwoPlayers"] = diagnostics.activePlayerCount <= 2 && diagnostics.maximumPlayersObserved <= 2
        // The audio ramp runs for .35 seconds; cleanup is scheduled after .40.
        // MainActor scheduling is not a hard real-time guarantee. Observe actual
        // completion with a bounded deadline instead of sampling once at .42.
        let cleanupWaitStarted = ProcessInfo.processInfo.systemUptime
        while !retiringPlayers.isEmpty && ProcessInfo.processInfo.systemUptime - cleanupWaitStarted < 1 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        diagnostics.qaCleanupWaitSeconds = ProcessInfo.processInfo.systemUptime - cleanupWaitStarted
        updatePlaybackDiagnostics()
        checks["retiringPlayerCleanedWithinOneSecond"] = diagnostics.activePlayerCount == 1
            && currentPlayer?.context == .home
            && (diagnostics.lastRetiringCleanupDelaySeconds ?? .infinity) <= 1
        recordDiagnostic("qa_cleanup_observed")

        setMuted(true)
        checks["mutePausesPlayer"] = currentPlayer?.player.isPlaying == false
        setMuted(false); setVolume(0)
        checks["zeroVolumePausesPlayer"] = currentPlayer?.player.isPlaying == false
        setVolume(0.5)
        try? await Task.sleep(for: .milliseconds(60))
        checks["volumeRestoreResumes"] = currentPlayer?.player.isPlaying == true

        let reloaded = WitchMusicCoordinator(defaults: defaults, bundle: bundle, installObservers: false, autoStart: false)
        checks["settingsReloadMatches"] = defaults != nil && reloaded.isMuted == isMuted && reloaded.volume == volume
        diagnostics.settingsReloadMatched = checks["settingsReloadMatches"]

        handleInterruptionBegan()
        handleInterruptionEnded(shouldResume: false)
        handleDidBecomeActive()
        setContext(.field)
        checks["interruptionWithoutShouldResumeStaysPaused"] = currentPlayer?.player.isPlaying == false && interruptionResumeDenied
        setMuted(true); setMuted(false); setContext(.battle)
        try? await Task.sleep(for: .milliseconds(60))
        handleInterruptionBegan()
        let pausedTime = currentPlayer?.player.currentTime
        handleInterruptionEnded(shouldResume: true)
        let resumedTime = currentPlayer?.player.currentTime
        checks["interruptionShouldResumeResumes"] = currentPlayer?.player.isPlaying == true
        if let pausedTime {
            checks["interruptionPositionRetained"] = (resumedTime ?? 0) >= pausedTime - 0.05
        } else {
            checks["interruptionPositionRetained"] = true
        }

        let missing = WitchMusicCoordinator(defaults: defaults, bundle: bundle, resourceURL: { _ in nil }, installObservers: false, autoStart: false)
        missing.setContext(.field)
        checks["missingTrackIsDiagnosticOnly"] = missing.diagnostics.lastError?.contains("missing music resource") == true

        // A corrupt file exercises the throwing AVAudioPlayer initializer with
        // an existing old track, not merely the missing-URL guard.
        pauseCurrentPlayer(); stopRetiringPlayers()
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WitchMusicQA", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let invalidURL = directory.appendingPathComponent("invalid-\(UUID().uuidString).wav")
            try Data("invalid QA audio".utf8).write(to: invalidURL)
            let invalid = WitchMusicCoordinator(defaults: defaults, bundle: bundle, resourceURL: { context in
                context == .home ? self.resourceURL(.home) : invalidURL
            }, installObservers: false, autoStart: false)
            invalid.setContext(.home)
            checks["corruptTrackFixtureStartedOldMusic"] = invalid.currentPlayer?.player.isPlaying == true
            invalid.setContext(.field)
            checks["corruptTrackPausesOldMusic"] = invalid.currentPlayer?.player.isPlaying == false
                && invalid.diagnostics.lastError?.contains("music player failed") == true
            try FileManager.default.removeItem(at: invalidURL)
        } catch {
            checks["corruptTrackPausesOldMusic"] = false
            errors.append("corrupt-track fixture: \(error.localizedDescription)")
        }

        setMuted(oldMuted); setVolume(oldVolume); setContext(oldContext)
        diagnostics.qaProbePassed = checks.values.allSatisfy { $0 }
        if diagnostics.qaProbePassed == false {
            errors.append("one or more real-player QA assertions failed")
            diagnostics.lastError = "QA probe failed: " + checks.filter { !$0.value }.keys.sorted().joined(separator: ",")
        }
        updatePlaybackDiagnostics()
        writeQAReceipt(WitchMusicProbeReceipt(settingsSuite: settingsSuiteName, checks: checks, initial: initial, final: snapshot, errors: errors))
        recordDiagnostic("qa_probe_finished")
    }

    private func recordDiagnostic(_ event: String) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated"), arguments.contains("--qa-music-diagnostics") else { return }
        do {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WitchMusicQA", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("latest_diagnostic.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let record = WitchMusicDiagnosticRecord(event: event, snapshot: snapshot)
            diagnosticHistory.append(record)
            if diagnosticHistory.count > 256 {
                diagnosticHistory.removeFirst(diagnosticHistory.count - 256)
            }
            try encoder.encode(record).write(to: url, options: .atomic)
            try encoder.encode(WitchMusicDiagnosticJournal(records: diagnosticHistory))
                .write(to: folder.appendingPathComponent("history.json"), options: .atomic)
        } catch {
            diagnostics.lastError = "could not write music diagnostic: \(error.localizedDescription)"
        }
    }

    private func writeQAReceipt(_ receipt: WitchMusicProbeReceipt) {
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            let folder = documents.appendingPathComponent("WitchMusicQA", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("probe_receipt.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: url, options: .atomic)
        } catch {
            diagnostics.lastError = "could not write music QA receipt: \(error.localizedDescription)"
        }
    }
}
#endif
