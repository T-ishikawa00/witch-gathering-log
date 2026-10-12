import Foundation
import CryptoKit

extension GameModel {
    /// Read-only receipt of the state actually loaded by GameModel after relaunch.
    /// This does not reopen, repair, claim rewards, or write the save repository.
    func writeQASaveReadbackIfRequested() {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated"), arguments.contains("--qa-readback-save"),
              let saveURL, saveURL.lastPathComponent.hasPrefix("qa-") else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let snapshotBytes = try encoder.encode(state)
            let snapshot = try JSONSerialization.jsonObject(with: snapshotBytes)
            let savedBytes = try Data(contentsOf: saveURL)
            let report: [String: Any] = [
                "scope": "ISOLATED_SIMULATOR_MODEL_READBACK_NOT_GAME_COMMAND",
                "saveFile": saveURL.lastPathComponent,
                "loadedExistingSave": qaLoadedExistingSave,
                "revision": state.revision,
                "snapshot": snapshot,
                "snapshotJSONSHA256": SHA256.hash(data: snapshotBytes).map { String(format: "%02x", $0) }.joined(),
                "saveFileSHA256": SHA256.hash(data: savedBytes).map { String(format: "%02x", $0) }.joined()
            ]
            let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            guard let value = String(data: bytes, encoding: .utf8) else { return }
            writeReceipt("qa_save_readback", value)
        } catch {
            writeReceipt("qa_save_readback_error", String(reflecting: error))
        }
        #endif
    }
}
