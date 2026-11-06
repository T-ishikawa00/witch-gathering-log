import Foundation

/// QA-only stall attribution. Context describes the latest requested state,
/// not a frame-perfect animation-state assertion.
/// Keeps bounded in-memory evidence and performs no per-frame file I/O.
@MainActor
final class FrameStallTelemetry {
    struct Context: Codable, Equatable {
        let phase: String
        let actorID: String?
        let state: String?
        let source: String
    }

    struct Stall: Codable {
        let monotonicUptimeNanoseconds: UInt64
        let sceneTimeBefore: Double
        let sceneTimeAfter: Double
        let rawDeltaMilliseconds: Double
        let clampedDeltaMilliseconds: Double
        let previousContext: Context
        let currentContext: Context
    }

    struct TextureCreate: Codable {
        let monotonicUptimeNanoseconds: UInt64
        let context: Context
        let relativePath: String
        let expectedWidth: Int
        let expectedHeight: Int
        let sourceWidth: Int?
        let sourceHeight: Int?
        let sourceOpenAndPropertiesMilliseconds: Double
        let thumbnailDecodeMilliseconds: Double
        let spriteKitTextureMilliseconds: Double
        let totalMilliseconds: Double
        let succeeded: Bool
        let failureStage: String?
    }

    struct RenderPreparation: Codable {
        let monotonicUptimeNanoseconds: UInt64
        let actorID: String
        let outcome: String
        let clipCount: Int
        let texturePaths: [String]
        let snapshotCount: Int
        let successfulSnapshotCount: Int
        let texturePreparationMilliseconds: Double
        let snapshotDurationMilliseconds: Double
        let snapshotCallMilliseconds: Double
        let durationMilliseconds: Double
        let failureReason: String?
    }

    static let capacity = 32
    static let thresholdSeconds = 0.050
    static let shared = FrameStallTelemetry()

    let enabled: Bool
    let wallClockAnchorUnixMilliseconds: Int64
    let monotonicAnchorNanoseconds: UInt64

    private(set) var totalStalls = 0
    private(set) var totalTextureCreates = 0
    private(set) var maxStall: Stall?
    private(set) var stalls: [Stall] = []
    private(set) var textureCreates: [TextureCreate] = []
    private(set) var totalRenderPreparations = 0
    private(set) var renderPreparations: [RenderPreparation] = []
    private(set) var currentContext = Context(phase: "startup", actorID: nil, state: nil, source: "process")

    private init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        enabled = arguments.contains("--qa-isolated")
        wallClockAnchorUnixMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        monotonicAnchorNanoseconds = Self.nowNanoseconds()
    }

    func recordStall(rawDelta: Double, clampedDelta: Double,
                     sceneTimeBefore: Double, sceneTimeAfter: Double,
                     previous: Context, current: Context) {
        guard enabled, rawDelta >= Self.thresholdSeconds else { return }
        totalStalls += 1
        let event = Stall(monotonicUptimeNanoseconds: Self.nowNanoseconds(),
                     sceneTimeBefore: sceneTimeBefore, sceneTimeAfter: sceneTimeAfter,
                     rawDeltaMilliseconds: rawDelta * 1_000,
                     clampedDeltaMilliseconds: clampedDelta * 1_000,
                     previousContext: previous, currentContext: current)
        if event.rawDeltaMilliseconds > (maxStall?.rawDeltaMilliseconds ?? 0) { maxStall = event }
        append(event, to: &stalls)
    }

    func setContext(_ context: Context) {
        guard enabled else { return }
        currentContext = context
    }

    func recordTextureCreate(_ event: TextureCreate) {
        guard enabled else { return }
        totalTextureCreates += 1
        append(event, to: &textureCreates)
    }

    func recordRenderPreparation(actorID: String, result: RegisteredPosePreparationResult) {
        guard enabled else { return }
        totalRenderPreparations += 1
        append(RenderPreparation(monotonicUptimeNanoseconds: Self.nowNanoseconds(), actorID: actorID,
                                 outcome: result.outcome, clipCount: result.clipCount,
                                 texturePaths: result.texturePaths, snapshotCount: result.snapshotCount,
                                 successfulSnapshotCount: result.successfulSnapshotCount,
                                 texturePreparationMilliseconds: result.texturePreparationMilliseconds,
                                 snapshotDurationMilliseconds: result.snapshotDurationMilliseconds,
                                 snapshotCallMilliseconds: result.snapshotCallMilliseconds,
                                 durationMilliseconds: result.durationMilliseconds,
                                 failureReason: result.failureReason), to: &renderPreparations)
    }

    func snapshot() -> [String: Any] {
        guard enabled else { return [:] }
        let encoder = JSONEncoder()
        func dictionaries<T: Encodable>(_ values: [T]) -> [[String: Any]] {
            values.compactMap { value in
                guard let data = try? encoder.encode(value),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return object
            }
        }
        return [
            "enabled": true,
            "capacity": Self.capacity,
            "stallThresholdMilliseconds": Self.thresholdSeconds * 1_000,
            "wallClockAnchorUnixMilliseconds": wallClockAnchorUnixMilliseconds,
            "monotonicAnchorNanoseconds": monotonicAnchorNanoseconds,
            "contextMeaning": "latest_requested_state_not_animation_frame",
            "totalStallEvents": totalStalls,
            "evictedStallEvents": max(0,totalStalls-stalls.count),
            "totalTextureCreateEvents": totalTextureCreates,
            "evictedTextureCreateEvents": max(0,totalTextureCreates-textureCreates.count),
            "totalRenderPreparationEvents": totalRenderPreparations,
            "evictedRenderPreparationEvents": max(0,totalRenderPreparations-renderPreparations.count),
            "maxStallEvent": dictionaries(maxStall.map { [$0] } ?? []).first as Any? ?? NSNull(),
            "stallEvents": dictionaries(stalls),
            "textureCreateEvents": dictionaries(textureCreates),
            "renderPreparationEvents": dictionaries(renderPreparations)
        ]
    }

    private func append<T>(_ value: T, to values: inout [T]) {
        if values.count == Self.capacity { values.removeFirst() }
        values.append(value)
    }

    static func nowNanoseconds() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    }
}
