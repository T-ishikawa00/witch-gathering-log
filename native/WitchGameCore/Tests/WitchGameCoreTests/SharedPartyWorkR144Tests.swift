import XCTest
@testable import WitchGameCore

final class SharedPartyWorkR144Tests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private let regionID = "R01"
    private let gatherG1 = "M_R01_G1"
    private let enemyE2 = "E_R01_02"

    private struct Harness {
        let profile: GameRuntimeConfigurationR098
        let store: SaveRepository
        let engine: GameEngine
    }

    private func makeHarness(policyEnabled: Bool = true, fileURL: URL? = nil,
                             initial supplied: GameSnapshot? = nil) throws -> Harness {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        var initial = try supplied ?? profile.makeNewSnapshot()
        initial.unlockedRegionIDs.insert(regionID)
        initial.activeRegionID = regionID
        initial.gatherTargetMaterialID = initial.gatherTargetMaterialID ?? gatherG1
        initial.partyWorkTargetR144 = nil
        initial.lastClaimAt = initial.lastClaimAt ?? epoch
        initial.offlineRemainderSeconds = 0
        let store = try SaveRepository(initial: initial, fileURL: fileURL)
        let policy = policyEnabled
            ? try PartyWorkPolicyR144(baseProfileID: profile.profileID,
                                      baseConfigurationFingerprint: profile.configurationFingerprint)
            : nil
        let engine = try GameEngine(catalog: profile.catalog, saves: store,
                                    candidateCombatOverlay: profile.combatOverlay,
                                    candidateCharacterGrowth: profile.growth,
                                    candidateLatentPolicy: profile.latentPolicy,
                                    candidatePartyWorkPolicyR144: policy)
        return Harness(profile: profile, store: store, engine: engine)
    }

    private func send(_ engine: GameEngine, _ command: GameCommand, id: UUID = UUID()) async throws -> CommandReceipt {
        let current = await engine.snapshot()
        return try await engine.dispatch(command, operationID: id, expectedRevision: current.revision)
    }

    private func winningSeed(_ engine: GameEngine, enemyID: String) async throws -> UInt64 {
        let state = await engine.snapshot()
        for seed in UInt64(1)...UInt64(32) {
            let trialStore = try SaveRepository(initial: state)
            let trialEngine = try GameEngine(catalog: engine.catalog, saves: trialStore,
                                             candidateCombatOverlay: engine.candidateCombatOverlay,
                                             candidateCharacterGrowth: engine.candidateCharacterGrowth,
                                             candidateLatentPolicy: engine.candidateLatentPolicy,
                                             candidatePartyWorkPolicyR144: engine.candidatePartyWorkPolicyR144)
            _ = try await trialEngine.dispatch(.resolveEncounter(enemyID: enemyID, seed: seed),
                                               operationID: UUID(), expectedRevision: state.revision)
            if (await trialEngine.snapshot()).lastCombatResult?.won == true { return seed }
        }
        throw CoreError.invalidCommand("test could not find a real winning combat seed for \(enemyID)")
    }

    private func clearE2(_ engine: GameEngine) async throws -> CommandReceipt {
        let seed = try await winningSeed(engine, enemyID: enemyE2)
        return try await send(engine, .resolveEncounter(enemyID: enemyE2, seed: seed))
    }

    private func testURL(_ label: String = #function) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-party-r144-\(label)-\(UUID().uuidString).json")
    }

    func testProfileAndPolicyArePinnedSeparatelyAndDefaultIsOptInOff() throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let policy = try PartyWorkPolicyR144(baseProfileID: profile.profileID,
                                             baseConfigurationFingerprint: profile.configurationFingerprint)
        XCTAssertEqual(profile.profileID, PartyWorkPolicyR144.expectedBaseProfileID)
        XCTAssertEqual(profile.configurationFingerprint, PartyWorkPolicyR144.expectedBaseConfigurationFingerprint)
        XCTAssertEqual(policy.baseConfigurationFingerprint, profile.configurationFingerprint)
        XCTAssertEqual(policy.policyFingerprint.count, 64)
        XCTAssertNotEqual(profile.configurationFingerprint, policy.policyFingerprint)
        XCTAssertNil(try GameEngine(catalog: profile.catalog, saves: SaveRepository(initial: profile.makeNewSnapshot())).candidatePartyWorkPolicyR144)
        XCTAssertThrowsError(try PartyWorkPolicyR144(baseProfileID: "other-profile"))
        XCTAssertThrowsError(try PartyWorkPolicyR144(baseConfigurationFingerprint: String(repeating: "0", count: 64)))
    }

    func testR144EngineRejectsRuntimeDependenciesThatDoNotMatchPinnedR098Profile() throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let policy = try PartyWorkPolicyR144(baseProfileID: profile.profileID,
                                             baseConfigurationFingerprint: profile.configurationFingerprint)
        let store = try SaveRepository(initial: profile.makeNewSnapshot())
        let wrongOverlay = CandidateCombatOverlay(id: "wrong", status: "UNAPPROVED_TEST_OVERLAY",
                                                  targetEnemyID: "E_R03_04", actionPattern: "wrong",
                                                  magnetParameters: profile.combatOverlay.magnetParameters)
        XCTAssertThrowsError(try GameEngine(catalog: profile.catalog, saves: store,
                                            candidateCombatOverlay: wrongOverlay,
                                            candidateCharacterGrowth: profile.growth,
                                            candidateLatentPolicy: profile.latentPolicy,
                                            candidatePartyWorkPolicyR144: policy))

        let wrongGrowth = CandidateCharacterGrowth(strengthBP: 750)
        XCTAssertThrowsError(try GameEngine(catalog: profile.catalog, saves: store,
                                            candidateCombatOverlay: profile.combatOverlay,
                                            candidateCharacterGrowth: wrongGrowth,
                                            candidateLatentPolicy: profile.latentPolicy,
                                            candidatePartyWorkPolicyR144: policy))

        var rawCatalog = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile.catalog)) as? [String: Any])
        var enemies = try XCTUnwrap(rawCatalog["enemies"] as? [[String: Any]])
        let enemyIndex = try XCTUnwrap(enemies.firstIndex(where: { $0["id"] as? String == enemyE2 }))
        enemies[enemyIndex]["attack"] = (enemies[enemyIndex]["attack"] as? Int ?? 0) + 1
        rawCatalog["enemies"] = enemies
        let wrongCatalog = try JSONDecoder().decode(GameCatalog.self,
                                                    from: JSONSerialization.data(withJSONObject: rawCatalog))
        XCTAssertThrowsError(try GameEngine(catalog: wrongCatalog, saves: store,
                                            candidateCombatOverlay: profile.combatOverlay,
                                            candidateCharacterGrowth: profile.growth,
                                            candidateLatentPolicy: profile.latentPolicy,
                                            candidatePartyWorkPolicyR144: policy))

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let latentURL = packageRoot.appendingPathComponent("Sources/WitchGameCore/Resources/candidate_latent_policy_r004.json")
        var latentBytes = try Data(contentsOf: latentURL)
        latentBytes.append(0x20) // Valid JSON whitespace, different exact pinned dependency bytes.
        let wrongLatentPolicy = try CandidateLatentSlotPolicyR003.load(data: latentBytes)
        XCTAssertThrowsError(try GameEngine(catalog: profile.catalog, saves: store,
                                            candidateCombatOverlay: profile.combatOverlay,
                                            candidateCharacterGrowth: profile.growth,
                                            candidateLatentPolicy: wrongLatentPolicy,
                                            candidatePartyWorkPolicyR144: policy))
    }

    func testR144RejectsCadenceOverridesAndUsesAuthoredRegionInterval() async throws {
        let harness = try makeHarness()
        let before = await harness.engine.snapshot()
        do {
            _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(1), secondsPerUnit: 1,
                                                       operationID: UUID(), expectedRevision: before.revision)
            XCTFail("candidate callers cannot shorten the catalog work cadence")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterRejectedOverride = await harness.engine.snapshot()
        XCTAssertEqual(afterRejectedOverride, before)

        let region = try XCTUnwrap(harness.profile.catalog.regions.first(where: { $0.id == regionID }))
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(TimeInterval(region.workSeconds)),
                                                   operationID: UUID(), expectedRevision: before.revision)
        let afterAuthoredInterval = await harness.engine.snapshot()
        XCTAssertEqual(afterAuthoredInterval.materials[gatherG1, default: 0], before.materials[gatherG1, default: 0] + 1)
    }

    func testDefaultRepeatRewardsRemainUnchangedAndPolicyFingerprintPreventsCrossModeReplay() async throws {
        let base = try makeHarness(policyEnabled: false)
        let command = GameCommand.startExpeditionAt(regionID: regionID, now: epoch)
        let operationID = UUID()
        _ = try await send(base.engine, command, id: operationID)
        let policy = try PartyWorkPolicyR144()
        let candidate = try GameEngine(catalog: base.profile.catalog, saves: base.store,
                                       candidateCombatOverlay: base.profile.combatOverlay,
                                       candidateCharacterGrowth: base.profile.growth,
                                       candidateLatentPolicy: base.profile.latentPolicy,
                                       candidatePartyWorkPolicyR144: policy)
        do {
            _ = try await candidate.dispatch(command, operationID: operationID, expectedRevision: 0)
            XCTFail("same operation ID must not replay across different runtime policy fingerprints")
        } catch let error as CoreError {
            XCTAssertEqual(error, .duplicateOperation)
        }

        let state = await base.engine.snapshot()
        let seed = try await winningSeed(base.engine, enemyID: enemyE2)
        _ = try await base.engine.dispatch(.resolveEncounter(enemyID: enemyE2, seed: seed),
                                           operationID: UUID(), expectedRevision: state.revision)
        var after = await base.engine.snapshot()
        let materialAfterFirst = after.materials["M_R01_E2", default: 0]
        let coinsAfterFirst = after.currency["coin", default: 0]
        let replayState = after
        _ = try await base.engine.dispatch(.resolveEncounter(enemyID: enemyE2, seed: seed),
                                           operationID: UUID(), expectedRevision: after.revision)
        after = await base.engine.snapshot()
        XCTAssertEqual(after.materials["M_R01_E2", default: 0], materialAfterFirst + 1)
        XCTAssertEqual(after.currency["coin", default: 0], coinsAfterFirst + 2)
        XCTAssertTrue(after.completedEncounterIDs.contains(enemyE2))
        XCTAssertNotEqual(after.revision, replayState.revision)
    }

    func testLegacySaveWithoutTypedTargetContinuesOnlyItsGatherTarget() async throws {
        let url = testURL()
        let legacy = try makeHarness(policyEnabled: false, fileURL: url)
        let oldClaim = try await legacy.engine.claimOffline(now: epoch.addingTimeInterval(300), secondsPerUnit: 300,
                                                              operationID: UUID(), expectedRevision: 0)
        XCTAssertTrue(oldClaim.result.contains("offline units=1; material=M_R01_G1"), "legacy receipt keeps its existing wording")
        let legacyState = await legacy.engine.snapshot()
        XCTAssertNil(legacyState.partyWorkTargetR144)
        XCTAssertEqual(legacyState.materials[gatherG1, default: 0], 1)

        let candidateStore = try SaveRepository(fileURL: url)
        let policy = try PartyWorkPolicyR144(baseProfileID: legacy.profile.profileID,
                                             baseConfigurationFingerprint: legacy.profile.configurationFingerprint)
        let candidate = try GameEngine(catalog: legacy.profile.catalog, saves: candidateStore,
                                       candidateCombatOverlay: legacy.profile.combatOverlay,
                                       candidateCharacterGrowth: legacy.profile.growth,
                                       candidateLatentPolicy: legacy.profile.latentPolicy,
                                       candidatePartyWorkPolicyR144: policy)
        _ = try await candidate.claimOffline(now: epoch.addingTimeInterval(600), secondsPerUnit: 300,
                                              operationID: UUID(), expectedRevision: legacyState.revision)
        let candidateState = await candidate.snapshot()
        XCTAssertEqual(candidateState.partyWorkTargetR144, .gather(gatherG1),
                       "the first candidate mutation records the validated legacy gather target explicitly")
        XCTAssertEqual(candidateState.materials[gatherG1, default: 0], 2)
        XCTAssertEqual(candidateState.completedEncounterIDs, legacyState.completedEncounterIDs)
    }

    func testCandidatePaysRealFirstClearOnceAndRealRepeatBattleZeroImmediateRewards() async throws {
        let harness = try makeHarness()
        _ = try await send(harness.engine, .startExpeditionAt(regionID: regionID, now: epoch))
        let seed = try await winningSeed(harness.engine, enemyID: enemyE2)
        let before = await harness.engine.snapshot()
        let firstID = UUID()
        let command = GameCommand.resolveEncounter(enemyID: enemyE2, seed: seed)
        let first = try await harness.engine.dispatch(command, operationID: firstID, expectedRevision: before.revision)
        let firstState = await harness.engine.snapshot()
        XCTAssertTrue(firstState.lastCombatResult?.won == true)
        XCTAssertEqual(firstState.materials["M_R01_E2", default: 0] - before.materials["M_R01_E2", default: 0], 1)
        XCTAssertEqual(firstState.currency["coin", default: 0] - before.currency["coin", default: 0], 2)

        let idempotent = try await harness.engine.dispatch(command, operationID: firstID, expectedRevision: before.revision)
        XCTAssertEqual(idempotent, first)
        let afterReplay = await harness.engine.snapshot()
        XCTAssertEqual(afterReplay, firstState)

        let repeatReceipt = try await send(harness.engine, command)
        let repeated = await harness.engine.snapshot()
        XCTAssertTrue(repeatReceipt.result.contains("repeat battle"))
        XCTAssertTrue(repeated.lastCombatResult?.won == true, "repeat is still an actual R6 combat resolution")
        XCTAssertEqual(repeated.lastEncounterID, enemyE2)
        XCTAssertEqual(repeated.completedEncounterIDs, firstState.completedEncounterIDs)
        XCTAssertEqual(repeated.materials, firstState.materials)
        XCTAssertEqual(repeated.currency, firstState.currency)
        do {
            _ = try await harness.engine.dispatch(.resolveEncounter(enemyID: enemyE2, seed: seed + 1),
                                                  operationID: firstID, expectedRevision: firstState.revision)
            XCTFail("same operation ID with different seed must fail")
        } catch let error as CoreError {
            XCTAssertEqual(error, .duplicateOperation)
        }
    }

    func testFirstCandidateEncounterOnLegacySavePersistsGatherMarkerInCombatTransaction() async throws {
        let legacy = try makeHarness(policyEnabled: false)
        let before = await legacy.engine.snapshot()
        XCTAssertNil(before.partyWorkTargetR144)
        let policy = try PartyWorkPolicyR144(baseProfileID: legacy.profile.profileID,
                                             baseConfigurationFingerprint: legacy.profile.configurationFingerprint)
        let candidate = try GameEngine(catalog: legacy.profile.catalog, saves: legacy.store,
                                       candidateCombatOverlay: legacy.profile.combatOverlay,
                                       candidateCharacterGrowth: legacy.profile.growth,
                                       candidateLatentPolicy: legacy.profile.latentPolicy,
                                       candidatePartyWorkPolicyR144: policy)
        let seed = try await winningSeed(candidate, enemyID: enemyE2)
        _ = try await candidate.dispatch(.resolveEncounter(enemyID: enemyE2, seed: seed),
                                         operationID: UUID(), expectedRevision: before.revision)
        let after = await candidate.snapshot()
        XCTAssertEqual(after.partyWorkTargetR144, .gather(gatherG1))
        XCTAssertNotEqual(after.revision, before.revision)
        XCTAssertNotNil(after.lastCombatResult)
    }

    func testLegacySaveMarkerAndWorkSettlementShareAtomicWrite() async throws {
        let url = testURL()
        let legacy = try makeHarness(policyEnabled: false, fileURL: url)
        _ = try await send(legacy.engine, .startExpeditionAt(regionID: regionID, now: epoch))
        let priorBytes = try Data(contentsOf: url)
        let legacyState = await legacy.engine.snapshot()
        let faultingStore = try SaveRepository(fileURL: url, faultInjector: { phase in
            if phase == .beforeStage { throw SaveRepositoryError.injectedWriteFailure("R144 marker atomicity") }
        })
        let policy = try PartyWorkPolicyR144(baseProfileID: legacy.profile.profileID,
                                             baseConfigurationFingerprint: legacy.profile.configurationFingerprint)
        let candidate = try GameEngine(catalog: legacy.profile.catalog, saves: faultingStore,
                                       candidateCombatOverlay: legacy.profile.combatOverlay,
                                       candidateCharacterGrowth: legacy.profile.growth,
                                       candidateLatentPolicy: legacy.profile.latentPolicy,
                                       candidatePartyWorkPolicyR144: policy)
        do {
            _ = try await candidate.claimOffline(now: epoch.addingTimeInterval(300), operationID: UUID(),
                                                  expectedRevision: legacyState.revision)
            XCTFail("injected atomic-write fault must reject the marker and work settlement together")
        } catch let error as SaveRepositoryError {
            XCTAssertEqual(error, .injectedWriteFailure("R144 marker atomicity"))
        }
        XCTAssertEqual(try Data(contentsOf: url), priorBytes)
        let reopened = try SaveRepository(fileURL: url)
        let reopenedState = await reopened.snapshot()
        XCTAssertEqual(reopenedState, legacyState)
        XCTAssertNil(reopenedState.partyWorkTargetR144)
    }

    func testRepeatBossVictoryReappliesIdempotentNextRegionUnlockWithoutRewards() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let boss = try XCTUnwrap(profile.catalog.enemies.first {
            $0.regionID == regionID && $0.id.hasSuffix("_B")
        })
        let regionIndex = try XCTUnwrap(profile.catalog.regions.firstIndex(where: { $0.id == regionID }))
        let nextRegion = try XCTUnwrap(profile.catalog.regions.indices.contains(regionIndex + 1)
                                       ? profile.catalog.regions[regionIndex + 1] : nil)
        var initial = try profile.makeNewSnapshot()
        initial.unlockedRegionIDs.insert(regionID)
        initial.unlockedRegionIDs.remove(nextRegion.id)
        initial.activeRegionID = regionID
        initial.gatherTargetMaterialID = gatherG1
        initial.lastClaimAt = epoch
        initial.completedEncounterIDs.insert(boss.id) // Repeated-victory state; no first-clear reward claim.
        if let prerequisite = boss.prerequisiteEncounterID { initial.completedEncounterIDs.insert(prerequisite) }
        let harness = try makeHarness(initial: initial)
        _ = try await harness.engine.dispatch(.startExpeditionAt(regionID: regionID, now: epoch),
                                              operationID: UUID(), expectedRevision: initial.revision)
        let ready = await harness.engine.snapshot()
        let materialID = boss.dropMaterialID
        let beforeMaterial = materialID.map { ready.materials[$0, default: 0] } ?? 0
        let beforeCoins = ready.currency["coin", default: 0]
        let seed = try await winningSeed(harness.engine, enemyID: boss.id)
        let receipt = try await harness.engine.dispatch(.resolveEncounter(enemyID: boss.id, seed: seed),
                                                        operationID: UUID(), expectedRevision: ready.revision)
        let after = await harness.engine.snapshot()
        XCTAssertTrue(after.lastCombatResult?.won == true)
        XCTAssertTrue(receipt.result.contains("repeat battle"))
        XCTAssertTrue(after.unlockedRegionIDs.contains(nextRegion.id), "a victory restores the idempotent next-region unlock")
        XCTAssertEqual(after.currency["coin", default: 0], beforeCoins)
        if let materialID {
            XCTAssertEqual(after.materials[materialID, default: 0], beforeMaterial,
                           "repeat victory still grants no immediate material")
        }
    }

    func testLegacyRepeatBossVictoryStillReappliesNextRegionUnlock() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let boss = try XCTUnwrap(profile.catalog.enemies.first {
            $0.regionID == regionID && $0.id.hasSuffix("_B")
        })
        let regionIndex = try XCTUnwrap(profile.catalog.regions.firstIndex(where: { $0.id == regionID }))
        let nextRegion = try XCTUnwrap(profile.catalog.regions.indices.contains(regionIndex + 1)
                                       ? profile.catalog.regions[regionIndex + 1] : nil)
        var initial = try profile.makeNewSnapshot()
        initial.unlockedRegionIDs.insert(regionID)
        initial.unlockedRegionIDs.remove(nextRegion.id)
        initial.activeRegionID = regionID
        initial.gatherTargetMaterialID = gatherG1
        initial.lastClaimAt = epoch
        initial.completedEncounterIDs.insert(boss.id)
        if let prerequisite = boss.prerequisiteEncounterID { initial.completedEncounterIDs.insert(prerequisite) }
        let legacy = try makeHarness(policyEnabled: false, initial: initial)
        _ = try await legacy.engine.dispatch(.startExpeditionAt(regionID: regionID, now: epoch),
                                             operationID: UUID(), expectedRevision: initial.revision)
        let ready = await legacy.engine.snapshot()
        let seed = try await winningSeed(legacy.engine, enemyID: boss.id)
        _ = try await legacy.engine.dispatch(.resolveEncounter(enemyID: boss.id, seed: seed),
                                             operationID: UUID(), expectedRevision: ready.revision)
        let after = await legacy.engine.snapshot()
        XCTAssertTrue(after.lastCombatResult?.won == true)
        XCTAssertTrue(after.completedEncounterIDs.contains(boss.id))
        XCTAssertTrue(after.unlockedRegionIDs.contains(nextRegion.id),
                      "legacy successful repeat boss victory must preserve the frozen unconditional unlock behavior")
    }

    func testGatherToInvestigationSwitchSettlesOldTargetAndDropsFractionalCarry() async throws {
        let harness = try makeHarness()
        _ = try await clearE2(harness.engine)
        let before = await harness.engine.snapshot()
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(150), secondsPerUnit: 300,
                                                   operationID: UUID(), expectedRevision: before.revision)
        let halfGather = await harness.engine.snapshot()
        XCTAssertEqual(halfGather.offlineRemainderSeconds, 150)

        let switchReceipt = try await harness.engine.setPartyWorkTargetR144(.investigate(enemyE2),
                                                                            now: epoch.addingTimeInterval(450),
                                                                            operationID: UUID(),
                                                                            expectedRevision: halfGather.revision)
        XCTAssertTrue(switchReceipt.result.contains("investigate"))
        let switched = await harness.engine.snapshot()
        XCTAssertEqual(switched.materials[gatherG1, default: 0] - halfGather.materials[gatherG1, default: 0], 1)
        XCTAssertEqual(switched.offlineRemainderSeconds, 0, "old gather fraction must not transfer")
        XCTAssertEqual(switched.partyWorkTargetR144, PartyWorkTargetR144.investigate(enemyE2))

        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(600), secondsPerUnit: 300,
                                                   operationID: UUID(), expectedRevision: switched.revision)
        let halfInvestigation = await harness.engine.snapshot()
        XCTAssertEqual(halfInvestigation.materials["M_R01_E2", default: 0], switched.materials["M_R01_E2", default: 0])
        XCTAssertEqual(halfInvestigation.offlineRemainderSeconds, 150)
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(750), secondsPerUnit: 300,
                                                   operationID: UUID(), expectedRevision: halfInvestigation.revision)
        let fullInvestigation = await harness.engine.snapshot()
        XCTAssertEqual(fullInvestigation.materials["M_R01_E2", default: 0] - switched.materials["M_R01_E2", default: 0], 1)
        XCTAssertEqual(fullInvestigation.offlineRemainderSeconds, 0)
    }

    func testRegionSwitchSettlesOldRegionBeforeSelectingNewGatherTarget() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let nextRegion = try XCTUnwrap(profile.catalog.regions.first(where: { $0.id != regionID }))
        var initial = try profile.makeNewSnapshot()
        initial.unlockedRegionIDs.insert(regionID)
        initial.unlockedRegionIDs.insert(nextRegion.id) // Selector-boundary fixture only; no unlock/reward claim.
        initial.completedEncounterIDs.formUnion(profile.catalog.enemies.filter { $0.boss }.map(\.id))
        initial.activeRegionID = regionID
        initial.gatherTargetMaterialID = gatherG1
        initial.lastClaimAt = epoch
        let nextMaterials = profile.catalog.availableGatherMaterialIDs(
            in: nextRegion.id, unlockedRegionIDs: initial.unlockedRegionIDs,
            completedEncounterIDs: initial.completedEncounterIDs)
        let nextMaterial = try XCTUnwrap(nextMaterials.first)
        let harness = try makeHarness(initial: initial)
        _ = try await harness.engine.dispatch(.startExpeditionAt(regionID: nextRegion.id,
                                                                  now: epoch.addingTimeInterval(450)),
                                              operationID: UUID(), expectedRevision: 0)
        let switched = await harness.engine.snapshot()
        XCTAssertEqual(switched.materials[gatherG1, default: 0] - initial.materials[gatherG1, default: 0], 1,
                       "elapsed time must settle under the old R01 target before region changes")
        XCTAssertEqual(switched.activeRegionID, nextRegion.id)
        XCTAssertEqual(switched.partyWorkTargetR144, .gather(nextMaterial))
        XCTAssertEqual(switched.offlineRemainderSeconds, 0, "fraction cannot cross a region boundary")
        let nextInterval = TimeInterval(max(1, nextRegion.workSeconds))
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(450 + nextInterval / 2),
                                                   operationID: UUID(), expectedRevision: switched.revision)
        let halfNewRegion = await harness.engine.snapshot()
        XCTAssertEqual(halfNewRegion.materials[nextMaterial, default: 0], initial.materials[nextMaterial, default: 0])
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(450 + nextInterval),
                                                   operationID: UUID(), expectedRevision: halfNewRegion.revision)
        let afterNewRegionUnit = await harness.engine.snapshot()
        XCTAssertEqual(afterNewRegionUnit.materials[nextMaterial, default: 0],
                       initial.materials[nextMaterial, default: 0] + 1)
    }

    func testSameTargetValidatesEveryTimestampAndSameTimeCannotDoublePay() async throws {
        let harness = try makeHarness()
        let initial = await harness.engine.snapshot()
        for command in [
            GameCommand.startExpeditionAt(regionID: regionID, now: epoch.addingTimeInterval(-1)),
            GameCommand.setGatherTargetAt(resourceID: gatherG1, now: epoch.addingTimeInterval(-1))
        ] {
            do {
                _ = try await harness.engine.dispatch(command, operationID: UUID(),
                                                      expectedRevision: initial.revision)
                XCTFail("same-target selector must reject a backward timestamp")
            } catch let error as CoreError {
                guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
            }
        }
        let afterRejectedSelectorTimes = await harness.engine.snapshot()
        XCTAssertEqual(afterRejectedSelectorTimes, initial)
        do {
            _ = try await harness.engine.setPartyWorkTargetR144(.gather(gatherG1),
                                                                 now: epoch.addingTimeInterval(-1),
                                                                 operationID: UUID(), expectedRevision: initial.revision)
            XCTFail("same target must still reject a backward timestamp")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterRejectedBackwards = await harness.engine.snapshot()
        XCTAssertEqual(afterRejectedBackwards, initial)

        let setID = UUID()
        let setReceipt = try await harness.engine.setPartyWorkTargetR144(.gather(gatherG1),
                                                                          now: epoch.addingTimeInterval(300),
                                                                          operationID: setID,
                                                                          expectedRevision: initial.revision)
        let afterSet = await harness.engine.snapshot()
        XCTAssertEqual(afterSet.materials[gatherG1, default: 0], initial.materials[gatherG1, default: 0] + 1,
                       "same-target selection settles earned work")
        let replayedSetReceipt = try await harness.engine.setPartyWorkTargetR144(.gather(gatherG1),
                                                                                  now: epoch.addingTimeInterval(300),
                                                                                  operationID: setID,
                                                                                  expectedRevision: initial.revision)
        XCTAssertEqual(replayedSetReceipt, setReceipt)
        do {
            _ = try await harness.engine.setPartyWorkTargetR144(.gather(gatherG1),
                                                                 now: epoch.addingTimeInterval(301),
                                                                 operationID: setID,
                                                                 expectedRevision: afterSet.revision)
            XCTFail("same operation ID with changed time must reject")
        } catch let error as CoreError {
            XCTAssertEqual(error, .duplicateOperation)
        }

        _ = try await clearE2(harness.engine)
        let afterBattle = await harness.engine.snapshot()
        do {
            _ = try await harness.engine.setPartyWorkTargetR144(.investigate(enemyE2),
                                                                 now: epoch.addingTimeInterval(301),
                                                                 operationID: setID,
                                                                 expectedRevision: afterBattle.revision)
            XCTFail("same operation ID with changed target must reject")
        } catch let error as CoreError {
            XCTAssertEqual(error, .duplicateOperation)
        }

        let claimID = UUID()
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(600), secondsPerUnit: 300,
                                                   operationID: claimID, expectedRevision: afterBattle.revision)
        let afterFirstClaim = await harness.engine.snapshot()
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(600), secondsPerUnit: 300,
                                                   operationID: UUID(), expectedRevision: afterFirstClaim.revision)
        let afterSecondClaim = await harness.engine.snapshot()
        XCTAssertEqual(afterSecondClaim.materials[gatherG1, default: 0],
                       afterFirstClaim.materials[gatherG1, default: 0],
                       "a new operation at the same timestamp cannot pay the same interval twice")
    }

    func testUnknownFutureMarkerOutsideR144TargetPathStillRejectsPrimary() async throws {
        let url = testURL()
        let harness = try makeHarness(fileURL: url)
        let before = await harness.engine.snapshot()
        _ = try await harness.engine.setPartyWorkTargetR144(.gather(gatherG1), now: epoch,
                                                             operationID: UUID(), expectedRevision: before.revision)
        let valid = try Data(contentsOf: url)
        try valid.write(to: url.appendingPathExtension("previous"), options: .atomic)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["unrelatedExtension"] = ["futureVersion": 2, "payload": "must remain fail-closed"]
        let malformed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try malformed.write(to: url, options: .atomic)
        do {
            _ = try SaveRepository(fileURL: url)
            XCTFail("the R144 exception must not whitelist future markers outside its exact path")
        } catch let error as SaveRepositoryError {
            guard case .unsupportedFutureVersionMarker(let path, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertFalse(path.contains("partyWorkTargetR144"))
        }
        XCTAssertEqual(try Data(contentsOf: url), malformed)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("previous")), valid)
    }

    func testInvestigationRejectsUndeclaredEnemyDropMaterial() throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let original = try XCTUnwrap(profile.catalog.enemies.first(where: { $0.id == enemyE2 }))
        let invalidEnemy = EnemyDefinition(id: original.id, name: original.name, regionID: original.regionID,
                                           hp: original.hp, attack: original.attack, defense: original.defense,
                                           boss: original.boss, dropMaterialID: "M_NOT_IN_CATALOG",
                                           prerequisiteEncounterID: original.prerequisiteEncounterID,
                                           actionPattern: original.actionPattern)
        XCTAssertThrowsError(try PartyWorkR144Validation.declaredDropMaterialID(for: invalidEnemy,
                                                                                catalog: profile.catalog))
    }

    func testInvestigationUsesOneLedgerPersistsAndNeverChangesCombatOrCoins() async throws {
        let url = testURL()
        let harness = try makeHarness(fileURL: url)
        _ = try await clearE2(harness.engine)
        var state = await harness.engine.snapshot()
        let earnedCombat = state.lastCombatResult
        let earnedEncounter = state.lastEncounterID
        let earnedClears = state.completedEncounterIDs
        let earnedUnlocks = state.unlockedRegionIDs
        let coins = state.currency["coin", default: 0]
        _ = try await harness.engine.setPartyWorkTargetR144(.investigate(enemyE2), now: epoch,
                                                             operationID: UUID(), expectedRevision: state.revision)
        state = await harness.engine.snapshot()
        let startMaterial = state.materials["M_R01_E2", default: 0]
        let startDust = state.materials["refine_dust", default: 0]
        let startXP = state.characterXP
        let claimID = UUID()
        let claimTime = epoch.addingTimeInterval(2 * 300)
        let receipt = try await harness.engine.claimOffline(now: claimTime, secondsPerUnit: 300,
                                                             operationID: claimID, expectedRevision: state.revision)
        let after = await harness.engine.snapshot()
        let region = try XCTUnwrap(harness.profile.catalog.regions.first(where: { $0.id == regionID }))
        XCTAssertEqual(after.materials["M_R01_E2", default: 0] - startMaterial, 2)
        XCTAssertEqual(after.materials["refine_dust", default: 0] - startDust, 2 * region.dustPerWork)
        for actor in after.partyActorIDs {
            XCTAssertEqual(after.characterXP[actor, default: 0] - startXP[actor, default: 0], 2 * region.xpPerWork)
        }
        XCTAssertEqual(after.currency["coin", default: 0], coins, "investigation explicitly grants no coins")
        XCTAssertEqual(after.lastCombatResult, earnedCombat)
        XCTAssertEqual(after.lastEncounterID, earnedEncounter)
        XCTAssertEqual(after.completedEncounterIDs, earnedClears)
        XCTAssertEqual(after.unlockedRegionIDs, earnedUnlocks)

        let duplicate = try await harness.engine.claimOffline(now: claimTime, secondsPerUnit: 300,
                                                               operationID: claimID, expectedRevision: state.revision)
        XCTAssertEqual(duplicate, receipt)
        let afterDuplicate = await harness.engine.snapshot()
        XCTAssertEqual(afterDuplicate, after)
        let reopened = try SaveRepository(fileURL: url)
        let reopenedState = await reopened.snapshot()
        XCTAssertEqual(reopenedState, after)
        let reopenedReceipt = await reopened.receipt(for: claimID)
        XCTAssertEqual(reopenedReceipt, receipt)
    }

    func testInvalidTargetsBackwardClockAndUnknownPersistedKindFailClosed() async throws {
        let url = testURL()
        let harness = try makeHarness(fileURL: url)
        var state = await harness.engine.snapshot()
        do {
            _ = try await harness.engine.setPartyWorkTargetR144(.investigate(enemyE2), now: epoch,
                                                                  operationID: UUID(), expectedRevision: state.revision)
            XCTFail("uncleared enemy cannot be investigated")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterUnclearedReject = await harness.engine.snapshot()
        XCTAssertEqual(afterUnclearedReject, state)

        do {
            _ = try await harness.engine.setPartyWorkTargetR144(.gather("M_UNKNOWN"), now: epoch,
                                                                  operationID: UUID(), expectedRevision: state.revision)
            XCTFail("unknown material cannot be selected")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterUnknownTarget = await harness.engine.snapshot()
        XCTAssertEqual(afterUnknownTarget, state)

        do {
            _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(-1), secondsPerUnit: 300,
                                                       operationID: UUID(), expectedRevision: state.revision)
            XCTFail("backward clock must reject atomically")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterBackwardsClock = await harness.engine.snapshot()
        XCTAssertEqual(afterBackwardsClock, state)

        _ = try await harness.engine.setPartyWorkTargetR144(.gather(gatherG1), now: epoch,
                                                             operationID: UUID(), expectedRevision: state.revision)
        let valid = try Data(contentsOf: url)
        let previousURL = url.appendingPathExtension("previous")
        try valid.write(to: previousURL, options: .atomic)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        var target = try XCTUnwrap(snapshot["partyWorkTargetR144"] as? [String: Any])
        target["kind"] = "unknown-work"
        snapshot["partyWorkTargetR144"] = target
        object["snapshot"] = snapshot
        let malformedPrimary = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try malformedPrimary.write(to: url, options: .atomic)
        do {
            _ = try SaveRepository(fileURL: url)
            XCTFail("unknown discriminator must refuse the primary without recovery")
        } catch let error as SaveRepositoryError {
            guard case .unsupportedFutureVersionMarker = error else { return XCTFail("unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: url), malformedPrimary)
        XCTAssertEqual(try Data(contentsOf: previousURL), valid)
        XCTAssertTrue(oldR140PreflightRefusesCandidateTarget(valid), "R140 raw futureVersion preflight must reject candidate-target saves")

        state = await harness.engine.snapshot()
        XCTAssertEqual(state.partyWorkTargetR144, PartyWorkTargetR144.gather(gatherG1))
    }

    func testFortyEightHourCapReopenAndDefaultReaderRefusesCandidateTarget() async throws {
        let url = testURL()
        let harness = try makeHarness(fileURL: url)
        var before = await harness.engine.snapshot()
        _ = try await harness.engine.setPartyWorkTargetR144(.gather(gatherG1), now: epoch,
                                                             operationID: UUID(), expectedRevision: before.revision)
        before = await harness.engine.snapshot()
        let firstID = UUID()
        let firstReceipt = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(72 * 3600),
                                                                   secondsPerUnit: 300, cap: 72 * 3600,
                                                                   operationID: firstID, expectedRevision: before.revision)
        let after = await harness.engine.snapshot()
        XCTAssertEqual(after.materials[gatherG1, default: 0] - before.materials[gatherG1, default: 0], 576,
                       "caller cap cannot exceed shared 48-hour candidate cap")
        XCTAssertEqual(after.offlineRemainderSeconds, 0)
        let duplicate = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(72 * 3600),
                                                               secondsPerUnit: 300, cap: 72 * 3600,
                                                               operationID: firstID, expectedRevision: before.revision)
        XCTAssertEqual(duplicate, firstReceipt)
        let afterReplay = await harness.engine.snapshot()
        XCTAssertEqual(afterReplay, after)

        let reloaded = try SaveRepository(fileURL: url)
        let reloadedState = await reloaded.snapshot()
        XCTAssertEqual(reloadedState, after)
        before = await reloaded.snapshot()
        let defaultEngine = try GameEngine(catalog: harness.profile.catalog, saves: reloaded,
                                           candidateCombatOverlay: harness.profile.combatOverlay,
                                           candidateCharacterGrowth: harness.profile.growth,
                                           candidateLatentPolicy: harness.profile.latentPolicy)
        do {
            _ = try await defaultEngine.claimOffline(now: epoch.addingTimeInterval(73 * 3600), secondsPerUnit: 300,
                                                      operationID: UUID(), expectedRevision: before.revision)
            XCTFail("default reader must not reinterpret R144 target as legacy gather")
        } catch let error as CoreError {
            XCTAssertEqual(error, .invalidCommand("R144 candidate save requires the matching opt-in policy"))
        }
        do {
            _ = try await defaultEngine.dispatch(.resolveEncounter(enemyID: enemyE2, seed: 1),
                                                  operationID: UUID(), expectedRevision: before.revision)
            XCTFail("default engine must refuse encounter dispatch from candidate-target save")
        } catch let error as CoreError {
            XCTAssertEqual(error, .invalidCommand("R144 candidate save requires the matching opt-in policy"))
        }
        let unchangedAfterDefaultRefusal = await reloaded.snapshot()
        XCTAssertEqual(unchangedAfterDefaultRefusal, before)
    }

    func testNumericOverflowRejectsWithoutChangingSnapshot() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        var initial = try profile.makeNewSnapshot()
        initial.unlockedRegionIDs.insert(regionID)
        initial.activeRegionID = regionID
        initial.gatherTargetMaterialID = gatherG1
        initial.materials[gatherG1] = Int.max
        initial.lastClaimAt = epoch
        let harness = try makeHarness(initial: initial)
        let before = await harness.engine.snapshot()
        do {
            _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(300), secondsPerUnit: 300,
                                                       operationID: UUID(), expectedRevision: before.revision)
            XCTFail("material addition overflow must reject the full transaction")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let after = await harness.engine.snapshot()
        XCTAssertEqual(after, before)
    }

    func testEarnedFirstE2PlusWorkMakesFamiliarRecipeButNotStaffG2Recipe() async throws {
        let harness = try makeHarness()
        let initial = await harness.engine.snapshot()
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(6 * 300), secondsPerUnit: 300,
                                                   operationID: UUID(), expectedRevision: initial.revision)
        let gathered = await harness.engine.snapshot()
        XCTAssertEqual(gathered.materials[gatherG1, default: 0], 6)
        let e2ClearSeed = try await winningSeed(harness.engine, enemyID: enemyE2)
        _ = try await harness.engine.dispatch(.resolveEncounter(enemyID: enemyE2, seed: e2ClearSeed),
                                              operationID: UUID(), expectedRevision: gathered.revision)
        var state = await harness.engine.snapshot()
        XCTAssertTrue(state.completedEncounterIDs.contains(enemyE2), "unlock comes from the actual simulated victory")
        XCTAssertEqual(state.materials["M_R01_E2", default: 0], 1, "actual first clear earns the first E2")
        _ = try await harness.engine.setPartyWorkTargetR144(.investigate(enemyE2),
                                                             now: epoch.addingTimeInterval(6 * 300),
                                                             operationID: UUID(), expectedRevision: state.revision)
        state = await harness.engine.snapshot()
        _ = try await harness.engine.claimOffline(now: epoch.addingTimeInterval(11 * 300), secondsPerUnit: 300,
                                                   operationID: UUID(), expectedRevision: state.revision)
        state = await harness.engine.snapshot()
        XCTAssertEqual(state.materials["M_R01_E2", default: 0], 6)
        XCTAssertEqual(state.materials[gatherG1, default: 0], 6)

        let familiar = try XCTUnwrap(harness.profile.catalog.recipes.first(where: { $0.id == "RC_EQ_F_01" }))
        XCTAssertTrue(familiar.costs.allSatisfy { state.materials[$0.key, default: 0] >= $0.value })
        _ = try await send(harness.engine, .craftRecipe("RC_EQ_F_01"))
        state = await harness.engine.snapshot()
        if let outputID = familiar.outputGearID {
            XCTAssertTrue(state.gear.contains(where: { $0.definitionID == outputID }))
        } else {
            XCTFail("R098 familiar recipe must declare its output template")
        }

        let staff = try XCTUnwrap(harness.profile.catalog.recipes.first(where: { $0.id == "RC_EQ_W_01" }))
        XCTAssertEqual(staff.costs["M_R01_G2"], 6)
        XCTAssertFalse(staff.costs.allSatisfy { state.materials[$0.key, default: 0] >= $0.value },
                       "this actual first-clear plus investigation route does not synthesize staff G2")
        let beforeFailedCraft = state
        do {
            _ = try await send(harness.engine, .craftRecipe("RC_EQ_W_01"))
            XCTFail("staff recipe remains unaffordable without its required G2")
        } catch let error as CoreError {
            guard case .insufficientResource = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterFailedCraft = await harness.engine.snapshot()
        XCTAssertEqual(afterFailedCraft, beforeFailedCraft)
    }

    private func oldR140PreflightRefusesCandidateTarget(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        func walk(_ value: Any) -> Bool {
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if key == "futureVersion", let number = child as? NSNumber, number.intValue > 1 { return true }
                    if walk(child) { return true }
                }
            } else if let array = value as? [Any] {
                return array.contains(where: walk)
            }
            return false
        }
        return walk(root)
    }
}
