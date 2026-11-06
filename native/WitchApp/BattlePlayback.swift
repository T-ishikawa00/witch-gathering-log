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
            scene.requestEnemyEventRenderTraceFinishR145(reason: Task.isCancelled ? "BATTLE_CANCELLED" : "BATTLE_FINISHED")
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
              syntheticDash2TailR047: SyntheticDash2TailRequestR047? = nil,
              enemyEventRenderTraceR145: EnemyEventRenderRequestR145? = nil,
              completion: ((Int, Int) -> Void)? = nil,
              r214ReplayID: String? = nil) async {
        battleTargetWarningTextR299=nil
        // Describe the mountain dragon's announced aim before cover or barriers
        // resolve. Its single and party tells can share the heavy event kind.
        let warningEnemyHP=battle.initialEnemyHP.filter { id, _ in
            (battle.entityPresentation[id]?.catalogID ?? id) == "B_R04_B"
        }
        var targetWarning=BattleTargetWarningR299(initialEnemyHP:warningEnemyHP,
                                                partyIDs:Set(battle.initialPartyHP.keys))
        var battleTimingTraceR319: BattleTimingTraceR319?
        var battleTimingSamplerR319: Task<Void, Never>?
        var battleTimingCompletedR319 = false
        defer {
            let cancelledR319 = Task.isCancelled
            let endedAtUnixR319 = Date().timeIntervalSince1970
            let endedAtMonotonicR319 = ProcessInfo.processInfo.systemUptime
            battleTimingSamplerR319?.cancel()
            if let traceR319 = battleTimingTraceR319 {
                let samplerR319 = battleTimingSamplerR319
                let resultR319 = cancelledR319 ? "CANCELLED" : (battleTimingCompletedR319 ? "COMPLETED" : "EARLY_RETURN")
                Task { @MainActor in
                    await samplerR319?.value
                    traceR319.finish(endedAtUnixTime: endedAtUnixR319,
                                     endedAtMonotonicUptime: endedAtMonotonicR319,
                                     cancelled: cancelledR319, completion: resultR319)
                }
            }
            battleTargetWarningTextR299=nil
            if Task.isCancelled {
                scene.cancelPendingPartyCasts()
                if syntheticDash2TailR047 != nil {
                    _ = scene.finishSyntheticDash2TailR047(observedMilliseconds: 0, sceneActive: sceneActive, cancelled: true)
                }
                scene.requestEnemyEventRenderTraceFinishR145(reason: "BATTLE_CANCELLED")
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
            if let request = enemyEventRenderTraceR145 {
                let started = scene.beginEnemyEventRenderTraceR145(request: request)
                writeReceipt("enemy_event_render_r145_armed", started ? "STARTED" : "PRECONDITION_FAIL",
                             metadata: ["runID": request.runID, "encounterID": request.encounterID,
                                        "actorID": request.actorID, "saveKey": request.saveKey,
                                        "saveFilename": saveURL?.lastPathComponent ?? "",
                                        "processID": ProcessInfo.processInfo.processIdentifier])
            }
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
        if r214ReplayID == nil,
           ProcessInfo.processInfo.arguments.filter({ $0 == BattleTimingTraceR319.argument }).count == 1,
           saveURL?.deletingLastPathComponent().lastPathComponent == "Witch03to05DevelopmentR169",
           let applicationSupportR319 = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let traceR319 = BattleTimingTraceR319.makeIfRequested(
                arguments: ProcessInfo.processInfo.arguments, applicationSupport: applicationSupportR319,
                encounterID: state.lastEncounterID, saveFilename: saveURL?.lastPathComponent ?? "") {
            battleTimingTraceR319 = traceR319
            battleTimingSamplerR319 = Task { @MainActor [weak self, weak traceR319] in
                guard let self, let traceR319 else { return }
                while !Task.isCancelled && traceR319.count < BattleTimingTraceR319.maximumSamples {
                    traceR319.append(sceneActive: self.sceneActive, scenePaused: self.scene.isPaused,
                                     battleElapsed: self.battleElapsed,
                                     presentationClock: self.scene.presentationClock, frameCount: self.scene.frames)
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                }
            }
        }
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
        for (eventIndex, event) in battle.events.enumerated() {
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
            targetWarning.consume(event)
            let warningText=targetWarning.current.map { warning in
                warning.isPartyWide ? "全員を狙う攻撃" : "\(Self.actorNames[warning.targetID] ?? "仲間")を狙う攻撃"
            }
            if battleTargetWarningTextR299 != warningText { battleTargetWarningTextR299=warningText }
            scene.present(event, r214ReplayID: r214ReplayID,
                          r214ReplayEventSequence: r214ReplayID == nil ? nil : eventIndex + 1)
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
        if completion != nil, Task.isCancelled { return }
        scene.finishHP(party:battle.remainingPartyHP,enemies:battle.remainingEnemyHP)
        guard !Task.isCancelled else { return }
        battleTimingCompletedR319 = true
        completion?(battle.events.count, mismatches.count)
    }
}
