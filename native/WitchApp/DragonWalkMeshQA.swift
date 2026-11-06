import Foundation

/// Isolated Simulator observers for the unapproved R038 gait and legacy R004 pause probe.
/// Neither route changes combat events or save data.
extension GameModel {
    func runDragonWalkMeshPauseQAIfRequested(actorID: String) async -> Bool {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if DragonGaitR038SequenceQA.isRequested(arguments: args, actorID: actorID) {
            guard let saveURL,
                  let saveKey = args.first(where: { $0.hasPrefix("--qa-save-key=") })?.split(separator: "=", maxSplits: 1).last.map(String.init) else {
                writeReceipt("dragon_gait_r038_sequence_failed", "FAILED_MISSING_QA_SAVE_CONTEXT")
                return true
            }
            let previousFightContext = activeAreaFightEnemyID
            let previousFighting = fighting
            activeAreaFightEnemyID = "B_R04_B"
            syncScene()
            scene.setEnemy("B_R04_B")
            defer {
                activeAreaFightEnemyID = previousFightContext
                fighting = previousFighting
                syncScene()
            }
            let result = await scene.runDragonGaitR038SequenceQA(
                actorID: actorID, saveKey: saveKey,
                outputDirectory: saveURL.deletingLastPathComponent(),
                includesFlight: scene.hasDragonFlightState(actorID: actorID))
            writeReceipt("dragon_gait_r038_sequence", result)
            return true
        }
        guard actorID == "ACT_B_R04_B", args.contains("--qa-isolated"),
              args.contains("--qa-dragon-mesh-r004"),
              args.contains("--qa-dragon-mesh-pause-probe") else { return false }
        let previousFightContext = activeAreaFightEnemyID
        // The ordinary art viewer does not own a campaign encounter. Pin this
        // probe to the same area context as a real battle so foreground refresh
        // does not rebuild it as the saved gathering scene halfway through.
        activeAreaFightEnemyID = "B_R04_B"
        syncScene()
        scene.setEnemy("B_R04_B")
        defer { activeAreaFightEnemyID = previousFightContext; fighting = false }
        scene.auditEnemyState(.walk)
        guard let initialData = scene.artAuditJSON().data(using: .utf8),
              let initial = try? JSONSerialization.jsonObject(with: initialData) as? [String: Any],
              let presentations = initial["enemyPresentation"] as? [String: [String: Any]],
              let rig = presentations[actorID]?["partRig"] as? [String: Any],
              rig["walkMeshActive"] as? Bool == true,
              rig["walkMeshGeometryPresent"] as? Bool == true,
              rig["walkMeshReadback"] != nil else {
            writeReceipt("dragon_mesh_pause_failed", "Requested mesh was not active at probe entry")
            notice = "四脚歩行の検証を開始できません"
            return true
        }
        notice = "四脚歩行の停止検証"
        writeReceipt("dragon_mesh_pause_started", actorID)
        let startedAt = ISO8601DateFormatter().string(from: Date())
        let start = ProcessInfo.processInfo.systemUptime
        var rows: [[String: Any]] = []
        for index in 0..<180 {
            guard !Task.isCancelled else { return true }
            if let data = scene.artAuditJSON().data(using: .utf8),
               let art = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rows.append(["sample": index,
                    "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
                    "sceneActive": sceneActive, "scenePaused": scene.isPaused,
                    "sceneFrames": art["frames"] ?? NSNull(),
                    "enemyPresentation": art["enemyPresentation"] ?? NSNull(),
                    "geometry": art["geometry"] ?? NSNull()])
            }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return true }
        }
        scene.auditEnemyState(.idle)
        let restored = scene.artAuditJSON()
        let payload: [String: Any] = ["requestedCandidate": "UNAPPROVED_TEST_OVERLAY",
            "status": "CAPTURED_REQUIRES_HOST_VALIDATION", "startedAt": startedAt,
            "saveFilename": saveURL?.lastPathComponent ?? "MISSING",
            "actorID": actorID, "rows": rows, "restoredIdleJSON": restored,
            "scenePausePolicyModified": false, "saveModifiedByProbe": false]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            writeReceipt("dragon_mesh_pause", json)
        }
        fighting = false
        notice = "四脚歩行の停止検証を完了"
        return true
        #else
        return false
        #endif
    }
}
