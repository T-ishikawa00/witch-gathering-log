import XCTest
@testable import WitchGameCore

/// Isolated integration checks for the candidate save -> GameEngine projector ->
/// actual encounter/challenge dispatch path. Catalog, enemies and challenge are
/// bundled synthetic/test-overlay content; this is not a live-save or balance claim.
final class CandidateLatentLiveIntegrationR032Tests: XCTestCase {
    private let seed: UInt64 = 30_032
    private var catalog: GameCatalog!
    private var policy: CandidateLatentSlotPolicyR003!

    override func setUpWithError() throws {
        catalog = try GameCatalog.bundledTestOverlay()
        policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
    }

    func testEncounterDispatchMatchesSameProjectedTimelineAndReplayIsAtomic() async throws {
        let initial = try candidateSnapshot()
        let gear = try XCTUnwrap(initial.gear.first(where: { $0.definitionID == "EQ_W_01" }))
        let slots = try XCTUnwrap(gear.candidateLatentSlots)
        let typedParty = try projectedParty(initial)
        let enemy = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "E_R01_01" }))
        let expected = try R6TimelineSimulator.run(
            party: typedParty,
            enemies: [Combatant(id: enemy.id, maxHP: enemy.hp, attack: enemy.attack,
                                defense: enemy.defense, actionPattern: enemy.actionPattern ?? "standard")],
            seed: seed,
            entityPresentation: [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy",
                catalogID: enemy.id, label: enemy.name, assetKey: enemy.id)])
        let strippedParty = typedParty.map { actor in
            var copy = actor
            copy.candidateLatentModifiersR004 = nil
            return copy
        }
        XCTAssertEqual(statsSignature(typedParty), statsSignature(strippedParty),
                       "the control removes only the typed modifier field; projected base stats stay fixed")
        let statsMatchedWithoutPayload = try R6TimelineSimulator.run(
            party: strippedParty,
            enemies: [Combatant(id: enemy.id, maxHP: enemy.hp, attack: enemy.attack,
                                defense: enemy.defense, actionPattern: enemy.actionPattern ?? "standard")],
            seed: seed,
            entityPresentation: [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy",
                catalogID: enemy.id, label: enemy.name, assetKey: enemy.id)])
        XCTAssertNotEqual(expected.events, statsMatchedWithoutPayload.events,
                          "same projected base stats with the typed field removed must exercise the latent timeline path")
        let typedHit = try XCTUnwrap(expected.events.first { $0.kind == "direct" && $0.sourceID == "C_WITCH" })
        let plainHit = try XCTUnwrap(statsMatchedWithoutPayload.events.first { $0.kind == "direct" && $0.sourceID == "C_WITCH" })
        XCTAssertGreaterThan(typedHit.amount, plainHit.amount)

        let saveURL = temporarySaveURL("encounter")
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try GameEngine(catalog: catalog, saves: store, candidateLatentPolicy: policy)
        let operationID = UUID(uuidString: "32000000-0000-4000-8000-000000000001")!
        let receipt = try await engine.dispatch(.resolveEncounter(enemyID: enemy.id, seed: seed),
                                                operationID: operationID, expectedRevision: initial.revision)
        let after = await engine.snapshot()
        XCTAssertEqual(after.lastCombatResult, expected, "dispatch must use the same candidate projection and seed as direct Timeline execution")
        XCTAssertTrue(receipt.result.hasPrefix("VICTORY:") || receipt.result.hasPrefix("DEFEAT:"))
        XCTAssertEqual(receipt.revision, initial.revision + 1)
        let savedGear = try XCTUnwrap(after.gear.first(where: { $0.id == gear.id }))
        XCTAssertEqual(savedGear.id, gear.id)
        XCTAssertEqual(savedGear.candidateLatentSlots, slots, "rawQ payload and gear UUID survive actual battle persistence")

        let bytesBeforeReplay = try Data(contentsOf: saveURL)
        let snapshotBeforeReplay = after
        let replay = try await engine.dispatch(.resolveEncounter(enemyID: enemy.id, seed: seed),
                                               operationID: operationID, expectedRevision: initial.revision)
        XCTAssertEqual(replay, receipt)
        let afterReplay = await engine.snapshot()
        XCTAssertEqual(afterReplay, snapshotBeforeReplay)
        XCTAssertEqual(try Data(contentsOf: saveURL), bytesBeforeReplay,
                       "same operation replay must not write a second revision or reward")

        let reopened = try SaveRepository(fileURL: saveURL)
        let reread = await reopened.snapshot()
        XCTAssertEqual(reread, snapshotBeforeReplay)
        XCTAssertEqual(try XCTUnwrap(reread.gear.first(where: { $0.id == gear.id })).candidateLatentSlots, slots)
    }

    func testChallengeDispatchMatchesSameProjectedTimelineAndPreservesPayload() async throws {
        var initial = try candidateSnapshot()
        let challenge = try XCTUnwrap(catalog.challenges.first(where: { $0.id == "CH_R01_01" }))
        let gateParts = challenge.unlockGate.split(separator: "_")
        initial.completedEncounterIDs.insert("B_\(gateParts[1])_\(gateParts[2])")
        let typedParty = try projectedParty(initial)
        let scenario = try catalog.challengeCombatScenario(challenge.id)
        let expected = try R6TimelineSimulator.run(party: typedParty, enemies: scenario.enemies,
                                                   seed: seed + 1, challengeID: challenge.id,
                                                   entityPresentation: scenario.entityPresentation)
        let strippedParty = typedParty.map { actor in var copy = actor; copy.candidateLatentModifiersR004 = nil; return copy }
        XCTAssertEqual(statsSignature(typedParty), statsSignature(strippedParty))
        let statsMatchedWithoutPayload = try R6TimelineSimulator.run(
            party: strippedParty,
            enemies: scenario.enemies, seed: seed + 1, challengeID: challenge.id,
            entityPresentation: scenario.entityPresentation)
        XCTAssertNotEqual(expected.events, statsMatchedWithoutPayload.events)
        let typedHit = try XCTUnwrap(expected.events.first { $0.kind == "direct" && $0.sourceID == "C_WITCH" })
        let plainHit = try XCTUnwrap(statsMatchedWithoutPayload.events.first { $0.kind == "direct" && $0.sourceID == "C_WITCH" })
        XCTAssertGreaterThan(typedHit.amount, plainHit.amount)

        let saveURL = temporarySaveURL("challenge")
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try GameEngine(catalog: catalog, saves: store, candidateLatentPolicy: policy)
        let operationID = UUID(uuidString: "32000000-0000-4000-8000-000000000002")!
        let receipt = try await engine.dispatch(.resolveChallenge(challengeID: challenge.id, seed: seed + 1),
                                                operationID: operationID, expectedRevision: initial.revision)
        let after = await engine.snapshot()
        XCTAssertEqual(after.lastCombatResult, expected,
                       "challenge dispatch must share the same candidate party projection and scenario")
        XCTAssertEqual(after.lastEncounterID, challenge.id)
        XCTAssertTrue(receipt.result.contains(challenge.id))
        let savedSlots = try XCTUnwrap(after.gear.first(where: { $0.definitionID == "EQ_W_01" })?.candidateLatentSlots)
        XCTAssertEqual(savedSlots, try XCTUnwrap(initial.gear.first(where: { $0.definitionID == "EQ_W_01" })?.candidateLatentSlots))

        let bytesBeforeReplay = try Data(contentsOf: saveURL)
        let dustBeforeReplay = after.materials["refine_dust", default: 0]
        let replay = try await engine.dispatch(.resolveChallenge(challengeID: challenge.id, seed: seed + 1),
                                               operationID: operationID, expectedRevision: initial.revision)
        XCTAssertEqual(replay, receipt)
        let afterReplay = await engine.snapshot()
        XCTAssertEqual(afterReplay, after)
        XCTAssertEqual(afterReplay.materials["refine_dust", default: 0], dustBeforeReplay)
        XCTAssertEqual(try Data(contentsOf: saveURL), bytesBeforeReplay)
        let reopened = try SaveRepository(fileURL: saveURL)
        let reopenedSnapshot = await reopened.snapshot()
        let reopenedReceipt = await reopened.receipt(for: operationID)
        XCTAssertEqual(reopenedSnapshot, after)
        XCTAssertEqual(reopenedReceipt, receipt,
                       "challenge operation receipt and result must survive save reload")
    }

    func testMixedLegacyAndVersionedSlotsSwapAndProjectQualityAndPercentExactlyOnce() async throws {
        var initial = try candidateSnapshot()
        guard let weaponIndex = initial.gear.firstIndex(where: { $0.definitionID == "EQ_W_01" }) else {
            throw CoreError.invalidCatalog("synthetic fixture is missing Witch starter weapon")
        }
        initial.gear[weaponIndex].enhancement = 10

        let legacyRingID = UUID(uuidString: "32000000-0000-4000-8000-000000000011")!
        let legacyRing = GearInstance(id: legacyRingID, definitionID: "EQ_RING_01", ownerID: "C_WITCH",
                                      enhancement: 10, latentEffectID: "LATENT_POWER_TEST",
                                      qualityID: "Q4", affixIDs: ["AFFIX_POWER_TEST"])
        let legacyAmuletID = UUID(uuidString: "32000000-0000-4000-8000-000000000012")!
        let legacyAmulet = GearInstance(id: legacyAmuletID, definitionID: "EQ_AMU_02", ownerID: "C_WITCH",
                                        enhancement: 10, latentEffectID: "LATENT_POWER_TEST",
                                        qualityID: "Q4", affixIDs: ["AFFIX_POWER_TEST"])
        let candidateAmuletID = UUID(uuidString: "32000000-0000-4000-8000-000000000013")!
        let candidateAmuletSlots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_POWER", rawQ: 1_000),
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 1_000),
            CandidateLatentSlotR003(affixID: "AF_CDR", rawQ: 1_000)
        ])
        let candidateAmulet = GearInstance(id: candidateAmuletID, definitionID: "EQ_AMU_01",
                                           candidateLatentSlots: candidateAmuletSlots, qualityID: "Q4")
        initial.gear += [legacyRing, legacyAmulet, candidateAmulet]
        initial.equippedGearIDs["C_WITCH|ring"] = legacyRingID
        initial.equippedGearIDs["C_WITCH|amulet"] = legacyAmuletID

        // Legacy nil-payload gear retains the historical Q4 multiplier and old
        // affix/latent aliases. The candidate weapon's Q4 remains an activation
        // threshold only for its stored slots; it does not quality-scale gear stats.
        let legacyQ4 = catalog.projectCombatant(for: "C_WITCH", with: [legacyRing])
        var legacyRingQ0 = legacyRing
        legacyRingQ0.qualityID = "Q0"
        let legacyQ0 = catalog.projectCombatant(for: "C_WITCH", with: [legacyRingQ0])
        XCTAssertGreaterThan(legacyQ4.attack, legacyQ0.attack,
                             "the mixed build must preserve legacy nil-item quality scaling")

        let weapon = initial.gear[weaponIndex]
        var candidateWeaponQ0 = weapon
        candidateWeaponQ0.qualityID = "Q0"
        let weaponQ4Projection = try catalog.projectCandidateCombatantR005(
            for: "C_WITCH", with: [weapon], candidateLatentPolicy: policy).combatant
        let weaponQ0Projection = try catalog.projectCandidateCombatantR005(
            for: "C_WITCH", with: [candidateWeaponQ0], candidateLatentPolicy: policy).combatant
        XCTAssertEqual(weaponQ4Projection.attack, weaponQ0Projection.attack,
                       "Q4 on versioned weapon slots must not multiply the candidate item's base gear attack")

        let saveURL = temporarySaveURL("mixed-slots")
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try GameEngine(catalog: catalog, saves: store, candidateLatentPolicy: policy)
        let equipID = UUID(uuidString: "32000000-0000-4000-8000-000000000014")!
        let equipReceipt = try await engine.dispatch(.equip(gearID: candidateAmuletID, actorID: "C_WITCH"),
                                                     operationID: equipID, expectedRevision: initial.revision)
        let afterEquip = await engine.snapshot()
        XCTAssertEqual(equipReceipt.revision, initial.revision + 1)
        XCTAssertEqual(afterEquip.equippedGearIDs["C_WITCH|amulet"], candidateAmuletID)
        XCTAssertNil(afterEquip.gear.first(where: { $0.id == legacyAmuletID })?.ownerID,
                     "equip replacement should release the previous nil-payload amulet")
        XCTAssertEqual(afterEquip.gear.first(where: { $0.id == legacyRingID })?.ownerID, "C_WITCH",
                       "legacy ring in a different slot remains equipped alongside versioned items")

        let typedParty = try projectedParty(afterEquip)
        let witch = try XCTUnwrap(typedParty.first(where: { $0.id == "C_WITCH" }))
        let candidateAggregate = try XCTUnwrap(witch.candidateLatentModifiersR004)
        let legacyBase = catalog.projectCombatant(for: "C_WITCH", with: [legacyRing])
        let weaponGearBase = catalog.gearAttackBonuses["EQ_W_01", default: 0] * 130 / 100
        let amuletGearBase = catalog.gearAttackBonuses["EQ_AMU_01", default: 0] * 100 / 100
        let preActorPercent = legacyBase.attack + weaponGearBase + amuletGearBase
        let expectedOnce = preActorPercent * (10_000 + candidateAggregate.powerPercentBP) / 10_000
        XCTAssertEqual(witch.attack, expectedOnce,
                       "candidate actor power percent is applied once after legacy and candidate slot projection")
        let twice = expectedOnce * (10_000 + candidateAggregate.powerPercentBP) / 10_000
        XCTAssertNotEqual(witch.attack, twice, "candidate actor percent must not be applied a second time")
        XCTAssertEqual(candidateAggregate.powerPercentBP, 600)

        let enemy = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "E_R01_01" }))
        let expected = try R6TimelineSimulator.run(party: typedParty,
            enemies: [Combatant(id: enemy.id, maxHP: enemy.hp, attack: enemy.attack,
                                defense: enemy.defense, actionPattern: enemy.actionPattern ?? "standard")],
            seed: seed + 4,
            entityPresentation: [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy",
                catalogID: enemy.id, label: enemy.name, assetKey: enemy.id)])
        let fightOperation = UUID(uuidString: "32000000-0000-4000-8000-000000000015")!
        _ = try await engine.dispatch(.resolveEncounter(enemyID: enemy.id, seed: seed + 4),
                                      operationID: fightOperation, expectedRevision: afterEquip.revision)
        let afterBattle = await engine.snapshot()
        XCTAssertEqual(afterBattle.lastCombatResult, expected)
        XCTAssertEqual(afterBattle.gear.first(where: { $0.id == legacyRingID })?.candidateLatentSlots, nil)
        XCTAssertEqual(afterBattle.gear.first(where: { $0.id == candidateAmuletID })?.candidateLatentSlots,
                       candidateAmuletSlots)

        let reopened = try SaveRepository(fileURL: saveURL)
        let reread = await reopened.snapshot()
        XCTAssertEqual(reread, afterBattle)
        XCTAssertEqual(reread.equippedGearIDs["C_WITCH|amulet"], candidateAmuletID)
        XCTAssertEqual(reread.equippedGearIDs["C_WITCH|ring"], legacyRingID)
        XCTAssertEqual(reread.gear.first(where: { $0.id == candidateAmuletID })?.candidateLatentSlots,
                       candidateAmuletSlots, "equipped versioned amulet keeps its exact UUID and rawQ payload")
    }

    func testPolicyEnabledAllLegacySaveUsesExactLegacyDispatch() async throws {
        let initial = GameSnapshot.newGame(catalog: catalog)
        XCTAssertTrue(initial.gear.allSatisfy { $0.candidateLatentSlots == nil })
        let legacyStore = try SaveRepository(initial: initial)
        let policyStore = try SaveRepository(initial: initial)
        let legacyEngine = try GameEngine(catalog: catalog, saves: legacyStore)
        let policyEngine = try GameEngine(catalog: catalog, saves: policyStore, candidateLatentPolicy: policy)
        let operation = UUID(uuidString: "32000000-0000-4000-8000-000000000003")!
        let lhs = try await legacyEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: seed + 2),
                                                  operationID: operation, expectedRevision: 0)
        let rhs = try await policyEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: seed + 2),
                                                  operationID: operation, expectedRevision: 0)
        XCTAssertEqual(lhs, rhs)
        let legacyAfter = await legacyEngine.snapshot()
        let policyAfter = await policyEngine.snapshot()
        XCTAssertEqual(legacyAfter, policyAfter,
                       "an enabled policy with an all-nil legacy save must preserve exact dispatch output and state")
    }

    func testInvalidStoredPayloadRejectsBattleWithoutChangingSaveOrReceipt() async throws {
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.gear[0].qualityID = "Q4"
        initial.gear[0].candidateLatentSlots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_UNKNOWN_TEST", rawQ: 1_000),
            CandidateLatentSlotR003(affixID: "AF_HASTE", rawQ: 1_000),
            CandidateLatentSlotR003(affixID: "AF_CRIT", rawQ: 1_000)
        ])
        let saveURL = temporarySaveURL("invalid")
        defer { try? FileManager.default.removeItem(at: saveURL.deletingLastPathComponent()) }
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try GameEngine(catalog: catalog, saves: store, candidateLatentPolicy: policy)
        let persistOp = UUID(uuidString: "32000000-0000-4000-8000-000000000004")!
        _ = try await engine.dispatch(.protect(gearID: initial.gear[0].id, protected: true),
                                      operationID: persistOp, expectedRevision: 0)
        let before = await engine.snapshot()
        let bytesBefore = try Data(contentsOf: saveURL)
        let rejectedOp = UUID(uuidString: "32000000-0000-4000-8000-000000000005")!
        do {
            _ = try await engine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: seed + 3),
                                          operationID: rejectedOp, expectedRevision: before.revision)
            XCTFail("invalid stored candidate payload must reject battle projection")
        } catch CandidateLatentPolicyErrorR003.unknownAffix("AF_UNKNOWN_TEST") {
            // Expected failure occurs before the transaction is committed.
        }
        let after = await engine.snapshot()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try Data(contentsOf: saveURL), bytesBefore)
        let rejectedReceipt = await store.receipt(for: rejectedOp)
        XCTAssertNil(rejectedReceipt, "rejected dispatch must not persist an operation receipt")
    }

    private func candidateSnapshot() throws -> GameSnapshot {
        var state = GameSnapshot.newGame(catalog: catalog)
        state.completedEncounterIDs.formUnion(catalog.enemies.map(\.id))
        guard let index = state.gear.firstIndex(where: { $0.definitionID == "EQ_W_01" && $0.ownerID == "C_WITCH" }) else {
            throw CoreError.invalidCatalog("synthetic fixture is missing the Witch starter weapon")
        }
        state.gear[index].qualityID = "Q4"
        state.gear[index].candidateLatentSlots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_DIRECT", rawQ: 1_000),
            CandidateLatentSlotR003(affixID: "AF_HASTE", rawQ: 1_000),
            CandidateLatentSlotR003(affixID: "AF_CRIT_DMG", rawQ: 1_000)
        ])
        return state
    }

    /// Mirrors GameEngine.makeCombatParty's real equipped-item selection and calls
    /// the exact Domain projector used by that dispatch path.
    private func projectedParty(_ state: GameSnapshot) throws -> [Combatant] {
        try state.partyActorIDs.map { actorID in
            let equipped = state.equippedGearIDs.filter { $0.key.hasPrefix(actorID + "|") }
                .compactMap { _, instanceID in state.gear.first(where: { $0.id == instanceID }) }
            return try catalog.projectCandidateCombatantR005(for: actorID, with: equipped,
                completedResearchIDs: state.completedResearchIDs,
                totalXP: state.characterXP[actorID, default: 0],
                candidateLatentPolicy: policy).combatant
        }
    }

    private func statsSignature(_ party: [Combatant]) -> [String] {
        party.map { "\($0.id)|\($0.maxHP)|\($0.attack)|\($0.defense)|\($0.guardChanceBP)|\($0.effectIDs.sorted())" }
    }

    private func temporarySaveURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("r032-latent-\(label)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("save.json")
    }
}
