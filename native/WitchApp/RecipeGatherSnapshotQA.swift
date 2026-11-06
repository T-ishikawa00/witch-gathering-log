import Foundation

extension GameModel {
    /// Read-only observer for the exact isolated R039 fixture. No Core command,
    /// resource grant, clock override, or ordinary-save write is performed here.
    func writeRecipeGatherSnapshotR039(_ stage: String) {
        guard let request = try? RecipeGoalQAFixtureR037.request(arguments: ProcessInfo.processInfo.arguments),
              request.scenario == .gatherShortage, let saveURL,
              saveURL.lastPathComponent == "qa-\(request.saveKey)-save.json",
              ["before_navigation", "route_confirmation", "handoff_applied", "normal_claim", "reopened"].contains(stage) else { return }
        let url = saveURL.deletingLastPathComponent().appendingPathComponent("recipe_gather_audit_\(request.saveKey).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let snapshot = try JSONSerialization.jsonObject(with: encoder.encode(state))
            var rows: [[String: Any]] = []
            if FileManager.default.fileExists(atPath: url.path) {
                guard let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                      document["schema"] as? String == "recipe-gather-audit-r039-v1",
                      document["saveKey"] as? String == request.saveKey,
                      let existing = document["rows"] as? [[String: Any]] else {
                    throw CoreError.invalidCommand("R039 QA audit identity mismatch; existing evidence preserved")
                }
                rows = existing
            }
            guard rows.count < 100 else { throw CoreError.invalidCommand("R039 QA audit row limit") }
            rows.append(["stage": stage, "uptime": ProcessInfo.processInfo.systemUptime, "snapshot": snapshot])
            let document: [String: Any] = ["schema": "recipe-gather-audit-r039-v1", "saveKey": request.saveKey,
                                          "saveFile": saveURL.lastPathComponent, "rows": rows]
            let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: url, options: .atomic)
        } catch {
            self.error = "採集導線の検証記録を保存できません: \(error)"
        }
    }
}
