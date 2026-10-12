import Foundation
import SpriteKit

struct EnemyLoopBoundaryMode: Codable {
    let state: String
    let presentationKind: String
    let supported: Bool
    let loops: Bool
    let frameCount: Int
    let expectedFPS: Double
    let expectedPeriodSeconds: Double
    let framePaths: [String]
    let phaseMetric: String
    let timelineBasis: String
}

/// QA-only observer for actual SpriteKit loop playback. It never changes clip
/// speed or action timing; SpriteKit's rendered frame/rig getter is sampled.
@MainActor final class EnemyLoopBoundaryTraceQA {
    enum Action {
        case none
        case play(EnemyMotionState)
        case finished(String)
    }

    let runID = UUID().uuidString
    let saveKey: String
    let requestedActorID: String
    let actorID: String
    let startedAt: String
    let startUptime = ProcessInfo.processInfo.systemUptime
    let descriptors: [EnemyLoopBoundaryMode]

    private let outputDirectory: URL
    private let marker = SKLabelNode(fontNamed: "Menlo-Bold")
    private var rows: [[String: Any]] = []
    private var modeResults: [[String: Any]] = []
    private var descriptorIndex = -1
    private var currentDescriptor: EnemyLoopBoundaryMode?
    private var currentModeStart = 0.0
    private var currentModeStartRow = 0
    private var previousSpriteFrame: Int?
    private var previousRigPhase: Int?
    private var lastRigWrapUptime = 0.0
    private var wrapCount = 0
    private var rigFingerprints: [[Double]] = []
    private var restoreIdlePending = false
    private var restoreSawIdle = false
    private var status = "RECORDING"
    private var completion: ((String) -> Void)?
    private var completed = false
    private var callbackPending = false
    private var markerRemovalPending = false

    static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if targetEnvironment(simulator)
        return arguments.contains("--qa-isolated") &&
            arguments.contains("--qa-loop-boundary-trace") &&
            arguments.contains(where: { $0.hasPrefix("--art-audit=") }) &&
            arguments.contains(where: { $0.hasPrefix("--qa-save-key=") })
        #else
        return false
        #endif
    }

    init?(requestedActorID: String, actorID: String, saveKey: String,
          outputDirectory: URL, descriptors: [EnemyLoopBoundaryMode]) {
        let safeKey = String(saveKey.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(80))
        guard !safeKey.isEmpty else { return nil }
        self.requestedActorID = requestedActorID
        self.actorID = actorID
        self.saveKey = safeKey
        self.outputDirectory = outputDirectory
        self.descriptors = descriptors
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.startedAt = formatter.string(from: Date())
    }

    func start(in scene: SKScene, completion: @escaping (String) -> Void) -> Action {
        self.completion = completion
        marker.name = "qa_enemy_loop_boundary_marker"
        marker.fontSize = 14
        marker.fontColor = .yellow
        marker.horizontalAlignmentMode = .left
        marker.verticalAlignmentMode = .top
        marker.position = CGPoint(x: 8, y: scene.size.height - 90)
        marker.zPosition = 1000
        // Isolated QA only: keep the visible identifier readable over every
        // biome so OCR can correlate encoded pixels without guessing digits.
        let backing = SKSpriteNode(color: .black, size: CGSize(width: 126, height: 24))
        backing.anchorPoint = CGPoint(x: 0, y: 1)
        backing.position = CGPoint(x: -3, y: 3)
        backing.zPosition = -1
        marker.addChild(backing)
        marker.text = "LOOP 0000"
        scene.addChild(marker)
        return advance(to: 0)
    }

    func sample(presentation: [String: Any], root: CGPoint, scene: SKScene,
                sceneFrame: Int) -> Action {
        guard !completed else { return .none }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - startUptime
        if !restoreIdlePending && (elapsed > 40 || rows.count >= 2_400) {
            status = elapsed > 40 ? "INCOMPLETE_WHOLE_TRACE_TIMEOUT" : "INCOMPLETE_ROW_LIMIT"
            if let descriptor = currentDescriptor {
                modeResults.append(["state": descriptor.state, "status": status,
                                    "wrapCount": wrapCount, "windowStartRow": currentModeStartRow,
                                    "windowEndRow": rows.count - 1])
            }
            restoreIdlePending = true
            return .play(.idle)
        }
        let sampleNumber = rows.count
        marker.text = String(format: "LOOP %04d", sampleNumber)

        let rig = presentation["partRig"] as? [String: Any] ?? [:]
        let isRig = presentation["isPartRig"] as? Bool == true
        let state = presentation["state"] as? String ?? "none"
        let requestedState = restoreIdlePending ? "idle" : (currentDescriptor?.state ?? "idle")
        let spriteFrame = (presentation["frameIndex"] as? Int) ?? -1
        let rigFrame = (rig["frameIndex"] as? Int) ?? -1
        let overlayFrame = (rig["walkLegOverlayFrameIndex"] as? Int) ?? -1
        let overlayActive = rig["walkLegOverlayActive"] as? Bool == true
        let observedOverlayFrame = overlayActive ? overlayFrame : -1
        let observedFrame = isRig ? (observedOverlayFrame >= 0 ? observedOverlayFrame : rigFrame) : spriteFrame
        let actualStateMatches = state == requestedState
        let viewOrigin = scene.view?.convert(CGPoint.zero, to: nil) ?? .zero
        let viewSize = scene.view?.bounds.size ?? .zero
        var row: [String: Any] = [
            "sequence": sampleNumber,
            "videoMarker": marker.text ?? "",
            "phase": "didFinishUpdate",
            "elapsedSeconds": elapsed,
            "modeElapsedSeconds": currentModeStart > 0 ? now - currentModeStart : 0,
            "sceneFrame": sceneFrame,
            "viewWindowOrigin": [viewOrigin.x, viewOrigin.y],
            "viewContentScale": scene.view?.contentScaleFactor ?? 0,
            "viewSize": [viewSize.width, viewSize.height],
            "sceneSize": [scene.size.width, scene.size.height],
            "activeMode": requestedState,
            "actorID": actorID,
            "root": [root.x, root.y],
            "presentation": [
                "state": state,
                "isPartRig": isRig,
                "frameIndex": observedFrame,
                "framePath": isRig ? (overlayActive ? ((rig["walkLegOverlayFramePath"] as? String) ?? "") : "") : ((presentation["framePath"] as? String) ?? ""),
                "frameIdentityApplicable": !isRig || overlayActive,
                "phaseIndex": isRig ? rigFrame : -1,
                "actionRunning": isRig ? ((rig["actionRunning"] as? Bool) ?? false) : true,
                "partRig": rig
            ]
        ]
        // Preserve isolated R050 diagnostics from the exact didFinishUpdate
        // snapshot. The observer must not infer a logical step from identical
        // visual poses or resample the node after this frame was recorded.
        if let moth = presentation["qaMothIdleRegistration"] as? [String: Any],
           var observed = row["presentation"] as? [String: Any] {
            observed["qaMothIdleRegistration"] = moth
            row["presentation"] = observed
        }
        if let descriptor = currentDescriptor {
            row["expectedPresentationKind"] = descriptor.presentationKind
            row["phaseMetric"] = descriptor.phaseMetric
            row["timelineBasis"] = descriptor.timelineBasis
        }
        rows.append(row)

        if restoreIdlePending {
            if actualStateMatches && (!isRig || (rig["actionRunning"] as? Bool == true)) {
                restoreSawIdle = true
                let finalStatus = status == "RECORDING"
                    ? (modeResults.contains(where: { ($0["status"] as? String) == "OBSERVED_TWO_LOOP_BOUNDARIES" })
                        ? "CAPTURED_REQUIRES_HOST_VALIDATION" : "INCONCLUSIVE_NO_LOOP_CAPTURE")
                    : status
                finish(status: finalStatus)
                return .finished(finalStatus)
            }
            if elapsed > 3 {
                status = "INCOMPLETE_IDLE_RESTORE_TIMEOUT"
                finish(status: status)
                return .finished(status)
            }
            return .none
        }

        guard currentDescriptor != nil, actualStateMatches else {
            if now - startUptime > 3, currentDescriptor != nil {
                status = "INCOMPLETE_PRESENTATION_STATE_MISMATCH"
                finish(status: status)
                return .finished(status)
            }
            return .none
        }

        if isRig && currentDescriptor!.presentationKind == "part_rig_leg_overlay" {
            guard overlayActive, overlayFrame >= 0 else { return timeoutIfNeeded(now: now) }
            if let previousSpriteFrame,
               previousSpriteFrame == currentDescriptor!.frameCount - 1, overlayFrame == 0 {
                wrapCount += 1
                lastRigWrapUptime = now
            }
            previousSpriteFrame = overlayFrame
        } else if isRig {
            let running = rig["actionRunning"] as? Bool == true
            guard running else { return timeoutIfNeeded(now: now) }
            let phaseIndex = (rig["frameIndex"] as? Int) ?? -1
            if phaseIndex >= 0 {
                if let previousRigPhase, previousRigPhase >= currentDescriptor!.frameCount - 1, phaseIndex == 0 {
                    wrapCount += 1
                    lastRigWrapUptime = now
                }
                previousRigPhase = phaseIndex
            } else {
                let fingerprint = rigFingerprint(rig["walkMeshReadback"] as? [String: Any])
                if let fingerprint {
                    if rigFingerprints.isEmpty { rigFingerprints.append(fingerprint) }
                    else if now - currentModeStart >= currentDescriptor!.expectedPeriodSeconds * 0.8,
                            now - lastRigWrapUptime >= currentDescriptor!.expectedPeriodSeconds * 0.8,
                            distance(fingerprint, rigFingerprints[0]) <= 0.002 {
                        wrapCount += 1
                        lastRigWrapUptime = now
                    }
                    if rigFingerprints.count < 64 { rigFingerprints.append(fingerprint) }
                }
            }
        } else {
            guard spriteFrame >= 0 else { return timeoutIfNeeded(now: now) }
            if let previousSpriteFrame,
               previousSpriteFrame == currentDescriptor!.frameCount - 1, spriteFrame == 0 {
                wrapCount += 1
                lastRigWrapUptime = now
            }
            previousSpriteFrame = spriteFrame
        }

        let modeElapsed = now - currentModeStart
        let requiredDuration = currentDescriptor!.expectedPeriodSeconds * 2 + 0.3
        if wrapCount >= 2 && modeElapsed >= requiredDuration {
            let completedResult: [String: Any] = [
                "state": currentDescriptor!.state,
                "presentationKind": currentDescriptor!.presentationKind,
                "loops": true,
                "frameCount": currentDescriptor!.frameCount,
                "expectedFPS": currentDescriptor!.expectedFPS,
                "expectedPeriodSeconds": currentDescriptor!.expectedPeriodSeconds,
                "framePaths": currentDescriptor!.framePaths,
                "phaseMetric": currentDescriptor!.phaseMetric,
                "timelineBasis": currentDescriptor!.timelineBasis,
                "windowStartRow": currentModeStartRow,
                "windowEndRow": rows.count - 1,
                "windowStartElapsedSeconds": currentModeStart - startUptime,
                "windowEndElapsedSeconds": elapsed,
                "observedDurationSeconds": modeElapsed,
                "wrapCount": wrapCount,
                "status": "OBSERVED_TWO_LOOP_BOUNDARIES"
            ]
            modeResults.append(completedResult)
            return advance(to: descriptorIndex + 1)
        }
        return timeoutIfNeeded(now: now)
    }

    private func timeoutIfNeeded(now: Double) -> Action {
        guard let descriptor = currentDescriptor else { return advance(to: descriptorIndex + 1) }
        let timeout = min(12, max(3, descriptor.expectedPeriodSeconds * 2 + 4))
        guard now - currentModeStart > timeout else { return .none }
        modeResults.append(["state": descriptor.state, "status": "INCOMPLETE_LOOP_TIMEOUT",
                            "wrapCount": wrapCount, "expectedPeriodSeconds": descriptor.expectedPeriodSeconds,
                            "windowStartRow": currentModeStartRow, "windowEndRow": rows.count - 1])
        status = "INCOMPLETE_LOOP_TIMEOUT"
        restoreIdlePending = true
        return .play(.idle)
    }

    private func advance(to index: Int) -> Action {
        descriptorIndex = index
        previousSpriteFrame = nil
        previousRigPhase = nil
        rigFingerprints.removeAll(keepingCapacity: true)
        wrapCount = 0
        lastRigWrapUptime = 0
        while descriptorIndex < descriptors.count {
            let descriptor = descriptors[descriptorIndex]
            let reason: String? = !descriptor.supported ? "UNSUPPORTED_STATE" :
                descriptor.frameCount <= 1 ? "NOT_ANIMATED" :
                !descriptor.loops ? "NOT_LOOPING" :
                !descriptor.expectedFPS.isFinite || descriptor.expectedFPS <= 0 ||
                !descriptor.expectedPeriodSeconds.isFinite || descriptor.expectedPeriodSeconds <= 0 ? "INVALID_LOOP_METADATA" : nil
            if let reason {
                modeResults.append(["state": descriptor.state, "presentationKind": descriptor.presentationKind,
                                    "loops": descriptor.loops, "frameCount": descriptor.frameCount,
                                    "expectedFPS": descriptor.expectedFPS, "expectedPeriodSeconds": descriptor.expectedPeriodSeconds,
                                    "framePaths": descriptor.framePaths, "phaseMetric": descriptor.phaseMetric,
                                    "timelineBasis": descriptor.timelineBasis,
                                    "status": reason])
                descriptorIndex += 1
                continue
            }
            currentDescriptor = descriptor
            currentModeStart = ProcessInfo.processInfo.systemUptime
            currentModeStartRow = rows.count
            return .play(EnemyMotionState(rawValue: descriptor.state) ?? .idle)
        }
        currentDescriptor = nil
        restoreIdlePending = true
        return .play(.idle)
    }

    func restoredIdleFrameObserved() -> Bool { restoreSawIdle }

    func abort(_ reason: String) {
        status = reason
        finish(status: reason)
    }

    func deliverCompletionAfterRenderedFrame() {
        guard callbackPending else { return }
        callbackPending = false
        if markerRemovalPending { marker.removeFromParent(); markerRemovalPending = false }
        completion?(status)
        completion = nil
    }

    private func finish(status: String) {
        guard !completed else { return }
        completed = true
        self.status = status
        markerRemovalPending = true
        let payload: [String: Any] = [
            "schema": "enemy_loop_boundary_trace_r001",
            "status": status,
            "saveKey": saveKey,
            "runID": runID,
            "actorID": actorID,
            "requestedActorID": requestedActorID,
            "startedAt": startedAt,
            "startUptime": startUptime,
            "finishedUptime": ProcessInfo.processInfo.systemUptime,
            "modes": modeResults,
            "activeMode": currentDescriptor?.state ?? "idle_restore",
            "rows": rows,
            "rowCount": rows.count,
            "markerContract": "LOOP %04d at scene coordinate (8, scene.height - 90); sequence matches row number",
            "captureContract": "didFinishUpdate observations of current presentation getters; no clip speed modification",
            "rigIdentityContract": "PartRig telemetry is phase/action/readback, not sprite-frame identity"
        ]
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let name = "loop_boundary_\(saveKey)_\(runID).json"
            try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
        } catch {
            self.status = "FAILED_TRACE_WRITE: \(error.localizedDescription)"
        }
        callbackPending = true
    }

    private func rigFingerprint(_ value: [String: Any]?) -> [Double]? {
        guard let value, let vertices = value["sampledLowerVertices"] as? [[String: Any]], !vertices.isEmpty else { return nil }
        var result: [Double] = []
        for vertex in vertices {
            guard let delta = vertex["deltaArtworkPixels"] as? [NSNumber], delta.count == 2 else { return nil }
            result.append(delta[0].doubleValue); result.append(delta[1].doubleValue)
        }
        return result
    }

    private func distance(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        return zip(lhs, rhs).map { pair in abs(pair.0 - pair.1) }.max() ?? .infinity
    }
}
