import Foundation
import SpriteKit

/// Isolated full-battle observer for ERNA's five weapon fixtures.
/// It records the existing rendered scene only; it does not schedule or alter actions.
@MainActor final class ERNAStaffMotionTraceQA_R040 {
    static let schema = "erna-staff-motion-trace-r040"
    static let rowLimit = 5_400

    private weak var scene: SKScene?
    private let request: ERNAStaffMotionTraceRequestR040
    private let outputURL: URL
    private let runID = UUID().uuidString.lowercased()
    private let startedAt = ISO8601DateFormatter().string(from: Date())
    private let startedUptime = ProcessInfo.processInfo.systemUptime
    private var rows: [[String: Any]] = []
    private var marker: SKNode?
    private var markerReattachCount = 0
    private var markerGeneration = -1
    private var markerLifecycle: [[String: Any]] = []
    private var expectedPartyCastRoots: [[String: String]] = []
    private var observedEvents: [[String: Any]] = []
    private var completionPending: String?
    private var completionReason: String?
    private var terminalSampleNeeded = false
    private var finalMarkerSetAtFrame: Int?
    private var finalMarkerConfirmationFrame: Int?
    private var incompletePartyRows = 0
    private var flushed = false

    init(scene: SKScene, request: ERNAStaffMotionTraceRequestR040, outputDirectory: URL,
         sceneGeneration: Int, expectedPartyCastRoots: [[String: String]]) {
        self.scene = scene
        self.request = request
        self.outputURL = outputDirectory.appendingPathComponent("erna_staff_\(request.saveKey)_\(runID).json")
        self.expectedPartyCastRoots = expectedPartyCastRoots
        rows.reserveCapacity(1_800)
        _ = ensureMarker(on: scene, generation: sceneGeneration, sceneFrame: nil)
    }

    private func ensureMarker(on scene: SKScene, generation: Int, sceneFrame: Int?) -> Bool {
        let detached = marker != nil && marker?.parent !== scene
        if marker == nil {
            let group = SKNode()
            group.name = "qa_erna_staff_trace_marker"
            group.zPosition = 20_001
            let back = SKShapeNode(rectOf: CGSize(width: 132, height: 26), cornerRadius: 3)
            back.name = "qa_erna_staff_trace_marker_back"
            back.fillColor = .black.withAlphaComponent(0.88)
            back.strokeColor = .white.withAlphaComponent(0.9)
            back.lineWidth = 1
            group.addChild(back)
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.name = "qa_erna_staff_trace_marker_text"
            label.fontSize = 14
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            group.addChild(label)
            marker = group
            scene.addChild(group)
            recordMarker("initial_attach", scene: scene, generation: generation, frame: sceneFrame)
        } else if detached, let marker {
            marker.removeFromParent()
            scene.addChild(marker)
            markerReattachCount += 1
            recordMarker("reattach", scene: scene, generation: generation, frame: sceneFrame)
        }
        marker?.position = CGPoint(x: 86, y: scene.size.height - 76)
        markerGeneration = generation
        return detached
    }

    private func recordMarker(_ name: String, scene: SKScene, generation: Int, frame: Int?) {
        let p = marker?.position ?? .zero
        markerLifecycle.append(["event": name, "sceneGeneration": generation,
                               "sceneFrame": frame as Any? ?? NSNull(),
                               "position": [Double(p.x), Double(p.y)],
                               "parentMatchesScene": marker?.parent === scene,
                               "uptime": ProcessInfo.processInfo.systemUptime])
    }

    func recordPartyCombatEvent(kind: String, actorID: String, rootActionID: String?, sceneFrame: Int) {
        guard !flushed, let rootActionID, !rootActionID.isEmpty else { return }
        observedEvents.append(["eventKind": kind, "actorID": actorID,
                              "rootActionID": rootActionID, "sceneFrame": sceneFrame])
    }

    func sample(sceneFrame: Int, sceneTime: TimeInterval, sceneGeneration: Int,
                partyCastStates: [[String: Any]], ernaStaff: [String: Any],
                scene currentScene: SKScene) {
        guard !flushed else { return }
        let reattached = ensureMarker(on: currentScene, generation: sceneGeneration, sceneFrame: sceneFrame)
        if reattached && completionPending == nil {
            marker?.removeFromParent(); marker = nil
            completionPending = "INCOMPLETE_MARKER_REBUILT"
            completionReason = "scene_generation_changed_during_capture"
            flush(status: completionPending ?? "INCOMPLETE", sceneGeneration: sceneGeneration)
            return
        }
        if completionPending != nil && !terminalSampleNeeded {
            if reattached {
                marker?.removeFromParent(); marker = nil
                flush(status: "INCOMPLETE_TERMINAL_MARKER_REBUILT", sceneGeneration: sceneGeneration)
                return
            }
            if finalMarkerSetAtFrame != nil && finalMarkerConfirmationFrame == nil {
                finalMarkerConfirmationFrame = sceneFrame
            }
            marker?.removeFromParent(); marker = nil
            flush(status: completionPending ?? "INCOMPLETE", sceneGeneration: sceneGeneration)
            return
        }
        let actors = Set(partyCastStates.compactMap { $0["actorID"] as? String })
        let malformed = partyCastStates.contains { row in
            guard row["bodyExists"] as? Bool == true,
                  let asset = row["bodyAssetID"] as? String, !asset.isEmpty,
                  let index = row["bodyFrameIndex"] as? Int, index >= 0 else { return true }
            return false
        }
        if partyCastStates.count != 4 || actors != Set(["ERNA", "LUNA", "AIRA", "NOIR"]) || malformed {
            incompletePartyRows += 1
        }
        let sequence = rows.count
        (marker?.childNode(withName: "qa_erna_staff_trace_marker_text") as? SKLabelNode)?.text = String(format: "ERNA %04d", sequence)
        var row: [String: Any] = ["sequence": sequence, "phase": "didFinishUpdate",
                                  "sceneFrame": sceneFrame, "sceneTime": sceneTime,
                                  "uptime": ProcessInfo.processInfo.systemUptime,
                                  "sceneGeneration": sceneGeneration,
                                  "videoMarker": String(format: "ERNA %04d", sequence),
                                  "videoMarkerVisible": marker?.parent === currentScene,
                                  "markerReattached": reattached,
                                  "markerGeneration": markerGeneration,
                                  "partyCastStates": partyCastStates,
                                  "partyCastStateActorIDs": partyCastStates.compactMap { $0["actorID"] as? String }.sorted(),
                                  "ernaStaff": ernaStaff]
        row["staffSceneFrameMatchesRow"] = ernaStaff["sceneFrame"] as? Int == sceneFrame
        row["staffSceneTimeMatchesRow"] = ernaStaff["sceneTime"] as? Double == sceneTime
        rows.append(row)
        if rows.count >= Self.rowLimit {
            completionPending = "INCOMPLETE_ROW_LIMIT"
            completionReason = "row_limit_reached_before_battle_completion"
        }
        if terminalSampleNeeded {
            terminalSampleNeeded = false
            finalMarkerSetAtFrame = sceneFrame
        }
    }

    func battleFinished(won: Bool) {
        guard !flushed, completionPending == nil else { return }
        if incompletePartyRows > 0 {
            completionPending = "INCOMPLETE_PARTY_OBSERVATION_GAP"
            completionReason = "battle_finished_with_missing_party_snapshot_rows"
        } else {
            completionPending = "CAPTURED_FULL_BATTLE"
            completionReason = won ? "battle_finished_victory" : "battle_finished_defeat"
        }
        terminalSampleNeeded = true
    }

    func abort(reason: String, sceneGeneration: Int) {
        guard !flushed else { return }
        completionPending = "INCOMPLETE_\(reason)"
        completionReason = reason
        terminalSampleNeeded = false
        marker?.removeFromParent(); marker = nil
        flush(status: completionPending ?? "INCOMPLETE", sceneGeneration: sceneGeneration)
    }

    private func flush(status: String, sceneGeneration: Int) {
        guard !flushed else { return }
        flushed = true
        let payload: [String: Any] = [
            "schema": Self.schema, "status": status, "runID": runID,
            "saveKey": request.saveKey, "fixture": request.fixture,
            "encounterID": request.encounterID, "actorID": "ERNA", "gearID": request.gearID,
            "costume": request.costume, "captureScope": "full_battle_party_casts",
            "startedAt": startedAt, "startedUptime": startedUptime,
            "finishedUptime": ProcessInfo.processInfo.systemUptime,
            "outputFilename": outputURL.lastPathComponent,
            "sceneGenerationAtFinish": sceneGeneration,
            "completionReason": completionReason as Any? ?? NSNull(),
            "expectedPartyCastRoots": expectedPartyCastRoots,
            "observedPartyCombatEvents": observedEvents,
            "incompletePartySnapshotRows": incompletePartyRows,
            "rowLimit": Self.rowLimit,
            "finalMarkerRenderedFrameCount": finalMarkerSetAtFrame != nil && finalMarkerConfirmationFrame != nil ? 1 : 0,
            "finalMarkerSetAtSceneFrame": finalMarkerSetAtFrame as Any? ?? NSNull(),
            "finalMarkerConfirmationSceneFrame": finalMarkerConfirmationFrame as Any? ?? NSNull(),
            "markerReattachCount": markerReattachCount,
            "markerLifecycleEvents": markerLifecycle,
            "rows": rows
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL, options: .atomic)
        } catch { print("ERNAStaffMotionTraceQA_R040 write failed: \(error)") }
    }
}
