import Foundation

@MainActor extension GameModel {
    func runPartyFrameAuditIfRequested() {
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"),let raw=args.first(where:{$0.hasPrefix("--qa-party-frame=")}) else{return}
        let parts=raw.dropFirst("--qa-party-frame=".count).split(separator:":").map(String.init)
        guard parts.count==3,let index=Int(parts[2]) else{writeReceipt("party_frame_error","Expected ACTOR:STATE:INDEX");return}
        tab="探索";fighting=true;notice="装備位置の固定フレーム検証";syncScene();scene.setEnemies([])
        Task {
            // Allow the SpriteView to mount and settle its layout before selecting a frame.
            try? await Task.sleep(for:.milliseconds(400))
            guard scene.beginPartyFrameAudit(actor:parts[0],state:parts[1],index:index) else{writeReceipt("party_frame_error","Invalid request or scene not mounted");return}
            for _ in 0..<200 {
                if scene.partyFrameAuditReady {break}
                try? await Task.sleep(for:.milliseconds(40))
            }
            guard scene.partyFrameAuditReady else{writeReceipt("party_frame_error","Requested texture frame was not reached");return}
            // Fresh receipts on both sides of a screenshot prove the held target stayed stable.
            for _ in 0..<120 {
                writeReceipt("party_frame",scene.artAuditJSON())
                try? await Task.sleep(for:.milliseconds(250))
            }
        }
    }
}
