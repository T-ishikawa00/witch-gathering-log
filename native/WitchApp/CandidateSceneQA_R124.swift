import Foundation

/// Read-only render evidence for isolated candidate comparison. No save mutation.
@MainActor extension GameModel {
    func runCandidateSceneR124IfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated"), arguments.contains("--qa-candidate-scene-r124") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            for _ in 0..<160 {
                writeReceipt("candidate_scene_r124", scene.artAuditJSON(), metadata: ["processID": ProcessInfo.processInfo.processIdentifier, "saveFilename": saveURL?.lastPathComponent ?? "", "uptime": ProcessInfo.processInfo.systemUptime])
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
