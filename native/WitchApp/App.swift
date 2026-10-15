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
    @Published var saveRecoveryMessage: String?
    private var qaStartupFailureInjected = false
    @Published var state = GameSnapshot()
    @Published var catalog: GameCatalog?
    @Published var error: String?
    @Published var notice: String = "小さな発見を、またひとつ。"
    @Published var preparationMessage: String?
    @Published var battleResolutionMessage: String?
    /// Presentation only: the committed save and combat calculation never read this notice.
    @Published var battleTargetWarningTextR299: String?
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
    @Published private(set) var sharedPartyWorkR146Enabled = false
    @Published private(set) var wardrobeCandidateDevelopmentR169Enabled = false
    @Published private(set) var firstCraftAidCapabilityR179: FirstCraftAidCapabilityR179 = .disabled
    @Published var opening: [UUID] = []
    @Published var collectionSummary: GatheringSummary?
    @Published var sharedPartyWorkSummaryTargetR146: String?
    @Published var comparison: [UUID] = []
    @Published var availableMaterials: [String:Set<String>] = [:]
    @Published var battleElapsed = 0
    var sceneActive = true { didSet { updatePrimaryScenePauseR275() } }
    // Transient ownership only; furniture preview never writes the save or shares the live scene.
    private var furniturePreviewOwnersR275 = Set<UUID>()
    func setFurniturePreviewActiveR275(_ active: Bool, owner: UUID) {
        if active { furniturePreviewOwnersR275.insert(owner) }
        else { furniturePreviewOwnersR275.remove(owner) }
        updatePrimaryScenePauseR275()
    }
    private func updatePrimaryScenePauseR275() {
        scene.isPaused = !sceneActive || !furniturePreviewOwnersR275.isEmpty
    }
    var playbackTask: Task<Void,Never>?
    private var savedCombatReplayRequestedR217 = false
    private var savedCombatReplayBaselineBytesR217: Data?
    @Published private(set) var savedCombatReplayStatusR217: String?
    var lastBattleOperationID: UUID?
    let scene = LivingScene(size:CGSize(width:402,height:600))
    @Published var purchaseStatus="未開始"
    var qaPurchaseBridge:StoreKitLocalQABridge?
    var qaPurchaseSink:GameStoreKitQASink?
    @Published var qaFailPurchaseWrites=false
    var engine: GameEngine?
    private var runtimeConfiguration: GameRuntimeConfigurationR098?
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
        wardrobeCandidateDevelopmentR169Enabled = false
        firstCraftAidCapabilityR179 = .disabled
        startupDiagnostic = nil
        saveRecoveryMessage = nil
        let arguments=ProcessInfo.processInfo.arguments
        let qa=arguments.contains("--qa-isolated")
        #if targetEnvironment(simulator) && DEBUG && STANDARD_PLAY_R169
        let savedReplayBuildAllowedR217 = true
        #else
        let savedReplayBuildAllowedR217 = false
        #endif
        let replayFlagR217 = "--r217-replay-saved-combat"
        let replayFlagCountR217 = arguments.filter { $0 == replayFlagR217 }.count
        guard replayFlagCountR217 <= 1,
              replayFlagCountR217 == 0 || (savedReplayBuildAllowedR217 && !qa) else {
            startupState = .failed("保存済み戦闘の再生は R169 開発用 Simulator でのみ利用できます。")
            return
        }
        savedCombatReplayRequestedR217 = replayFlagCountR217 == 1
        var developmentPlayR169 = false
        var selectedStartupModeR169: StandardPlayStartupSelectionR169.Mode = .ordinaryR098
        var firstCraftCapabilityR179: FirstCraftAidCapabilityR179 = .disabled
        let r169DevelopmentBuildEnabled = StandardPlayBuildPolicyR332.standardPlayEnabled
        do {
            let r146GateEnabled = try SharedPartyWorkLaunchGateR146.parse(
                arguments: arguments, environment: ProcessInfo.processInfo.environment)
            selectedStartupModeR169 = try StandardPlayStartupSelectionR169.resolve(
                developmentBuildEnabled: r169DevelopmentBuildEnabled,
                isolatedR146GateEnabled: r146GateEnabled, arguments: arguments)
            guard !savedCombatReplayRequestedR217 || selectedStartupModeR169 == .standardPlayR169 else {
                throw CoreError.invalidCommand("R217 requires the existing R169 development save namespace")
            }
            sharedPartyWorkR146Enabled = selectedStartupModeR169.usesSharedPartyWork
            developmentPlayR169 = selectedStartupModeR169 == .standardPlayR169
            wardrobeCandidateDevelopmentR169Enabled = developmentPlayR169
            firstCraftCapabilityR179 = developmentPlayR169 && StandardPlayBuildPolicyR332.firstCraftAidEnabled
                ? .enabled : .disabled
            firstCraftAidCapabilityR179 = firstCraftCapabilityR179
        } catch {
            startupState = .failed("R146/R169 startup selection rejected: \(String(reflecting: error))")
            return
        }
        AreaFlowQAHook.configure(arguments: arguments, isolated: qa)
        do {
            if qa,let value=arguments.first(where:{$0.hasPrefix("--qa-load-delay-ms=")}),let milliseconds=Int(value.dropFirst("--qa-load-delay-ms=".count)) {
                try await Task.sleep(for:.milliseconds(min(max(milliseconds,0),10_000)))
            }
            if qa,arguments.contains("--qa-load-failure-once"),!qaStartupFailureInjected {
                qaStartupFailureInjected=true
                throw CoreError.invalidCommand("QA one-shot startup failure")
            }
            let growthArgument=qa ? arguments.first(where:{$0.hasPrefix("--qa-character-growth-bp=")}):nil
            let growthBP: Int
            if let growthArgument {
                guard let parsed=Int(growthArgument.dropFirst("--qa-character-growth-bp=".count)),
                      GameRuntimeConfigurationR098.allowedGrowthStrengthBP.contains(parsed) else {
                    throw CoreError.invalidCommand("Unsupported QA character growth profile")
                }
                growthBP=parsed
            } else { growthBP=GameRuntimeConfigurationR098.defaultGrowthStrengthBP }
            let runtime=try GameRuntimeConfigurationR098.resolve(growthStrengthBP:growthBP)
            runtimeConfiguration=runtime
            let enhancementRuntimeR230 = try developmentPlayR169 ? GameRuntimeEnhancementProfileR230(base: runtime) : nil
            let naturalRuntimeR350 = NaturalGearBuildPolicyR350.enabled ? enhancementRuntimeR230.map(GameRuntimeNaturalGearProfileR350.init(base:)) : nil
            let refinementRuntimeR352 = NaturalGearRefinementBuildPolicyR352.enabled ? naturalRuntimeR350.map(GameRuntimeRefinementProfileR352.init(base:)) : nil
            let dismantleRuntimeR353 = GearDismantleBuildPolicyR353.enabled ? refinementRuntimeR352.map(GameRuntimeDismantleProfileR353.init(base:)) : nil
            let wardrobeCandidateR128Enabled = WardrobeCandidateCatalogR128.enabled(arguments: arguments, developmentEnabled: developmentPlayR169)
            let wardrobeCandidateR130Enabled = WardrobeCandidateCatalogR130.enabled(arguments: arguments, developmentEnabled: developmentPlayR169)
            if arguments.contains(WardrobeCandidateResolverR128.flag), !wardrobeCandidateR128Enabled {
                throw CoreError.invalidCommand("R128 wardrobe requires the complete isolated gate and a UUID save key")
            }
            if arguments.contains(WardrobeCandidateCatalogR130.flag), !wardrobeCandidateR130Enabled {
                throw CoreError.invalidCommand("R130 AIRA apron requires the complete R128 isolated candidate gate")
            }
            let r128Catalog = try wardrobeCandidateR128Enabled ? WardrobeCandidateCatalogR128.extending(runtime.catalog) : runtime.catalog
            let c = try wardrobeCandidateR130Enabled ? WardrobeCandidateCatalogR130.extending(r128Catalog) : r128Catalog
            catalog = c
            let saveNamespace = selectedStartupModeR169.saveNamespace
            let baseFolder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(saveNamespace)
            let fixture=qa ? arguments.first(where:{$0.hasPrefix("--qa-fixture=")}).map{String($0.dropFirst(13))}:nil
            let key=qa ? arguments.first(where:{$0.hasPrefix("--qa-save-key=")}).map{String($0.dropFirst(14)).filter{$0.isLetter || $0.isNumber || $0=="-"}}:nil
            let r259Actor = arguments.first(where: { $0.hasPrefix("--art-audit=") }).map { String($0.dropFirst("--art-audit=".count)) } ?? ""
            let r259SequenceRequested = JellyfishMeshSequenceQAR259.isRequested(actorID: r259Actor)
            let r259CandidateRequestPresent = arguments.contains("--qa-jelly-mesh-r254") ||
                arguments.contains("--qa-jelly-sequence-r259") || arguments.contains(where: { $0.hasPrefix("--qa-jelly-profile=") })
            if r259CandidateRequestPresent && !r259SequenceRequested {
                throw CoreError.invalidCommand("R259 request is incomplete or invalid; no shared save namespace was opened")
            }
            let folder: URL
            if r259SequenceRequested {
                guard let key, UUID(uuidString: key) != nil else { throw CoreError.invalidCommand("R259 requires a UUID save key") }
                folder = baseFolder.appendingPathComponent("R259-" + key, isDirectory: true)
                guard !FileManager.default.fileExists(atPath: folder.path) else {
                    throw CoreError.invalidCommand("R259 run namespace already exists; use a new unique save key")
                }
            } else {
                folder = baseFolder
            }
            let r131ComparisonRequest = try GearComparisonQAFixtureR131.request(
                arguments: Array(arguments.dropFirst()), isolated: qa, fixture: fixture, saveKey: key)
            qaPartyMotionStepMode = qa && !(key ?? "").isEmpty && arguments.contains("--qa-party-motion") && arguments.contains("--qa-party-motion-step")
            let recipeGoalScenario: RecipeGoalQAFixtureR037.Scenario?
            if qa && fixture == "recipe-goal-r037" {
                let request = try RecipeGoalQAFixtureR037.request(arguments: arguments)
                guard request.saveKey == key else { throw CoreError.invalidCommand("recipe-goal QA save key mismatch") }
                recipeGoalScenario = request.scenario
            } else { recipeGoalScenario = nil }
            let url=folder.appendingPathComponent(qa ? "qa-"+(key ?? "r002")+"-save.json":"save.json");saveURL=url
            if savedCombatReplayRequestedR217 {
                guard FileManager.default.fileExists(atPath: url.path),
                      let existingBytes = try? Data(contentsOf: url) else {
                    throw CoreError.invalidCommand("R217 requires an existing development save; it never creates a replay fixture")
                }
                savedCombatReplayBaselineBytesR217 = existingBytes
            }
            qaLoadedExistingSave=qa && FileManager.default.fileExists(atPath:url.path)
            qaEquipmentMultiRequestR084 = nil
            if arguments.contains(where: { $0.hasPrefix(EquipmentMultiConsumerRequestR084.flagPrefix) || $0.hasPrefix(EquipmentMultiConsumerRequestR084.showcaseFlagPrefix) }) {
                switch EquipmentMultiConsumerRequestR084.parse(arguments: arguments, existingSaveLoaded: qaLoadedExistingSave) {
                case .success(let request): qaEquipmentMultiRequestR084 = request
                case .failure(let reason): throw CoreError.invalidCommand("equipment multi-consumer QA rejected: " + reason.rawValue)
                }
            }
            let latentPolicy = runtime.latentPolicy
            var initial: GameSnapshot
            if FileManager.default.fileExists(atPath: url.path) {
                // SaveRepository decodes the existing bytes; never generate missing slots.
                initial = GameSnapshot()
            } else if let request = qaEquipmentMultiRequestR084 {
                initial = try EquipmentMultiConsumerFixtureR084.make(catalog: c, variantID: request.variant.id)
            } else if let recipeGoalScenario {
                initial = try RecipeGoalQAFixtureR037.make(catalog: c, policy: latentPolicy, scenario: recipeGoalScenario)
            } else if qa && fixture == "latent-slots-r031" {
                initial = try LatentGearQAFixture.make(catalog: c, policy: latentPolicy)
            } else if let request = r131ComparisonRequest {
                initial = try request.makeInitialSnapshot(runtime: runtime)
            } else if fixture != nil {
                initial = try await QAScenarios.initial(catalog: c, scenario: fixture)
            } else {
                initial = try runtime.makeNewSnapshot()
            }
            // New R179 eligibility is stamped only onto an actually absent, newly created R169 save.
            // Existing primary/previous generations keep their decoded marker (missing means false).
            if developmentPlayR169, firstCraftCapabilityR179.isEnabled,
               !FileManager.default.fileExists(atPath: url.path) {
                initial.firstCraftAidEligibleR179 = true
            }
            let repository=try SaveRepository(initial:initial,fileURL:url)
            let saveRecovery=await repository.recoveryStatus()
            let r169ExistingSave = developmentPlayR169 && StandardPlayStartupSelectionR169.requiresExistingTarget(recoverySource: saveRecovery.source)
            if saveRecovery.recoveredPreviousGeneration {
                saveRecoveryMessage="直前の正常なセーブから復元しました。最後の操作が反映されていない場合があります。"
            }
            if qa {
                let recovery=try JSONSerialization.jsonObject(with:JSONEncoder().encode(saveRecovery))
                writeReceipt("save_recovery",saveRecovery.source.rawValue,metadata:["recovery":recovery])
            }
            // App and long-run tests resolve the same explicit, unapproved profile.
            // Existing saves retain their stored latent slots; no item upgrade is inferred.
            let growth=runtime.growth
            if let enhancementRuntimeR230 {
                let workPolicy = try sharedPartyWorkR146Enabled ? PartyWorkPolicyR144(
                    baseProfileID: runtime.profileID, baseConfigurationFingerprint: runtime.configurationFingerprint) : nil
                engine = try enhancementRuntimeR230.makeEngine(saves: repository,
                    appearanceCatalog: (wardrobeCandidateR128Enabled || wardrobeCandidateR130Enabled) ? c : nil,
                    candidatePartyWorkPolicyR144: workPolicy,
                    firstCraftAidCapabilityR179: firstCraftCapabilityR179,
                    naturalGearDiscoveryPolicyR350: naturalRuntimeR350?.policy,
                    naturalGearRefinementPolicyR352: refinementRuntimeR352?.policy,
                    gearDismantleRefundPolicyR353: dismantleRuntimeR353?.policy)
            } else if sharedPartyWorkR146Enabled {
                engine = try runtime.makeSharedPartyWorkEngineR146(
                    saves: repository,
                    appearanceCatalog: (wardrobeCandidateR128Enabled || wardrobeCandidateR130Enabled) ? c : nil,
                    firstCraftAidCapabilityR179: firstCraftCapabilityR179)
            } else {
                engine = try runtime.makeEngine(saves: repository,
                    appearanceCatalog: (wardrobeCandidateR128Enabled || wardrobeCandidateR130Enabled) ? c : nil,
                    firstCraftAidCapabilityR179: firstCraftCapabilityR179)
            }
            await refresh()
            if savedCombatReplayRequestedR217 {
                guard saveRecovery.source == .primary, !saveRecovery.recoveredPreviousGeneration,
                      state.lastClaimAt != nil, let savedBattle = state.lastCombatResult,
                      let encounterID = state.lastEncounterID, let c = catalog,
                      let expectedBytes = savedCombatReplayBaselineBytesR217,
                      (try? Data(contentsOf: url)) == expectedBytes,
                      Self.savedBattleR217(savedBattle, matches: encounterID, catalog: c) else {
                    throw CoreError.invalidCommand("R217 replay refused: requires an unchanged current Primary save with a valid persisted combat result")
                }
            }
            if refinementRuntimeR352 == nil, state.naturalGearRefinementR352 != nil {
                throw CoreError.invalidCommand("This save requires the refinement development capability used to create it")
            }
            if naturalRuntimeR350 == nil, state.naturalGearDiscoveryR350 != nil {
                throw CoreError.invalidCommand("This save requires the natural-gear development capability used to create it")
            }
            if !sharedPartyWorkR146Enabled, state.partyWorkTargetR144 != nil {
                throw CoreError.invalidCommand("This save uses the R144 shared-work candidate; reopen with its isolated R146 QA gate")
            }
            if sharedPartyWorkR146Enabled {
                try await prepareFreshSharedPartyWorkR146(
                    existingSaveLoaded: qaLoadedExistingSave || r169ExistingSave,
                    freshSaveReceiptMode: developmentPlayR169 ? nil : "UNAPPROVED_SIMULATOR_QA_CANDIDATE")
            }
            if developmentPlayR169 {
                let policy = try PartyWorkPolicyR144(baseProfileID: runtime.profileID,
                    baseConfigurationFingerprint: runtime.configurationFingerprint)
                let appearanceEncoder = JSONEncoder(); appearanceEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                let effectiveAppearanceCatalog = try appearanceEncoder.encode(c)
                writeReceipt("standard_play_identity_r169", "UNAPPROVED_LOCAL_DEVELOPMENT_PROFILE", metadata: [
                    "runtimeProfileID": dismantleRuntimeR353?.profileID ?? refinementRuntimeR352?.profileID ?? naturalRuntimeR350?.profileID ?? enhancementRuntimeR230?.profileID ?? runtime.profileID,
                    "runtimeConfigurationFingerprint": dismantleRuntimeR353?.configurationFingerprint ?? refinementRuntimeR352?.configurationFingerprint ?? naturalRuntimeR350?.configurationFingerprint ?? enhancementRuntimeR230?.configurationFingerprint ?? runtime.configurationFingerprint,
                    "baseRuntimeProfileID": runtime.profileID,
                    "baseRuntimeConfigurationFingerprint": runtime.configurationFingerprint,
                    "enhancementProjectionPolicy": engine?.enhancementProjectionPolicyR230.rawValue ?? EnhancementProjectionPolicyR230.legacy.rawValue,
                    "enhancementPolicySHA256": enhancementRuntimeR230 == nil ? "legacy" : GearEnhancementGrowthR230.policySHA256,
                    "partyWorkPolicyID": PartyWorkPolicyR144.policyID,
                    "partyWorkPolicyFingerprint": policy.policyFingerprint,
                    "catalogSHA256": runtime.catalogSHA256,
                    "effectiveAppearanceCatalogSHA256": SHA256.hash(data: effectiveAppearanceCatalog).map { String(format: "%02x", $0) }.joined(),
                    "candidateAppearanceIDs": Array(c.appearances.dropFirst(runtime.catalog.appearances.count)).map(\.id),
                    "wardrobeCandidateDevelopmentEnabled": wardrobeCandidateDevelopmentR169Enabled,
                    "equipmentLoadoutsCandidateR342Enabled": EquipmentLoadoutsBuildPolicyR342.enabled,
                    "enhancementRuntimeProfileID": enhancementRuntimeR230?.profileID ?? "disabled",
                    "enhancementRuntimeConfigurationFingerprint": enhancementRuntimeR230?.configurationFingerprint ?? "disabled",
                    "naturalGearCandidateR350Enabled": naturalRuntimeR350 != nil,
                    "naturalGearPolicyID": naturalRuntimeR350 == nil ? "disabled" : NaturalGearDiscoveryPolicyR350.policyID,
                    "naturalGearPolicyFingerprint": naturalRuntimeR350?.policy.policyFingerprint ?? "disabled",
                    "naturalGearLedgerInitialized": state.naturalGearDiscoveryR350 != nil,
                    "naturalGearRefinementCandidateR352Enabled": refinementRuntimeR352 != nil,
                    "naturalGearRefinementPolicyID": refinementRuntimeR352 == nil ? "disabled" : NaturalGearRefinementPolicyR352.policyID,
                    "naturalGearRefinementPolicyFingerprint": refinementRuntimeR352?.policy.policyFingerprint ?? "disabled",
                    "naturalGearRefinementLedgerInitialized": state.naturalGearRefinementR352 != nil,
                    "gearDismantleCandidateR353Enabled": dismantleRuntimeR353 != nil,
                    "gearDismantlePolicyID": dismantleRuntimeR353 == nil ? "disabled" : GearDismantleRefundPolicyR353.policyID,
                    "gearDismantlePolicyFingerprint": dismantleRuntimeR353?.policy.policyFingerprint ?? "disabled",
                    "purchaseEnabled": false, "adRewardsEnabled": false,
                    "humanApproval": false,
                    "firstCraftAidPolicyID": firstCraftCapabilityR179.policyID,
                    "firstCraftAidPolicyFingerprint": firstCraftCapabilityR179.policyFingerprint,
                    "firstCraftAidEnabled": firstCraftCapabilityR179.isEnabled,
                    "firstCraftAidEligibleSave": state.firstCraftAidEligibleR179 == true,
                    "firstCraftAlreadyUsed": state.craftedGearOnce
                ])
            }
            if qa {
                let manifest=try JSONSerialization.jsonObject(with:runtime.canonicalManifest)
                if wardrobeCandidateR128Enabled {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    let effective = try encoder.encode(c)
                    writeReceipt("wardrobe_catalog_r128", c.version, metadata: [
                        "baseConfigurationFingerprint": runtime.configurationFingerprint,
                        "effectiveCatalogSHA256": SHA256.hash(data: effective).map { String(format: "%02x", $0) }.joined(),
                        "appearanceIDs": c.appearances.map(\.id), "status": "UNAPPROVED_LOCAL_CANDIDATE"])
                }
                writeReceipt("runtime_configuration",runtime.configurationFingerprint,metadata:[
                    "profileID":runtime.profileID,"profileVersion":runtime.profileVersion,
                    "manifest":manifest,"existingSaveLoaded":qaLoadedExistingSave,
                    "initialization":"\(fixture ?? "fresh-or-existing")","humanApproval":false])
            }
            if qa { writeReceipt("candidate_latent_policy", "R005_UNAPPROVED_CANDIDATE|versionedItems=\(state.gear.filter{$0.candidateLatentSlots != nil}.count)|legacyItems=\(state.gear.filter{$0.candidateLatentSlots == nil}.count)") }
            if qa {writeReceipt("candidate_character_growth",growth.id+"|"+growth.status)}
            if qa { writeReceipt("candidate_combat_overlay","R014_E_R03_04|UNAPPROVED_TEST_OVERLAY|mark=800ms|windup=1200ms|coefficient=12500bp") }
            if qa,ProcessInfo.processInfo.arguments.contains("--qa-persist-fixture"),!FileManager.default.fileExists(atPath:url.path),let engine {
                guard let region=state.activeRegionID ?? c.regions.first?.id else{throw CoreError.invalidCommand("QA fixture has no region")}
                _ = try await engine.dispatch(.startExpeditionAt(regionID:region,now:Date()),operationID:UUID(),expectedRevision:state.revision)
                await refresh();writeReceipt("fixture_setup","Explicit QA fixture persisted before validation")
            }
            if state.lastClaimAt==nil,let engine, !savedCombatReplayRequestedR217 {
                _ = try await engine.claimOffline(now:Date(),operationID:UUID(),expectedRevision:state.revision);await refresh()
            }
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
            if let request = r131ComparisonRequest {
                selectedActor = request.actorID
                comparison = try request.comparisonIDs()
                sheet = "比較"
                writeReceipt("r131_gear_comparison_fixture", "SYNTHETIC_NOT_EARNED", metadata: [
                    "fixture": request.fixture, "saveKey": request.saveKey,
                    "actorID": request.actorID,
                    "baselineGearID": GearComparisonQAFixtureR131.baselineGearIDString,
                    "comparisonGearIDs": GearComparisonQAFixtureR131.firstChoiceIDString + "," + GearComparisonQAFixtureR131.secondChoiceIDString,
                    "unlockMarker": request.fixture == GearComparisonQAFixtureR131.unlockedFixture ? "SYNTHETIC_B_R05_B" : "NONE",
                    "rewardDispatchAfterSetup": false])
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
                    if JellyfishMeshSequenceQAR259.isRequested(actorID: id), let saveURL,
                       let saveKeyArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--qa-save-key=") }) {
                        let saveKey = String(saveKeyArgument.dropFirst("--qa-save-key=".count))
                        let result = await scene.runJellyfishSequenceR259(
                            actorID: id, saveKey: saveKey,
                            outputDirectory: saveURL.deletingLastPathComponent())
                        writeReceipt("jellyfish_mesh_sequence_r259", result, metadata: [
                            "saveFilename": saveURL.lastPathComponent,
                            "processID": ProcessInfo.processInfo.processIdentifier,
                            "saveKey": saveKey,
                            "profile": ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--qa-jelly-profile=") }) ?? ""])
                        fighting = false
                        writeReceipt("art_audit", scene.artAuditJSON())
                        return
                    }
                    if JellyfishMeshSequenceQAR137.isRequested(actorID: id), let saveURL,
                       let saveKeyArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--qa-save-key=") }) {
                        let saveKey = String(saveKeyArgument.dropFirst("--qa-save-key=".count))
                        let result = await scene.runJellyfishSequenceR137(
                            actorID: id, saveKey: saveKey,
                            outputDirectory: saveURL.deletingLastPathComponent())
                        writeReceipt("jellyfish_mesh_sequence_r137", result, metadata: [
                            "saveFilename": saveURL.lastPathComponent,
                            "processID": ProcessInfo.processInfo.processIdentifier, "saveKey": saveKey])
                        fighting = false
                        writeReceipt("art_audit", scene.artAuditJSON())
                        return
                    }
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
            if savedCombatReplayRequestedR217 {
                playbackTask = Task { await self.runSavedCombatReplayR217() }
            }
            if qa { writeQAStartupIdentity("ready") }
            if qa { await runIsolatedWalkCycleR018IfRequested(arguments: arguments, fixture: fixture, saveKey: key) }
            if qa { runGatherNodeRuntimeQAIfRequested() }
            if qa { writeQASaveReadbackIfRequested() }
            if qa {runPartyFrameAuditIfRequested()}
            if qa { runCandidateSceneR124IfRequested() }
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
            if let saveError=error as? SaveRepositoryError {
                switch saveError {
                case .unsupportedFutureSchemaVersion, .unsupportedFutureVersionMarker, .invalidSchemaVersion:
                    startupState = .failed("このセーブは対応していない形式です。元のデータは保持しています。対応する新しいアプリで開いてください。")
                default:
                    startupState = .failed("セーブを読み込めませんでした。元のデータは保持しています。もう一度お試しください。")
                }
            } else {
                startupState = .failed("保存データまたはゲーム資料を開けませんでした。もう一度お試しください。")
            }
            if qa { writeQAStartupIdentity("failed") }
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
        let investigationActive = sharedPartyWorkR146Enabled && state.partyWorkTargetR144?.kind == .investigate
        return R015AreaSceneRouting.resolve(regionID: chosenRegion,
                                            activeFightEnemyID: activeAreaFightEnemyID,
                                            selectedGatherMaterialID: activeAreaFightEnemyID == nil && !investigationActive ? state.gatherTargetMaterialID : nil,
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
        let investigationActive = sharedPartyWorkR146Enabled && state.partyWorkTargetR144?.kind == .investigate
        scene.configure(place:place,areaResolution:areaSceneResolution,
                        selectedGatherMaterialID:fighting || investigationActive ? nil:state.gatherTargetMaterialID,
                        cosmetics:sceneAppearance,furniture:sceneFurniture,
                        wardrobeCandidateDevelopmentEnabled:wardrobeCandidateDevelopmentR169Enabled)
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
        // Presence of an unrenderable/unknown weapon is distinct from an empty slot.
        // This read-only presentation marker does not alter ownership or equipment.
        v.removeValue(forKey: "APPRENTICE_EQUIPPED_WEAPON_ID")
        if let instanceID = state.equippedGearIDs["C_APPRENTICE|weapon"] {
            v["APPRENTICE_EQUIPPED_WEAPON_ID"] = state.gear.first(where: { $0.id == instanceID })?.definitionID ?? "<missing-owned-instance>"
        }
        let qaArguments = ProcessInfo.processInfo.arguments
        let wardrobeCandidatesEnabled = WardrobeCandidateCatalogR128.enabled(
            arguments: qaArguments, developmentEnabled: wardrobeCandidateDevelopmentR169Enabled)
        if !wardrobeCandidatesEnabled {
            if qaArguments.contains("--qa-isolated"), qaArguments.contains(LunaMantleOverlayR097.qaFlag) {
                v[LunaMantleOverlayR097.appearanceKey] = LunaMantleOverlayR097.appearanceValue
            }
            if qaArguments.contains("--qa-isolated"), qaArguments.contains(LunaMantleBooklessR127.qaFlag) {
                v[LunaMantleOverlayR097.appearanceKey] = LunaMantleBooklessR127.appearanceValue
            }
        } else if let catalog {
            v = WardrobeCandidateResolverR128.sceneMetadata(base: v, selectedByActor: state.selectedCosmeticIDs,
                ownedIDs: state.ownedCosmeticIDs, catalog: catalog, arguments: qaArguments,
                developmentEnabled: wardrobeCandidateDevelopmentR169Enabled)
        }
        if let catalog {
            v = WardrobeCandidateCatalogR130.sceneMetadata(base: v, selectedByActor: state.selectedCosmeticIDs,
                ownedIDs: state.ownedCosmeticIDs, catalog: catalog, arguments: qaArguments,
                developmentEnabled: wardrobeCandidateDevelopmentR169Enabled)
        } else { v.removeValue(forKey: WardrobeCandidateCatalogR130.sceneKey) }
        return v
    }
    func act(_ command:GameCommand,_ message:String?=nil) {
        guard !busy,let engine else{return};busy=true
        Task {
            let before = state
            do {
                let receipt = try await engine.dispatch(command, operationID: UUID(), expectedRevision: state.revision)
                await refresh()
                WitchAudioCoordinator.shared.playAfterSuccessfulCommand(command, result: receipt.result)
                notice = message ?? receipt.result
                appendNaturalGearNoticeR350(since: before)
            } catch { self.error = GameText.error(error); await refresh() }
            busy = false
        }
    }
    func clearPendingGatherVisualForSharedWorkR146() { pendingGatherVisualMaterialID = nil }
    func setPendingGatherVisualForSharedWorkR146(_ materialID: String?) { pendingGatherVisualMaterialID = materialID }

    func collect(){
        if sharedPartyWorkR146Enabled { collectSharedPartyWorkR146(); return }
        guard !busy,let engine else{return};pendingGatherVisualMaterialID=nil;busy=true;Task{do{let before=state;let r=try await engine.claimOffline(now:Date(),operationID:UUID(),expectedRevision:state.revision);await refresh();collectionSummary=GatheringSummary(before:before,after:state,catalog:catalog);if let materialID=before.gatherTargetMaterialID,collectionSummary?.materials.contains(where:{$0.0==materialID && $0.1>0}) == true {pendingGatherVisualMaterialID=materialID};if collectionSummary?.isEmpty == false {WitchAudioCoordinator.shared.play(.gather)};notice=collectionSummary?.isEmpty == true ? "次の発見を待っています。":"採集の成果をしまいました。";sheet="採集の成果";writeReceipt("offline",r.result);writeRecipeGatherSnapshotR039("normal_claim")}catch{self.error=GameText.error(error)};busy=false}}
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
    private func writeR214ReplayTraceR239(replayID: String, rows: [[String: Any]]) {
        guard let saveURL, UUID(uuidString: replayID) != nil, rows.count <= 16 else { return }
        let destination = saveURL.deletingLastPathComponent()
            .appendingPathComponent("last_r214_causal_trace_r239_\(replayID).json")
        let payload: [String: Any] = [
            "schema": "r214-replay-trace-r239-v1", "replayID": replayID,
            "processID": ProcessInfo.processInfo.processIdentifier,
            "rowCount": rows.count, "rows": rows
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        // This uniquely replay-bound QA sidecar is updated atomically; it never writes the game save.
        try? data.write(to: destination, options: .atomic)
    }

    @discardableResult
    private func writeUniqueSavedCombatReplayReceiptR217(replayID: String, status: String, metadata: [String: Any]) -> Bool {
        guard let saveURL else { return false }
        let destination = saveURL.deletingLastPathComponent()
            .appendingPathComponent("last_saved_combat_replay_r217_\(replayID).json")
        var receipt: [String: Any] = [
            "kind": "saved_combat_replay_r217", "value": status,
            "revision": state.revision, "date": ISO8601DateFormatter().string(from: Date())
        ]
        for (key, value) in metadata where !["kind", "value", "revision", "date"].contains(key) {
            receipt[key] = value
        }
        guard JSONSerialization.isValidJSONObject(receipt),
              let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try data.write(to: destination, options: .withoutOverwriting)
            return true
        } catch {
            return false
        }
    }

    func writeReceipt(_ kind:String,_ value:String,metadata:[String:Any]=[:]){guard let saveURL else{return};let p=saveURL.deletingLastPathComponent().appendingPathComponent("last_\(kind).json");var obj:[String:Any]=["kind":kind,"value":value,"revision":state.revision,"date":ISO8601DateFormatter().string(from:Date())];for (key,value) in metadata where !["kind","value","revision","date"].contains(key){obj[key]=value};if let d=try? JSONSerialization.data(withJSONObject:obj,options:.prettyPrinted){try? d.write(to:p,options:.atomic)}}
    private func writeQAStartupIdentity(_ phase:String) {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"),
              let saveURL,saveURL.lastPathComponent.hasPrefix("qa-") else{return}
        var metadata:[String:Any]=["saveFilename":saveURL.lastPathComponent,
                                  "processID":ProcessInfo.processInfo.processIdentifier,
                                  "uptime":ProcessInfo.processInfo.systemUptime,
                                  "schema":"native-startup-identity-r120-v1"]
        if let data=try? Data(contentsOf:saveURL) {
            metadata["saveSHA256"]=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
            metadata["saveBytes"]=data.count
        }
        if let executable=Bundle.main.executableURL,let data=try? Data(contentsOf:executable) {
            metadata["executableSHA256"]=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        }
        if let runtimeConfiguration {
            metadata["configurationFingerprint"]=runtimeConfiguration.configurationFingerprint
            metadata["profileID"]=runtimeConfiguration.profileID
        }
        if let startupDiagnostic {metadata["startupDiagnostic"]=startupDiagnostic}
        writeReceipt("runtime_identity",phase,metadata:metadata)
    }
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
    private static func savedBattleR217(_ battle: CombatResult, matches encounterID: String, catalog: GameCatalog) -> Bool {
        guard battle.ticks > 0, !battle.events.isEmpty, !battle.initialEnemyHP.isEmpty,
              battle.initialEnemyHP.values.allSatisfy({ $0 > 0 }) else { return false }
        let initialIDs = Set(battle.initialEnemyHP.keys)
        let presentationIDs = Set(battle.entityPresentation.values.compactMap(\.catalogID))
        if let enemy = catalog.enemies.first(where: { $0.id == encounterID }) {
            return !enemy.regionID.isEmpty && (initialIDs.contains(enemy.id) || presentationIDs.contains(enemy.id))
        }
        if let challenge = catalog.challenges.first(where: { $0.id == encounterID }) {
            let expected = Set(challenge.enemyIDs)
            return !expected.isEmpty && !expected.isDisjoint(with: initialIDs.union(presentationIDs))
        }
        return false
    }

    /// Re-renders the already-persisted result. This route never dispatches a command.
    private func runSavedCombatReplayR217() async {
        guard savedCombatReplayRequestedR217, let saveURL, let expectedSaveBytes = savedCombatReplayBaselineBytesR217 else {
            savedCombatReplayStatusR217 = "REFUSED_NO_BASELINE"
            error = "保存済み戦闘の基準セーブを確認できないため、再生しませんでした。"
            return
        }
        let currentSaveBytes = try? Data(contentsOf: saveURL)
        guard let catalog, let encounterID = state.lastEncounterID, let battle = state.lastCombatResult,
              Self.savedBattleR217(battle, matches: encounterID, catalog: catalog),
              currentSaveBytes == expectedSaveBytes else {
            savedCombatReplayStatusR217 = "REFUSED"
            error = "保存済み戦闘の対象またはセーブ状態を確認できないため、再生しませんでした。"
            let currentSHA = currentSaveBytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "UNREADABLE"
            writeReceipt("saved_combat_replay_r217", "REFUSED", metadata: [
                "dispatchCount": 0, "saveBytesUnchanged": currentSaveBytes == expectedSaveBytes,
                "saveSHA256Before": SHA256.hash(data: expectedSaveBytes).map { String(format: "%02x", $0) }.joined(),
                "saveSHA256Current": currentSHA
            ])
            return
        }
        guard state.lastClaimAt != nil else {
            savedCombatReplayStatusR217 = "REFUSED_MISSING_WORK_CLOCK"
            error = "作業時計が未設定のセーブは、通常起動処理で保存が変わる可能性があるため再生しませんでした。"
            return
        }
        let regionID = catalog.enemies.first(where: { $0.id == encounterID })?.regionID
            ?? catalog.challenges.first(where: { $0.id == encounterID })?.region
        guard let regionID else {
            savedCombatReplayStatusR217 = "REFUSED_UNKNOWN_REGION"
            error = "保存済み戦闘の地域を特定できないため、再生しませんでした。"
            return
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let combatBytes = try? encoder.encode(battle) else {
            savedCombatReplayStatusR217 = "REFUSED_UNENCODABLE_RESULT"
            return
        }
        let combatSHA = SHA256.hash(data: combatBytes).map { String(format: "%02x", $0) }.joined()
        let initialSnapshot = state
        guard let engine else {
            savedCombatReplayStatusR217 = "REFUSED_ENGINE_UNAVAILABLE"
            return
        }
        let engineBefore = await engine.snapshot()
        guard engineBefore == initialSnapshot else {
            savedCombatReplayStatusR217 = "REFUSED_STALE_ENGINE_SNAPSHOT"
            error = "表示中のセーブ状態が読み込み時から変わったため、再生しませんでした。"
            return
        }

        tab = "探索"; chosenRegion = regionID; fighting = true; busy = true
        activeAreaFightEnemyID = catalog.enemies.contains(where: { $0.id == encounterID })
            ? encounterID
            : catalog.challenges.first(where: { $0.id == encounterID })?.enemyIDs.first
        notice = "保存済み戦闘の演出を再生中です。報酬処理は実行しません。"
        syncScene()
        let viewDeadline = ProcessInfo.processInfo.systemUptime + 15
        while !scene.isForegroundRenderedForR047 && ProcessInfo.processInfo.systemUptime < viewDeadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
        }
        guard scene.isForegroundRenderedForR047, !Task.isCancelled else {
            fighting = false; busy = false; activeAreaFightEnemyID = nil; syncScene()
            savedCombatReplayStatusR217 = "REFUSED_SCENE_NOT_RENDERED"
            error = "戦闘シーンが表示状態にならなかったため、再生しませんでした。"
            return
        }

        savedCombatReplayStatusR217 = "PLAYING"
        let replayID = UUID().uuidString
        let mode = ProcessInfo.processInfo.arguments.contains("--r214-hit-deferral=off") ? "r214_deferral_off" : "r214_deferral_default"
        writeReceipt("saved_combat_replay_r217", "STARTED", metadata: [
            "replayID": replayID, "mode": mode, "encounterID": encounterID,
            "saveFilename": saveURL.lastPathComponent, "saveSHA256Before": SHA256.hash(data: expectedSaveBytes).map { String(format: "%02x", $0) }.joined(),
            "combatResultSHA256": combatSHA, "ticks": battle.ticks, "won": battle.won, "dispatchCount": 0,
            "processID": ProcessInfo.processInfo.processIdentifier
        ])
        var playbackCompletionR217: (eventsPresented: Int, hpMismatchCount: Int)?
        var causalRowsR239: [[String: Any]] = []
        var causalExecuteR239: (actorID: String, eventSequence: Int, rootActionID: String,
                                 sceneGeneration: Int, startedUptime: TimeInterval, hitEventSequence: Int?)?
        scene.onR214ReplayLifecycleR239 = { [weak self] observedReplayID, row in
            let acceptedKinds: Set<String> = ["execute_started", "execute_completed", "hit_visual_deferred",
                "hit_visual_started_after_execute", "hit_visual_rejected_after_execute",
                "hit_visual_completed", "hit_visual_cancelled"]
            guard observedReplayID == replayID,
                  let kind = row["kind"] as? String, acceptedKinds.contains(kind) else { return }
            guard let actorID = row["actorID"] as? String,
                  let eventSequence = row["eventSequence"] as? Int,
                  let rootActionID = row["rootActionID"] as? String, !rootActionID.isEmpty,
                  let sceneGeneration = row["sceneGeneration"] as? Int else { return }

            if causalExecuteR239 == nil {
                // Ignore ordinary hit lifecycle noise before the first instrumented execute.
                guard kind == "execute_started" else { return }
                causalExecuteR239 = (actorID, eventSequence, rootActionID, sceneGeneration,
                                     ProcessInfo.processInfo.systemUptime, nil)
                causalRowsR239 = [row]
                self?.writeR214ReplayTraceR239(replayID: observedReplayID, rows: causalRowsR239)
                return
            }
            guard var execute = causalExecuteR239,
                  ProcessInfo.processInfo.systemUptime - execute.startedUptime <= 5.0,
                  actorID == execute.actorID, sceneGeneration == execute.sceneGeneration else { return }

            let linkedExecuteSequence = row["executeEventSequence"] as? Int
            let linkedExecuteRoot = row["executeRootActionID"] as? String
            switch kind {
            case "execute_completed":
                guard eventSequence == execute.eventSequence, rootActionID == execute.rootActionID else { return }
            case "hit_visual_deferred":
                guard linkedExecuteSequence == execute.eventSequence,
                      linkedExecuteRoot == execute.rootActionID else { return }
                if execute.hitEventSequence == nil { execute.hitEventSequence = eventSequence }
                guard execute.hitEventSequence == eventSequence else { return }
            case "hit_visual_started_after_execute", "hit_visual_rejected_after_execute",
                 "hit_visual_completed", "hit_visual_cancelled":
                guard linkedExecuteSequence == execute.eventSequence,
                      linkedExecuteRoot == execute.rootActionID,
                      let hitSequence = execute.hitEventSequence else { return }
                let rowHitSequence = row["eventSequence"] as? Int
                let groupedHitSequences = row["deferredHitEventSequences"] as? [Int] ?? []
                guard rowHitSequence == hitSequence || groupedHitSequences.contains(hitSequence) else { return }
            default:
                return
            }
            causalExecuteR239 = execute
            guard causalRowsR239.count < 16 else { return }
            var capturedRow = row
            capturedRow["r239ObservationElapsedWallSeconds"] =
                max(0, ProcessInfo.processInfo.systemUptime - execute.startedUptime)
            causalRowsR239.append(capturedRow)
            self?.writeR214ReplayTraceR239(replayID: observedReplayID, rows: causalRowsR239)
        }
        await play(battle, completion: { eventsPresented, hpMismatchCount in
            playbackCompletionR217 = (eventsPresented, hpMismatchCount)
        }, r214ReplayID: replayID)
        scene.onR214ReplayLifecycleR239 = nil
        let playbackCompleted = !Task.isCancelled
            && playbackCompletionR217?.eventsPresented == battle.events.count
        if playbackCompleted {
            await presentBattleResolution(won: battle.won)
        }
        let afterBytes = try? Data(contentsOf: saveURL)
        let afterCombatBytes = state.lastCombatResult.flatMap { try? encoder.encode($0) }
        let engineAfter = await engine.snapshot()
        let engineUnchanged = engineAfter == initialSnapshot
        let saveUnchanged = afterBytes == expectedSaveBytes
        let resultUnchanged = state.lastCombatResult == battle && afterCombatBytes == combatBytes
        var passed = playbackCompleted && !Task.isCancelled && saveUnchanged && resultUnchanged && engineUnchanged
        var finalStatus = passed ? "COMPLETED_PRESENTATION_ONLY"
            : (playbackCompleted ? "FAILED_STATE_CHANGED" : "INCOMPLETE_PLAYBACK")
        savedCombatReplayStatusR217 = finalStatus
        let finalMetadata: [String: Any] = [
            "replayID": replayID, "mode": mode, "encounterID": encounterID,
            "saveSHA256Before": SHA256.hash(data: expectedSaveBytes).map { String(format: "%02x", $0) }.joined(),
            "saveSHA256After": afterBytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "UNREADABLE",
            "saveBytesUnchanged": saveUnchanged, "combatResultSHA256": combatSHA,
            "combatResultUnchanged": resultUnchanged, "engineSnapshotUnchanged": engineUnchanged,
            "dispatchCount": 0, "renderAudit": scene.artAuditJSON(), "processID": ProcessInfo.processInfo.processIdentifier,
            "playbackCompleted": playbackCompleted,
            "eventsPresented": playbackCompletionR217?.eventsPresented ?? 0,
            "expectedEventCount": battle.events.count,
            "preFinishHPMismatchCount": playbackCompletionR217.map { $0.hpMismatchCount } ?? -1
        ]
        let uniqueReceiptWritten = writeUniqueSavedCombatReplayReceiptR217(replayID: replayID, status: finalStatus, metadata: finalMetadata)
        if !uniqueReceiptWritten {
            passed = false
            finalStatus = "FAILED_UNIQUE_RECEIPT_WRITE"
            savedCombatReplayStatusR217 = finalStatus
        }
        writeReceipt("saved_combat_replay_r217", finalStatus, metadata: finalMetadata.merging(["uniqueSidecarWritten": uniqueReceiptWritten]) { _, new in new })
        fighting = false; busy = false; activeAreaFightEnemyID = nil; syncScene()
        notice = passed ? "保存済み戦闘の演出を再生しました。セーブと報酬は変わっていません。"
            : "再生後に状態差を検出しました。結果を確認してください。"
        if !passed { error = "保存済み戦闘の再生後にセーブまたは状態の差を検出しました。" }
    }

    func fight(_ enemy:EnemyDefinition){
        guard !busy,let engine else{return}
        // This HUD value belongs to the current presentation, not the previous fight.
        battleElapsed=0
        busy=true;fighting=true;activeAreaFightEnemyID=enemy.id;syncScene();scene.setEnemy(enemy.id)
        let qaArgs = ProcessInfo.processInfo.arguments
        var fullBattleEquipmentMotionRequest: EquipmentMotionTraceRequest?
        var enemyEventRenderRequestR145: EnemyEventRenderRequestR145?
        if qaArgs.contains(EnemyEventRenderRequestR145.flag) {
            #if targetEnvironment(simulator)
            let result = EnemyEventRenderRequestR145.parse(
                arguments: qaArgs, isSimulator: true, encounterID: enemy.id,
                saveFilename: saveURL?.lastPathComponent,
                outputDirectory: saveURL?.deletingLastPathComponent())
            switch result {
            case .success(let request):
                enemyEventRenderRequestR145 = request
                writeReceipt("enemy_event_render_r145_start", "PENDING_ACTUAL_BATTLE",
                             metadata: ["runID": request.runID, "encounterID": request.encounterID,
                                        "actorID": request.actorID, "saveKey": request.saveKey,
                                        "saveFilename": saveURL?.lastPathComponent ?? "",
                                        "processID": ProcessInfo.processInfo.processIdentifier])
            case .failure(let failure):
                writeReceipt("enemy_event_render_r145_start", "PRECONDITION_FAIL",
                             metadata: ["reason": failure.rawValue, "encounterID": enemy.id,
                                        "processID": ProcessInfo.processInfo.processIdentifier])
            }
            #else
            writeReceipt("enemy_event_render_r145_start", "PRECONDITION_FAIL",
                         metadata: ["reason": "SIMULATOR_ONLY", "encounterID": enemy.id,
                                    "processID": ProcessInfo.processInfo.processIdentifier])
            #endif
        }
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
                           ernaStaffMotionTrace: ernaStaffMotionTraceRequest,
                           enemyEventRenderTraceR145: enemyEventRenderRequestR145)
                if battle.won {
                    let delta=GatheringSummary(before:battleBefore,after:state,catalog:catalog)
                    let rewardParts = delta.materials.map { "\(GameText.name($0.0)) +\($0.1)" }
                        + delta.currency.map { "\(GameText.name($0.0)) +\($0.1)" }
                        + delta.experience.map { actorID, amount in
                            let actorName = GameModel.actorNames[actorID] ?? GameText.name(actorID)
                            return "\(actorName) EXP +\(amount)"
                        }
                    let rewardLine = rewardParts.joined(separator: "・")
                    notice="\(enemy.name)を乗り越えました。獲得: \(rewardLine.isEmpty ? "なし" : rewardLine)"
                } else {
                    notice = DefeatGuidanceR229.message(state: state, catalog: catalog)
                }
            } else {
                if let request = enemyEventRenderRequestR145 {
                    writeReceipt("enemy_event_render_r145_result", "NO_COMBAT_RESULT",
                                 metadata: ["runID": request.runID, "encounterID": request.encounterID,
                                            "actorID": request.actorID, "saveKey": request.saveKey,
                                            "processID": ProcessInfo.processInfo.processIdentifier])
                }
                notice = r.result
            }
            appendNaturalGearNoticeR350(since: battleBefore)
            await presentBattleResolution(won:state.lastCombatResult?.won ?? false);writeReceipt("battle",r.result);writeReceipt("battle_art",scene.artAuditJSON())
        }catch{self.error=GameText.error(error);writeReceipt("battle_error",String(reflecting:error))};activeAreaFightEnemyID=nil;busy=false;fighting=false;syncScene()}
    }
    func summon(_ count: Int) {
        guard let runtimeConfiguration, !busy, let engine else { return }
        busy = true
        Task {
            let before = state
            do {
                _ = try await engine.dispatch(.mockSummon(poolDefinitionIDs: runtimeConfiguration.summonPoolIDs,
                    count: count, costCurrencyID: "ticket_free", seed: UInt64(bitPattern: state.revision) &+ 17),
                    operationID: UUID(), expectedRevision: state.revision)
                await refresh()
                let prior = Set(before.gear.map(\.id))
                let natural = Set(naturalGearArrivalsR350(since: before).map(\.id))
                opening = state.gear.map(\.id).filter { !prior.contains($0) && !natural.contains($0) }
                sheet = "開封"
                notice = "魔導庫から装備が\(count)点届きました。"
                appendNaturalGearNoticeR350(since: before)
            } catch { self.error = GameText.error(error); await refresh() }
            busy = false
        }
    }
    func daily(){act(.dailyClaim(now:Date()),"今日の無料鑑定券を受け取りました。")}
}

enum Palette {static let ink=Color(red:0.035,green:0.065,blue:0.085);static let panel=Color(red:0.055,green:0.10,blue:0.12);static let gold=Color(red:0.82,green:0.69,blue:0.43);static let text=Color(red:0.94,green:0.91,blue:0.82)}

struct RootView:View {
    @State private var workshopMode = "craft_new"
    @State private var enemyPage=0
    @State private var exploreControlsExpanded=false
    @State private var pendingRecipeGatherHandoff: RecipeGatherHandoffR039?
    @State private var pendingRecipeInvestigationHandoff: RecipeInvestigationHandoffR158?
    @State private var pendingResearchGatherHandoffR310: ResearchGatherHandoffR310?
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
                    if model.tab == "仲間" {
                        companionScreen
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                    } else {
                        ZStack(alignment:.bottom){
                            SpriteView(scene:model.scene)
                                .accessibilityElement(children:.ignore)
                                .accessibilityLabel(sceneAccessibilitySummary)
                                .accessibilityAddTraits(.isImage)
                                .accessibilityIdentifier("living_scene")
                            if model.tab == "家" {homeOverlay}
                            else if model.tab == "探索" {exploreOverlay}
                            else {Palette.ink; ScrollViewReader { proxy in
                                ScrollView {
                                    if model.tab == "工房" { workshop }
                                    else {
                                        ResearchView(model:model, onGatherSource:prepareResearchGatherHandoffR310, scrollToSection:{ identifier in
                                            withAnimation(.easeInOut(duration:0.3)) { proxy.scrollTo(identifier, anchor:.top) }
                                        }).padding(16)
                                    }
                                }.accessibilityIdentifier("workshop_scroll")
                            }}
                        }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
                    }
                    footer
                }
            }.sheet(isPresented:Binding(get:{model.sheet != nil},set:{if !$0{model.sheet=nil}}),onDismiss:{pendingResearchGatherHandoffR310=nil;model.presentPendingGatherVisualAfterResultDismissal()}){
                sheet(model.sheet ?? "設定")
                    .interactiveDismissDisabled(model.busy && pendingResearchGatherHandoffR310 != nil)
            }
            .alert(model.error == nil && model.saveRecoveryMessage != nil ? "セーブを復元しました":"確認が必要です",isPresented:Binding(get:{model.error != nil || model.saveRecoveryMessage != nil},set:{if !$0{model.error=nil;model.saveRecoveryMessage=nil}})){
                Button("閉じる",role:.cancel){model.error=nil;model.saveRecoveryMessage=nil}
                    .accessibilityIdentifier("dismiss_save_notice")
            }message:{Text(model.error ?? model.saveRecoveryMessage ?? "").accessibilityIdentifier("save_notice_message")}
            .onChange(of:model.fighting){_,fighting in if fighting {exploreControlsExpanded=false;pendingRecipeGatherHandoff=nil;pendingRecipeInvestigationHandoff=nil}}
            .onChange(of:model.tab){_,tab in
                if tab != "探索", pendingRecipeGatherHandoff != nil || pendingRecipeInvestigationHandoff != nil {
                    pendingRecipeGatherHandoff = nil
                    pendingRecipeInvestigationHandoff = nil
                    model.chosenRegion = model.state.activeRegionID ?? model.chosenRegion
                }
                model.syncScene()
            }.onChange(of:model.selectedActor){_,_ in model.syncScene()}
            .onChange(of:phase){_,p in
                model.sceneActive = p == .active
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
        if model.fighting {
            if model.savedCombatReplayStatusR217 == "PLAYING" { return "保存済み戦闘結果の演出を再生中です。ゲーム状態と報酬には作用しません。" }
            return "\(model.catalog?.regions.first{$0.id==model.chosenRegion}?.name ?? "探索")で仲間4人が自動戦闘中です。戦闘操作はありません。"
        }
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
        if model.sharedPartyWorkR146Enabled, let catalog = model.catalog {
            SharedPartyWorkProgressR146(state:model.state,catalog:catalog)
        } else if let catalog = model.catalog {
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
                Text(model.sharedPartyWorkR146Enabled ? "共同作業の成果を受け取る" : "成果を受け取る")
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
        .accessibilityLabel(model.sharedPartyWorkR146Enabled ? "共同作業の成果を受け取る" : "成果を受け取る")
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
                                pendingRecipeInvestigationHandoff = nil
                                enemyPage=0
                                if model.sharedPartyWorkR146Enabled {
                                    model.selectSharedPartyWorkRegionR146(region.id)
                                } else {
                                    model.chosenRegion=region.id
                                    model.act(.startExpeditionAt(regionID:region.id,now:Date()),region.name+"へ出発。")
                                    model.syncScene()
                                }
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
                    if let handoff = pendingRecipeInvestigationHandoff {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("制作目標の材料").font(.headline)
                            Text("\(GameText.name(handoff.materialID)) · \(model.recipeRegionNames([handoff.regionID])) · あと\(handoff.missing)個")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("recipe_investigation_handoff_summary")
                            if model.state.activeRegionID != handoff.regionID {
                                Text("地域を切り替えると、切替前の共同作業分が所持数に反映されます。")
                                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                            Button { applyRecipeInvestigationHandoff(handoff) } label: {
                                Label("この魔物を再調査する", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                            .disabled(model.busy || model.fighting)
                            .accessibilityIdentifier("recipe_investigation_apply")
                            Button {
                                pendingRecipeInvestigationHandoff = nil
                                model.chosenRegion = model.state.activeRegionID ?? model.chosenRegion
                                model.syncScene()
                            } label: {
                                Text("閉じる").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }.disabled(model.busy).accessibilityIdentifier("recipe_investigation_dismiss")
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("recipe_investigation_handoff")
                    }
                    Spacer(minLength:dynamicTypeSize > .large ? 10:70)
                    if model.fighting {
                        VStack(alignment:.leading,spacing:6) {
                            Text(model.battleResolutionMessage ?? model.preparationMessage ?? (ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--art-audit=") || $0.hasPrefix("--qa-party-frame=") || $0=="--qa-party-motion"}) ? model.notice:(model.qaCombatPreview ? "R6検証・報酬なし ・ \(model.battleElapsed)秒":"4人で自動戦闘中 ・ \(model.battleElapsed)秒")))
                                .font(.title3)
                                .accessibilityIdentifier(model.battleResolutionMessage == nil ? "battle_progress":"battle_resolution")
                            if model.battleResolutionMessage == nil, model.preparationMessage == nil,
                               let warning=model.battleTargetWarningTextR299 {
                                Text(warning).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.gold)
                                    .fixedSize(horizontal:false,vertical:true)
                                    .accessibilityIdentifier("battle_target_warning_r299")
                            }
                        }
                            .padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Palette.ink.opacity(0.8))
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
                            if model.sharedPartyWorkR146Enabled { SharedPartyWorkPanelR146(model:model) }
                            Text(model.notice).font(.caption)
                            if dynamicTypeSize > .large {
                                if !model.sharedPartyWorkR146Enabled {
                                    LazyVStack(alignment:.leading,spacing:8) {
                                        ForEach(gatherMaterialIDs,id:\.self) { id in gatherButton(id,expanded:true) }
                                    }
                                }
                                LazyVStack(spacing:10) { ForEach(regionEnemies) { enemy in enemyButton(enemy,expanded:true) } }
                            } else {
                                if !model.sharedPartyWorkR146Enabled {
                                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:4) {
                                        ForEach(gatherMaterialIDs,id:\.self) { id in gatherButton(id,expanded:false) }
                                    }
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
                            let investigationActive = model.sharedPartyWorkR146Enabled && model.state.partyWorkTargetR144?.kind == .investigate
                            if !investigationActive, let materialID=model.state.gatherTargetMaterialID,
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
                                    Label(model.sharedPartyWorkR146Enabled ? "共同作業の成果を受け取る" : "成果を受け取る",systemImage:"basket").frame(maxWidth:.infinity,minHeight:44,alignment:dynamicTypeSize > .large ? .leading:.center)
                                        .contentShape(.interaction,Rectangle())
                                }.disabled(model.busy || (model.sharedPartyWorkR146Enabled && model.fighting)).accessibilityIdentifier("claim_offline")
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
        pendingRecipeInvestigationHandoff = nil
        model.writeRecipeGatherSnapshotR039("before_navigation")
        pendingRecipeGatherHandoff = RecipeGatherHandoffR039(recipeID: recipeID, materialID: materialID, regionID: regionID, missing: missing)
        model.chosenRegion = regionID
        model.tab = "探索"
        model.sheet = nil
        model.notice = "\(GameText.name(materialID))の採集先を確認しています。始めるには下の操作を選んでください。"
        model.syncScene()
        model.writeRecipeGatherSnapshotR039("route_confirmation")
    }

    private func prepareResearchGatherHandoffR310(_ route: ResearchGatherHandoffR310) {
        guard !model.busy, !model.fighting,
              ResearchGatherRouteR310.resolve(route, catalog:model.catalog, state:model.state) != nil else {
            model.error = "素材の不足数や採集条件が変わりました。研究を開き直してください。"
            return
        }
        // A sheet is only a preview: region, work target, clock and save stay untouched.
        pendingResearchGatherHandoffR310 = route
        model.sheet = "研究の採集先"
    }

    private func applyResearchGatherHandoffR310(_ route: ResearchGatherHandoffR310) {
        guard !model.busy, !model.fighting else { return }
        Task { @MainActor in
            do {
                try await model.applyResearchGatherHandoffR310(route)
                pendingResearchGatherHandoffR310 = nil
                pendingRecipeGatherHandoff = nil
                pendingRecipeInvestigationHandoff = nil
                exploreControlsExpanded = false
                model.chosenRegion = model.state.activeRegionID ?? route.regionID
                model.sheet = nil
                model.tab = "探索"
                model.syncScene()
            } catch {
                model.error = GameText.error(error)
            }
        }
    }

    private func prepareRecipeInvestigationHandoff(_ route: RecipeInvestigationHandoffR158) {
        guard !model.busy, !model.fighting, model.sharedPartyWorkR146Enabled,
              let catalog = model.catalog,
              let goal = model.previewRecipeGoal,
              RecipeInvestigationRouteR158.contains(route, goal: goal, catalog: catalog,
                  state: model.state, sharedWorkEnabled: true) else {
            model.error = "再調査の条件が変わりました。制作目標を開き直してください。"
            return
        }
        // Navigation only. Work target and saved snapshot remain untouched until explicit apply.
        pendingRecipeGatherHandoff = nil
        pendingRecipeInvestigationHandoff = route
        model.chosenRegion = route.regionID
        model.tab = "探索"
        model.sheet = nil
        let enemyName = catalog.enemies.first { $0.id == route.enemyID }?.name ?? "討伐済みの魔物"
        model.notice = "\(enemyName)の再調査内容を確認しています。開始するには下の操作を選んでください。"
        model.syncScene()
    }

    private func applyRecipeInvestigationHandoff(_ route: RecipeInvestigationHandoffR158) {
        guard !model.busy else { return }
        Task { @MainActor in
            do {
                try await model.applyRecipeInvestigationHandoffR158(route)
                pendingRecipeInvestigationHandoff = nil
                model.chosenRegion = route.regionID
                model.tab = "探索"
                model.syncScene()
            } catch {
                model.error = GameText.error(error)
            }
        }
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
            pendingRecipeInvestigationHandoff = nil
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
    /// The companion screen gives selection, portrait, and stats separate regions.
    /// The SpriteKit scene resizes to this viewport, so portrait sizing follows the
    /// available region instead of sitting behind the stats card.
    private var companionScreen:some View {
        GeometryReader { geometry in
            let portraitHeight = min(280, max(170, geometry.size.height * 0.40))
            VStack(spacing:0) {
                if dynamicTypeSize.isAccessibilitySize {
                    let actorName = GameModel.actorNames[model.selectedActor] ?? "仲間"
                    Text("表示中：" + actorName)
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                        .padding(.horizontal,12)
                        .background(Palette.panel)
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel("表示中の仲間")
                        .accessibilityValue(actorName)
                        .accessibilityIdentifier("companion_selected_context")
                }
                ScrollView(.vertical) {
                    VStack(spacing:8) {
                        companionSelector
                        companionPortrait(height: portraitHeight)
                        companionSummary
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .padding(.vertical,8)
                }
                .scrollIndicators(dynamicTypeSize.isAccessibilitySize ? .visible : .hidden)
                .accessibilityIdentifier("companion_scroll")
            }
        }
        .foregroundStyle(Palette.text)
    }
    private func companionPortrait(height:CGFloat)->some View {
        SpriteView(scene:model.scene)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(sceneAccessibilitySummary)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("living_scene")
            .frame(maxWidth:.infinity)
            .frame(height:height)
            .clipShape(RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.gold.opacity(0.35),lineWidth:1))
            .padding(.horizontal,12)
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
            if EquipmentLoadoutsBuildPolicyR342.enabled {
                action("装備セット",symbol:"square.stack",id:"equipment_loadouts") { model.sheet="装備セット" }
            }
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
            ForEach(model.workshopCraftRecipesR395) { recipe in
                let gear=model.catalog?.gear.first{$0.id==recipe.outputGearID}
                VStack(alignment:.leading,spacing:10) {
                    HStack(alignment:.top,spacing:12) {
                        AssetIcon(id:"ICO_"+(recipe.outputGearID ?? ""),size:52).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:6) {
                            Text(gear?.name ?? recipe.outputGearID ?? "装備").font(.headline).fixedSize(horizontal:false,vertical:true)
                            Text(model.recipeCostDescriptionR179(recipe.id))
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
        if name == "共同作業の成果",let summary=model.collectionSummary {
            SharedPartyWorkSummaryViewR146(targetLabel:model.sharedPartyWorkSummaryTargetR146,summary:summary,onInspectAllNewGear: {
                model.opening = summary.gainedGear.map(\.id)
                model.sheet = "開封"
            })
        }
        else if name == "採集の成果",let summary=model.collectionSummary {GatheringSummaryView(summary:summary,onInspectAllNewGear: {
            model.opening = summary.gainedGear.map(\.id)
            model.sheet = "開封"
        })}
        else if name == "装備" || name == "開封" {inventory(opening:name=="開封")}
        else if name == "魔導庫" {GachaView(model:model)}
        else if name == "確率" {GachaRulesView(model:model)}
        else if name == "模様替え" {title("暮らしを整える","家具を置いて、仲間の居場所を。");FurnitureRoomPreviewR275(model:model);action(model.state.placedFurnitureIDs.contains("FURN_DESK_BOTANICAL") ? "机をしまう":"植物研究の机を置く",symbol:"chair.lounge",id:"place_desk"){model.act(.placeFurniture("FURN_DESK_BOTANICAL",placed:!model.state.placedFurnitureIDs.contains("FURN_DESK_BOTANICAL")),"家の模様替えを保存しました。")}.disabled(!model.state.ownedFurnitureIDs.contains("FURN_DESK_BOTANICAL"));if !model.state.ownedFurnitureIDs.contains("FURN_DESK_BOTANICAL"){Button("無料の研究机を受け取る"){model.act(.setFurniture("FURN_DESK_BOTANICAL",owned:true),"研究机を受け取りました。")}.frame(minHeight:44)}}
        else if name == "試着" {WardrobeView(model:model)}
        else if name == "比較" {GearComparisonView(model:model)}
        else if name == "装備セット" && EquipmentLoadoutsBuildPolicyR342.enabled {EquipmentLoadoutsViewR342(model:model)}
        else if name == "研究の採集先", let route=pendingResearchGatherHandoffR310 {
            ResearchGatherPreviewR310(model:model,route:route,onApply:{applyResearchGatherHandoffR310(route)})
        }
        else if name == "制作目標" {RecipeGoalView(model: model, onGatherSource: { recipeID, materialID, regionID, missing in
            prepareRecipeGatherHandoff(recipeID: recipeID, materialID: materialID, regionID: regionID, missing: missing)
        }, onInvestigationSource: { route in
            prepareRecipeInvestigationHandoff(route)
        })}
        else if name == "広告検証" && model.localAdRewardQAEnabled {LocalAdQAPanel(model:model)}
        else if name == "購入検証" && model.localStoreKitQAEnabled {GameStoreKitQAPanel(model:model)}
        else if name == "商店" {title("森の小さな商店","衣装と家具で、自分だけの暮らしを。");HStack{AssetIcon(id:"FURN_DESK_BOTANICAL",size:130).accessibilityHidden(true);VStack(alignment:.leading){Text("植物研究の机");Text("無料の初期家具").font(.caption);Button("模様替えへ"){model.sheet="模様替え"}.frame(minHeight:44)}};Text("衣装・有料家具の販売準備中").foregroundStyle(Palette.gold);Button("購入の復元（未提供）"){}.frame(minHeight:44).disabled(true).accessibilityHint("購入復元機能はまだ提供されていません");Text("この開発版では料金は発生しません。").font(.caption)}
        else {title("設定","ローカル開発版");musicControls;Toggle("効果音を消音",isOn:Binding(get:{audio.isMuted},set:{audio.setMuted($0)})).accessibilityIdentifier("audio_mute");VStack(alignment:.leading,spacing:4){Text("効果音の音量 \(Int(audio.volume*100))%").font(.caption);Slider(value:Binding(get:{Double(audio.volume)},set:{audio.setVolume(Float($0))}),in:0...1).accessibilityLabel("効果音の音量").accessibilityIdentifier("audio_volume")};if model.localAdRewardQAEnabled{Button("任意報酬のローカル検証"){model.sheet="広告検証"}.frame(minHeight:44)};if model.localStoreKitQAEnabled{Button("Xcode購入検証"){model.sheet="購入検証"}.frame(minHeight:44)};Text("進行状況は自動で保存されます。");Text("この開発版では購入・広告機能は利用できません。").font(.caption).foregroundStyle(.secondary);Button("保存状態を再読み込み"){Task{await model.refresh()}}.frame(minHeight:44)}
    }.padding(20)}.id(name).accessibilityIdentifier("sheet_scroll_"+name).background(Palette.ink).navigationTitle(name).navigationBarTitleDisplayMode(.inline).toolbarBackground(Palette.ink,for:.navigationBar).toolbar{ToolbarItem(placement:.topBarTrailing){Button{model.closeSheet()}label:{Image(systemName:"xmark").frame(width:44,height:44)}.disabled(model.busy && name == "研究の採集先").accessibilityLabel("閉じる").accessibilityHint("この画面を閉じます").foregroundStyle(Color.white)}}}.tint(Palette.gold).foregroundStyle(Palette.text)}
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
