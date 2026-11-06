import Foundation
import SpriteKit

/// QA-only observer for the already-running ERNA walk action. It never drives
/// the walk or changes its timing. R002 keeps the marker alive through an
/// observed idle restoration before it writes a terminal PASS status.
@MainActor final class ERNAStaffWalkCycleTraceQA_R002 {
    enum Directive: Equatable { case continueObserving, restoreIdle, finished }
    private enum Stage { case walking, completionMarker, restoreActionPending, verifyIdle, idleMarker, done }

    static let schema = "erna-staff-walk-cycle-trace-r002"
    static let rowLimit = 720
    static let timeoutSeconds: TimeInterval = 8.0
    static let idleCleanupTimeoutSeconds: TimeInterval = 1.5

    private weak var scene: SKScene?
    private let request: ERNAStaffWalkCycleRequestR002
    private let outputURL: URL
    private let expectedAssetIDs: [String]
    private let expectedIdleAssetIDs: [String]
    private let startedAt = ISO8601DateFormatter().string(from: Date())
    private let startedUptime = ProcessInfo.processInfo.systemUptime
    private let sceneGeneration: Int
    private var coverage: ERNAWalkCycleCoverageR002
    private var rows: [[String: Any]] = []
    private var marker: SKNode?
    private var flushed = false
    private var stage: Stage = .walking
    private var terminalStatus: String?
    private var completionReason: String?
    private var cleanupStartedUptime: TimeInterval?
    private var restorationSnapshot: [String: Any]?
    private var lastRestorationSnapshot: [String: Any]?
    private var restorationChecks: [String: Bool] = [:]

    init(scene: SKScene, request: ERNAStaffWalkCycleRequestR002,
         outputDirectory: URL, sceneGeneration: Int,
         expectedAssetIDs: [String], expectedIdleAssetIDs: [String]) {
        self.scene = scene
        self.request = request
        self.outputURL = outputDirectory.appendingPathComponent("erna_walk_cycle_\(request.saveKey)_\(UUID().uuidString.lowercased()).json")
        self.expectedAssetIDs = expectedAssetIDs
        self.expectedIdleAssetIDs = expectedIdleAssetIDs
        self.sceneGeneration = sceneGeneration
        self.coverage = ERNAWalkCycleCoverageR002(expectedAssetIDs: expectedAssetIDs, requiredWraps: 3)
        rows.reserveCapacity(360)
        attachMarker(on: scene)
    }

    private func attachMarker(on scene: SKScene) {
        let group = SKNode(); group.name = "qa_erna_walk_cycle_marker"; group.zPosition = 20_001
        let backing = SKShapeNode(rectOf: CGSize(width: 188, height: 28), cornerRadius: 3)
        backing.name = "qa_erna_walk_cycle_marker_back"
        backing.fillColor = .black.withAlphaComponent(0.9); backing.strokeColor = .white.withAlphaComponent(0.9); backing.lineWidth = 1
        group.addChild(backing)
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = "qa_erna_walk_cycle_marker_text"; label.fontSize = 13; label.fontColor = .white
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        label.text = "ERNA WALK ARMING"; group.addChild(label)
        group.position = CGPoint(x: 112, y: scene.size.height - 72)
        scene.addChild(group); marker = group
    }

    /// Called exactly once per didFinishUpdate. `restoreIdle` asks the caller
    /// to stop walk and request idle; `finished` is returned only after a
    /// distinct rendered idle sample and one additional marker-present frame.
    func sample(bodyState: [String: Any], staff: [String: Any],
                sceneFrame: Int, sceneTime: TimeInterval, sceneClock: TimeInterval,
                currentGeneration: Int, scene currentScene: SKScene) -> Directive {
        guard !flushed else { return .finished }
        if currentGeneration != sceneGeneration || marker?.parent !== currentScene {
            completionReason = "scene_generation_or_marker_changed_before_idle_restore"
            flush(status: "INCOMPLETE_SCENE_REBUILT", currentGeneration: currentGeneration)
            return .finished
        }

        switch stage {
        case .walking:
            if ProcessInfo.processInfo.systemUptime - startedUptime > Self.timeoutSeconds {
                beginCleanup(status: "INCOMPLETE_TIMEOUT", reason: "three_complete_walk_wraps_not_observed_before_timeout")
                return .continueObserving
            }
            if rows.count >= Self.rowLimit {
                beginCleanup(status: "INCOMPLETE_ROW_LIMIT", reason: "trace_row_limit_reached_before_idle_cleanup")
                return .continueObserving
            }
            let index = bodyState["bodyFrameIndex"] as? Int ?? -1
            let asset = bodyState["bodyAssetID"] as? String ?? ""
            let staffIndex = staff["bodyFrameIndex"] as? Int ?? -1
            let staffAsset = staff["bodyAssetID"] as? String ?? ""
            let active = bodyState["activePartyWalkAction"] as? Bool == true && staff["activeWalkAction"] as? Bool == true
            let outcome = coverage.observe(sceneFrame: sceneFrame, sceneTime: sceneTime,
                                           frameIndex: index, bodyAssetID: asset,
                                           activeWalkAction: active,
                                           staffFrameIndex: staffIndex, staffBodyAssetID: staffAsset)
            let sequence = rows.count
            let label = marker?.childNode(withName: "qa_erna_walk_cycle_marker_text") as? SKLabelNode
            label?.text = String(format: "ERNA WALK %04d", sequence)
            var row: [String: Any] = [
                "sequence": sequence, "phase": "didFinishUpdate", "sceneFrame": sceneFrame,
                "sceneTime": sceneTime, "sceneClock": sceneClock,
                "uptime": ProcessInfo.processInfo.systemUptime,
                "sceneGeneration": currentGeneration,
                "videoMarker": String(format: "ERNA WALK %04d", sequence),
                // This is attachment evidence only. OCR/video join is separate.
                "videoMarkerAttached": marker?.parent === currentScene,
                "actorID": "ERNA", "poseState": bodyState["poseState"] as? String ?? "",
                "activePartyWalkAction": bodyState["activePartyWalkAction"] as? Bool ?? false,
                "bodyAssetID": asset, "bodyFrameIndex": index, "bodyCanvasPx": bodyState["bodyCanvas"] as Any? ?? NSNull(),
                "staffActiveWalkAction": staff["activeWalkAction"] as? Bool ?? false,
                "staffBodyAssetID": staffAsset, "staffBodyFrameIndex": staffIndex,
                "costume": staff["costume"] as? String ?? "",
                "selectedGearID": staff["selectedGearID"] as? String ?? "",
                "selectedStaffAssetID": staff["selectedStaffAssetID"] as? String ?? "",
                "staff": staff, "coverageOutcome": String(describing: outcome)
            ]
            row["assetPathMatchesObservedIndex"] = index >= 0 && index < expectedAssetIDs.count && expectedAssetIDs[index] == asset
            row["sameFrameStaffBinding"] = staffIndex == index && staffAsset == asset
            rows.append(row)
            switch outcome {
            case .complete:
                beginCleanup(status: "CAPTURED_THREE_COMPLETE_WALK_CYCLES", reason: "three_ordered_wraps_and_all_nine_indices_observed")
                stage = .completionMarker
            case .failed(let reason):
                beginCleanup(status: "FAIL_WALK_COVERAGE", reason: reason)
            default: break
            }
            return .continueObserving

        case .completionMarker:
            marker?.childNode(withName: "qa_erna_walk_cycle_marker_text")?.isHidden = false
            (marker?.childNode(withName: "qa_erna_walk_cycle_marker_text") as? SKLabelNode)?.text = "ERNA WALK RESTORE IDLE"
            stage = .restoreActionPending
            return .continueObserving

        case .restoreActionPending:
            cleanupStartedUptime = ProcessInfo.processInfo.systemUptime
            stage = .verifyIdle
            (marker?.childNode(withName: "qa_erna_walk_cycle_marker_text") as? SKLabelNode)?.text = "ERNA WALK RESTORE IDLE"
            return .restoreIdle

        case .verifyIdle:
            let snapshot = makeRestorationSnapshot(bodyState: bodyState, staff: staff,
                                                   sceneFrame: sceneFrame, sceneTime: sceneTime,
                                                   sceneClock: sceneClock, generation: currentGeneration,
                                                   markerAttached: marker?.parent === currentScene)
            lastRestorationSnapshot = snapshot
            let checks = snapshot["checks"] as? [String: Bool] ?? [:]
            restorationChecks = checks
            if !checks.isEmpty && checks.values.allSatisfy({ $0 }) {
                restorationSnapshot = snapshot
                (marker?.childNode(withName: "qa_erna_walk_cycle_marker_text") as? SKLabelNode)?.text = "ERNA IDLE RESTORED"
                stage = .idleMarker
                return .continueObserving
            }
            if let cleanupStartedUptime,
               ProcessInfo.processInfo.systemUptime - cleanupStartedUptime > Self.idleCleanupTimeoutSeconds {
                terminalStatus = "INCOMPLETE_IDLE_RESTORE_TIMEOUT"
                completionReason = "idle_pose_and_staff_binding_not_observed_within_cleanup_deadline"
                flush(status: terminalStatus ?? "INCOMPLETE_IDLE_RESTORE_TIMEOUT", currentGeneration: currentGeneration)
                return .finished
            }
            (marker?.childNode(withName: "qa_erna_walk_cycle_marker_text") as? SKLabelNode)?.text = "ERNA RESTORING IDLE"
            return .continueObserving

        case .idleMarker:
            flush(status: terminalStatus ?? "INCOMPLETE_TERMINAL_STATUS_MISSING", currentGeneration: currentGeneration)
            return .finished

        case .done:
            return .finished
        }
    }

    func abort(reason: String, currentGeneration: Int) {
        guard !flushed else { return }
        completionReason = reason
        flush(status: "INCOMPLETE_" + reason, currentGeneration: currentGeneration)
    }

    private func beginCleanup(status: String, reason: String) {
        terminalStatus = status
        completionReason = reason
        stage = .restoreActionPending
    }

    private func makeRestorationSnapshot(bodyState: [String: Any], staff: [String: Any],
                                         sceneFrame: Int, sceneTime: TimeInterval, sceneClock: TimeInterval,
                                         generation: Int, markerAttached: Bool) -> [String: Any] {
        let pose = bodyState["poseState"] as? String ?? ""
        let bodyIndex = bodyState["bodyFrameIndex"] as? Int ?? -1
        let bodyAsset = bodyState["bodyAssetID"] as? String ?? ""
        let staffIndex = staff["bodyFrameIndex"] as? Int ?? -1
        let staffAsset = staff["bodyAssetID"] as? String ?? ""
        let expectedStaffID = "STAFF_\(request.gearID)"
        let checks: [String: Bool] = [
            "actorIsERNA": bodyState["actorID"] as? String == "ERNA",
            "poseIsIdle": pose == "idle",
            "outerWalkActionInactive": bodyState["activePartyWalkAction"] as? Bool == false,
            "nestedWalkActionInactive": staff["activeWalkAction"] as? Bool == false,
            "idleBodyAssetMatchesManifest": bodyAsset.isEmpty == false && expectedIdleAssetIDs.contains(bodyAsset),
            "sameFrameStaffBinding": staffIndex == bodyIndex && staffAsset == bodyAsset,
            "gearMatchesCase": staff["selectedGearID"] as? String == request.gearID,
            "costumeMatchesCase": staff["costume"] as? String == request.costume,
            "staffTextureMatchesCase": staff["selectedStaffAssetID"] as? String == expectedStaffID,
            "weaponNodeVisible": staff["weaponNodeExists"] as? Bool == true && staff["weaponHidden"] as? Bool == false,
            "handMaskVisibleAndAssigned": staff["handMaskExists"] as? Bool == true && staff["handMaskHidden"] as? Bool == false && staff["handMaskAssignedToCrop"] as? Bool == true,
            "markerAttachedForRestoreFrame": markerAttached
        ]
        return ["phase": "restorationSnapshot", "sceneFrame": sceneFrame, "sceneTime": sceneTime,
                "sceneClock": sceneClock, "uptime": ProcessInfo.processInfo.systemUptime,
                "sceneGeneration": generation, "actorID": "ERNA", "poseState": pose,
                "bodyAssetID": bodyAsset, "bodyFrameIndex": bodyIndex,
                "activePartyWalkAction": bodyState["activePartyWalkAction"] as Any? ?? NSNull(),
                "staff": staff, "checks": checks, "passed": checks.values.allSatisfy({ $0 })]
    }

    private func flush(status: String, currentGeneration: Int) {
        guard !flushed else { return }
        flushed = true; stage = .done
        marker?.removeFromParent(); marker = nil
        let payload: [String: Any] = [
            "schema": Self.schema, "status": status,
            "runID": outputURL.deletingPathExtension().lastPathComponent,
            "saveKey": request.saveKey, "fixture": request.fixture,
            "gearID": request.gearID, "costume": request.costume, "actorID": "ERNA",
            "startedAt": startedAt, "startedUptime": startedUptime,
            "finishedUptime": ProcessInfo.processInfo.systemUptime,
            "sceneGenerationAtStart": sceneGeneration, "sceneGenerationAtFinish": currentGeneration,
            "completionReason": completionReason as Any? ?? NSNull(),
            "requiredWraps": 3, "expectedFrameCount": 9,
            "expectedFrameAssetIDs": expectedAssetIDs, "expectedIdleAssetIDs": expectedIdleAssetIDs,
            "observedDistinctFrameIndices": coverage.uniqueIndices.sorted(),
            "observedWrapCount": coverage.wraps,
            "coverageOutcome": String(describing: coverage.outcome),
            "rowCount": rows.count, "rowLimit": Self.rowLimit,
            "restorationRequested": terminalStatus != nil,
            "restorationSnapshot": restorationSnapshot as Any? ?? NSNull(),
            "lastRestorationSnapshot": lastRestorationSnapshot as Any? ?? NSNull(),
            "restorationChecks": restorationChecks,
            "restorationVerified": restorationSnapshot != nil,
            "sceneClockOrClipDurationWasChanged": false, "battleStarted": false,
            "fixtureSetupPersistedBeforeObservation": true, "saveMutationDuringObservationRequested": false,
            "rows": rows
        ]
        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: outputURL, options: .atomic)
        } catch { print("ERNAStaffWalkCycleTraceQA_R002 write failed: \(error)") }
    }
}
