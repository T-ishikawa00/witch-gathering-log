import Foundation
import SpriteKit

/// Opt-in, isolated QA only. Buffers render observations and writes once, after
/// the cue, so file I/O cannot consume the animation's frame budget.
@MainActor final class GatherFrameTraceQA {
    private let start = ProcessInfo.processInfo.systemUptime
    private let key: String
    private let materialID: String
    private var rows: [[String: Any]] = []
    private var finished = false

    static func begin(materialID: String) -> GatherFrameTraceQA? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-gather-frame-trace"),
              let raw = args.first(where: { $0.hasPrefix("--qa-save-key=") }) else { return nil }
        return GatherFrameTraceQA(key: String(raw.dropFirst(14)).filter { $0.isLetter || $0.isNumber || $0 == "-" }, materialID: materialID)
        #else
        return nil
        #endif
    }

    private init(key: String, materialID: String) {
        self.key = key; self.materialID = materialID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.finish()
        }
    }

    func sample(phase: String, sceneTime: Double, rawDelta: Double, scene: SKScene, node: SKSpriteNode?) {
        guard !finished, rows.count < 500 else { return }
        var row: [String: Any] = ["phase": phase,
            "elapsed": ProcessInfo.processInfo.systemUptime - start,
            "sceneTime": sceneTime, "rawDelta": rawDelta,
            "scenePaused": scene.isPaused, "sceneSpeed": scene.speed,
            "viewPaused": scene.view?.isPaused as Any? ?? NSNull(),
            "nodePresent": node?.parent != nil]
        if let node {
            row["alpha"] = node.alpha; row["nodeSpeed"] = node.speed
            row["respawnAction"] = node.action(forKey: "gather_visual_respawn") != nil
            row["presentation"] = GatherNodePresentation.qaSnapshot(on: node, materialID: materialID)
        }
        rows.append(row)
    }

    private func finish() {
        guard !finished else { return }; finished = true
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Witch03to05R1")
        let payload: [String: Any] = ["saveKey": key, "materialID": materialID,
            "startUptime": start, "recordedAt": ISO8601DateFormatter().string(from: Date()), "rows": rows]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("gather_frame_trace_" + key + ".json"), options: .atomic)
        }
    }
}
