import Foundation
import SpriteKit

/// Isolated renderer sequence for a single ACT_E_R02_03 instance. The trace
/// records the same didFinishUpdate snapshot used by the renderer and a visible
/// marker that can be joined to the original native video; it does not mutate
/// game data or claim natural-motion acceptance.
@MainActor final class JellyfishMeshSequenceQAR137 {
    enum Action { case none, play(EnemyMotionState), finished(String) }
    private enum Stage: String {
        case initialIdle, firstMeshWalk, interstitialIdle, executeRecover, secondMeshWalk, resolve, terminal
    }

    static let requiredActorID = "ACT_E_R02_03"
    static let flag = "--qa-jelly-sequence-r137"
    let runID = UUID().uuidString
    let saveKey: String
    let actorID: String
    let sceneGeneration: Int
    private let outputDirectory: URL
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let marker = SKLabelNode(fontNamed: "Menlo-Bold")
    private var rows: [[String: Any]] = []
    private var stage: Stage = .initialIdle
    private var stageStart = 0.0
    private var sawExecute = false
    private var sawRecover = false
    private var previousWrapCount = 0
    private var status = "RECORDING"
    private var completion: ((String) -> Void)?
    private var completionPending = false
    private var markerRemovalPending = false
    private var markerRemovalAwaitingRenderedUpdate = false
    private var completed = false

    static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                            actorID: String) -> Bool {
        #if targetEnvironment(simulator)
        return arguments.contains("--qa-isolated") &&
            arguments.filter { $0 == "--qa-jelly-mesh-r135" }.count == 1 &&
            arguments.filter { $0 == flag }.count == 1 &&
            arguments.filter { $0 == "--art-audit=\(requiredActorID)" }.count == 1 &&
            actorID == requiredActorID &&
            arguments.filter { $0.hasPrefix("--qa-save-key=") }.count == 1
        #else
        return false
        #endif
    }

    init?(actorID: String, saveKey: String, sceneGeneration: Int, outputDirectory: URL) {
        let safe = String(saveKey.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(80))
        guard actorID == Self.requiredActorID, !safe.isEmpty else { return nil }
        self.actorID = actorID
        self.saveKey = safe
        self.sceneGeneration = sceneGeneration
        self.outputDirectory = outputDirectory
    }

    func start(in scene: SKScene, completion: @escaping (String) -> Void) -> Action {
        self.completion = completion
        marker.name = "qa_jelly_mesh_r137_marker"
        marker.fontSize = 14
        marker.fontColor = .yellow
        marker.horizontalAlignmentMode = .left
        marker.verticalAlignmentMode = .top
        marker.position = CGPoint(x: 8, y: scene.size.height - 90)
        marker.zPosition = 10_000
        let backing = SKSpriteNode(color: .black, size: CGSize(width: 154, height: 24))
        backing.anchorPoint = CGPoint(x: 0, y: 1)
        backing.position = CGPoint(x: -3, y: 3)
        backing.zPosition = -1
        marker.addChild(backing)
        marker.text = "J137 0000"
        scene.addChild(marker)
        stageStart = ProcessInfo.processInfo.systemUptime
        return .play(.idle)
    }

    func sample(presentation: [String: Any], motion: EnemyMotionController,
                scene: SKScene, sceneFrame: Int, currentSceneGeneration: Int) -> Action {
        guard !completed else { return .none }
        let now = ProcessInfo.processInfo.systemUptime
        func fail(_ reason: String) -> Action {
            motion.stop()
            return finish(reason)
        }
        if currentSceneGeneration != sceneGeneration {
            return fail("INCOMPLETE_SCENE_REBUILT")
        }
        if now - startedAt > 24 || rows.count >= 1_400 {
            return fail(now - startedAt > 24 ? "INCOMPLETE_SEQUENCE_TIMEOUT" : "INCOMPLETE_ROW_LIMIT")
        }
        marker.text = String(format: "J137 %04d", rows.count)
        let jelly = presentation["qaJellyMeshR135"] as? [String: Any] ?? [:]
        let phase = jelly["phase"] as? Double ?? -1
        let frameIndex = jelly["frameIndex"] as? Int ?? -1
        let wraps = jelly["observedWrapCount"] as? Int ?? 0
        let root = motion.node.position
        let viewOrigin: CGPoint = scene.view?.convert(CGPoint.zero, to: nil) ?? CGPoint.zero
        let viewSize: CGSize = scene.view?.bounds.size ?? CGSize.zero
        var row: [String: Any] = [
            "sequence": rows.count,
            "videoMarker": marker.text ?? "",
            "samplePhase": "didFinishUpdate_after_actions_before_render",
            "elapsedSeconds": now - startedAt,
            "stage": stage.rawValue,
            "stageElapsedSeconds": now - stageStart,
            "sceneFrame": sceneFrame,
            "sceneGeneration": currentSceneGeneration,
            "actorID": actorID,
            "nodeAttachedToScene": motion.node.parent === scene,
            "nodeVisible": !motion.node.isHidden && motion.node.alpha > 0,
            "nodeAlpha": motion.node.alpha,
            "root": [root.x, root.y],
            "viewOrigin": [viewOrigin.x, viewOrigin.y],
            "viewSize": [viewSize.width, viewSize.height],
            "sceneSize": [scene.size.width, scene.size.height],
            "motionState": motion.currentMotionState?.rawValue ?? "none",
            "presentation": presentation
        ]
        let candidatePhase: [String: Any] = ["phase": phase, "frameIndex": frameIndex,
                               "wrapCount": wraps,
                               "actionRunning": jelly["candidateActionRunning"] as? Bool == true,
                               "gridColumns": jelly["actualGridColumns"] as? Int ?? 0,
                               "gridRows": jelly["actualGridRows"] as? Int ?? 0,
                               "sourceTextureSHA256": jelly["sourceTextureSHA256"] as? String ?? "",
                               "sourceTextureIdentityMatches": jelly["sourceTextureIdentityMatches"] as? Bool == true,
                               "reason": jelly["reason"] as? String ?? ""]
        row["candidatePhase"] = candidatePhase
        rows.append(row)

        let state = motion.currentMotionState
        if state == .execute { sawExecute = true }
        if sawExecute && state == .recover { sawRecover = true }
        switch stage {
        case .initialIdle:
            guard state == .idle else { return timedMismatch(now, "idle", motion: motion) }
            if now - stageStart >= 0.35 { stage = .firstMeshWalk; stageStart = now; return .play(.walk) }
        case .firstMeshWalk:
            guard state == .walk else { return timedMismatch(now, "mesh_walk", motion: motion) }
            guard jelly["applied"] as? Bool == true,
                  jelly["candidateID"] as? String == JellyfishMeshRigR135QA.candidateID,
                  jelly["sourceTextureIdentityMatches"] as? Bool == true,
                  jelly["actualGridColumns"] as? Int == 24,
                  jelly["actualGridRows"] as? Int == 24,
                  jelly["actualGridVertexCount"] as? Int == 625,
                  jelly["actualGridFingerprint"] as? String == jelly["geometryFingerprint"] as? String,
                  jelly["actualGridMatchesExpectedFingerprint"] as? Bool == true,
                  jelly["subdivisionLevelsMatchesOriginal"] as? Bool == true,
                  (0..<12).contains(frameIndex), phase >= 0, phase < 1,
                  (jelly["geometryFingerprint"] as? String)?.count == 64,
                  jelly["candidateActionRunning"] as? Bool == true else {
                return fail("INCOMPLETE_MESH_CANDIDATE_NOT_ACTIVE")
            }
            if wraps >= 3 && wraps > previousWrapCount {
                previousWrapCount = wraps
                stage = .interstitialIdle; stageStart = now
                return .play(.idle)
            }
            previousWrapCount = max(previousWrapCount, wraps)
        case .interstitialIdle:
            guard state == .idle,
                  jelly["applied"] as? Bool != true,
                  jelly["geometryPresent"] as? Bool != true,
                  jelly["catalogWalkGeometryRestored"] as? Bool == true,
                  jelly["subdivisionLevelsRestored"] as? Bool == true,
                  jelly["candidateActionRunning"] as? Bool != true else {
                return fail("INCOMPLETE_WARP_NOT_CLEARED_AFTER_FIRST_WALK")
            }
            if now - stageStart >= 0.3 { stage = .executeRecover; stageStart = now; return .play(.execute) }
        case .executeRecover:
            if sawExecute && sawRecover && state == .idle {
                stage = .secondMeshWalk; stageStart = now; previousWrapCount = 0
                return .play(.walk)
            }
            if now - stageStart > 6 { return fail("INCOMPLETE_EXECUTE_RECOVER_NOT_OBSERVED") }
        case .secondMeshWalk:
            guard state == .walk else { return timedMismatch(now, "second_mesh_walk", motion: motion) }
            guard jelly["applied"] as? Bool == true,
                  jelly["sourceTextureIdentityMatches"] as? Bool == true,
                  jelly["actualGridMatchesExpectedFingerprint"] as? Bool == true,
                  jelly["subdivisionLevelsMatchesOriginal"] as? Bool == true,
                  (jelly["observedWrapCount"] as? Int ?? 0) >= 1 else { return .none }
            stage = .resolve; stageStart = now
            return .play(.resolve)
        case .resolve:
            if state == .resolve,
               jelly["applied"] as? Bool != true,
               jelly["geometryPresent"] as? Bool != true,
               jelly["catalogWalkGeometryRestored"] as? Bool == true,
               jelly["subdivisionLevelsRestored"] as? Bool == true,
               jelly["candidateActionRunning"] as? Bool != true,
               presentation["spriteActionRunning"] as? Bool == false {
                return finish("CAPTURED_REQUIRES_HOST_AND_VIDEO_VALIDATION")
            }
            if now - stageStart > 5 { return fail("INCOMPLETE_RESOLVE_OR_CLEANUP") }
        case .terminal:
            return .none
        }
        return .none
    }

    func deliverCompletionAfterRenderedFrame() {
        guard completionPending, !completed, !markerRemovalPending else { return }
        completionPending = false
        completed = true
        marker.removeFromParent()
        markerRemovalPending = true
    }

    func deliverCompletionAfterMarkerRemoval() {
        guard markerRemovalPending else { return }
        guard markerRemovalAwaitingRenderedUpdate else {
            // This first call shares the didFinishUpdate callback that removed
            // the marker. Wait for the next callback, after a marker-free frame
            // had an opportunity to render, before resuming the native driver.
            markerRemovalAwaitingRenderedUpdate = true
            return
        }
        markerRemovalPending = false
        completion?(status)
        completion = nil
    }

    func abort(_ reason: String) {
        _ = finish(reason)
        guard !completed else { return }
        marker.removeFromParent()
        completionPending = false
        completed = true
        completion?(status)
        completion = nil
    }

    private func timedMismatch(_ now: Double, _ expected: String, motion: EnemyMotionController) -> Action {
        if now - stageStart > 2 {
            motion.stop()
            return finish("INCOMPLETE_EXPECTED_\(expected.uppercased())")
        }
        return .none
    }

    private func finish(_ newStatus: String) -> Action {
        guard !completed, !completionPending else { return .none }
        status = newStatus
        stage = .terminal
        let payload: [String: Any] = [
            "schema": "jellyfish-mesh-sequence-r137-v1",
            "status": status,
            "runID": runID,
            "saveKey": saveKey,
            "actorID": actorID,
            "candidateID": JellyfishMeshRigR135QA.candidateID,
            "formalArtAdoption": false,
            "startedUptime": startedAt,
            "finishedUptime": ProcessInfo.processInfo.systemUptime,
            "rowCount": rows.count,
            "rows": rows
        ]
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let url = outputDirectory.appendingPathComponent("jelly_mesh_sequence_r137_\(saveKey)_\(runID).json")
            var receipt = payload
            receipt["completion"] = [
                "saveFilename": url.lastPathComponent,
                "processID": ProcessInfo.processInfo.processIdentifier,
                "saveKey": saveKey
            ]
            let receiptBytes = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
            try receiptBytes.write(to: url, options: [.atomic])
            completionPending = true
        } catch {
            status = "INCOMPLETE_TRACE_WRITE_FAILED_\(String(reflecting: error))"
            completionPending = true
        }
        return .none
    }
}
