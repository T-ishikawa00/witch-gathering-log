import Foundation

/// QA-only state observer. It consumes SpriteKit readbacks from didFinishUpdate;
/// it never schedules, pauses, speeds up, or edits an animation.
@MainActor
final class RenderBoundStateObserverR084 {
    struct Completion: Equatable {
        let state: String
        let renderGeneration: Int
    }

    let requestID: String
    let actorID: String
    let requestedState: String
    let expectedSettledState: String
    let looping: Bool
    let expectedR064WalkBackend: Bool
    let expectedR064SourceSHA256: String?

    private(set) var rows: [[String: Any]] = []
    private(set) var completionEvents: [Completion] = []
    private(set) var firstActiveRenderGeneration: Int?
    private(set) var completionRenderGeneration: Int?
    private var settledRun = 0
    private var finished = false
    private let maxRows = 1800
    private let requiredStableRows = 3
    private(set) var settled = false
    private(set) var rowLimitReached = false

    static func requestedStates(actorID: String) -> [String]? {
        switch actorID {
        case "ACT_B_R03_A": return ["execute", "hit"]
        case "ACT_E_R02_03": return ["recover"]
        case "ACT_B_R04_B": return ["hit", "idle", "walk"]
        default: return nil
        }
    }

    init(requestID: String, actorID: String, requestedState: String,
         expectedSettledState: String, looping: Bool, expectedR064WalkBackend: Bool = false,
         expectedR064SourceSHA256: String? = nil) {
        self.requestID = requestID
        self.actorID = actorID
        self.requestedState = requestedState
        self.expectedSettledState = expectedSettledState
        self.looping = looping
        self.expectedR064WalkBackend = expectedR064WalkBackend
        self.expectedR064SourceSHA256 = expectedR064SourceSHA256
    }

    func recordActionCompletion(state: String, renderGeneration: Int) {
        guard !finished, renderGeneration >= 0 else { return }
        completionEvents.append(Completion(state: state, renderGeneration: renderGeneration))
    }

    /// Returns true only after a request-specific, rendered action start and
    /// either the matching action callback plus stable follow-up, or a stable
    /// active loop readback. `presentation` is the actual controller snapshot.
    func sample(presentation: [String: Any], sceneFrame: Int, sceneTime: Double,
                root: [Double], completionThisGeneration: [Completion]) -> Bool {
        guard !finished else { return true }
        for event in completionThisGeneration where event.renderGeneration == sceneFrame {
            recordActionCompletion(state: event.state, renderGeneration: event.renderGeneration)
        }

        let actualState = presentation["state"] as? String ?? "unknown"
        let isRig = presentation["isPartRig"] as? Bool == true
        let rig = presentation["partRig"] as? [String: Any] ?? [:]
        let backend = rig["normalEntryBackendR068"] as? String ?? "not_applicable"
        let r064Requested = rig["walkFourLegR064Requested"] as? Bool == true
        let r064Mounted = rig["walkFourLegR064MountPresent"] as? Bool == true
        let r064Active = rig["walkFourLegR064Active"] as? Bool == true
        let r064Action = rig["walkFourLegR064ActionRunning"] as? Bool == true
        let r064Pivots = rig["walkFourLegR064Pivots"] as? [[String: Any]] ?? []
        let r064Source = rig["walkFourLegR064SourceSHA256"] as? String ?? ""
        let r064PartitionMismatch = rig["walkFourLegR064RecompositionByteMismatchCount"] as? Int ?? -1
        let spriteAction = presentation["spriteActionRunning"] as? Bool == true
        let registered = presentation["registeredPoses"] as? [String: Any] ?? [:]
        let registeredAction = registered["actionRunning"] as? Bool == true
        let rigAction = rig["actionRunning"] as? Bool == true
        let actionRunning = requestedState == "walk" && r064Requested
            ? r064Mounted && r064Active && r064Action
            : (isRig ? (rigAction || r064Action || registeredAction) : (spriteAction || registeredAction))

        let activeReadback = actualState == requestedState && actionRunning
        if activeReadback && firstActiveRenderGeneration == nil {
            firstActiveRenderGeneration = sceneFrame
        }

        let completionForRequest = completionEvents.contains {
            $0.state == requestedState && $0.renderGeneration == sceneFrame
        }
        if completionForRequest { completionRenderGeneration = sceneFrame }

        let settledReadback: Bool
        if looping {
            settledReadback = activeReadback
        } else {
            settledReadback = completionRenderGeneration != nil
                && actualState == expectedSettledState
                && actionRunning
        }
        let r064RowsFinite = r064Pivots.count == 4 && r064Pivots.allSatisfy { row in
            let anglesFinite = ["lowerAngleRadians", "wristAngleRadians"].allSatisfy { key in
                guard let value = row[key] as? NSNumber else { return false }
                return value.doubleValue.isFinite
            }
            let toe = row["toeBodyLocal"] as? [Double] ?? []
            return row["toeReadbackFinite"] as? Bool == true
                && row["upperAttached"] as? Bool == true
                && row["lowerAttached"] as? Bool == true
                && row["wristAttached"] as? Bool == true
                && anglesFinite && toe.count == 2 && toe.allSatisfy { $0.isFinite }
        }
        let r064ContractOK = !expectedR064WalkBackend || (
            backend == "r064LocalDefaultCandidate" && r064Requested && r064Mounted
            && r064Active && r064Action && r064RowsFinite
            && (expectedR064SourceSHA256 == nil || r064Source == expectedR064SourceSHA256)
            && r064PartitionMismatch == 0
        )
        let row: [String: Any] = [
            "sequence": rows.count,
            "requestID": requestID,
            "actorID": actorID,
            "requestedState": requestedState,
            "expectedSettledState": expectedSettledState,
            "sceneFrame": sceneFrame,
            "sceneTime": sceneTime,
            "root": root,
            "actualState": actualState,
            "frameIndex": presentation["frameIndex"] ?? -1,
            "framePath": presentation["framePath"] ?? "",
            "isPartRig": isRig,
            "actionRunning": actionRunning,
            "activeReadback": activeReadback,
            "completionThisGeneration": completionThisGeneration.map {
                ["state": $0.state, "renderGeneration": $0.renderGeneration]
            },
            "completionForRequest": completionForRequest,
            "firstActiveRenderGeneration": firstActiveRenderGeneration ?? NSNull(),
            "completionRenderGeneration": completionRenderGeneration ?? NSNull(),
            "backend": backend,
            "r064Requested": r064Requested,
            "r064MountPresent": r064Mounted,
            "r064Active": r064Active,
            "r064ActionRunning": r064Action,
            "r064PivotCount": r064Pivots.count,
            "r064PivotReadbackFinite": r064RowsFinite,
            "r064SourceSHA256": r064Source,
            "r064RecompositionByteMismatchCount": r064PartitionMismatch,
            "r064ContractOK": r064ContractOK,
            "partRigReadback": isRig ? rig : NSNull()
        ]
        rows.append(row)
        guard rows.count < maxRows else { finished = true; rowLimitReached = true; return true }

        if firstActiveRenderGeneration != nil && settledReadback && r064ContractOK {
            settledRun += 1
        } else {
            settledRun = 0
        }
        if settledRun >= requiredStableRows {
            finished = true
            settled = true
        }
        return finished
    }

    func json(status: String, finishReason: String) -> [String: Any] {
        [
            "schema": "render_bound_enemy_state_r084_v1",
            "status": status,
            "finishReason": finishReason,
            "requestID": requestID,
            "actorID": actorID,
            "requestedState": requestedState,
            "expectedSettledState": expectedSettledState,
            "looping": looping,
            "expectedR064WalkBackend": expectedR064WalkBackend,
            "expectedR064SourceSHA256": expectedR064SourceSHA256 as Any? ?? NSNull(),
            "firstActiveRenderGeneration": firstActiveRenderGeneration.map { $0 as Any } ?? NSNull(),
            "completionRenderGeneration": completionRenderGeneration.map { $0 as Any } ?? NSNull(),
            "completionEvents": completionEvents.map {
                ["state": $0.state, "renderGeneration": $0.renderGeneration]
            },
            "rowCount": rows.count,
            "rows": rows,
            "contract": "readback-only at didFinishUpdate after SpriteKit actions; no playback duration, speed, pause, state, or game command changes"
        ]
    }
}
