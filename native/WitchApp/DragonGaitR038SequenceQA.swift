import Foundation
import SpriteKit

/// Isolated visual observer for the unapproved R038 gait candidate. State
/// requests are issued between rendered samples; no gameplay events are sent.
@MainActor final class DragonGaitR038SequenceQA {
    enum Action {
        case none
        case play(EnemyMotionState)
        case finished(String)
    }

    private struct Phase {
        let sequenceID: String
        let state: EnemyMotionState
        let minimumDuration: Double
        let requiredWraps: Int
    }

    let runID = UUID().uuidString
    let saveKey: String
    let actorID = "ACT_B_R04_B"
    let startedAt: String
    let startUptime = ProcessInfo.processInfo.systemUptime

    private let outputDirectory: URL
    private let includesFlight: Bool
    private let usesDistalR007: Bool
    private let usesFourLegR064: Bool
    private var observedDistalRotationRows = 0
    private var observedFourLegMotionRows = 0
    private let marker = SKLabelNode(fontNamed: "Menlo-Bold")
    private var phases: [Phase] = []
    private var results: [[String: Any]] = []
    private var rows: [[String: Any]] = []
    private var phaseIndex = -1
    private var phaseStartedAt: Double?
    private var phaseRequestedAt = 0.0
    private var phaseStartRow = 0
    private var failureLifecycle = DragonGaitR038FailureLifecycle()
    private var failureCleanupRows: [[String: Any]] = []
    private var previousWalkProgress: Double?
    private var observedWalkWraps = 0
    private var subdivisionBaseline: Int?
    private var status = "RECORDING"
    private var completed = false
    private var completionPending = false
    private var markerRemovalPending = false
    private var completion: ((String) -> Void)?

    static let sequenceFlag = "--qa-dragon-gait-r038-sequence-probe"

    static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                            actorID: String = "ACT_B_R04_B") -> Bool {
        #if targetEnvironment(simulator)
        let hasAuditTarget = arguments.contains("--art-audit=\(actorID)")
        let hasSaveKey = arguments.contains { $0.hasPrefix("--qa-save-key=") }
        return actorID == "ACT_B_R04_B" &&
            DragonGaitR038QA.isEnabled(arguments: arguments) &&
            arguments.contains(sequenceFlag) && hasAuditTarget && hasSaveKey &&
            !arguments.contains("--qa-loop-boundary-trace") &&
            !arguments.contains("--qa-dragon-mesh-r004") &&
            !arguments.contains("--qa-dragon-mesh-pause-probe")
        #else
        return false
        #endif
    }

    init?(actorID: String, saveKey: String, outputDirectory: URL, includesFlight: Bool) {
        guard actorID == "ACT_B_R04_B" else { return nil }
        let safeKey = String(saveKey.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(80))
        guard !safeKey.isEmpty else { return nil }
        self.saveKey = safeKey
        self.outputDirectory = outputDirectory
        self.includesFlight = includesFlight
        self.usesDistalR007 = DragonDistalLegR007QA.isEnabled(arguments: ProcessInfo.processInfo.arguments)
        self.usesFourLegR064 = DragonFourLegStanceR064QA.isEnabled(arguments: ProcessInfo.processInfo.arguments)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.startedAt = formatter.string(from: Date())

        phases = [
            Phase(sequenceID: "idle-walk-idle", state: .idle, minimumDuration: 0.5, requiredWraps: 0),
            Phase(sequenceID: "idle-walk-idle", state: .walk, minimumDuration: 3.9, requiredWraps: 3),
            Phase(sequenceID: "idle-walk-idle", state: .idle, minimumDuration: 0.5, requiredWraps: 0)
        ]
        if includesFlight {
            phases += [
                Phase(sequenceID: "flight-walk-flight", state: .flight, minimumDuration: 0.5, requiredWraps: 0),
                Phase(sequenceID: "flight-walk-flight", state: .walk, minimumDuration: 3.9, requiredWraps: 3),
                Phase(sequenceID: "flight-walk-flight", state: .flight, minimumDuration: 0.5, requiredWraps: 0)
            ]
        } else {
            results.append(["sequenceID": "flight-walk-flight",
                            "status": "NOT_APPLICABLE_OR_UNAVAILABLE",
                            "reason": "ACT_B_R04_B runtime controller has no flight state"])
        }
    }

    func start(in scene: SKScene, completion: @escaping (String) -> Void) -> Action {
        self.completion = completion
        marker.name = "qa_dragon_gait_r038_marker"
        marker.fontName = "Menlo-Bold"
        marker.fontSize = 14
        marker.fontColor = .white
        marker.horizontalAlignmentMode = .left
        marker.verticalAlignmentMode = .top
        marker.position = CGPoint(x: 8, y: scene.size.height - 90)
        marker.zPosition = 1000
        let backing = SKSpriteNode(color: .black, size: CGSize(width: 245, height: 24))
        backing.anchorPoint = CGPoint(x: 0, y: 1)
        backing.position = CGPoint(x: -3, y: 3)
        backing.zPosition = -1
        marker.addChild(backing)
        marker.text = (usesFourLegR064 ? "R064" : (usesDistalR007 ? "R007" : "R038")) + " idle idle-walk-idle 0000"
        scene.addChild(marker)
        return advance(to: 0)
    }

    func sample(presentation: [String: Any], root: CGPoint, scene: SKScene,
                sceneFrame: Int) -> Action {
        guard !completed else { return .none }
        let now = ProcessInfo.processInfo.systemUptime
        let rig = presentation["partRig"] as? [String: Any] ?? [:]
        let actualState = presentation["state"] as? String ?? "none"
        let active = (usesFourLegR064 ? rig["walkFourLegR064Active"] : (usesDistalR007 ? rig["walkDistalR007Active"] : rig["walkGaitR038Active"])) as? Bool == true
        let geometryActive = (usesFourLegR064 ? rig["walkFourLegR064MountPresent"] : (usesDistalR007 ? rig["walkDistalR007MountPresent"] : rig["walkGaitR038GeometryPresent"])) as? Bool == true
        // R007 exposes a mounted-part flag, while the legacy R038 renderer
        // requires the independent actual SpriteKit warpGeometry readback.
        let geometryActuallyPresent: Bool
        if usesFourLegR064 || usesDistalR007 {
            geometryActuallyPresent = geometryActive
        } else {
            geometryActuallyPresent = rig["walkGaitR038WarpGeometryActuallyPresent"] as? Bool == true
        }
        let actionRunning = (usesFourLegR064 ? rig["walkFourLegR064ActionRunning"] : (usesDistalR007 ? rig["walkDistalR007ActionRunning"] : rig["walkGaitR038ActionRunning"])) as? Bool == true
        let overlayActive = rig["walkLegOverlayActive"] as? Bool == true
        let bodyVisible = (usesFourLegR064 ? rig["walkFourLegR064BodyVisible"] : (usesDistalR007 ? rig["walkDistalR007BodyVisible"] : rig["walkGaitR038BodyVisible"])) as? Bool == true
        let subdivision = rig["bodySubdivisionLevels"] as? Int ?? -1
        let originalSubdivision = rig["walkGaitR038OriginalSubdivisionLevels"] as? Int ?? -1
        let modeRequested = (usesFourLegR064 ? rig["walkFourLegR064Requested"] : (usesDistalR007 ? rig["walkDistalR007Requested"] : rig["walkGaitR038Requested"])) as? Bool == true
        let r064SourceMatches = !usesFourLegR064 || (rig["walkFourLegR064SourceSHA256"] as? String == DragonFourLegStanceMountR064.sourceSHA256)
        let r064PartitionExact = !usesFourLegR064 || (rig["walkFourLegR064RecompositionByteMismatchCount"] as? Int == 0)
        let modeReady = (usesFourLegR064 ? rig["walkFourLegR064Status"] : (usesDistalR007 ? rig["walkDistalR007Status"] : rig["walkGaitR038Status"])) as? String == "candidate_ready_unapproved" && r064SourceMatches && r064PartitionExact
        let bodyTextureRestored = usesFourLegR064 ? (rig["walkFourLegR064BodyTextureRestored"] as? Bool == true) : (rig["walkDistalR007BodyTextureRestored"] as? Bool == true)
        let bodyTexturePartitioned = usesFourLegR064 ? (rig["walkFourLegR064BodyCoreInstalled"] as? Bool == true) : (rig["walkDistalR007BodyTexturePartitioned"] as? Bool == true)
        let distalPivots = usesFourLegR064 ? (rig["walkFourLegR064Pivots"] as? [[String: Any]] ?? []) : (rig["walkDistalR007Pivots"] as? [[String: Any]] ?? [])
        let expectedR007IDs: Set<String> = ["left_outer_distal", "left_inner_distal", "right_inner_distal", "right_outer_distal"]
        let expectedR064IDs: Set<String> = ["fore_far", "fore_near", "hind_far", "hind_near"]
        let distalPivotIDs = Set(distalPivots.compactMap { ($0["segmentID"] ?? $0["legID"]) as? String })
        let distalPivotShapeContract: Bool
        let distalPivotDetachedContract: Bool
        let distalPivotContract: Bool
        let distalIsMoving: Bool
        if usesFourLegR064 {
            distalPivotShapeContract = distalPivots.count == 4 && distalPivots.allSatisfy { row in
                guard let upper = row["upperAttached"] as? Bool, upper,
                      let lower = row["lowerAttached"] as? Bool, lower,
                      let wrist = row["wristAttached"] as? Bool, wrist,
                      let lowerAngle = row["lowerAngleRadians"] as? Double, lowerAngle.isFinite,
                      let wristAngle = row["wristAngleRadians"] as? Double, wristAngle.isFinite,
                      let toe = row["toeBodyLocal"] as? [Double], toe.count == 2 else { return false }
                return toe.allSatisfy(\.isFinite)
            }
            distalPivotContract = distalPivotShapeContract && distalPivotIDs == expectedR064IDs
            distalPivotDetachedContract = distalPivots.count == 4 && distalPivots.allSatisfy { $0["upperAttached"] as? Bool == false && $0["lowerAttached"] as? Bool == false }
            distalIsMoving = distalPivots.contains { row in
                guard let a = row["lowerAngleRadians"] as? Double, let b = row["wristAngleRadians"] as? Double else { return false }
                return a.isFinite && b.isFinite && (abs(a) > 0.0001 || abs(b) > 0.0001)
            }
            if phaseIndex >= 0 && phases.indices.contains(phaseIndex) && phases[phaseIndex].state == .walk && actualState == "walk" && active && geometryActive && distalIsMoving {
                observedFourLegMotionRows += 1
            }
        } else {
            distalPivotShapeContract = distalPivots.count == 4 && distalPivots.allSatisfy { row in
                guard let attached = row["attached"] as? Bool, attached,
                      let rotation = row["rotationRadians"] as? Double, rotation.isFinite,
                      let position = row["position"] as? [Double], position.count == 2 else { return false }
                return position.allSatisfy(\.isFinite)
            }
            distalPivotContract = distalPivotShapeContract && distalPivotIDs == expectedR007IDs
            distalPivotDetachedContract = distalPivots.count == 4 && distalPivots.allSatisfy { $0["attached"] as? Bool == false }
            distalIsMoving = distalPivots.contains { row in
                guard let rotation = row["rotationRadians"] as? Double else { return false }
                return rotation.isFinite && abs(rotation) > 0.0001
            }
            if usesDistalR007 && phaseIndex >= 0 && phases.indices.contains(phaseIndex) && phases[phaseIndex].state == .walk && actualState == "walk" && active && geometryActive && distalIsMoving {
                observedDistalRotationRows += 1
            }
        }

        // Start the failure/cleanup path once. Subsequent samples never reset
        // the cleanup deadline, even if the triggering condition persists.
        if failureLifecycle.failureReason == nil {
            if now - startUptime > 32 {
                beginFailure("SEQUENCE_TIMEOUT", now: now)
                return .play(.idle)
            }
            if rows.count >= 2_000 {
                beginFailure("ROW_LIMIT", now: now)
                return .play(.idle)
            }
        }
        if let reason = failureLifecycle.failureReason {
            let cleanup = [
                "sceneFrame": sceneFrame, "monotonicUptime": now,
                "sequenceElapsedSeconds": now - startUptime, "actualState": actualState,
                "failureReason": reason, "cleanupDeadline": failureLifecycle.cleanupDeadline as Any? ?? NSNull(),
                "walkGaitR038Active": active, "walkGaitR038GeometryPresent": geometryActive,
                "walkGaitR038WarpGeometryActuallyPresent": geometryActuallyPresent,
                "walkGaitR038ActionRunning": actionRunning, "walkLegOverlayActive": overlayActive,
                "walkGaitR038BodyVisible": bodyVisible, "bodySubdivisionLevels": subdivision,
                "walkGaitR038OriginalSubdivisionLevels": originalSubdivision,
                "walkFourLegR064Active": rig["walkFourLegR064Active"] ?? NSNull(),
                "walkFourLegR064MountPresent": rig["walkFourLegR064MountPresent"] ?? NSNull(),
                "walkFourLegR064BodyTextureRestored": rig["walkFourLegR064BodyTextureRestored"] ?? NSNull(),
                "walkFourLegR064Pivots": rig["walkFourLegR064Pivots"] ?? NSNull(),
                "walkDistalR007Active": rig["walkDistalR007Active"] ?? NSNull(),
                "walkDistalR007MountPresent": rig["walkDistalR007MountPresent"] ?? NSNull(),
                "walkDistalR007BodyTextureRestored": bodyTextureRestored,
                "walkDistalR007ActionRunning": rig["walkDistalR007ActionRunning"] ?? NSNull(),
                "walkDistalR007Pivots": rig["walkDistalR007Pivots"] ?? NSNull()
            ] as [String: Any]
            if failureCleanupRows.count < 24 { failureCleanupRows.append(cleanup) }
            let warpClean = !active && !geometryActuallyPresent && !actionRunning && bodyVisible && !overlayActive &&
                (!(usesDistalR007 || usesFourLegR064) || (bodyTextureRestored && !bodyTexturePartitioned && distalPivotDetachedContract))
            switch failureLifecycle.evaluateCleanup(now: now, actualStateIsIdle: actualState == "idle", warpClean: warpClean) {
            case .waiting:
                return .none
            case .completed(let terminalStatus):
                finish(status: terminalStatus)
                return .finished(terminalStatus)
            }
        }
        guard phases.indices.contains(phaseIndex) else {
            return finishSequence()
        }
        let phase = phases[phaseIndex]
        let elapsed = phaseStartedAt.map { max(0, now - $0) } ?? 0
        let progress = (rig["normalizedProgress"] as? NSNumber)?.doubleValue
        let framePosition = (rig["framePosition"] as? NSNumber)?.doubleValue

        marker.text = String(format: "%@ %@ %@ %04d", usesFourLegR064 ? "R064" : (usesDistalR007 ? "R007" : "R038"), phase.sequenceID, phase.state.rawValue, rows.count)
        var row: [String: Any] = [
            "row": rows.count, "runID": runID, "saveKey": saveKey,
            "sequenceID": phase.sequenceID, "phaseIndex": phaseIndex,
            "requestedState": phase.state.rawValue, "actualState": actualState,
            "monotonicUptime": now, "sequenceElapsedSeconds": now - startUptime,
            "phaseElapsedSeconds": elapsed, "sceneFrame": sceneFrame,
            "actorRoot": [root.x, root.y], "sceneSize": [scene.size.width, scene.size.height],
            "candidateBackend": usesFourLegR064 ? "canonical_four_leg_source_masks_r064" : (usesDistalR007 ? "exact_source_distal_masks_r007" : "localized_full_texture_warp_r038"),
            "walkGaitR038Status": rig["walkGaitR038Status"] as? String ?? "missing",
            "walkGaitR038Requested": rig["walkGaitR038Requested"] as? Bool ?? false,
            "walkDistalR007Status": rig["walkDistalR007Status"] ?? NSNull(),
            "walkDistalR007Requested": rig["walkDistalR007Requested"] ?? NSNull(),
            "walkDistalR007Active": rig["walkDistalR007Active"] ?? NSNull(),
            "walkDistalR007MountPresent": rig["walkDistalR007MountPresent"] ?? NSNull(),
            "walkDistalR007BodyTexturePartitioned": bodyTexturePartitioned,
            "walkDistalR007BodyTextureRestored": bodyTextureRestored,
            "walkDistalR007ActionRunning": rig["walkDistalR007ActionRunning"] ?? NSNull(),
            "walkDistalR007SourceSHA256": rig["walkDistalR007SourceSHA256"] ?? NSNull(),
            "walkDistalR007MaskedPixelCount": rig["walkDistalR007MaskedPixelCount"] ?? NSNull(),
            "walkDistalR007JointOverlapPixelCounts": rig["walkDistalR007JointOverlapPixelCounts"] ?? NSNull(),
            "walkDistalR007Pivots": usesDistalR007 ? distalPivots : [],
            "walkFourLegR064Pivots": usesFourLegR064 ? distalPivots : [],
            "walkFourLegR064SourceSHA256": rig["walkFourLegR064SourceSHA256"] ?? NSNull(),
            "walkFourLegR064RecompositionByteMismatchCount": rig["walkFourLegR064RecompositionByteMismatchCount"] ?? NSNull(),
            "walkGaitR038Active": active, "walkGaitR038GeometryPresent": geometryActive,
            "walkGaitR038WarpGeometryActuallyPresent": geometryActuallyPresent,
            "walkGaitR038ActionRunning": actionRunning, "walkLegOverlayActive": overlayActive,
            "walkGaitR038BodyVisible": bodyVisible,
            "bodySubdivisionLevels": subdivision,
            "walkGaitR038OriginalSubdivisionLevels": originalSubdivision,
            "presentationDurationSeconds": rig["durationSeconds"] ?? NSNull(),
            "presentationFramePosition": framePosition ?? -1,
            "normalizedProgress": progress ?? -1,
            "presentation": rig
        ]
        rows.append(row)

        guard actualState == phase.state.rawValue else {
            if now - phaseRequestedAt > 1.5 {
                beginFailure("STATE_MISMATCH_\(phase.sequenceID)_\(phase.state.rawValue)_ACTUAL_\(actualState)", now: now)
                return .play(.idle)
            }
            return .none
        }
        if phaseStartedAt == nil {
            phaseStartedAt = now
            phaseStartRow = rows.count - 1
            if subdivisionBaseline == nil { subdivisionBaseline = subdivision }
            row["phaseElapsedSeconds"] = 0
            rows[rows.count - 1] = row
        }

        guard modeRequested, modeReady else {
            beginFailure(usesFourLegR064 ? "R064_CANDIDATE_NOT_READY" : (usesDistalR007 ? "R007_CANDIDATE_NOT_READY" : "R038_CANDIDATE_NOT_READY"), now: now)
            return .play(.idle)
        }
        if phase.state == .walk {
            guard active, geometryActive, geometryActuallyPresent, actionRunning,
                  bodyVisible, !overlayActive,
                  (!(usesDistalR007 || usesFourLegR064) || (bodyTexturePartitioned && distalPivotContract)),
                  let progress, progress.isFinite, (-0.001...1.001).contains(progress),
                  let framePosition, framePosition.isFinite,
                  (-0.01...12.01).contains(framePosition) else {
                beginFailure("WALK_PRESENTATION_CONTRACT", now: now)
                return .play(.idle)
            }
            if let previousWalkProgress,
               previousWalkProgress > 0.75, progress < 0.25 {
                observedWalkWraps += 1
            }
            previousWalkProgress = progress
            if elapsed >= phase.minimumDuration, observedWalkWraps >= phase.requiredWraps {
                finishPhase(phase, now: now, status: usesFourLegR064 ? "OBSERVED_R064_FOUR_LEG_PHASE_WRAPS" : (usesDistalR007 ? "OBSERVED_THREE_DISTAL_PHASE_WRAPS" : "OBSERVED_THREE_WARP_PHASE_WRAPS"))
                return advance(to: phaseIndex + 1)
            }
            if elapsed > 7.0 {
                beginFailure("WALK_PHASE_WRAP_COUNT_\(observedWalkWraps)", now: now)
                return .play(.idle)
            }
        } else {
            let restored = !active && !geometryActuallyPresent && !actionRunning &&
                bodyVisible && !overlayActive && subdivision == (subdivisionBaseline ?? originalSubdivision) &&
                (!(usesDistalR007 || usesFourLegR064) || (bodyTextureRestored && !bodyTexturePartitioned && distalPivotDetachedContract))
            guard restored else {
                beginFailure("WARP_CLEANUP_OR_STATE_EXIT", now: now)
                return .play(.idle)
            }
            if elapsed >= phase.minimumDuration {
                finishPhase(phase, now: now, status: "OBSERVED_STATE_AND_CLEANUP")
                return advance(to: phaseIndex + 1)
            }
        }
        return .none
    }

    func abort(_ reason: String) {
        guard !completed else { return }
        beginFailure(reason, now: ProcessInfo.processInfo.systemUptime)
        finish(status: "INCOMPLETE_\(reason)")
    }

    func deliverCompletionAfterRenderedFrame() {
        guard completionPending else { return }
        completionPending = false
        if markerRemovalPending { marker.removeFromParent(); markerRemovalPending = false }
        completion?(status)
        completion = nil
    }

    private func advance(to next: Int) -> Action {
        guard phases.indices.contains(next) else { return finishSequence() }
        phaseIndex = next
        phaseStartedAt = nil
        phaseRequestedAt = ProcessInfo.processInfo.systemUptime
        phaseStartRow = rows.count
        previousWalkProgress = nil
        observedWalkWraps = 0
        return .play(phases[next].state)
    }

    private func finishPhase(_ phase: Phase, now: Double, status: String) {
        results.append(["sequenceID": phase.sequenceID, "state": phase.state.rawValue,
                        "status": status, "minimumDurationSeconds": phase.minimumDuration,
                        "observedDurationSeconds": phaseStartedAt.map { max(0, now - $0) } ?? 0,
                        "requiredWraps": phase.requiredWraps, "observedWraps": observedWalkWraps,
                        "rowStart": phaseStartRow,
                        "rowEnd": max(-1, rows.count - 1)])
    }

    private func beginFailure(_ reason: String, now: Double) {
        guard failureLifecycle.beginFailure(reason, now: now) else { return }
        status = "INCOMPLETE_\(reason)"
        completionPending = false
    }

    private func finishSequence() -> Action {
        if failureLifecycle.failureReason != nil { return .play(.idle) }
        if usesFourLegR064 && observedFourLegMotionRows == 0 {
            beginFailure("R064_NO_NONZERO_JOINT_MOTION_OBSERVED", now: ProcessInfo.processInfo.systemUptime)
            return .play(.idle)
        }
        if usesDistalR007 && observedDistalRotationRows == 0 {
            beginFailure("R007_NO_NONZERO_PIVOT_ROTATION_OBSERVED", now: ProcessInfo.processInfo.systemUptime)
            return .play(.idle)
        }
        status = "CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW"
        finish(status: status)
        return .finished(status)
    }

    private func finish(status: String) {
        guard !completed,
              case .completed(let acceptedStatus)? = failureLifecycle.complete(status) else { return }
        completed = true
        self.status = acceptedStatus
        markerRemovalPending = true
        let payload: [String: Any] = [
            "schema": usesFourLegR064 ? "dragon_gait_sequence_qa_r064_r001" : (usesDistalR007 ? "dragon_gait_sequence_qa_r006" : "dragon_gait_r038_sequence_qa_r005"),
            "candidateBackend": usesFourLegR064 ? "dragon_four_leg_contact_schedule_r064_canonical_pixel_masks" : (usesDistalR007 ? "dragon_distal_leg_rig_r007_exact_runtime_source_masks" : "dragon_localized_leg_warp_r038"),
            "status": acceptedStatus, "failureReason": failureLifecycle.failureReason as Any? ?? NSNull(),
            "failureCleanupDeadline": failureLifecycle.cleanupDeadline as Any? ?? NSNull(),
            "runID": runID, "saveKey": saveKey, "actorID": actorID,
            "startedAt": startedAt, "startUptime": startUptime,
            "finishedUptime": ProcessInfo.processInfo.systemUptime,
            "candidate": usesFourLegR064 ? "UNAPPROVED_R064_CANONICAL_FOUR_LEG_MASK_ADAPTER" : (usesDistalR007 ? "UNAPPROVED_R007_EXACT_SOURCE_DISTAL_LEG_RIG" : "UNAPPROVED_R038_LOCALIZED_FULL_TEXTURE_WARP"),
            "observedFourLegMotionRowCount": observedFourLegMotionRows,
            "candidatePeriodSeconds": 1.2,
            "observedDistalRotationRowCount": observedDistalRotationRows,
            "includesFlightSequence": includesFlight,
            "flightUnavailableStatus": includesFlight ? NSNull() : "NOT_APPLICABLE_OR_UNAVAILABLE",
            "sequences": results, "rowCount": rows.count, "rows": rows,
            "failureCleanupSampleCount": failureCleanupRows.count, "failureCleanupSamples": failureCleanupRows,
            "captureContract": "didFinishUpdate samples; no pause/speed/time modification; game commands and saves are not changed",
            "visualReviewRequired": true
        ]
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputDirectory.appendingPathComponent("dragon_gait_r038_\(saveKey)_\(runID).json"), options: .atomic)
        } catch {
            self.status = "FAILED_TRACE_WRITE_\(error.localizedDescription)"
        }
        completionPending = true
    }
}
