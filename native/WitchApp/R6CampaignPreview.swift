import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

private enum PreviewPreparationFailure: Error {
    case spriteViewUnavailable
    case registeredRenderPreparationFailed
}

extension GameModel {
    private func writeR043PreflightReceipt(_ value: String, metadata: [String: Any] = [:]) {
        guard let saveURL else { return }
        var object: [String: Any] = [
            "kind": "r043_preflight", "value": value,
            "revision": state.revision, "date": ISO8601DateFormatter().string(from: Date())
        ]
        for (key, item) in metadata where !["kind", "value", "revision", "date"].contains(key) {
            object[key] = item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        let name = "r043_preflight_\(UUID().uuidString).json"
        try? data.write(to: saveURL.deletingLastPathComponent().appendingPathComponent(name), options: .atomic)
    }

    private func writeR043Receipt(_ kind: String, saveKey: String?, value: String, metadata: [String: Any] = [:]) {
        guard let saveURL, let saveKey,
              EquipmentMotionTraceRequest.isSafe(saveKey) else { return }
        var object: [String: Any] = [
            "kind": "r043_\(kind)", "value": value, "saveKey": saveKey,
            "revision": state.revision, "date": ISO8601DateFormatter().string(from: Date())
        ]
        for (key, item) in metadata where !["kind", "value", "saveKey", "revision", "date"].contains(key) {
            object[key] = item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? data.write(to: saveURL.deletingLastPathComponent().appendingPathComponent("r043_\(saveKey)_\(kind).json"), options: .atomic)
    }
    private func writeR047Receipt(_ kind: String, saveKey: String?, value: String, metadata: [String: Any] = [:]) {
        guard let saveURL, let saveKey, EquipmentMotionTraceRequest.isSafe(saveKey) else { return }
        let object: [String: Any] = ["schema":SyntheticDash2VisualTailR047.schema,"kind":kind,"saveKey":saveKey,"value":value,"revision":state.revision,"date":ISO8601DateFormatter().string(from:Date())].merging(metadata){_,new in new}
        guard let data=try? JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]) else{return}
        try? data.write(to:saveURL.deletingLastPathComponent().appendingPathComponent("r047_\(saveKey)_\(kind).json"),options:.atomic)
    }
    /// Explicit isolated QA route; it never dispatches a rewarding command.
    func previewCampaignR6(_ enemy:EnemyDefinition) {
        let arguments=ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated"),!busy,let engine else{return}
        let tailR047=arguments.contains(EquipmentMotionTraceRequest.syntheticDash2TailR047Flag)
        let synthetic=arguments.contains(EquipmentMotionTraceRequest.syntheticDash2Flag) || tailR047
        let requestedSaveKey=arguments.first(where:{$0.hasPrefix("--qa-save-key=")}).map{String($0.dropFirst("--qa-save-key=".count))}
        guard !synthetic || enemy.id == SyntheticPartyDash2PreviewR043.encounterID else {
            if tailR047 { writeR047Receipt("precondition", saveKey: requestedSaveKey, value: "PRECONDITION_FAIL", metadata:["reason":"wrong_encounter","encounterID":enemy.id]) }
            else { writeR043PreflightReceipt("PRECONDITION_FAIL", metadata:["reason":"wrong_encounter","encounterID":enemy.id]) }
            return
        }
        let traceRequest: EquipmentMotionTraceRequest?
        if arguments.contains(EquipmentMotionTraceRequest.fullBattleFlag) {
            guard let saveURL else {
                writeR043PreflightReceipt("PRECONDITION_FAIL", metadata:["reason":"save_url_missing"])
                return
            }
            switch EquipmentMotionTraceRequest.parse(arguments: arguments, actualEncounterID: enemy.id,
                                                       outputDirectory: saveURL.deletingLastPathComponent(),
                                                       existingSaveLoaded: qaLoadedExistingSave) {
            case .success(let request): traceRequest=request
            case .failure(let failure):
                if tailR047 { writeR047Receipt("precondition", saveKey: requestedSaveKey, value: "PRECONDITION_FAIL", metadata:["reason":failure.rawValue]) }
                else { writeR043PreflightReceipt("PRECONDITION_FAIL", metadata:["reason":failure.rawValue]) }
                return
            }
        } else {
            if synthetic {
                if tailR047 { writeR047Receipt("precondition", saveKey: requestedSaveKey, value: "PRECONDITION_FAIL", metadata:["reason":"full_battle_observer_required"]) }
                else { writeR043PreflightReceipt("PRECONDITION_FAIL", metadata:["reason":"full_battle_observer_required"]) }
                return
            }
            traceRequest=nil
        }
        busy=true;fighting=true;qaCombatPreview=true
        if synthetic { activeAreaFightEnemyID = enemy.id }
        chosenRegion=enemy.regionID;tab="探索";syncScene();scene.setEnemy(enemy.id)
        scene.damageNumberDivisor=R6CampaignQAAdapter.fixedPointScale
        playbackTask=Task {
            do {
                let before=await engine.snapshot()
                let beforeBytes=saveURL.flatMap{try? Data(contentsOf:$0)}
                var preparation = "not_run"
                if synthetic {
                    // This launch-only path can run before SpriteView appears. Match the
                    // normal `play` renderer preparation, but fail closed before creating
                    // the synthetic battle if the mounted SpriteKit view is not ready.
                    var viewWaitMilliseconds = 0
                    while scene.view == nil && !Task.isCancelled && viewWaitMilliseconds < 10_000 {
                        try await Task.sleep(for: .milliseconds(25))
                        viewWaitMilliseconds += 25
                    }
                    guard !Task.isCancelled, scene.view != nil else {
                        writeR043Receipt("precondition", saveKey: traceRequest?.saveKey, value: "PRECONDITION_FAIL", metadata: ["reason":"sprite_view_unavailable"])
                        throw PreviewPreparationFailure.spriteViewUnavailable
                    }
                    preparation = await scene.prepareRegisteredEnemyRendering()
                    let expectedActorID = "ACT_" + enemy.id
                    let auditData = scene.artAuditJSON().data(using: .utf8)
                    let audit = auditData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    let geometry = audit?["geometry"] as? [String: [String: Any]]
                    let enemyPresentation = audit?["enemyPresentation"] as? [String: Any]
                    let mounted = geometry?[expectedActorID]
                    let mountedActorMatches = (audit?["actorIDs"] as? [String]) == [expectedActorID]
                        && enemyPresentation?[expectedActorID] != nil
                        && ["width", "height", "textureWidth", "textureHeight"].allSatisfy {
                            let value = (mounted?[$0] as? NSNumber)?.doubleValue ?? 0
                            return value.isFinite && value > 0
                        }
                    let clips = ArtLibrary.index[expectedActorID]?["clips"] as? [String: [String: Any]]
                    let spriteFramesNeedNoRegisteredWarmup = clips.map {
                        !$0.isEmpty && !$0.values.contains { $0["mode"] as? String == "registered_keyposes_v1" }
                    } ?? false
                    guard let preparationData = preparation.data(using: .utf8),
                          let preparationObject = try? JSONSerialization.jsonObject(with: preparationData) as? [String: Any],
                          let preparationOutcome = preparationObject["outcome"] as? String,
                          mountedActorMatches,
                          (["prepared", "textures_prepared_snapshot_skipped"].contains(preparationOutcome)
                            || (preparationOutcome == "not_applicable" && spriteFramesNeedNoRegisteredWarmup)) else {
                        writeR043Receipt("precondition", saveKey: traceRequest?.saveKey, value: "PRECONDITION_FAIL", metadata: ["reason":"registered_render_preparation_failed", "preparation":preparation])
                        throw PreviewPreparationFailure.registeredRenderPreparationFailed
                    }
                }
                // Only this synthetic preview uses the pinned QA seed. Ordinary R6
                // previews keep their existing state-derived seed.
                let seed=synthetic ? SyntheticPartyDash2PreviewR043.deterministicSeed : (UInt64(bitPattern: before.revision) &+ 1001)
                let battle: CombatResult
                if synthetic {
                    battle=try await SyntheticPartyDash2PreviewR043.run(engine:engine,seed:seed,snapshot:before)
                } else {
                    battle=try await engine.previewCampaignEncounterR6QA(enemyID:enemy.id,seed:seed)
                }
                if tailR047 {
                    guard let saveURL, let traceRequest,
                          let donorData = try? JSONEncoder().encode(battle) else {
                        throw PreviewPreparationFailure.registeredRenderPreparationFailed
                    }
                    guard beforeBytes != nil else { throw PreviewPreparationFailure.registeredRenderPreparationFailed }
                    let plan = try SyntheticDash2VisualTailR047.makePlan(from: battle)
                    let prefixData = try JSONEncoder().encode(plan.playback)
                    let directory = saveURL.deletingLastPathComponent()
                    try donorData.write(to: directory.appendingPathComponent("r047_\(traceRequest.saveKey)_full_donor.json"), options: .atomic)
                    try prefixData.write(to: directory.appendingPathComponent("r047_\(traceRequest.saveKey)_playback_prefix.json"), options: .atomic)
                    try prefixData.write(to: directory.appendingPathComponent("r047_\(traceRequest.saveKey)_submitted_playback.json"), options: .atomic)
                    let target = plan.playback.events[plan.targetImpactIndex]
                    let tailRequest = SyntheticDash2TailRequestR047(saveKey: traceRequest.saveKey,
                        outputDirectory: directory, rootActionID: target.rootActionID ?? SyntheticDash2VisualTailR047.rootActionID,
                        targetEnemyID: target.targetID, targetCastStartIndex: plan.targetCastStartIndex,
                        targetImpactIndex: plan.targetImpactIndex,
                        targetCastStartTimestampMs: plan.targetCastStartTimestampMs,
                        targetImpactTimestampMs: plan.targetImpactTimestampMs, tailMilliseconds: plan.tailMilliseconds)
                    let metadata: [String: Any] = ["schema":SyntheticDash2VisualTailR047.schema,
                        "saveKey":traceRequest.saveKey, "fullDonorEventCount":plan.fullDonorEventCount,
                        "targetCastStartIndex":plan.targetCastStartIndex, "targetImpactIndex":plan.targetImpactIndex,
                        "targetCastStartTimestampMs":plan.targetCastStartTimestampMs,
                        "targetImpactTimestampMs":plan.targetImpactTimestampMs,
                        "playbackEventCount":plan.playback.events.count,
                        "targetRootActionID":target.rootActionID ?? "",
                        "engineCommandCount":0,"rewardGranted":false,"ordinaryBattleClaim":false,
                        "revisionBeforePlayback":before.revision,
                        "expectedPostPlaybackSnapshotUnchanged":true,
                        "expectedPostPlaybackSaveBytesUnchanged":beforeBytes != nil,
                        "fullDonorSHA256":R047SHA256.hex(donorData), "playbackPrefixSHA256":R047SHA256.hex(prefixData)]
                    let metaData = try JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys])
                    try metaData.write(to:directory.appendingPathComponent("r047_\(traceRequest.saveKey)_plan.json"),options:.atomic)
                    await play(plan.playback,syntheticDash2TailR047:tailRequest)
                } else {
                    if let saveURL, let data = try? JSONEncoder().encode(battle) {
                        let filename = synthetic ? "r043_\(traceRequest?.saveKey ?? "missing")_battle.json" : "r6_preview_battle.json"
                        try? data.write(to: saveURL.deletingLastPathComponent().appendingPathComponent(filename), options: .atomic)
                    }
                    await play(battle,equipmentMotionTrace:traceRequest)
                }
                if !tailR047 { await presentBattleResolution(won:battle.won) }
                let after=await engine.snapshot()
                let afterBytes=saveURL.flatMap{try? Data(contentsOf:$0)}
                let snapshotUnchanged=before==after
                let unchanged=snapshotUnchanged && beforeBytes==afterBytes
                let fileState=beforeBytes != nil && afterBytes != nil ? "EXISTING_SAVE_BYTES":beforeBytes == nil && afterBytes == nil ? "NO_SAVE_BOTH":"FILE_EXISTENCE_CHANGED"
                let bytesVerified=beforeBytes != nil && afterBytes != nil && beforeBytes==afterBytes
                var traceValue:[String:Any]=["status":unchanged ? "PASS_CORE_SAVE_UNCHANGED":"FAIL_SAVE_CHANGED",
                                "encounterID":enemy.id,"seed":seed,"syntheticHPOverride":synthetic,
                                "syntheticEnemyHPMultiplier":synthetic ? SyntheticPartyDash2PreviewR043.enemyHPMultiplier:1,
                                "maxDurationMs":synthetic ? SyntheticPartyDash2PreviewR043.maxDurationMs:0,
                                "snapshotUnchanged":snapshotUnchanged,"fileState":fileState,
                                "existingFileBytesVerified":bytesVerified,
                                "saveKey":traceRequest?.saveKey ?? ""]
                if tailR047 {
                    traceValue.merge(["saveSnapshotUnchanged":snapshotUnchanged,"saveBytesUnchanged":bytesVerified,
                                      "revisionBefore":before.revision,"revisionAfter":after.revision,
                                      "engineCommandCount":0,"rewardGranted":false,"ordinaryBattleClaim":false]) { _,new in new }
                }
                let traceData=(try? JSONSerialization.data(withJSONObject:traceValue,options:.sortedKeys)) ?? Data()
                let traceText = String(data: traceData, encoding: .utf8) ?? "ENCODING_FAILED"
                if tailR047 {
                    writeR047Receipt("capture", saveKey: traceRequest?.saveKey, value: traceText,
                                     metadata: ["ordinaryBattleClaim":false,"rewardGranted":false])
                    writeR047Receipt("art", saveKey: traceRequest?.saveKey, value: scene.artAuditJSON())
                    writeR047Receipt("render_preparation", saveKey: traceRequest?.saveKey, value: preparation)
                } else if synthetic {
                    writeR043Receipt("capture", saveKey: traceRequest?.saveKey, value: traceText)
                    writeR043Receipt("art", saveKey: traceRequest?.saveKey, value: scene.artAuditJSON())
                    writeR043Receipt("render_preparation", saveKey: traceRequest?.saveKey, value: preparation)
                } else {
                    notice="R6検証完了・報酬なし・保存"+(unchanged ? "変更なし":"不一致")
                    writeReceipt("r6_preview",enemy.id+" won="+String(battle.won)+" snapshotUnchanged="+String(snapshotUnchanged)+" fileState="+fileState+" existingFileBytesVerified="+String(bytesVerified)+" profile="+R6CampaignQAAdapter.profileID)
                    writeReceipt("r6_preview_art",scene.artAuditJSON())
                }
                if !unchanged {error="R6検証で保存データの不一致を検出しました。"}
                if tailR047 { notice="R047合成視覚追跡完了・報酬なし・保存"+(unchanged ? "変更なし":"不一致") }
                else if synthetic { notice="R043合成プレビュー完了・報酬なし・保存"+(unchanged ? "変更なし":"不一致") }
            } catch {
                self.error=GameText.error(error)
                if tailR047 { writeR047Receipt("error", saveKey: traceRequest?.saveKey, value: String(reflecting:error)) }
                else if synthetic { writeR043Receipt("error", saveKey: traceRequest?.saveKey, value: String(reflecting:error)) }
                else if arguments.contains(EquipmentMotionTraceRequest.syntheticDash2Flag) { writeR043PreflightReceipt(String(reflecting:error)) }
                else { writeReceipt("r6_preview_error",String(reflecting:error)) }
            }
            scene.damageNumberDivisor=1
            if synthetic { activeAreaFightEnemyID = nil }
            busy=false;fighting=false;qaCombatPreview=false
            if synthetic { syncScene() }
        }
    }
}

private enum R047SHA256 {
    static func hex(_ data:Data)->String {
        #if canImport(CryptoKit)
        return CryptoKit.SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        #else
        return ""
        #endif
    }
}
