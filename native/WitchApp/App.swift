import SwiftUI
import SpriteKit
import CryptoKit

@main struct WitchGatheringApp: App {
    @StateObject private var model = GameModel()
    var body: some Scene { WindowGroup { RootView(model:model).preferredColorScheme(.dark) } }
}

@MainActor final class GameModel: ObservableObject {
    enum StartupState: Equatable { case loading, ready, failed(String) }
    private struct ArtAuditSettlePlan {
        let delaySeconds: Double
        let expectedState: String
        let contract: String
    }
    @Published private(set) var startupState: StartupState = .loading
    @Published private(set) var startupDiagnostic: String?
    private var qaStartupFailureInjected = false
    @Published var state = GameSnapshot()
    @Published var catalog: GameCatalog?
    @Published var error: String?
    @Published var notice: String = "小さな発見を、またひとつ。"
    @Published var preparationMessage: String?
    @Published var battleResolutionMessage: String?
    @Published var busy = false
    @Published var tab = "家"
    @Published var sheet: String?
    @Published var previewRecipeID: String?
    @Published var previewRecipeGearID: UUID?
    private var pendingGatherVisualMaterialID:String?
    @Published var selectedActor = "C_WITCH"
    @Published var chosenRegion = "R01"
    /// Transient field presentation context; this is not persisted in GameSnapshot.
    var activeAreaFightEnemyID:String?
    @Published var fighting = false
    /// Explicit XCTest-only barrier for party motion captures. Disabled unless all three
    /// isolated QA launch arguments are present; the ordinary QA and gameplay cadence is unchanged.
    @Published private(set) var qaPartyMotionStepMode = false
    @Published private(set) var qaPartyMotionStepWaitingPhase: String?
    private var qaPartyMotionStepContinuation: CheckedContinuation<Void, Never>?
    @Published var qaCombatPreview = false
    @Published var opening: [UUID] = []
    @Published var collectionSummary: GatheringSummary?
    @Published var comparison: [UUID] = []
    @Published var availableMaterials: [String:Set<String>] = [:]
    @Published var battleElapsed = 0
    var sceneActive = true
    var playbackTask: Task<Void,Never>?
    var lastBattleOperationID: UUID?
    let scene = LivingScene(size:CGSize(width:402,height:600))
    @Published var purchaseStatus="未開始"
    var qaPurchaseBridge:StoreKitLocalQABridge?
    var qaPurchaseSink:GameStoreKitQASink?
    @Published var qaFailPurchaseWrites=false
    var engine: GameEngine?
    var saveURL: URL?
    var qaLoadedExistingSave=false
    var qaEquipmentMultiRequestR084: EquipmentMultiConsumerRequestR084?
    static let spriteIDs = ["C_WITCH":"ERNA","C_APPRENTICE":"LUNA","C_SMITH":"AIRA","C_FAMILIAR":"NOIR"]
    static let actorNames = ["C_WITCH":"エルナ","C_APPRENTICE":"ルナ","C_SMITH":"アイラ","C_FAMILIAR":"ノワール"]
    init(){scene.scaleMode = .resizeFill;Task{await load()}}
    private func waitForQAPartyMotionAdvance(_ phase: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard qaPartyMotionStepContinuation == nil else {
                writeReceipt("party_motion_step", "INCOMPLETE_DUPLICATE_WAIT", metadata: ["phase": phase])
                continuation.resume()
                return
            }
            qaPartyMotionStepWaitingPhase = phase
            qaPartyMotionStepContinuation = continuation
            writeReceipt("party_motion_step", "WAITING_FOR_TEST_ADVANCE", metadata: ["phase": phase])
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(90))
                guard let self,
                      self.qaPartyMotionStepWaitingPhase == phase,
                      let pending = self.qaPartyMotionStepContinuation else { return }
                self.qaPartyMotionStepWaitingPhase = nil
                self.qaPartyMotionStepContinuation = nil
                self.writeReceipt("party_motion_step", "AUTO_ADVANCE_TIMEOUT", metadata: ["phase": phase])
                pending.resume()
            }
        }
    }

    func advanceQAPartyMotionStep() {
        guard qaPartyMotionStepMode,
              let phase = qaPartyMotionStepWaitingPhase,
              let continuation = qaPartyMotionStepContinuation else {
            writeReceipt("party_motion_step", "REJECTED_NO_PENDING_PHASE")
            return
        }
        qaPartyMotionStepWaitingPhase = nil
        qaPartyMotionStepContinuation = nil
        writeReceipt("party_motion_step", "ADVANCED_BY_XCTEST", metadata: ["phase": phase])
        continuation.resume()
    }

    func load() async {
        startupState = .loading
        let arguments=ProcessInfo.processInfo.arguments
        let qa=arguments.contains("--qa-isolated")
        AreaFlowQAHook.configure(arguments: arguments, isolated: qa)
        do {
            if qa,let value=arguments.first(where:{$0.hasPrefix("--qa-load-delay-ms=")}),let milliseconds=Int(value.dropFirst("--qa-load-delay-ms=".count)) {
                try await Task.sleep(for:.milliseconds(min(max(milliseconds,0),10_000)))
            }
            if qa,arguments.contains("--qa-load-failure-once"),!qaStartupFailureInjected {
                qaStartupFailureInjected=true
                throw CoreError.invalidCommand("QA one-shot startup failure")
            }
            let c=try GameCatalog.bundledTestOverlay();catalog=c
            let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Witch03to05R1")
            let fixture=qa ? arguments.first(where:{$0.hasPrefix("--qa-fixture=")}).map{String($0.dropFirst(13))}:nil
            let key=qa ? arguments.first(where:{$0.hasPrefix("--qa-save-key=")}).map{String($0.dropFirst(14)).filter{$0.isLetter || $0.isNumber || $0=="-"}}:nil
            qaPartyMotionStepMode = qa && !(key ?? "").isEmpty && arguments.contains("--qa-party-motion") && arguments.contains("--qa-party-motion-step")
            let recipeGoalScenario: RecipeGoalQAFixtureR037.Scenario?
            if qa && fixture == "recipe-goal-r037" {
                let request = try RecipeGoalQAFixtureR037.request(arguments: arguments)
                guard request.saveKey == key else { throw CoreError.invalidCommand("recipe-goal QA save key mismatch") }
                recipeGoalScenario = request.scenario
            } else { recipeGoalScenario = nil }
            let url=folder.appendingPathComponent(qa ? "qa-"+(key ?? "r002")+"-save.json":"save.json");saveURL=url
            qaLoadedExistingSave=qa && FileManager.default.fileExists(atPath:url.path)
            qaEquipmentMultiRequestR084 = nil
            if arguments.contains(where: { $0.hasPrefix(EquipmentMultiConsumerRequestR084.flagPrefix) || $0.hasPrefix(EquipmentMultiConsumerRequestR084.showcaseFlagPrefix) }) {
                switch EquipmentMultiConsumerRequestR084.parse(arguments: arguments, existingSaveLoaded: qaLoadedExistingSave) {
                case .success(let request): qaEquipmentMultiRequestR084 = request
                case .failure(let reason): throw CoreError.invalidCommand("equipment multi-consumer QA rejected: " + reason.rawValue)
                }
            }
            let latentPolicy = try CandidateLatentSlotPolicyR003.loadBundledR004()
            let initial: GameSnapshot
            if FileManager.default.fileExists(atPath: url.path) {
                // SaveRepository decodes the existing bytes; never generate missing slots.
                initial = GameSnapshot()
            } else if let request = qaEquipmentMultiRequestR084 {
                initial = try EquipmentMultiConsumerFixtureR084.make(catalog: c, variantID: request.variant.id)
            } else if let recipeGoalScenario {
                initial = try RecipeGoalQAFixtureR037.make(catalog: c, policy: latentPolicy, scenario: recipeGoalScenario)
            } else if qa && fixture == "latent-slots-r031" {
                initial = try LatentGearQAFixture.make(catalog: c, policy: latentPolicy)
            } else if fixture != nil {
                initial = try await QAScenarios.initial(catalog: c, scenario: fixture)
            } else {
                initial = try GameSnapshot.newCandidateGame(catalog: c, candidateLatentPolicy: latentPolicy)
            }
            let repository=try SaveRepository(initial:initial,fileURL:url)
            // Explicit development-candidate composition. The catalog and canonical
            // R6 source profiles remain unchanged; this is not Human adoption.
            // R017 paired saved/starter-loadout comparisons selected 500 bp for
            // this local development candidate. Core's default and R6 stay unchanged.
            let growthBP=qa ? arguments.first(where:{$0.hasPrefix("--qa-character-growth-bp=")}).flatMap{Int($0.dropFirst("--qa-character-growth-bp=".count))}:nil
            let growth=CandidateCharacterGrowth(strengthBP:growthBP.flatMap{[0,250,500,750,1000,2500,10000].contains($0) ? $0:nil} ?? 500)
            engine=try GameEngine(catalog:c,saves:repository,candidateCombatOverlay:.r014LocalCandidate,candidateCharacterGrowth:growth,candidateLatentPolicy:latentPolicy);await refresh()
            if qa { writeReceipt("candidate_latent_policy", "R005_UNAPPROVED_CANDIDATE|versionedItems=\(state.gear.filter{$0.candidateLatentSlots != nil}.count)|legacyItems=\(state.gear.filter{$0.candidateLatentSlots == nil}.count)") }
            if qa {writeReceipt("candidate_character_growth",growth.id+"|"+growth.status)}
            if qa { writeReceipt("candidate_combat_overlay","R014_E_R03_04|UNAPPROVED_TEST_OVERLAY|mark=800ms|windup=1200ms|coefficient=12500bp") }
            if qa,ProcessInfo.processInfo.arguments.contains("--qa-persist-fixture"),!FileManager.default.fileExists(atPath:url.path),let engine {
                guard let region=state.activeRegionID ?? c.regions.first?.id else{throw CoreError.invalidCommand("QA fixture has no region")}
                _ = try await engine.dispatch(.startExpeditionAt(regionID:region,now:Date()),operationID:UUID(),expectedRevision:state.revision)
                await refresh();writeReceipt("fixture_setup","Explicit QA fixture persisted before validation")
            }
            if state.lastClaimAt==nil,let engine {_ = try await engine.claimOffline(now:Date(),operationID:UUID(),expectedRevision:state.revision);await refresh()}
            if let recipeGoalScenario, let key, arguments.contains("--qa-recipe-goal-baseline") {
                let baselineURL = folder.appendingPathComponent("recipe_goal_fixture_" + key + ".json")
                if !qaLoadedExistingSave {
                    let data = try RecipeGoalQAFixtureR037.receiptData(scenario: recipeGoalScenario,
                                                                      saveKey: key, catalog: c, state: state)
                    // A unique receipt is retained per save key. Never replace a previous baseline.
                    try data.write(to: baselineURL, options: .withoutOverwriting)
                } else if !FileManager.default.fileExists(atPath: baselineURL.path) {
                    throw CoreError.invalidCommand("recipe-goal QA baseline is missing for this existing save")
                }
            }
            // Restore the saved expedition before choosing the initial screen.
            // Keep this out of refresh(): challenge playback temporarily displays
            // another region and must not jump back during foreground refreshes.
            if let region=state.activeRegionID,c.regions.contains(where:{$0.id==region}) {
                chosenRegion=region
            }
            if let s=arguments.first(where:{$0.hasPrefix("--screen=")}) {let v=String(s.dropFirst(9));if ["家","探索","仲間","工房","採集帳"].contains(v){tab=v}else{sheet=v}}
            if qa, fixture == "latent-slots-r031", arguments.contains("--qa-latent-compare") {
                comparison = [LatentGearQAFixture.lowItemID, LatentGearQAFixture.highItemID]
                sheet = "比較"
            }
            syncScene()
            if qa, arguments.contains(where: { $0.hasPrefix(ERNAStaffWalkCycleRequestR002.flag) }) {
                if let saveURL, let key, let fixture {
                    switch ERNAStaffWalkCycleRequestR002.parse(arguments: arguments, fixture: fixture,
                                                               saveKey: key, existingSaveLoaded: qaLoadedExistingSave,
                                                               outputDirectory: saveURL.deletingLastPathComponent()) {
                    case .success(let request):
                        tab = "探索"
                        chosenRegion = state.activeRegionID ?? c.regions.first?.id ?? "R01"
                        syncScene()
                        let result = scene.beginERNAStaffWalkCycleTrace(
                            request: request, outputDirectory: saveURL.deletingLastPathComponent(),
                            onStatus: { [weak self] value, details in
                                guard let self else { return }
                                self.writeReceipt("erna_staff_walk_cycle_start", value,
                                    metadata: details.merging(["gearID": request.gearID, "costume": request.costume,
                                                               "fixture": request.fixture, "saveKey": request.saveKey]) { current, _ in current })
                            })
                        let value = result["queued"] as? Bool == true ? "ARMING_STABLE_SCENE" : "PRECONDITION_FAIL"
                        writeReceipt("erna_staff_walk_cycle_start", value,
                                     metadata: result.merging(["gearID": request.gearID, "costume": request.costume,
                                                               "fixture": request.fixture, "saveKey": request.saveKey]) { current, _ in current })
                    case .failure(let failure):
                        writeReceipt("erna_staff_walk_cycle_start", "PRECONDITION_FAIL", metadata: ["reason": failure.rawValue])
                    }
                } else {
                    writeReceipt("erna_staff_walk_cycle_start", "PRECONDITION_FAIL", metadata: ["reason": "save_or_fixture_context_missing"])
                }
            }
            if qaLoadedExistingSave, recipeGoalScenario == .gatherShortage { writeRecipeGatherSnapshotR039("reopened") }
            WitchAudioCoordinator.shared.runQASmokeProbeIfRequested()
            await WitchMusicCoordinator.shared.runQAProbeIfRequested()
            if qa,let arg=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--qa-pose=")}) {
                let pose=String(arg.dropFirst(10))
                if ["idle","anticipate","execute","recover","hit","resolve"].contains(pose) {scene.auditPartyState(pose);writeReceipt("appearance_art",scene.artAuditJSON())}
            }
            if localStoreKitQAEnabled {do{try await startLocalStoreKitQA()}catch{purchaseStatus=String(reflecting:error)}}
            if qa,let arg=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--qa-challenge=")}),let challenge=c.challenges.first(where:{$0.id==String(arg.dropFirst(15))}) {self.challenge(challenge)}
            if qa,let arg=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--qa-r6-preview=")}),let enemy=c.enemies.first(where:{$0.id==String(arg.dropFirst(16))}) {previewCampaignR6(enemy)}
            if qa,
               !ProcessInfo.processInfo.arguments.contains(where: {$0.hasPrefix("--qa-r6-preview=")}),
               let arg=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--qa-encounter=")}),let enemy=c.enemies.first(where:{$0.id==String(arg.dropFirst(15))}) {
                chosenRegion=enemy.regionID;tab="探索"
                if let engine {_ = try await engine.dispatch(.startExpeditionAt(regionID:enemy.regionID,now:Date()),operationID:UUID(),expectedRevision:state.revision);await refresh()}
                syncScene();fight(enemy)
            }
            if let request = qaEquipmentMultiRequestR084, request.evidenceMode == "forced_render_showcase", let saveURL {
                chosenRegion = "R01"; tab = "探索"; fighting = true; busy = true; syncScene(); scene.setEnemies([])
                Task {
                    let start = ProcessInfo.processInfo.systemUptime
                    while scene.view == nil && ProcessInfo.processInfo.systemUptime - start < 10 {
                        try? await Task.sleep(for: .milliseconds(30))
                    }
                    let started = scene.beginEquipmentMultiR084(request: request, outputDirectory: saveURL.deletingLastPathComponent())
                    writeReceipt("equipment_multi_start", started ? "STARTED_SHOWCASE" : "PRECONDITION_FAIL")
                    while scene.equipmentMultiActiveR084 && ProcessInfo.processInfo.systemUptime - start < 60 && !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(30))
                    }
                    if scene.equipmentMultiActiveR084 { scene.finishEquipmentMultiR084(reason: "SHOWCASE_TIMEOUT_OR_CANCELLED") }
                    busy = false
                    writeReceipt("equipment_multi_showcase", "FINISHED_CHECK_RAW_TRACE", metadata: ["naturalCombatEvidence": false])
                }
            }
            if qa,ProcessInfo.processInfo.arguments.contains("--qa-party-motion") {
                tab="探索";fighting=true;syncScene();scene.setEnemies([])
                Task {for state in ["idle","walk","anticipate","execute","recover","hit","resolve"] {
                    notice="味方動作検証: "+state;scene.auditPartyState(state);writeReceipt("party_state",state)
                    try? await Task.sleep(for:.milliseconds(200));writeReceipt("party_geometry",scene.artAuditJSON())
                    if qaPartyMotionStepMode { await waitForQAPartyMotionAdvance(state) }
                    else { try? await Task.sleep(for:.milliseconds(1800)) }
                };qaPartyMotionStepMode=false;qaPartyMotionStepWaitingPhase=nil;fighting=false;writeReceipt("party_art",scene.artAuditJSON())}
            }
            if qa,let arg=arguments.first(where:{$0.hasPrefix("--qa-effect=")}) {
                let id=String(arg.dropFirst(12));chosenRegion=id.components(separatedBy:"_").first{$0.hasPrefix("R")} ?? "R01";tab="探索";fighting=true;notice="演出の表示検証";syncScene()
                Task {try? await Task.sleep(for:.milliseconds(300));scene.auditEffect(id);try? await Task.sleep(for:.milliseconds(100));writeReceipt("effect_art",scene.artAuditJSON());try? await Task.sleep(for:.seconds(2));writeReceipt("effect_cleanup",scene.artAuditJSON());fighting=false}
            }
            if qa,let arg=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--art-audit=")}) {
                let id=String(arg.dropFirst(12));tab="探索";chosenRegion=id.components(separatedBy:"_").first{$0.hasPrefix("R")} ?? "R01";fighting=true;syncScene();scene.setEnemy(id.replacingOccurrences(of:"ACT_",with:""));
                Task {
                    let preparation: String
                    do {
                        preparationMessage="戦闘アートの描画を準備しています…"
                        defer { preparationMessage = nil }
                        var viewWaitMilliseconds = 0
                        while scene.view == nil && !Task.isCancelled && viewWaitMilliseconds < 10_000 {
                            do { try await Task.sleep(for:.milliseconds(25)) } catch { return }
                            viewWaitMilliseconds += 25
                        }
                        guard !Task.isCancelled else { return }
                        do { try await Task.sleep(for:.milliseconds(25)) } catch { return }
                        preparation = await scene.prepareRegisteredEnemyRendering()
                    }
                    writeReceipt("registered_render_preparation", preparation)
                    if EnemyLoopBoundaryTraceQA.isRequested(), let saveURL,
                       let saveKeyArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--qa-save-key=") }) {
                        let saveKey = String(saveKeyArgument.dropFirst("--qa-save-key=".count))
                        let result = await scene.runEnemyLoopBoundaryTrace(
                            actorID: id, saveKey: saveKey,
                            outputDirectory: saveURL.deletingLastPathComponent())
                        writeReceipt("loop_boundary_trace", result)
                        fighting = false
                        writeReceipt("art_audit", scene.artAuditJSON())
                        return
                    }
                    if await runDragonWalkMeshPauseQAIfRequested(actorID: id) { return }
                    var modes=EnemyMotionState.requiredStates
                    let renderBoundR084Requested = ProcessInfo.processInfo.arguments.contains("--qa-isolated")
                        && ProcessInfo.processInfo.arguments.contains("--qa-render-bound-enemy-state-r084")
                    if renderBoundR084Requested {
                        if let selected = RenderBoundStateObserverR084.requestedStates(actorID: id) {
                            modes = selected.compactMap(EnemyMotionState.init(rawValue:))
                        } else {
                            modes = []
                            writeReceipt("render_bound_r084_precondition", "INCOMPLETE_UNSUPPORTED_ACTOR", metadata: ["actorID": id])
                        }
                    } else if ProcessInfo.processInfo.arguments.contains("--qa-art-flight") {
                        modes += [.flight,.idle,.walk,.idle]
                    }
                    for mode in modes {
                        notice="美術検証: "+mode.rawValue
                        if renderBoundR084Requested {
                            let requestID = UUID().uuidString
                            guard let settlePlan = renderBoundSettlePlanR084(actorID: id, state: mode.rawValue) else {
                                writeReceipt("render_bound_r084_\(id)_\(mode.rawValue)", "INCOMPLETE_NO_SETTLE_CONTRACT", metadata: ["requestID": requestID, "actorID": id, "requestedState": mode.rawValue])
                                continue
                            }
                            let expectedR064Walk = id == "ACT_B_R04_B" && mode == .walk
                            let payload = await scene.runRenderBoundStateRequestR084(
                                requestID: requestID, actorID: id, state: mode,
                                expectedSettledState: settlePlan.expectedState,
                                looping: settlePlan.contract == "loop_remains_active",
                                expectedR064WalkBackend: expectedR064Walk)
                            writeReceipt("render_bound_r084_\(id)_\(mode.rawValue)", payload, metadata: [
                                "requestID": requestID,
                                "actorID": id,
                                "requestedState": mode.rawValue,
                                "nominalFollowupContract": settlePlan.contract,
                                "nominalDelaySeconds": settlePlan.delaySeconds,
                                "r064BackendRequired": expectedR064Walk
                            ])
                            continue
                        }
                        let requestID = UUID().uuidString
                        let requestUptime = ProcessInfo.processInfo.systemUptime
                        let settlePlan = artAuditSettlePlan(actorID: id, state: mode.rawValue)
                        var requestMetadata: [String: Any] = [
                            "qaStateRequestID": requestID,
                            "qaRequestedState": mode.rawValue,
                            "qaRequestUptime": requestUptime
                        ]
                        if let settlePlan {
                            requestMetadata["qaExpectedSettledState"] = settlePlan.expectedState
                            requestMetadata["qaSettleDelaySeconds"] = settlePlan.delaySeconds
                            requestMetadata["qaSettleContract"] = settlePlan.contract
                        }
                        scene.auditEnemyState(mode)
                        writeReceipt("art_state",id+":"+mode.rawValue,metadata:requestMetadata)
                        try? await Task.sleep(for:.milliseconds(150))
                        let earlyPayload=scene.artAuditJSON()
                        var earlyMetadata=requestMetadata
                        earlyMetadata["qaSampleUptime"] = ProcessInfo.processInfo.systemUptime
                        writeReceipt("art_sample_"+mode.rawValue+"_early",earlyPayload,metadata:earlyMetadata)
                        try? await Task.sleep(for:.milliseconds(250))
                        let latePayload=scene.artAuditJSON()
                        var lateMetadata=requestMetadata
                        lateMetadata["qaSampleUptime"] = ProcessInfo.processInfo.systemUptime
                        writeReceipt("art_sample_"+mode.rawValue+"_late",latePayload,metadata:lateMetadata)
                        if let settlePlan {
                            let targetUptime=requestUptime+settlePlan.delaySeconds
                            let remaining=targetUptime-ProcessInfo.processInfo.systemUptime
                            if remaining > 0 {
                                try? await Task.sleep(for:.milliseconds(max(1,Int(remaining*1000)+10)))
                            }
                            let settledPayload=scene.artAuditJSON()
                            var settledMetadata=requestMetadata
                            settledMetadata["qaSampleUptime"] = ProcessInfo.processInfo.systemUptime
                            writeReceipt("art_sample_"+mode.rawValue+"_settled",settledPayload,metadata:settledMetadata)
                        } else {
                            writeReceipt("art_sample_"+mode.rawValue+"_settled","settle timing unavailable",metadata:requestMetadata.merging(["qaSettleContract":"missing_timing"]) { _, new in new })
                        }
                        try? await Task.sleep(for:.milliseconds(1600))
                    }
                    fighting=false
                    writeReceipt("art_audit",scene.artAuditJSON())
                }
            }
            runActiveBattleQAIfRequested()
            startupState = .ready
            if qa { await runIsolatedWalkCycleR018IfRequested(arguments: arguments, fixture: fixture, saveKey: key) }
            if qa { runGatherNodeRuntimeQAIfRequested() }
            if qa { writeQASaveReadbackIfRequested() }
            if qa {runPartyFrameAuditIfRequested()}
            if qa { runEffectMechanicPreviewIfRequested() }
            if qa { runMultiEnemyMechanicPreviewIfRequested() }
            if qa { runEffectBudgetRegressionIfRequested() }
            if qa { runSceneTextureCacheQAIfRequested() }
            if qa && (arguments.contains(where:{$0.hasPrefix("--qa-area-flow-b64=")}) || arguments.contains(where:{$0.hasPrefix("--qa-area-availability-probe=")})) {
                Task { await runAreaFlowQAHookIfRequested() }
            }
        }catch{
            let diagnostic=String(reflecting:error)
            startupDiagnostic=diagnostic
            NSLog("Witch startup load failed: %@",diagnostic)
            startupState = .failed("保存データまたはゲーム資料を開けませんでした。もう一度お試しください。")
        }
    }
    func refresh() async {if let engine{state=await engine.snapshot();for region in catalog?.regions ?? [] {availableMaterials[region.id]=Set(await engine.availableGatherMaterials(in:region.id))}}; syncScene()}
    /// R015 local candidate route: active battle enemy first, otherwise the selected
    /// gather material, otherwise the first R4 area for the selected region.
    private var areaSceneResolution:R015AreaSceneResolution? {
        guard tab == "探索" else { return nil }
        var availability = R015AreaSceneRouting.variantAvailability(index: ArtLibrary.index, artRoot: ArtLibrary.root)
        if let missing = AreaFlowQAHook.availabilityOverrideVariantID {
            availability = .init(fullFrameIDs: availability.fullFrameIDs.subtracting([missing]),
                                 layeredIDs: availability.layeredIDs.subtracting([missing]))
        }
        return R015AreaSceneRouting.resolve(regionID: chosenRegion,
                                            activeFightEnemyID: activeAreaFightEnemyID,
                                            selectedGatherMaterialID: activeAreaFightEnemyID == nil ? state.gatherTargetMaterialID : nil,
                                            availableVariantIDs: availability.fullFrameIDs.union(availability.layeredIDs),
                                            layeredVariantIDs: availability.layeredIDs)
    }
    var candidateCharacterGrowth:CandidateCharacterGrowth?{engine?.candidateCharacterGrowth}
    func characterProgress(for actorID:String)->CandidateCharacterGrowth.Progress? {
        guard candidateCharacterGrowth != nil else{return nil}
        return CandidateCharacterGrowth.progress(totalXP:state.characterXP[actorID,default:0])
    }
    func combatant(for actorID:String)->Combatant? {
        let gear=state.equippedGearIDs.filter{$0.key.hasPrefix(actorID+"|")}.values.compactMap{id in state.gear.first{$0.id==id}}
        return try? gearStats(for: actorID, with: gear).combatant
    }
    func syncScene() {
        let place:LivingScene.Place = tab == "探索" ? .field(chosenRegion)
            : tab == "仲間" ? .portrait(Self.spriteIDs[selectedActor] ?? "ERNA") : .home
        scene.configure(place:place,areaResolution:areaSceneResolution,
                        selectedGatherMaterialID:fighting ? nil:state.gatherTargetMaterialID,
                        cosmetics:sceneAppearance,furniture:sceneFurniture)
        // Configure the shared ambient session before the first music request,
        // including load/refresh calls made before RootView is constructed.
        _ = WitchAudioCoordinator.shared
        WitchMusicCoordinator.shared.setContext(fighting ? .battle : tab == "探索" ? .field : .home)
    }
    var sceneAppearance:[String:String] {
        var v=state.selectedCosmeticIDs
        let actorID="C_WITCH"
        let selectedAppearance=state.selectedWeaponAppearanceIDs[actorID]
        // Gear identity is distinct from the selected appearance sprite. Keep a
        // dedicated scene metadata key for observers and per-gear registration.
        v.removeValue(forKey: "WITCH_EQUIPPED_GEAR")
        if let instanceID=state.equippedGearIDs[actorID+"|weapon"],
           let instance=state.gear.first(where:{$0.id==instanceID}),
           let catalog,
           let projection=catalog.gearAppearanceProjection(for:instance,actorID:actorID,in:state),
           projection.isEquipped {
            v["WITCH_EQUIPPED_GEAR"] = projection.gearID
        }
        if let instanceID=state.equippedGearIDs[actorID+"|weapon"],
           let instance=state.gear.first(where:{$0.id==instanceID}),
           let catalog,
           let projection=catalog.gearAppearanceProjection(for:instance,actorID:actorID,in:state),
           let resolved=projection.resolvedWeaponSpriteAssetID {
            v["WITCH_WEAPON"]=resolved
        } else {
            // Keep the independently selected owned wardrobe appearance visible when no
            // supported/equipped gear attachment can be projected.
            v["WITCH_WEAPON"]=selectedAppearance
        }
        if let catalog {
            for candidate in catalog.equippedVisualCandidates(in:state) {v[candidate.sceneKey]=candidate.gearID}
        }
        return v
    }
    func act(_ command:GameCommand,_ message:String?=nil) {
        guard !busy,let engine else{return};busy=true
        Task {do{let receipt=try await engine.dispatch(command,operationID:UUID(),expectedRevision:state.revision);await refresh();WitchAudioCoordinator.shared.playAfterSuccessfulCommand(command,result:receipt.result);notice=message ?? receipt.result}catch{self.error=GameText.error(error);await refresh()};busy=false}
    }
    func collect(){guard !busy,let engine else{return};pendingGatherVisualMaterialID=nil;busy=true;Task{do{let before=state;let r=try await engine.claimOffline(now:Date(),operationID:UUID(),expectedRevision:state.revision);await refresh();collectionSummary=GatheringSummary(before:before,after:state);if let materialID=before.gatherTargetMaterialID,collectionSummary?.materials.contains(where:{$0.0==materialID && $0.1>0}) == true {pendingGatherVisualMaterialID=materialID};if collectionSummary?.isEmpty == false {WitchAudioCoordinator.shared.play(.gather)};notice=collectionSummary?.isEmpty == true ? "次の発見を待っています。":"採集の成果をしまいました。";sheet="採集の成果";writeReceipt("offline",r.result);writeRecipeGatherSnapshotR039("normal_claim")}catch{self.error=GameText.error(error)};busy=false}}
    func presentPendingGatherVisualAfterResultDismissal(){
        guard sheet == nil else { return }
        guard !fighting, tab == "探索", let materialID = pendingGatherVisualMaterialID else {
            if fighting || tab != "探索" { pendingGatherVisualMaterialID = nil }
            return
        }
        pendingGatherVisualMaterialID = nil
        scene.playGatherCollection(materialID: materialID)
    }
    func closeSheet(){ sheet=nil }
    private func artAuditSettlePlan(actorID:String,state:String)->ArtAuditSettlePlan? {
        guard let clips=ArtLibrary.index[actorID]?["clips"] as? [String:[String:Any]] else{return nil}
        func duration(_ name:String)->Double? {
            guard let clip=clips[name] else{return nil}
            if let frames=clip["frames"] as? [String],!frames.isEmpty,
               let fps=(clip["fps"] as? NSNumber)?.doubleValue,fps.isFinite,fps>0 {
                return Double(frames.count)/fps
            }
            if let value=clip["duration_seconds"] as? NSNumber {
                let seconds=value.doubleValue
                if seconds.isFinite,seconds>0{return seconds}
            }
            return nil
        }
        guard let current=clips[state],let currentDuration=duration(state) else{return nil}
        let expected:String
        let contract:String
        var total=currentDuration
        if state=="execute" {
            guard let recoverDuration=duration("recover") else{return nil}
            total += recoverDuration
            expected="idle"
            contract="execute_then_recover_to_idle"
        } else if current["loop"] as? Bool == true {
            expected=state
            contract="loop_remains_active"
        } else if state=="resolve" {
            expected="resolve"
            contract="terminal_resolve_holds"
        } else {
            expected="idle"
            contract="nonloop_returns_to_idle"
        }
        let delay=total+0.10
        guard delay.isFinite,delay>0,delay<=10 else{return nil}
        return ArtAuditSettlePlan(delaySeconds:delay,expectedState:expected,contract:contract)
    }
    /// R084's two dragon loop requests use the actual PartRig loop action and
    /// render readback; the legacy duration planner only understands sprite
    /// frame arrays and has no duration for this rig's idle/walk descriptors.
    private func renderBoundSettlePlanR084(actorID:String,state:String)->ArtAuditSettlePlan? {
        if actorID == "ACT_B_R04_B", (state == "idle" || state == "walk") {
            return ArtAuditSettlePlan(delaySeconds: 0, expectedState: state,
                                      contract: "loop_remains_active")
        }
        return artAuditSettlePlan(actorID: actorID, state: state)
    }
    func writeReceipt(_ kind:String,_ value:String,metadata:[String:Any]=[:]){guard let saveURL else{return};let p=saveURL.deletingLastPathComponent().appendingPathComponent("last_\(kind).json");var obj:[String:Any]=["kind":kind,"value":value,"revision":state.revision,"date":ISO8601DateFormatter().string(from:Date())];for (key,value) in metadata where !["kind","value","revision","date"].contains(key){obj[key]=value};if let d=try? JSONSerialization.data(withJSONObject:obj,options:.prettyPrinted){try? d.write(to:p,options:.atomic)}}
    /// Starts a renderer-only isolated walk capture after the normal field scene
    /// has rendered several stable frames. It never dispatches a game command.
    private func runIsolatedWalkCycleR018IfRequested(arguments: [String], fixture: String?, saveKey: String?) async {
        let flag = "--qa-equipment-walk-cycle-r018"
        guard arguments.contains(flag) else { return }
        let payloadArguments = Array(arguments.dropFirst())
        let keyArguments = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        let fixtureArguments = arguments.filter { $0.hasPrefix("--qa-fixture=") }
        let allowedArguments: (String) -> Bool = { argument in
            argument == "--qa-isolated" || argument == flag || argument == "--qa-readback-save" ||
            argument == "--qa-fixture=details-C_SMITH-03" || argument == "--qa-persist-fixture" || argument.hasPrefix("--qa-save-key=") ||
            argument == "--screen=探索" || argument.hasPrefix("--qa-load-delay-ms=")
        }
        guard arguments.contains("--qa-isolated"),
              arguments.filter({ $0 == flag }).count == 1,
              keyArguments.count == 1, fixtureArguments.count == 1,
              fixture == "details-C_SMITH-03",
              let saveKey, UUID(uuidString: saveKey) != nil,
              keyArguments[0] == "--qa-save-key=" + saveKey,
              fixtureArguments[0] == "--qa-fixture=details-C_SMITH-03",
              arguments.filter({ $0 == "--qa-persist-fixture" }).count == 1,
              !qaLoadedExistingSave,
              payloadArguments.allSatisfy(allowedArguments),
              let saveURL, let beforeBytes = try? Data(contentsOf: saveURL) else {
            writeReceipt("isolated_walk_cycle_r018_start", "PRECONDITION_FAIL",
                         metadata: ["reason": "requires_fresh_isolated_details_fixture_unique_uuid_and_only_allowlisted_args"])
            return
        }
        tab = "探索"
        chosenRegion = state.activeRegionID ?? catalog?.regions.first?.id ?? "R01"
        fighting = false
        syncScene()
        var previousFrame = -1
        var stableRenderedFrames = 0
        for _ in 0..<240 {
            guard !Task.isCancelled else {
                writeReceipt("isolated_walk_cycle_r018_start", "PRECONDITION_FAIL", metadata: ["reason": "cancelled_while_waiting_for_scene"])
                return
            }
            if scene.view != nil, scene.frames > previousFrame {
                stableRenderedFrames += 1
                previousFrame = scene.frames
                if stableRenderedFrames >= 3 { break }
            } else if scene.view == nil {
                stableRenderedFrames = 0
            }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
        }
        guard stableRenderedFrames >= 3 else {
            writeReceipt("isolated_walk_cycle_r018_start", "PRECONDITION_FAIL",
                         metadata: ["reason": "scene_not_rendering_three_stable_frames", "sceneFrames": scene.frames])
            return
        }
        let started = scene.beginIsolatedWalkCycleR018(saveKey: saveKey,
            outputDirectory: saveURL.deletingLastPathComponent())
        let beforeSHA = SHA256.hash(data: beforeBytes).map { String(format: "%02x", $0) }.joined()
        writeReceipt("isolated_walk_cycle_r018_start", started ? "ARMED_ISOLATED_RENDERER_CAPTURE" : "PRECONDITION_FAIL",
                     metadata: ["saveKey": saveKey, "fixture": fixture ?? "",
                                "gearID": "EQ_S_03", "actorID": "AIRA",
                                "sceneFramesAtArm": scene.frames, "stableRenderedFrames": stableRenderedFrames,
                                "stateRevision": state.revision, "saveSHA256Before": beforeSHA,
                                "gameCommandDispatched": false,
                                "scope": "isolated_existing_playWalk_renderer"])
        guard started else { return }
        let filenamePrefix = "walk_cycle_r018_\(saveKey)_"
        var result: [String: Any]?
        var resultFilename: String?
        for _ in 0..<240 {
            if let urls = try? FileManager.default.contentsOfDirectory(at: saveURL.deletingLastPathComponent(),
                                                                       includingPropertiesForKeys: nil),
               let url = urls.first(where: { $0.lastPathComponent.hasPrefix(filenamePrefix) && $0.pathExtension == "json" }),
               let data = try? Data(contentsOf: url),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = object
                resultFilename = url.lastPathComponent
                break
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        let afterBytes = try? Data(contentsOf: saveURL)
        let afterSHA = afterBytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing"
        let status = result?["status"] as? String ?? "INCOMPLETE_RECEIPT_TIMEOUT"
        writeReceipt("isolated_walk_cycle_r018_result", status,
                     metadata: ["saveKey": saveKey, "resultFilename": resultFilename ?? "",
                                "saveSHA256Before": beforeSHA, "saveSHA256After": afterSHA,
                                "saveBytesUnchanged": beforeSHA == afterSHA,
                                "stateRevision": state.revision,
                                "scope": "isolated_renderer_only_not_ordinary_gameplay"])
    }
    func fight(_ enemy:EnemyDefinition){
        guard !busy,let engine else{return};busy=true;fighting=true;activeAreaFightEnemyID=enemy.id;syncScene();scene.setEnemy(enemy.id)
        let qaArgs = ProcessInfo.processInfo.arguments
        var fullBattleEquipmentMotionRequest: EquipmentMotionTraceRequest?
        if qaArgs.contains(where: { $0.hasPrefix("--qa-equipment-motion-trace") }) {
            if let saveURL {
                let result = EquipmentMotionTraceRequest.parse(
                    arguments: qaArgs, actualEncounterID: enemy.id,
                    outputDirectory: saveURL.deletingLastPathComponent(),
                    existingSaveLoaded: qaLoadedExistingSave)
                switch result {
                case .success(let request):
                    // Full-battle recording arms after normal scene preparation.
                    // refresh/configure may legitimately rebuild the pre-battle scene.
                    let started: Bool
                    if request.captureScope == .fullBattleParty {
                        fullBattleEquipmentMotionRequest = request
                        started = true
                    } else {
                        started = scene.beginEquipmentMotionTrace(request: request,
                            outputDirectory: saveURL.deletingLastPathComponent())
                    }
                    writeReceipt("equipment_motion_trace_start", request.captureScope == .fullBattleParty ? "PENDING_BATTLE_PREPARATION" : (started ? "STARTED" : "PRECONDITION_FAIL"),
                                 metadata: ["actorID":EquipmentMotionTraceRequest.actorID,
                                            "gearID":EquipmentMotionTraceRequest.gearID,
                                            "fixture":request.fixture, "encounterID":request.encounterID,
                                            "saveKey":request.saveKey])
                case .failure(let failure):
                    writeReceipt("equipment_motion_trace_start", "PRECONDITION_FAIL", metadata: ["reason":failure.rawValue])
                }
            } else {
                writeReceipt("equipment_motion_trace_start", "PRECONDITION_FAIL", metadata: ["reason":"save_directory_unavailable"])
            }
        }
        var ernaStaffMotionTraceRequest: ERNAStaffMotionTraceRequestR040?
        if qaArgs.contains(where: { $0.hasPrefix(ERNAStaffMotionTraceRequestR040.flag) }) {
            if let saveURL {
                switch ERNAStaffMotionTraceRequestR040.parse(
                    arguments: qaArgs, actualEncounterID: enemy.id,
                    outputDirectory: saveURL.deletingLastPathComponent(),
                    existingSaveLoaded: qaLoadedExistingSave) {
                case .success(let request):
                    ernaStaffMotionTraceRequest = request
                    writeReceipt("erna_staff_motion_trace_start", "PENDING_BATTLE_PREPARATION",
                                 metadata: ["gearID": request.gearID, "costume": request.costume,
                                            "fixture": request.fixture, "encounterID": request.encounterID,
                                            "saveKey": request.saveKey])
                case .failure(let failure):
                    writeReceipt("erna_staff_motion_trace_start", "PRECONDITION_FAIL",
                                 metadata: ["reason": failure.rawValue])
                }
            } else {
                writeReceipt("erna_staff_motion_trace_start", "PRECONDITION_FAIL",
                             metadata: ["reason": "save_directory_unavailable"])
            }
        }
        let battleBefore=state
        let operationID=UUID();lastBattleOperationID=operationID
        if ProcessInfo.processInfo.arguments.contains("--qa-isolated"),let data=try? JSONEncoder().encode(state),let saveURL {try? data.write(to:saveURL.deletingLastPathComponent().appendingPathComponent("battle_before.json"),options:.atomic)}
        playbackTask=Task{do{
            let r=try await engine.dispatch(.resolveEncounter(enemyID:enemy.id,seed:UInt64(bitPattern:state.revision) &+ 1001),operationID:operationID,expectedRevision:state.revision)
            await refresh()
            if let battle=state.lastCombatResult {
                await play(battle, equipmentMotionTrace: fullBattleEquipmentMotionRequest,
                           ernaStaffMotionTrace: ernaStaffMotionTraceRequest)
                if battle.won {
                    let delta=GatheringSummary(before:battleBefore,after:state)
                    let gains=delta.materials+delta.currency+delta.experience
                    let rewardLine=gains.map { "\(GameText.name($0.0)) +\($0.1)" }.joined(separator:"・")
                    notice="\(enemy.name)を乗り越えました。獲得: \(rewardLine.isEmpty ? "なし" : rewardLine)"
                } else {
                    notice="あと少し。装備と研究を見直そう。"
                }
            }else{notice=r.result}
            await presentBattleResolution(won:state.lastCombatResult?.won ?? false);writeReceipt("battle",r.result);writeReceipt("battle_art",scene.artAuditJSON())
        }catch{self.error=GameText.error(error);writeReceipt("battle_error",String(reflecting:error))};activeAreaFightEnemyID=nil;busy=false;fighting=false;syncScene()}
    }
    func summon(_ count:Int){guard let catalog,!busy,let engine else{return};busy=true;Task{do{let before=Set(state.gear.map(\.id));_ = try await engine.dispatch(.mockSummon(poolDefinitionIDs:catalog.gear.map(\.id),count:count,costCurrencyID:"ticket_free",seed:(UInt64(bitPattern:state.revision) &+ 17)),operationID:UUID(),expectedRevision:state.revision);await refresh();opening=state.gear.map(\.id).filter{!before.contains($0)};sheet="開封";notice="新しい装備が届きました。"}catch{self.error=GameText.error(error)};busy=false}}
    func daily(){act(.dailyClaim(now:Date()),"今日の無料鑑定券を受け取りました。")}
}

enum Palette {static let ink=Color(red:0.035,green:0.065,blue:0.085);static let panel=Color(red:0.055,green:0.10,blue:0.12);static let gold=Color(red:0.82,green:0.69,blue:0.43);static let text=Color(red:0.94,green:0.91,blue:0.82)}

struct RootView:View {
    @State private var workshopMode = "craft_new"
    @State private var enemyPage=0
    @State private var exploreControlsExpanded=false
    @State private var pendingRecipeGatherHandoff: RecipeGatherHandoffR039?
    @ObservedObject var model:GameModel
    @ObservedObject private var audio = WitchAudioCoordinator.shared
    @ObservedObject private var music = WitchMusicCoordinator.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body:some View {
        Group {
            switch model.startupState {
            case .loading: startupView
            case .failed(let message): startupFailureView(message)
            case .ready: readyView
            }
        }.tint(Palette.gold)
    }
    private var readyView: some View {
        GeometryReader { _ in
            ZStack {Palette.ink.ignoresSafeArea()
                VStack(spacing:0){header
                    ZStack(alignment:.bottom){
                        SpriteView(scene:model.scene)
                            .accessibilityElement(children:.ignore)
                            .accessibilityLabel(sceneAccessibilitySummary)
                            .accessibilityAddTraits(.isImage)
                            .accessibilityIdentifier("living_scene")
                        if model.tab == "家" {homeOverlay}
                        else if model.tab == "探索" {exploreOverlay}
                        else if model.tab == "仲間" {companionOverlay}
                        else {Palette.ink; ScrollView{if model.tab == "工房"{workshop}else{journal}}.accessibilityIdentifier("workshop_scroll")}
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
                    footer
                }
            }.sheet(isPresented:Binding(get:{model.sheet != nil},set:{if !$0{model.sheet=nil}}),onDismiss:{model.presentPendingGatherVisualAfterResultDismissal()}){sheet(model.sheet ?? "設定")}
            .alert("確認が必要です",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("閉じる",role:.cancel){model.error=nil}}message:{Text(model.error ?? "")}
            .onChange(of:model.fighting){_,fighting in if fighting {exploreControlsExpanded=false;pendingRecipeGatherHandoff=nil}}
            .onChange(of:model.tab){_,tab in
                if tab != "探索", pendingRecipeGatherHandoff != nil {
                    pendingRecipeGatherHandoff = nil
                    model.chosenRegion = model.state.activeRegionID ?? model.chosenRegion
                }
                model.syncScene()
            }.onChange(of:model.selectedActor){_,_ in model.syncScene()}
            .onChange(of:phase){_,p in
                model.sceneActive = p == .active
                model.scene.isPaused = p != .active
                model.scene.auditBattleEntryLifecycle(phase:p == .active ? "active" : p == .background ? "background" : "inactive")
                if p == .active {Task{await model.refresh()}}
            }
        }
    }
    private var startupView: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            VStack(spacing:16) {
                Image(systemName:"moon.stars.fill").font(.system(size:36)).foregroundStyle(Palette.gold).accessibilityHidden(true)
                Text("魔女の採集帳").font(.system(size:26,weight:.semibold,design:.serif)).foregroundStyle(Palette.text)
                ProgressView().tint(Palette.gold)
                Text("暮らしの準備をしています…").font(.body).foregroundStyle(Palette.text).accessibilityIdentifier("launch_loading")
            }.padding(28).accessibilityElement(children:.contain)
        }
    }
    private func startupFailureView(_ message:String) -> some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            VStack(spacing:16) {
                Image(systemName:"moon.stars.fill").font(.system(size:36)).foregroundStyle(Palette.gold).accessibilityHidden(true)
                Text("魔女の採集帳").font(.system(size:26,weight:.semibold,design:.serif)).foregroundStyle(Palette.text)
                Text("起動できませんでした").font(.title3).foregroundStyle(Palette.text)
                Text(message).font(.body).multilineTextAlignment(.center).foregroundStyle(Palette.text).accessibilityIdentifier("launch_error")
                Button("もう一度読み込む") { Task { await model.load() } }
                    .frame(minWidth:180,minHeight:48).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:10))
                    .accessibilityIdentifier("launch_retry")
            }.padding(28).accessibilityElement(children:.contain)
        }
    }
    private var sceneAccessibilitySummary:String {
        if model.qaCombatPreview { return "戦闘検証プレビュー。報酬はありません。" }
        if model.fighting { return "\(model.catalog?.regions.first{$0.id==model.chosenRegion}?.name ?? "探索")で仲間4人が自動戦闘中です。戦闘操作はありません。" }
        if model.tab == "家" {
            let activity=model.sceneFurniture.contains("FURN_DESK_BOTANICAL") ? "植物研究の机でルナが本を読んでいます。":""
            return "家の背景です。エルナ、ルナ、アイラ、ノワールが過ごしています。"+activity+"模様替えや探索は画面上のボタンから操作できます。"
        }
        if model.tab == "探索" { return "\(model.catalog?.regions.first{$0.id==model.chosenRegion}?.name ?? "探索")の背景です。仲間4人と出会った魔物が表示されています。地域は上部から、採集素材と魔物は採集・魔物ボタンから選べます。" }
        if model.tab == "仲間" { return "仲間の背景です。上部から仲間を選び、試着または装備比較へ進めます。" }
        return "装飾背景です。操作は画面上のテキストとボタンから行えます。"
    }
    private var header:some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:8) {
                    HStack(spacing:10) {
                        Image(systemName:"moon.stars.fill").font(.title).foregroundStyle(Palette.gold).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:2) {
                            Text("魔女の採集帳").font(.system(size:20,weight:.semibold,design:.serif))
                            if !dynamicTypeSize.isAccessibilitySize {
                                Text(model.tab=="家" ? "森の奥から、ただいま。":model.tab).font(.caption).foregroundStyle(Palette.gold)
                            } else if model.tab != "家" {
                                Text(model.tab).font(.caption).foregroundStyle(Palette.gold)
                            }
                        }
                        Spacer(minLength:4)
                        Button{model.sheet="設定"}label:{Image(systemName:"gearshape").frame(width:44,height:44)}
                            .accessibilityLabel("設定を開く").accessibilityIdentifier("settings")
                    }
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:20) {
                            currencyLabel("コイン",value:model.state.currency["coin",default:0],symbol:"circle.fill")
                            currencyLabel("無料鑑定券",value:model.state.currency["ticket_free",default:0],symbol:"sparkles")
                        }.fixedSize()
                        VStack(alignment:.leading,spacing:4) {
                            currencyLabel("コイン",value:model.state.currency["coin",default:0],symbol:"circle.fill")
                            currencyLabel("無料鑑定券",value:model.state.currency["ticket_free",default:0],symbol:"sparkles")
                        }.fixedSize(horizontal:false,vertical:true)
                    }.font(.caption.monospacedDigit())
                }
            } else {
                HStack(spacing:12){
                    Image(systemName:"moon.stars.fill").font(.title).foregroundStyle(Palette.gold).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:2){Text("魔女の採集帳").font(.system(size:20,weight:.semibold,design:.serif));Text(model.tab=="家" ? "森の奥から、ただいま。":model.tab).font(.caption).foregroundStyle(Palette.gold)}
                    Spacer(minLength:4)
                    VStack(alignment:.trailing,spacing:3){currencyLabel("コイン",value:model.state.currency["coin",default:0],symbol:"circle.fill");currencyLabel("無料鑑定券",value:model.state.currency["ticket_free",default:0],symbol:"sparkles")}.font(.caption.monospacedDigit())
                    Button{model.sheet="設定"}label:{Image(systemName:"gearshape").frame(width:44,height:44)}.accessibilityLabel("設定を開く").accessibilityIdentifier("settings")
                }
            }
        }.padding(.horizontal,16).padding(.vertical,8).foregroundStyle(Palette.text).background(Palette.ink).overlay(alignment:.bottom){Rectangle().fill(Palette.gold.opacity(0.5)).frame(height:1)}
    }
    private func currencyLabel(_ title:String,value:Int,symbol:String)->some View {
        Label("\(value)",systemImage:symbol).accessibilityLabel("所持\(title) \(value)")
    }
    private var footer:some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    ForEach(["家","探索","仲間","工房","採集帳"],id:\.self) { name in
                        Button { model.tab=name } label: { Label(name,systemImage:model.tab==name ? "checkmark":"circle") }
                            .accessibilityIdentifier("choose_tab_"+name)
                    }
                } label: {
                    HStack {
                        Text("移動："+model.tab).font(.caption.weight(.medium)).fixedSize(horizontal:false,vertical:true)
                        Spacer(minLength:4)
                        Image(systemName:"chevron.up.chevron.down").accessibilityHidden(true)
                    }.padding(12).frame(maxWidth:.infinity,minHeight:56).foregroundStyle(Palette.text)
                }.disabled(model.fighting).accessibilityLabel("画面を選ぶ、"+model.tab)
                    .accessibilityHint("家、探索、仲間、工房、採集帳へ移動します")
                    .accessibilityIdentifier("tab_"+model.tab)

            } else {
                HStack(spacing:0) {
                    ForEach(Array(zip(["家","探索","仲間","工房","採集帳"],["house.fill","safari","person.2.fill","hammer","book.closed"])),id:\.0) { name,symbol in tabButton(name,symbol) }
                }
            }
        }.padding(.horizontal,8).padding(.top,8).background(Palette.ink).overlay(alignment:.top){Rectangle().fill(Palette.gold.opacity(0.5)).frame(height:1)}
    }
    private func tabButton(_ name:String,_ symbol:String)->some View {
        Button{model.tab=name}label:{
            VStack(spacing:6){Image(systemName:symbol).font(.system(size:22)).accessibilityHidden(true);Text(name).font(.caption.weight(.medium)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)}
                .frame(maxWidth:.infinity,minHeight:dynamicTypeSize.isAccessibilitySize ? 72:58).foregroundStyle(model.tab==name ? Palette.gold:Palette.text.opacity(0.92))
        }.buttonStyle(.plain).disabled(model.fighting).accessibilityLabel(name).accessibilityAddTraits(model.tab==name ? .isSelected:[]).accessibilityIdentifier("tab_"+name)
    }
    @ViewBuilder private func gatheringProgress(showMaterialName:Bool = true) -> some View {
        if let catalog = model.catalog {
            GatheringProgressViewR041(catalog:catalog,state:model.state,showMaterialName:showMaterialName)
        }
    }
    private var homeOverlay:some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Reserve the upper 58% of the scene for the room and party.
                        Spacer(minLength: 0)
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 10) {
                                accessibilityHomeClaimAction
                                gatheringProgress()
                                VStack(alignment: .leading, spacing: 8) {
                                    Button { model.sheet = "模様替え" } label: {
                                        Label("模様替え", systemImage: "chair.lounge")
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    }
                                    Button { model.sheet = "魔導庫" } label: {
                                        Label("魔導庫", systemImage: "sparkles")
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    }
                                    Button("試着") { model.sheet = "試着" }
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .accessibilityIdentifier("home_try_on")
                                    Button("商店") { model.sheet = "商店" }
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .accessibilityIdentifier("home_shop")
                                    Button("探索へ") { model.tab = "探索" }
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.ink.opacity(0.90))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold.opacity(0.6), lineWidth: 1))
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                        }
                        .frame(height: min(geometry.size.height, max(geometry.size.height * 0.42, 144)))
                        .scrollIndicators(.visible)
                        .accessibilityIdentifier("home_scroll")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                homeOverlayStandard
            }
        }
        .foregroundStyle(Palette.text)
    }

    /// AXXXL-only claim treatment: retain the full label and font size, but give
    /// the Japanese label the card's full width instead of sharing a narrow row
    /// with both the basket and trailing chevron. This avoids a third text line
    /// pushing the primary control beyond the initial 42% scroll viewport.
    private var accessibilityHomeClaimAction: some View {
        Button { model.collect() } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "basket").accessibilityHidden(true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                // Decorative symbols do not inherit the enlarged reading font.
                // The complete action text below still follows Dynamic Type.
                .font(.system(size: 24, weight: .semibold))
                Text("成果を受け取る")
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LinearGradient(colors: [Palette.panel, Palette.ink], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.gold, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(model.busy)
        .accessibilityLabel("成果を受け取る")
        .accessibilityIdentifier("claim_offline")
    }

    private var homeOverlayStandard: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing:12) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment:.leading,spacing:8) {
                                Button { model.sheet="模様替え" } label: { Label("模様替え",systemImage:"chair.lounge").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                                Button { model.sheet="魔導庫" } label: { Label("魔導庫",systemImage:"sparkles").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                            }
                        } else {
                            HStack(alignment:.top,spacing:12) {
                                Button { model.sheet="模様替え" } label: { Label("模様替え",systemImage:"chair.lounge").frame(maxWidth:.infinity,minHeight:44) }
                                Button { model.sheet="魔導庫" } label: { Label("魔導庫",systemImage:"sparkles").frame(maxWidth:.infinity,minHeight:44) }
                            }
                        }
                    }.font(.caption).padding(12).background(Palette.ink.opacity(0.6))
                    Spacer(minLength:dynamicTypeSize.isAccessibilitySize ? 12:24)
                    VStack(alignment:.leading,spacing:10) {
                        gatheringProgress()
                        action("成果を受け取る",symbol:"basket",id:"claim_offline"){model.collect()}
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment:.leading,spacing:4) {
                                Button("試着") { model.sheet="試着" }.frame(minHeight:44).accessibilityIdentifier("home_try_on")
                                Button("商店") { model.sheet="商店" }.frame(minHeight:44).accessibilityIdentifier("home_shop")
                                Button("探索へ") { model.tab="探索" }.fontWeight(.semibold).frame(minHeight:44)
                            }
                        } else {
                            HStack { Button("試着"){model.sheet="試着"}.frame(minHeight:44).accessibilityIdentifier("home_try_on");Button("商店"){model.sheet="商店"}.frame(minHeight:44).accessibilityIdentifier("home_shop");Spacer();Button("探索へ  ›"){model.tab="探索"}.fontWeight(.semibold).frame(minHeight:44) }
                        }
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Palette.ink).clipShape(RoundedRectangle(cornerRadius:14))
                        .overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.gold.opacity(0.6),lineWidth:1))
                }.padding(14).frame(minHeight:geometry.size.height,alignment:.bottom)
            }.scrollIndicators(dynamicTypeSize.isAccessibilitySize ? .visible : .hidden).accessibilityIdentifier("home_scroll")
        }.foregroundStyle(Palette.text)
    }

    private var exploreOverlay:some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment:.leading,spacing:12) {
                    Menu {
                        ForEach(model.catalog?.regions ?? []) { region in
                            Button {
                                pendingRecipeGatherHandoff = nil
                                model.chosenRegion=region.id;enemyPage=0
                                model.act(.startExpeditionAt(regionID:region.id,now:Date()),region.name+"へ出発。")
                                model.syncScene()
                            } label: {
                                Label(region.name,systemImage:model.state.unlockedRegionIDs.contains(region.id) ? (model.chosenRegion==region.id ? "checkmark":"map") : "lock.fill")
                            }.disabled(!model.state.unlockedRegionIDs.contains(region.id) || model.busy || model.fighting)
                                .accessibilityIdentifier("choose_region_"+region.id)
                        }
                    } label: {
                        HStack(spacing:10) {
                            Image(systemName:"map").accessibilityHidden(true)
                            Text(model.catalog?.regions.first{$0.id==model.chosenRegion}?.name ?? "探索する地域").fixedSize(horizontal:false,vertical:true)
                            Spacer(minLength:4)
                            Image(systemName:"chevron.down").accessibilityHidden(true)
                        }.font(.callout).padding(12).frame(maxWidth:.infinity,minHeight:48,alignment:.leading).background(Palette.ink).clipShape(RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(ContrastPreservingButtonStyle())
                        .accessibilityLabel("地域を選ぶ、"+(model.catalog?.regions.first{$0.id==model.chosenRegion}?.name ?? ""))
                        .accessibilityIdentifier("region_"+model.chosenRegion)
                        .disabled(model.busy || model.fighting)
                    if let handoff = pendingRecipeGatherHandoff {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("制作目標の材料").font(.headline)
                            Text("\(GameText.name(handoff.materialID)) · \(model.recipeRegionNames([handoff.regionID])) · あと\(handoff.missing)個")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("recipe_gather_handoff_summary")
                            if model.state.activeRegionID != handoff.regionID {
                                Text("地域を切り替えると、切替前の採集分が所持数に反映されます。")
                                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                            Button { applyRecipeGatherHandoff(handoff) } label: {
                                Label("この素材を採集する", systemImage: "leaf")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                            .disabled(model.busy || model.fighting)
                            .accessibilityIdentifier("recipe_gather_apply")
                            Button {
                                pendingRecipeGatherHandoff = nil
                                model.chosenRegion = model.state.activeRegionID ?? model.chosenRegion
                                model.syncScene()
                            } label: {
                                Text("閉じる").frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                                .disabled(model.busy)
                                .accessibilityIdentifier("recipe_gather_dismiss")
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("recipe_gather_handoff")
                    }
                    Spacer(minLength:dynamicTypeSize > .large ? 10:70)
                    if model.fighting {
                        Text(model.battleResolutionMessage ?? model.preparationMessage ?? (ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--art-audit=") || $0.hasPrefix("--qa-party-frame=") || $0=="--qa-party-motion"}) ? model.notice:(model.qaCombatPreview ? "R6検証・報酬なし ・ \(model.battleElapsed)秒":"4人で自動戦闘中 ・ \(model.battleElapsed)秒")))
                            .font(.title3).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Palette.ink.opacity(0.8))
                            .accessibilityIdentifier(model.battleResolutionMessage == nil ? "battle_progress":"battle_resolution")
                            .overlay(alignment: .trailing) {
                                if model.qaPartyMotionStepMode, let phase = model.qaPartyMotionStepWaitingPhase {
                                    Button("次へ") { model.advanceQAPartyMotionStep() }
                                        .font(.caption).frame(minWidth: 44, minHeight: 44)
                                        .accessibilityIdentifier("qa_party_motion_advance")
                                        .accessibilityValue(phase)
                                        .padding(.trailing, 8)
                                }
                            }
                    } else if exploreControlsExpanded {
                        VStack(alignment:.leading,spacing:12) {
                            HStack(alignment:.center) {
                                Text("採集と魔物").font(.system(.title2,design:.serif))
                                Spacer(minLength:4)
                                Button { exploreControlsExpanded=false } label: {
                                    Label("風景へ",systemImage:"chevron.down").font(.caption).frame(minHeight:44)
                                }.accessibilityIdentifier("explore_controls_close")
                            }
                            gatheringProgress()
                            Text(model.notice).font(.caption)
                            if dynamicTypeSize > .large {
                                LazyVStack(alignment:.leading,spacing:8) {
                                    ForEach(gatherMaterialIDs,id:\.self) { id in gatherButton(id,expanded:true) }
                                }
                                LazyVStack(spacing:10) { ForEach(regionEnemies) { enemy in enemyButton(enemy,expanded:true) } }
                            } else {
                                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:4) {
                                    ForEach(gatherMaterialIDs,id:\.self) { id in gatherButton(id,expanded:false) }
                                }
                                HStack(alignment:.top,spacing:8) {
                                    ForEach(Array(regionEnemies.dropFirst(enemyPage*3).prefix(3))) { enemy in
                                        enemyButton(enemy,expanded:false).frame(maxWidth:.infinity)
                                    }
                                }
                                if regionEnemies.count>3 {
                                    HStack {
                                        Button("前へ",systemImage:"chevron.left"){enemyPage=max(0,enemyPage-1)}
                                            .disabled(enemyPage==0).accessibilityIdentifier("enemies_previous")
                                        Spacer()
                                        Text("\(enemyPage+1) / \((regionEnemies.count+2)/3)").font(.caption).accessibilityLabel("魔物の一覧、\(enemyPage+1)ページ目")
                                        Spacer()
                                        Button("次へ",systemImage:"chevron.right"){enemyPage=min((regionEnemies.count-1)/3,enemyPage+1)}
                                            .disabled((enemyPage+1)*3>=regionEnemies.count).accessibilityIdentifier("enemies_next")
                                    }.buttonStyle(ContrastPreservingButtonStyle()).frame(minHeight:44)
                                }
                            }
                        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                            .background(Palette.ink).clipShape(RoundedRectangle(cornerRadius:14))
                    } else {
                        VStack(alignment:.leading,spacing:5) {
                            if let materialID=model.state.gatherTargetMaterialID,
                               gatherMaterialIDs.contains(materialID) {
                                HStack(spacing:6) {
                                    AssetIcon(id:"ICO_"+materialID,size:22).accessibilityHidden(true)
                                    Text(GameText.name(materialID)+"を採集中").font(.caption).accessibilityIdentifier("explore_gather_target")
                                    Spacer(minLength:4)
                                }
                            }
                            gatheringProgress(showMaterialName:false)
                            Text(model.notice).font(.caption2).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil:2)
                            let actionLayout:AnyLayout = dynamicTypeSize > .large
                                ? AnyLayout(VStackLayout(alignment:.leading,spacing:10))
                                : AnyLayout(HStackLayout(spacing:10))
                            actionLayout {
                                Button { model.collect() } label: {
                                    Label("成果を受け取る",systemImage:"basket").frame(maxWidth:.infinity,minHeight:44,alignment:dynamicTypeSize > .large ? .leading:.center)
                                        .contentShape(.interaction,Rectangle())
                                }.disabled(model.busy).accessibilityIdentifier("claim_offline")
                                Button { exploreControlsExpanded=true } label: {
                                    Label("採集・魔物",systemImage:"chevron.up").frame(maxWidth:.infinity,minHeight:44,alignment:dynamicTypeSize > .large ? .leading:.center)
                                        .contentShape(.interaction,Rectangle())
                                }.accessibilityLabel("採集する素材と魔物を選ぶ").accessibilityIdentifier("explore_controls")
                            }.font(.caption).buttonStyle(ContrastPreservingButtonStyle())
                        }.padding(10).background(Palette.ink).clipShape(RoundedRectangle(cornerRadius:14))
                            .overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.gold.opacity(0.5),lineWidth:1))
                    }
                }.padding(12).frame(minHeight:geometry.size.height,alignment:.top)
            }.scrollIndicators(dynamicTypeSize.isAccessibilitySize ? .visible : .hidden).accessibilityIdentifier("explore_scroll")
        }.foregroundStyle(Palette.text)
    }
    private func prepareRecipeGatherHandoff(recipeID: String, materialID: String, regionID: String, missing: Int) {
        guard !model.busy, !model.fighting, missing > 0,
              let catalog = model.catalog,
              model.state.unlockedRegionIDs.contains(regionID),
              catalog.regions.contains(where: { $0.id == regionID }),
              catalog.availableGatherMaterialIDs(in: regionID,
                                                  unlockedRegionIDs: model.state.unlockedRegionIDs,
                                                  completedEncounterIDs: model.state.completedEncounterIDs).contains(materialID) else {
            model.error = "この採集場所は現在利用できません。目標と解放状況を確認してください。"
            return
        }
        // View-only navigation: no dispatch, save, revision, or resource change.
        model.writeRecipeGatherSnapshotR039("before_navigation")
        pendingRecipeGatherHandoff = RecipeGatherHandoffR039(recipeID: recipeID, materialID: materialID, regionID: regionID, missing: missing)
        model.chosenRegion = regionID
        model.tab = "探索"
        model.sheet = nil
        model.notice = "\(GameText.name(materialID))の採集先を確認しています。始めるには下の操作を選んでください。"
        model.syncScene()
        model.writeRecipeGatherSnapshotR039("route_confirmation")
    }

    private func applyRecipeGatherHandoff(_ route: RecipeGatherHandoffR039) {
        guard !model.busy else { return }
        Task { @MainActor in
            do {
                try await model.applyRecipeGatherHandoffR039(route)
                model.writeRecipeGatherSnapshotR039("handoff_applied")
                pendingRecipeGatherHandoff = nil
                model.chosenRegion = route.regionID
                model.tab = "探索"
                model.syncScene()
            } catch {
                model.error = GameText.error(error)
            }
        }
    }

    private var gatherMaterialIDs:[String] { model.catalog?.materialIDs.filter{$0.hasPrefix("M_"+model.chosenRegion+"_G")} ?? [] }
    private var regionEnemies:[EnemyDefinition] { model.catalog?.enemies.filter{$0.regionID==model.chosenRegion} ?? [] }
    private func gatherButton(_ id:String,expanded:Bool)->some View {
        Button {
            pendingRecipeGatherHandoff = nil
            model.act(.setGatherTargetAt(resourceID:id,now:Date()),GameText.name(id)+"を探しています。成果は家で受け取れます。")
        } label: {
            HStack(spacing:6) { AssetIcon(id:"ICO_"+id,size:expanded ? 32:24).accessibilityHidden(true); Text("\(GameText.name(id)) \(model.state.materials[id,default:0])").font(expanded ? .body:.caption).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true); if expanded { Spacer(minLength:0) } }.padding(8).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        }.buttonStyle(ContrastPreservingButtonStyle()).disabled(!(model.availableMaterials[model.chosenRegion]?.contains(id) ?? false) || model.busy)
            .accessibilityLabel("\(GameText.name(id))、所持\(model.state.materials[id,default:0])")
            .accessibilityHint(model.availableMaterials[model.chosenRegion]?.contains(id) ?? false ? "採集目標に設定します":"この素材はまだ選べません")
            .accessibilityIdentifier("gather_"+id)
    }
    private func enemyButton(_ enemy:EnemyDefinition,expanded:Bool)->some View {
        Button { model.fight(enemy) } label: {
            Group {
                if expanded {
                    HStack(spacing:10) {
                        AssetIcon(id:"ACT_"+enemy.id,size:56).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:4) {
                            Text(enemy.name).font(.body).foregroundStyle(Color.white).multilineTextAlignment(.leading).padding(2)
                            if enemy.boss { Text("ボス").font(.caption).foregroundStyle(Color.white).padding(.horizontal,4).background(Palette.ink) }
                        }
                        Spacer(minLength:0)
                        Image(systemName:"chevron.right").accessibilityHidden(true)
                    }.frame(maxWidth:.infinity,minHeight:56,alignment:.leading)
                } else {
                    VStack(alignment:.leading,spacing:4) {
                        AssetIcon(id:"ACT_"+enemy.id,size:44).accessibilityHidden(true)
                        Text(enemy.name).font(.body).foregroundStyle(Color.white).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true).padding(2)
                        if enemy.boss { Text("ボス").font(.body).foregroundStyle(Color.white).padding(.horizontal,4).background(Palette.ink) }
                        else { Image(systemName:"arrow.right.circle.fill").font(.caption).foregroundStyle(Color.white).accessibilityHidden(true) }
                    }.frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:44)
                }
            }.padding(6).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:9))
        }.buttonStyle(ContrastPreservingButtonStyle()).accessibilityLabel("\(enemy.boss ? "ボス" : "魔物")、\(enemy.name)と戦う")
            .accessibilityHint("4人で自動戦闘を開始します")
            .accessibilityIdentifier("fight_"+enemy.id)
    }
    private var selectedCompanionWeaponName:String {
        guard let id=model.state.equippedGearIDs[model.selectedActor+"|weapon"],
              let instance=model.state.gear.first(where:{$0.id==id && $0.ownerID==model.selectedActor}),
              let definition=model.catalog?.gear.first(where:{$0.id==instance.definitionID && $0.slot=="weapon"}) else{return "未装備"}
        return definition.name
    }
    private var companionOverlay:some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { VStack(spacing:16) { companionSelector; Color.clear.frame(height:80); companionSummary } }
            } else {
                VStack { companionSelector; Spacer(minLength:24); companionSummary }
            }
        }.foregroundStyle(Palette.text)
    }
    private var companionSelector:some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:dynamicTypeSize > .large ? 2:4),spacing:8) {
            ForEach(model.state.partyActorIDs,id:\.self) { id in
                Button { model.selectedActor=id } label: {
                    VStack(spacing:6) {
                        AssetIcon(id:(GameModel.spriteIDs[id] ?? "ERNA")+"__idle",size:48).accessibilityHidden(true)
                        Text(GameModel.actorNames[id] ?? id).font(.caption).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,minHeight:72).padding(6)
                        .background(model.selectedActor==id ? Palette.panel:Palette.ink)
                        .clipShape(RoundedRectangle(cornerRadius:10))
                        .overlay(RoundedRectangle(cornerRadius:10).stroke(model.selectedActor==id ? Palette.gold:Color.clear,lineWidth:1))
                }.accessibilityLabel(GameModel.actorNames[id] ?? id)
                    .accessibilityValue(model.selectedActor==id ? "選択中":"")
                    .accessibilityIdentifier("companion_"+id)
            }
        }.padding(12)
    }
    private var companionSummary:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(GameModel.actorNames[model.selectedActor] ?? "仲間").font(.system(.title2,design:.serif)).fixedSize(horizontal:false,vertical:true)
                Spacer()
                Button("試着") { model.sheet="試着" }.frame(minWidth:44,minHeight:44)
            }
            Text("装備："+selectedCompanionWeaponName).font(.caption).foregroundStyle(Palette.gold)
                .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("companion_equipped_weapon")
            if let progress=model.characterProgress(for:model.selectedActor) {
                HStack {
                    Text("Lv \(progress.level)").font(.headline).accessibilityIdentifier("companion_level")
                    Spacer()
                    Text(progress.xpToNextLevel.map{"次のLvまで \($0) EXP"} ?? "Lv上限に到達").font(.caption).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("companion_xp")
                }
                if let stats=model.combatant(for:model.selectedActor) {
                    Text("体力 \(stats.maxHP)　攻撃 \(stats.attack)　防御 \(stats.defense)").font(.caption).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("companion_stats")
                } else {
                    Text("装備の性能を確認できません。").font(.caption).foregroundStyle(Palette.gold)
                        .accessibilityIdentifier("companion_stats_error")
                }
            }
            action("所持装備を比べる",symbol:"shield",id:"inventory") { model.sheet="装備" }
        }.padding(16).background(Palette.ink).clipShape(RoundedRectangle(cornerRadius:14)).padding(12)
    }
    private var workshop:some View {
        VStack(alignment:.leading,spacing:16) {
            title("小さな工房","採集した素材を、次の冒険の力に。")
            RecipeGoalSummaryView(model: model)
            HStack(spacing: 12) {
                workshopModeButton("制作", kind: "craft_new")
                workshopModeButton("進化", kind: "evolve_in_place")
            }
            if workshopMode == "evolve_in_place" {
                if !model.recipeGoals.contains(where: { $0.kind == "evolve_in_place" }) {
                    Text("進化の元になる装備を手に入れると、ここに表示されます。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Text("持っている装備を育てる").font(.headline)
                ForEach(model.recipeGoals.filter { $0.kind == "evolve_in_place" }, id: \.recipeID) { goal in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            AssetIcon(id: "ICO_" + goal.outputGearID, size: 52).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.recipeGearName(goal.outputGearID)).font(.headline)
                                Text(model.recipeGearName(goal.parentTemplateID ?? "") + "から進化")
                                    .font(.caption).foregroundStyle(Palette.gold)
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                        Button { model.showRecipeGoal(goal.recipeID) } label: {
                            Text("材料と入手先").fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.bordered).accessibilityIdentifier("recipe_detail_" + goal.recipeID).disabled(model.busy)
                    }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            if workshopMode == "craft_new" {
            Text("新しい装備をつくる").font(.headline)
            ForEach(model.catalog?.recipes.filter{$0.kind == "craft_new"} ?? []) { recipe in
                let gear=model.catalog?.gear.first{$0.id==recipe.outputGearID}
                VStack(alignment:.leading,spacing:10) {
                    HStack(alignment:.top,spacing:12) {
                        AssetIcon(id:"ICO_"+(recipe.outputGearID ?? ""),size:52).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:6) {
                            Text(gear?.name ?? recipe.outputGearID ?? "装備").font(.headline).fixedSize(horizontal:false,vertical:true)
                            Text(recipe.costs.sorted{$0.key<$1.key}.map{"\(GameText.name($0.key)): \(model.state.materials[$0.key,default:0])/\($0.value)"}.joined(separator:" · "))
                                .font(.caption).foregroundStyle(Palette.gold).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                    Button { model.showRecipeGoal(recipe.id) } label: {
                        Text("材料と入手先").fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.bordered).accessibilityIdentifier("recipe_detail_" + recipe.id).disabled(model.busy)
                    Button { model.act(.craftRecipe(recipe.id),"装備を制作しました。仲間画面で比べてみよう。") } label: {
                        Text("制作").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.bordered).accessibilityIdentifier("craft_" + recipe.id)
                        .disabled(model.busy || model.recipeGoals.first(where: { $0.recipeID == recipe.id })?.ready != true)
                }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))
            }
            }
        }.padding(16).foregroundStyle(Palette.text)
    }
    private func workshopModeButton(_ label: String, kind: String) -> some View {
        Button { workshopMode = kind } label: {
            Text(label).font(.headline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 4)
                .foregroundStyle(workshopMode == kind ? Palette.ink : Palette.text)
                .background(workshopMode == kind ? Palette.gold : Palette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("workshop_mode_" + kind)
            .accessibilityAddTraits(workshopMode == kind ? [.isSelected] : [])
    }
    private var journal:some View {ResearchView(model:model).padding(16)}
    @ViewBuilder private var musicControls:some View {
        Toggle("音楽を消音",isOn:Binding(get:{music.isMuted},set:{music.setMuted($0)}))
            .accessibilityIdentifier("music_mute")
        VStack(alignment:.leading,spacing:4) {
            Text("音楽の音量 \(Int(music.volume*100))%").font(.caption)
            Slider(value:Binding(get:{Double(music.volume)},set:{music.setVolume(Float($0))}),in:0...1)
                .accessibilityLabel("音楽の音量").accessibilityIdentifier("music_volume")
        }
    }
    func title(_ text:String,_ sub:String)->some View {VStack(alignment:.leading,spacing:6){Text(text).font(.system(.title,design:.serif));Text(sub).font(.caption).foregroundStyle(Palette.gold)}}
    func action(_ text:String,symbol:String,id:String,perform:@escaping()->Void)->some View {Button(action:perform){HStack{Image(systemName:symbol);Text(text).fixedSize(horizontal:false,vertical:true);Spacer(minLength:4);Image(systemName:"chevron.right").accessibilityHidden(true)}.padding(14).background(LinearGradient(colors:[Palette.panel,Palette.ink],startPoint:.top,endPoint:.bottom)).overlay(RoundedRectangle(cornerRadius:10).stroke(Palette.gold,lineWidth:1)).clipShape(RoundedRectangle(cornerRadius:10))}.disabled(model.busy).accessibilityIdentifier(id)}
    @ViewBuilder func sheet(_ name:String)->some View {NavigationStack{ScrollView{VStack(alignment:.leading,spacing:16){
        if name == "採集の成果",let summary=model.collectionSummary {GatheringSummaryView(summary:summary)}
        else if name == "装備" || name == "開封" {inventory(opening:name=="開封")}
        else if name == "魔導庫" {GachaView(model:model)}
        else if name == "確率" {GachaRulesView(model:model)}
        else if name == "模様替え" {title("暮らしを整える","家具を置いて、仲間の居場所を。");AssetIcon(id:"FURN_DESK_BOTANICAL",size:230).frame(maxWidth:.infinity).accessibilityLabel("植物研究の机の見本");action(model.state.placedFurnitureIDs.contains("FURN_DESK_BOTANICAL") ? "机をしまう":"植物研究の机を置く",symbol:"chair.lounge",id:"place_desk"){model.act(.placeFurniture("FURN_DESK_BOTANICAL",placed:!model.state.placedFurnitureIDs.contains("FURN_DESK_BOTANICAL")),"家の模様替えを保存しました。")}.disabled(!model.state.ownedFurnitureIDs.contains("FURN_DESK_BOTANICAL"));if !model.state.ownedFurnitureIDs.contains("FURN_DESK_BOTANICAL"){Button("無料の研究机を受け取る"){model.act(.setFurniture("FURN_DESK_BOTANICAL",owned:true),"研究机を受け取りました。")}.frame(minHeight:44)}}
        else if name == "試着" {WardrobeView(model:model)}
        else if name == "比較" {GearComparisonView(model:model)}
        else if name == "制作目標" {RecipeGoalView(model: model, onGatherSource: { recipeID, materialID, regionID, missing in
            prepareRecipeGatherHandoff(recipeID: recipeID, materialID: materialID, regionID: regionID, missing: missing)
        })}
        else if name == "広告検証" && model.localAdRewardQAEnabled {LocalAdQAPanel(model:model)}
        else if name == "購入検証" && model.localStoreKitQAEnabled {GameStoreKitQAPanel(model:model)}
        else if name == "商店" {title("森の小さな商店","衣装と家具で、自分だけの暮らしを。");HStack{AssetIcon(id:"FURN_DESK_BOTANICAL",size:130).accessibilityHidden(true);VStack(alignment:.leading){Text("植物研究の机");Text("無料の初期家具").font(.caption);Button("模様替えへ"){model.sheet="模様替え"}.frame(minHeight:44)}};Text("衣装・有料家具の販売準備中").foregroundStyle(Palette.gold);Button("購入の復元（未提供）"){}.frame(minHeight:44).disabled(true).accessibilityHint("購入復元機能はまだ提供されていません");Text("この開発版では料金は発生しません。").font(.caption)}
        else {title("設定","ローカル開発版");musicControls;Toggle("効果音を消音",isOn:Binding(get:{audio.isMuted},set:{audio.setMuted($0)})).accessibilityIdentifier("audio_mute");VStack(alignment:.leading,spacing:4){Text("効果音の音量 \(Int(audio.volume*100))%").font(.caption);Slider(value:Binding(get:{Double(audio.volume)},set:{audio.setVolume(Float($0))}),in:0...1).accessibilityLabel("効果音の音量").accessibilityIdentifier("audio_volume")};if model.localAdRewardQAEnabled{Button("任意報酬のローカル検証"){model.sheet="広告検証"}.frame(minHeight:44)};if model.localStoreKitQAEnabled{Button("Xcode購入検証"){model.sheet="購入検証"}.frame(minHeight:44)};Text("保存状態: revision \(model.state.revision)");Text("4人完全自動・5地域の統合試験中。ゲームバランスと新規美術は未承認候補です。");Text("本番課金・広告配信は無効です。物理iPhone、購入価値、自然な全アニメーションの検証は継続中です。").font(.caption).foregroundStyle(.secondary);Button("保存状態を再読み込み"){Task{await model.refresh()}}.frame(minHeight:44)}
    }.padding(20)}.accessibilityIdentifier("sheet_scroll_"+name).background(Palette.ink).navigationTitle(name).navigationBarTitleDisplayMode(.inline).toolbarBackground(Palette.ink,for:.navigationBar).toolbar{ToolbarItem(placement:.topBarTrailing){Button{model.closeSheet()}label:{Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityLabel("閉じる").accessibilityHint("この画面を閉じます").foregroundStyle(Color.white)}}}.tint(Palette.gold).foregroundStyle(Palette.text)}
    func inventory(opening:Bool)->some View {InventoryView(model:model,opening:opening)}

}
struct SheetID:Identifiable{let id:String}
private struct ContrastPreservingButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.foregroundStyle(Color.white).opacity(configuration.isPressed ? 0.82:1)
    }
}
struct AssetIcon:View {let id:String;var size:CGFloat=48
    var body:some View {Group{if let image=load(){Image(uiImage:image).resizable().scaledToFit()}else{Image(systemName:"sparkle").resizable().scaledToFit().foregroundStyle(Palette.gold.opacity(0.5)).padding(size*0.3)}}.frame(width:size,height:size)}
    func load()->UIImage?{ArtLibrary.image(id)}
}
