import Foundation

/// The core commits once before presentation. Rendering never grants rewards.
extension GameModel {
    /// Keep the battle scene alive until the authored terminal clip and the
    /// party's result pose have actually received foreground rendering time.
    /// Rewards are already committed; this phase does not dispatch a command.
    func presentBattleResolution(won:Bool) async {
        guard !Task.isCancelled else{return}
        let duration=scene.finishBattle(won:won)
        let start=scene.presentationClock
        battleResolutionMessage=won ? "戦いを乗り越えました。":"いったん家で休もう。"
        defer {
            scene.finishEquipmentMultiR084(reason: Task.isCancelled ? "BATTLE_CANCELLED" : "COMPLETED")
            battleResolutionMessage=nil;scene.releaseBattleResult()
        }
        let qa=ProcessInfo.processInfo.arguments.contains("--qa-isolated")
        let resolutionID=UUID().uuidString
        var samples:[[String:Any]]=[]
        while !Task.isCancelled {
            if qa,samples.count<300 {
                samples.append(scene.battleResolutionSnapshot.merging(["sceneActive":sceneActive]){_,new in new})
            }
            if sceneActive,scene.presentationClock-start>=duration {break}
            do {try await Task.sleep(for:.milliseconds(50))} catch {break}
        }
        if qa {
            let receipt:[String:Any]=["resolutionID":resolutionID,"saveFile":saveURL?.lastPathComponent ?? "","enemyID":activeAreaFightEnemyID ?? state.lastEncounterID ?? "","won":won,"requestedSeconds":duration,"renderedSeconds":scene.presentationClock-start,"cancelled":Task.isCancelled,"samples":samples]
            if let data=try? JSONSerialization.data(withJSONObject:receipt,options:.sortedKeys),let value=String(data:data,encoding:.utf8) {
                writeReceipt("battle_resolution",value)
                writeReceipt("battle_resolution_"+resolutionID,value)
            }
        }
    }
    func play(_ battle:CombatResult, equipmentMotionTrace: EquipmentMotionTraceRequest? = nil,
              ernaStaffMotionTrace: ERNAStaffMotionTraceRequestR040? = nil,
              syntheticDash2TailR047: SyntheticDash2TailRequestR047? = nil) async {
        defer {
            if Task.isCancelled {
                scene.cancelPendingPartyCasts()
                if syntheticDash2TailR047 != nil {
                    _ = scene.finishSyntheticDash2TailR047(observedMilliseconds: 0, sceneActive: sceneActive, cancelled: true)
                }
            }
        }
        scene.prepareCombatEntities(battle)
        scene.prepareCombatEffects(battle.events,remainingPartyHP:battle.remainingPartyHP)
        do {
            preparationMessage = "戦闘の演出を準備しています…"
            defer { preparationMessage = nil }
            // Yield a frame-sized interval so the normal fighting overlay can
            // publish this state before texture decoding or SpriteKit snapshots.
            try await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled else { return }
            _ = await scene.prepareRegisteredEnemyRendering()
            #if targetEnvironment(simulator)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--qa-isolated"), args.contains("--qa-entry-lifecycle-trace"),
               args.contains("--qa-battle-entry-trace"),
               args.contains("--qa-entry-preparation-delay-ms=3000") {
                // Stage the isolated UI driver before the real arrival starts.
                // Its 0.6-second action, playback speed and pause logic are unchanged.
                try await Task.sleep(for: .seconds(3))
            }
            #endif
        } catch {
            return
        }
        if Task.isCancelled { return }
        if let request = equipmentMotionTrace, let saveURL {
            let started = scene.beginEquipmentMotionTrace(request: request,
                outputDirectory: saveURL.deletingLastPathComponent())
            writeReceipt("equipment_motion_trace_armed", started ? "STARTED" : "PRECONDITION_FAIL",
                         metadata: ["saveKey": request.saveKey, "encounterID": request.encounterID])
        }
        if let request = ernaStaffMotionTrace, let saveURL {
            let result = scene.beginERNAStaffMotionTrace(request: request,
                outputDirectory: saveURL.deletingLastPathComponent())
            let started = result["started"] as? Bool == true
            writeReceipt("erna_staff_motion_trace_armed", started ? "STARTED" : "PRECONDITION_FAIL",
                         metadata: ["saveKey": request.saveKey, "encounterID": request.encounterID,
                                    "diagnostic": result["diagnostic"] ?? NSNull()])
        }
        scene.beginBattle(partyHP:battle.initialPartyHP,enemyHP:battle.initialEnemyHP)
        if let syntheticDash2TailR047 { scene.beginSyntheticDash2TailR047(request: syntheticDash2TailR047) }
        if let request = qaEquipmentMultiRequestR084, request.evidenceMode == "natural_full_battle", let saveURL {
            let started = scene.beginEquipmentMultiR084(request: request, outputDirectory: saveURL.deletingLastPathComponent())
            writeReceipt("equipment_multi_start", started ? "STARTED_NATURAL_BATTLE" : "PRECONDITION_FAIL")
        }
        scene.arriveForBattle()
        var entryDelay=0.6
        while entryDelay>0 || !sceneActive {
            if Task.isCancelled{return}
            try? await Task.sleep(for:.seconds(0.05));if sceneActive{entryDelay-=0.05}
        }
        let qa=ProcessInfo.processInfo.arguments.contains("--qa-isolated")
        let slowQA=qa && ProcessInfo.processInfo.arguments.contains("--qa-slow-battle")
        var previous = 0
        for event in battle.events {
            let timestamp=max(previous,event.timestampMs ?? event.tick*1_000)
            var delay=Double(timestamp-previous)/1_000 * (slowQA ? 2:1)
            while delay>0 || !sceneActive {
                if Task.isCancelled{return}
                let step=min(0.05,max(0.01,delay))
                try? await Task.sleep(for:.seconds(step))
                if sceneActive {delay-=step}
            }
            if Task.isCancelled{return}
            battleElapsed=timestamp/1_000
            scene.present(event)
            previous=timestamp
        }
        if let syntheticDash2TailR047 {
            let tailStart = scene.presentationClock
            let tailWallStart = ProcessInfo.processInfo.systemUptime
            let tailWallLimit = max(4.0, Double(syntheticDash2TailR047.tailMilliseconds) / 1_000 * 3.0)
            while !Task.isCancelled && sceneActive && scene.isForegroundRenderedForR047
                && scene.presentationClock - tailStart < Double(syntheticDash2TailR047.tailMilliseconds) / 1_000
                && ProcessInfo.processInfo.systemUptime - tailWallStart < tailWallLimit {
                try? await Task.sleep(for: .milliseconds(25))
            }
            let observed = max(0, Int((scene.presentationClock - tailStart) * 1_000))
            let tailReceipt = scene.finishSyntheticDash2TailR047(observedMilliseconds: observed, sceneActive: sceneActive, cancelled: Task.isCancelled)
            _ = tailReceipt
        }
        // Let the final presentation-only impact/recover frames finish before receipts and end-of-battle UI.
        await scene.finishCombatEffects()
        let mismatches=scene.hpMismatches(party:battle.remainingPartyHP,enemies:battle.remainingEnemyHP)
        if qa {
            let data=(try? JSONSerialization.data(withJSONObject:mismatches,options:.sortedKeys)) ?? Data()
            writeReceipt("presentation_hp",String(data:data,encoding:.utf8) ?? "ENCODING_FAILED")
            if !mismatches.isEmpty {error="戦闘表示のHP不一致を検出しました。検証記録を保存しています。"}
        }
        scene.finishHP(party:battle.remainingPartyHP,enemies:battle.remainingEnemyHP)
    }
}
