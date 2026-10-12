import Foundation
import CryptoKit

/// Explicit isolated Simulator workload. Uses the same committed command and
/// real-time playback path as tapping an encounter; no assumed victories.
extension GameModel {
    func runActiveBattleQAIfRequested() {
        #if targetEnvironment(simulator)
        let arguments=ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated"),arguments.contains("--qa-fixture=challenge"),
              let flag=arguments.first(where:{$0.hasPrefix("--qa-active-battle-suite=")}),
              let cycles=Int(flag.components(separatedBy:"=").last ?? ""),
              (1...3).contains(cycles), let catalog,let engine,let saveURL,
              saveURL.lastPathComponent.hasPrefix("qa-") else{return}
        let folder=saveURL.deletingLastPathComponent()
        let reportURL=folder.appendingPathComponent("active_battle_qa.json")
        let loadedExistingSave=qaLoadedExistingSave
        Task {
            var rows:[[String:Any]]=[]
            let began=Date()
            let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
            var initialSHA="UNAVAILABLE"
            func persist(_ status:String,_ failure:String?=nil) throws {
                var report:[String:Any]=["status":status,"scope":"ISOLATED_SIMULATOR_REAL_TIME_PLAYBACK_NOT_DEVICE_OR_BALANCE_APPROVAL","fixture":"challenge","began":ISO8601DateFormatter().string(from:began),"elapsedSeconds":Date().timeIntervalSince(began),"cyclesRequested":cycles,"encountersPerCycle":catalog.enemies.count,"saveFile":saveURL.lastPathComponent,"loadedExistingSave":loadedExistingSave,"initialSnapshotJSONSHA256":initialSHA,"cases":rows]
                if let failure{report["failure"]=failure}
                let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try data.write(to:reportURL,options:.atomic)
            }
            do {
                guard !loadedExistingSave else{try persist("REFUSED_REUSED_SAVE","Use a new isolated QA save key; existing save was preserved.");return}
                let initialData=try encoder.encode(state)
                initialSHA=SHA256.hash(data:initialData).map{String(format:"%02x",$0)}.joined()
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try initialData.write(to:folder.appendingPathComponent("active_battle_initial_snapshot.json"),options:.atomic)
                try persist("RUNNING")
                for cycle in 0..<cycles {
                    for enemy in catalog.enemies {
                        guard !Task.isCancelled else{try persist("CANCELLED");return}
                        chosenRegion=enemy.regionID;tab="探索"
                        if state.activeRegionID != enemy.regionID {
                            _ = try await engine.dispatch(.startExpeditionAt(regionID:enemy.regionID,now:Date()),operationID:UUID(),expectedRevision:state.revision)
                            await refresh()
                        }
                        syncScene()
                        let before=state,started=Date()
                        fight(enemy)
                        while busy {
                            try await Task.sleep(for:.milliseconds(100))
                            if Date().timeIntervalSince(started)>300 {try persist("FAILED","Playback exceeded 300 seconds: "+enemy.id);return}
                        }
                        if let error{try persist("FAILED",error);return}
                        guard let combat=state.lastCombatResult,state.lastEncounterID==enemy.id,let operationID=lastBattleOperationID else{try persist("FAILED","Missing encounter result or operation ID: "+enemy.id);return}
                        let reopened=try SaveRepository(fileURL:saveURL)
                        let readback=await reopened.snapshot()
                        // fight() has returned to the gathering scene by now.
                        // Its HP nodes are intentionally gone. Read the terminal
                        // playback check captured before that scene transition,
                        // requiring this command's committed revision.
                        let hpReceiptData=try Data(contentsOf:folder.appendingPathComponent("last_presentation_hp.json"))
                        guard let hpReceipt=try JSONSerialization.jsonObject(with:hpReceiptData) as? [String:Any],
                              hpReceipt["kind"] as? String == "presentation_hp",
                              (hpReceipt["revision"] as? NSNumber)?.int64Value == state.revision,
                              let hpJSON=hpReceipt["value"] as? String,
                              let hpData=hpJSON.data(using:.utf8),
                              let hp=try JSONSerialization.jsonObject(with:hpData) as? [String:[Int]] else {
                            try persist("FAILED","Missing or stale terminal HP receipt: "+enemy.id);return
                        }
                        let bytes=try Data(contentsOf:saveURL)
                        var row:[String:Any]=["cycle":cycle+1,"enemyID":enemy.id,"won":combat.won,"seconds":Date().timeIntervalSince(started),"revisionBefore":before.revision,"revisionAfter":state.revision,"revisionDelta":state.revision-before.revision,"reopenedSnapshotEqual":readback==state,"hpMismatches":hp,"saveSHA256":SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),"eventCount":combat.events.count]
                        row["seed"]=UInt64(bitPattern:before.revision) &+ 1001
                        row["operationID"]=operationID.uuidString
                        row["hpEvidencePhase"]="terminal_playback_before_gather_scene_return"
                        row["hpReceiptSHA256"]=SHA256.hash(data:hpReceiptData).map{String(format:"%02x",$0)}.joined()
                        row["materialDelta"]=Dictionary(uniqueKeysWithValues:Set(before.materials.keys).union(state.materials.keys).compactMap{key -> (String,Int)? in let delta=state.materials[key,default:0]-before.materials[key,default:0];return delta==0 ? nil:(key,delta)})
                        row["currencyDelta"]=Dictionary(uniqueKeysWithValues:Set(before.currency.keys).union(state.currency.keys).compactMap{key -> (String,Int)? in let delta=state.currency[key,default:0]-before.currency[key,default:0];return delta==0 ? nil:(key,delta)})
                        let metricsURL=folder.appendingPathComponent("runtime_metrics.json")
                        if let data=try? Data(contentsOf:metricsURL),let metrics=try? JSONSerialization.jsonObject(with:data){row["runtimeMetrics"]=metrics}
                        rows.append(row)
                        guard readback==state,state.revision==before.revision+1,hp.isEmpty else{try persist("FAILED","Save/revision/HP regression: "+enemy.id);return}
                        try persist("RUNNING")
                        try await Task.sleep(for:.milliseconds(450))
                    }
                }
                try persist("PASS")
            }catch{
                self.error="負荷検証または検証記録の保存に失敗しました。"+error.localizedDescription
                do{try persist("FAILED",String(reflecting:error))}catch{NSLog("Active battle QA receipt write failed: %@",String(reflecting:error))}
            }
        }
        #endif
    }
}
