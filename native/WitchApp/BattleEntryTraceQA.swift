import Foundation
import SpriteKit

/// Isolated Simulator observations on the actual battle path. No gameplay,
/// action timing, transforms, saves, or purchase state are changed by this probe.
@MainActor final class BattleEntryTraceQA {
    private let start = ProcessInfo.processInfo.systemUptime
    private let startedAt: String
    private let key: String
    private let runID = UUID().uuidString
    private let lifecycle: Bool
    private let marker = SKLabelNode(fontNamed: "Menlo-Bold")
    private var rows: [[String: Any]] = []
    private(set) var isRecording = true

    static func begin(in scene: SKScene) -> BattleEntryTraceQA? {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-battle-entry-trace"),
              let raw = args.first(where: { $0.hasPrefix("--qa-save-key=") }) else { return nil }
        let key = String(raw.dropFirst(14)).filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !key.isEmpty else { return nil }
        return BattleEntryTraceQA(key: key, scene: scene)
        #else
        return nil
        #endif
    }

    private init(key: String, scene: SKScene) {
        self.key = key
        lifecycle = ProcessInfo.processInfo.arguments.contains("--qa-entry-lifecycle-trace")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        startedAt = formatter.string(from: Date())
        marker.name = "qa_battle_entry_frame_marker"
        marker.fontSize = 14; marker.fontColor = .yellow
        marker.horizontalAlignmentMode = .left; marker.verticalAlignmentMode = .top
        marker.position = CGPoint(x: 8, y: scene.size.height - 90); marker.zPosition = 1000
        marker.text = "ENTRY START"; scene.addChild(marker)
        let seconds = lifecycle ? 8 : 2
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.finish()
        }
    }

    func sample(phase: String, sceneTime: Double, sceneClock: Double, sceneFrame: Int,
                rawDelta: Double, scene: SKScene, actors: [String: Any]) {
        guard isRecording, rows.count < (lifecycle ? 900 : 300) else { return }
        let number = rows.count
        let viewOrigin: CGPoint = scene.view?.convert(CGPoint.zero, to: nil) ?? CGPoint.zero
        let viewSize: CGSize = scene.view?.bounds.size ?? CGSize.zero
        if phase == "didFinishUpdate" { marker.text = String(format: "ENTRY %03d", number) }
        rows.append(["sample": number, "phase": phase, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
                     "sceneTime": sceneTime, "sceneClock": sceneClock, "sceneFrame": sceneFrame,
                     "rawDelta": rawDelta, "scenePaused": scene.isPaused, "sceneSpeed": scene.speed,
                     "sceneSize": [scene.size.width, scene.size.height],
                     "viewSize": [viewSize.width, viewSize.height],
                     "viewWindowOrigin": [viewOrigin.x, viewOrigin.y],
                     "viewContentScale": scene.view?.contentScaleFactor ?? 0,
                     "videoMarker": marker.text ?? "", "actors": actors])
    }

    private func finish() {
        guard isRecording else { return }; isRecording = false; marker.removeFromParent()
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Witch03to05R1")
        let payload: [String: Any] = ["status": "CAPTURED_REQUIRES_HOST_VALIDATION", "saveKey": key,
            "runID": runID, "startedAt": startedAt, "startUptime": start,
            "lifecycleRequested": lifecycle, "captureWindowSeconds": lifecycle ? 8 : 2,
            "sourcePath": "LivingScene.arriveForBattle -> didFinishUpdate", "entryDurationSeconds": 0.6,
            "meshPeriodSeconds": ProcessInfo.processInfo.arguments.contains("--qa-dragon-grounded-entry-r005") ? DragonGroundedEntryCandidate.duration : DragonWalkMeshCandidate.duration,
            "requestedMeshCandidate": ProcessInfo.processInfo.arguments.contains("--qa-dragon-mesh-r004"),
            "groundedEntryR005Requested": ProcessInfo.processInfo.arguments.contains("--qa-dragon-grounded-entry-r005"),
            "candidateAdopted": false, "coordinateEvidence": "SKNode getter and node conversion; video required for pixels",
            "pointSemantics": "Opaque source vertices near paws; not ground-contact or anatomy truth",
            "rows": rows]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            // Unique run suffix preserves repeated launches and avoids stale replacement evidence.
            try? data.write(to: folder.appendingPathComponent("battle_entry_" + key + "_" + runID + ".json"), options: .atomic)
        }
    }
}
