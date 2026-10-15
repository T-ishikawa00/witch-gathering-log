import Foundation

/// Renderer-only deduplication for consecutive enemy execute requests that
/// represent the same combat action at the same rendered scene frame.
public struct EnemyExecuteCoalescerR154: Sendable {
    private struct Identity: Equatable, Sendable {
        let rootActionID: String
        let sceneGeneration: Int
        let sceneFrame: Int
    }

    private var activeGeneration: Int?
    private var activeFrame: Int?
    private var lastByActor: [String: Identity] = [:]

    public init() {}

    /// Returns true only when the caller may safely suppress this restart.
    /// Invalid/missing identity is never coalesced and clears that actor's
    /// previous identity because the legacy animation will restart normally.
    public mutating func shouldCoalesce(actorID: String, rootActionID: String?,
                                        sceneGeneration: Int, sceneFrame: Int) -> Bool {
        guard !actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rootActionID,
              !rootActionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sceneGeneration >= 0, sceneFrame >= 0 else {
            lastByActor.removeValue(forKey: actorID)
            return false
        }
        advanceFrame(generation: sceneGeneration, frame: sceneFrame)
        let identity = Identity(rootActionID: rootActionID,
                                sceneGeneration: sceneGeneration,
                                sceneFrame: sceneFrame)
        guard let previous = lastByActor[actorID] else { return false }
        guard previous == identity else {
            // A different valid action at the same frame is a new request
            // boundary. Do not let a later repeat of the older identity merge
            // across this intervening request, especially if play is rejected.
            lastByActor.removeValue(forKey: actorID)
            return false
        }
        return true
    }

    /// Call only after the underlying EnemyMotionController accepted the
    /// execute request. Failed/missing clips must not block a later retry.
    public mutating func recordAccepted(actorID: String, rootActionID: String?,
                                        sceneGeneration: Int, sceneFrame: Int) {
        guard !actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rootActionID,
              !rootActionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sceneGeneration >= 0, sceneFrame >= 0 else { return }
        advanceFrame(generation: sceneGeneration, frame: sceneFrame)
        lastByActor[actorID] = Identity(rootActionID: rootActionID,
                                        sceneGeneration: sceneGeneration,
                                        sceneFrame: sceneFrame)
    }

    /// A hit, resolve, telegraph, or other non-coalesced motion request is a
    /// priority boundary: a later execute request must be allowed to start.
    public mutating func clear(actorID: String) {
        lastByActor.removeValue(forKey: actorID)
    }

    public mutating func clearAll() {
        activeGeneration = nil
        activeFrame = nil
        lastByActor.removeAll(keepingCapacity: false)
    }

    private mutating func advanceFrame(generation: Int, frame: Int) {
        guard activeGeneration != generation || activeFrame != frame else { return }
        activeGeneration = generation
        activeFrame = frame
        lastByActor.removeAll(keepingCapacity: true)
    }
}

/// The feature is opt-in only for an isolated Simulator launch with one
/// canonical save key. A normal launch never enables this renderer change.
public enum EnemyExecuteCoalescingGateR154 {
    public static let flag = "--qa-enemy-execute-coalescing-r154"

    public static func isEnabled(arguments: [String], environment: [String: String],
                                 isSimulator: Bool) -> Bool {
        let featureArguments = arguments.filter { $0.hasPrefix("--qa-enemy-execute-coalescing-r154") }
        guard featureArguments == [flag], isSimulator,
              environment["SIMULATOR_UDID"]?.isEmpty == false,
              environment["SIMULATOR_DEVICE_NAME"]?.isEmpty == false,
              arguments.filter({ $0 == "--qa-isolated" }).count == 1 else { return false }
        let saveKeys = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard saveKeys.count == 1,
              let raw = saveKeys[0].split(separator: "=", maxSplits: 1).last.map(String.init),
              let value = UUID(uuidString: raw), value.uuidString.lowercased() == raw else { return false }
        return true
    }
}
