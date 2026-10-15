import Foundation

/// Opt-in, read-only timing samples for a normal DEBUG development battle.
/// It never opens the save file and never changes SpriteKit/game clocks.
@MainActor
final class BattleTimingTraceR319 {
    static let argument = "--battle-timing-trace-r319"
    static let maximumSamples = 600

    struct Sample: Codable {
        let index: Int
        let monotonicUptime: TimeInterval
        let elapsedMonotonic: TimeInterval
        let sceneActive: Bool
        let scenePaused: Bool
        let battleElapsed: Int
        let presentationClock: TimeInterval
        let frameCount: Int
    }

    private struct Document: Codable {
        let schema: String
        let runID: String
        let encounterID: String?
        let encounterRoute: String
        let processID: Int32
        let saveFilename: String
        let sampleIntervalMilliseconds: Int
        let maximumSamples: Int
        let startedAtUnixTime: TimeInterval
        let startedAtMonotonicUptime: TimeInterval
        let endedAtUnixTime: TimeInterval
        let endedAtMonotonicUptime: TimeInterval
        let cancelled: Bool
        let completion: String
        let samples: [Sample]
    }

    private let runID = UUID().uuidString.lowercased()
    private let encounterID: String?
    private let saveFilename: String
    private let outputDirectory: URL
    private let startedAtUnixTime = Date().timeIntervalSince1970
    private let startedAtMonotonicUptime = ProcessInfo.processInfo.systemUptime
    private var samples: [Sample] = []
    private var finished = false

    private init(encounterID: String?, saveFilename: String, outputDirectory: URL) {
        self.encounterID = encounterID
        self.saveFilename = saveFilename
        self.outputDirectory = outputDirectory
        samples.reserveCapacity(Self.maximumSamples)
    }

    static func makeIfRequested(arguments: [String], applicationSupport: URL,
                                encounterID: String?, saveFilename: String) -> BattleTimingTraceR319? {
        #if DEBUG && STANDARD_PLAY_R169
        let optIns = arguments.filter { $0 == Self.argument }
        let hasQAArgument = arguments.contains { $0.hasPrefix("--qa") }
        guard optIns.count == 1, !hasQAArgument else { return nil }
        let output = applicationSupport.appendingPathComponent("WitchBattleTimingR319", isDirectory: true)
        return BattleTimingTraceR319(encounterID: encounterID, saveFilename: saveFilename,
                                     outputDirectory: output)
        #else
        return nil
        #endif
    }

    var count: Int { samples.count }

    func append(sceneActive: Bool, scenePaused: Bool, battleElapsed: Int,
                presentationClock: TimeInterval, frameCount: Int) {
        guard !finished, samples.count < Self.maximumSamples else { return }
        let now = ProcessInfo.processInfo.systemUptime
        samples.append(Sample(index: samples.count, monotonicUptime: now,
                              elapsedMonotonic: max(0, now - startedAtMonotonicUptime),
                              sceneActive: sceneActive, scenePaused: scenePaused,
                              battleElapsed: battleElapsed, presentationClock: presentationClock,
                              frameCount: frameCount))
    }

    func finish(endedAtUnixTime: TimeInterval, endedAtMonotonicUptime: TimeInterval,
                cancelled: Bool, completion: String) {
        guard !finished else { return }
        finished = true
        let route = encounterID?.hasPrefix("CH_") == true ? "challenge" : (encounterID == nil ? "unknown" : "ordinary_or_other")
        let document = Document(schema: "battle-timing-trace-r319-v1", runID: runID,
                                encounterID: encounterID, encounterRoute: route,
                                processID: ProcessInfo.processInfo.processIdentifier,
                                saveFilename: saveFilename, sampleIntervalMilliseconds: 200,
                                maximumSamples: Self.maximumSamples,
                                startedAtUnixTime: startedAtUnixTime,
                                startedAtMonotonicUptime: startedAtMonotonicUptime,
                                endedAtUnixTime: endedAtUnixTime,
                                endedAtMonotonicUptime: endedAtMonotonicUptime,
                                cancelled: cancelled, completion: completion, samples: samples)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return }
        let directory = outputDirectory
        let firstName = runID + ".json"
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                do {
                    try data.write(to: directory.appendingPathComponent(firstName), options: .withoutOverwriting)
                } catch {
                    // A collision gets a second unique filename in the same private namespace.
                    let fallback = UUID().uuidString.lowercased() + ".json"
                    try data.write(to: directory.appendingPathComponent(fallback), options: .withoutOverwriting)
                }
            } catch {
                // Telemetry is best effort. No fallback can write beside the game save.
            }
        }
    }
}
