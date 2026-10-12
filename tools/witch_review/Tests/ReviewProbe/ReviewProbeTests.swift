import XCTest
import WitchGameCore

final class ReviewProbeTests: XCTestCase {
    func testOperationIDCollisionIsRejectedButExactRetryIsIdempotent() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: .newGame(catalog: catalog)))
        let initialState = await engine.snapshot()
        let gearID = try XCTUnwrap(initialState.gear.first?.id)
        let op = UUID()
        let first = try await engine.dispatch(.protect(gearID: gearID, protected: true), operationID: op, expectedRevision: 0)
        let retry = try await engine.dispatch(.protect(gearID: gearID, protected: true), operationID: op, expectedRevision: 0)
        XCTAssertEqual(retry, first)
        do {
            _ = try await engine.dispatch(.protect(gearID: gearID, protected: false), operationID: op, expectedRevision: 0)
            XCTFail("same UUID with a different request must be rejected")
        } catch CoreError.duplicateOperation { }
        let afterCollision = await engine.snapshot()
        XCTAssertTrue(afterCollision.gear.first?.protected == true)
    }

    func testRegionCannotStartBeforeBossGate() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: .newGame(catalog: catalog)))
        do {
            _ = try await engine.dispatch(.startExpedition(regionID: "R05"), operationID: UUID(), expectedRevision: 0)
            XCTFail("locked R05 should not start from a fresh save")
        } catch CoreError.invalidCommand { }
        let state = await engine.snapshot()
        XCTAssertFalse(state.unlockedRegionIDs.contains("R05"))
    }

    func testTargetOutsidePoolIsRejectedWithoutSpendingTicket() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var state = GameSnapshot.newGame(catalog: catalog)
        state.gachaUnlocked = true
        state.currency["ticket_free"] = 1
        state.gachaPity = GachaPityState(drawsSinceTop: 99, targetTemplateID: "EQ_W_P2", guaranteeTargetOnNextTop: true)
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        do {
            _ = try await engine.dispatch(.mockSummon(poolDefinitionIDs: ["EQ_W_01"], count: 1, costCurrencyID: "ticket_free", seed: 123), operationID: UUID(), expectedRevision: 0)
            XCTFail("out-of-pool target must be rejected")
        } catch CoreError.invalidCommand { }
        let after = await engine.snapshot()
        XCTAssertEqual(after.currency["ticket_free"], 1)
        XCTAssertEqual(after.gear.count, GameSnapshot.newGame(catalog: catalog).gear.count)
    }

    func testCosmeticFingerprintSentinelCollisionIsRejected() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.ownedCosmeticIDs.insert("none")
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        let op = UUID()
        _ = try await engine.dispatch(.selectCosmetic(actorID: "C_WITCH", cosmeticID: nil), operationID: op, expectedRevision: 0)
        do {
            _ = try await engine.dispatch(.selectCosmetic(actorID: "C_WITCH", cosmeticID: "none"), operationID: op, expectedRevision: 0)
            XCTFail("nil and literal none are distinct payloads and must be rejected on UUID reuse")
        } catch CoreError.duplicateOperation { }
        let result = await engine.snapshot()
        XCTAssertNil(result.selectedCosmeticIDs["C_WITCH"])
    }

    func testPublicOwnershipCommandsGrantAppearanceAndFurnitureWithoutPurchase() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let costume = try XCTUnwrap(catalog.appearances.first { $0.kind == "costume" && !$0.actorIDs.isEmpty })
        let furniture = try XCTUnwrap(catalog.furnitureIDs.first)
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: .newGame(catalog: catalog)))
        _ = try await engine.dispatch(.setCosmetic(costume.id, owned: true), operationID: UUID(), expectedRevision: 0)
        _ = try await engine.dispatch(.selectCosmetic(actorID: costume.actorIDs[0], cosmeticID: costume.id), operationID: UUID(), expectedRevision: 1)
        _ = try await engine.dispatch(.setFurniture(furniture, owned: true), operationID: UUID(), expectedRevision: 2)
        _ = try await engine.dispatch(.placeFurniture(furniture, placed: true), operationID: UUID(), expectedRevision: 3)
        let state = await engine.snapshot()
        XCTAssertTrue(state.ownedCosmeticIDs.contains(costume.id))
        XCTAssertEqual(state.selectedCosmeticIDs[costume.actorIDs[0]], costume.id)
        XCTAssertTrue(state.ownedFurnitureIDs.contains(furniture))
        XCTAssertTrue(state.placedFurnitureIDs.contains(furniture))
        XCTAssertTrue(state.mockPurchaseRecords.isEmpty, "the public ownership setters bypass purchase-ledger proof")
    }

    func testCatalogPressureEffectWorksWhenEquippedOnSmith() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let smithEffects = Set(try XCTUnwrap(catalog.gear.first { $0.id == "EQ_S_02" }?.effects))
        XCTAssertTrue(smithEffects.contains("SMITH_PRESSURE"))
        let party = [
            Combatant(id: "C_WITCH", maxHP: 500, attack: 1, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 500, attack: 1, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 500, attack: 1, defense: 0, effectIDs: smithEffects),
            Combatant(id: "C_FAMILIAR", maxHP: 500, attack: 1, defense: 0)
        ]
        let foe = Combatant(id: "FOE", maxHP: 100_000, attack: 10, defense: 0, actionPattern: "multiHit")
        let result = try CombatSimulator.run(party: party, enemies: [foe], seed: 7, maxTicks: 10)
        XCTAssertTrue(result.events.contains { $0.kind == "smith_pressure" })
        XCTAssertTrue(result.events.contains { $0.kind == "smith_hammer" })
        let pressureEvents = result.events.filter { $0.kind == "smith_pressure" }
        let pressureRoots = Set(pressureEvents.compactMap { $0.rootActionID })
        XCTAssertEqual(pressureRoots.count, pressureEvents.count, "only one pressure event per enemy root action")
        let contactRoots = Set(result.events.filter { $0.kind == "enemy_hit" }.compactMap { $0.rootActionID })
        XCTAssertEqual(pressureRoots, contactRoots, "current implementation charges pressure for every contacting enemy root, without an eligible-counter event")
        XCTAssertFalse(result.events.contains { $0.kind == "guard" || $0.kind == "counter" }, "the R6 counter/guard trigger is not modeled")
        XCTAssertTrue(result.events.contains { $0.kind == "smith_hammer" && $0.sourceID == "C_SMITH" }, "pressure is consumed by the next direct-attack phase")
    }

    func testCatalogHealAndPoisonEffectsActivateOnTheirActors() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let poisonEffects = Set(try XCTUnwrap(catalog.gear.first { $0.id == "EQ_W_P2" }?.effects))
        let healerEffects = Set(try XCTUnwrap(catalog.gear.first { $0.id == "EQ_A_02" }?.effects))
        XCTAssertTrue(poisonEffects.contains("POISON_SHATTER"))
        XCTAssertTrue(poisonEffects.contains("POISON_BURST_25_AT_5"))
        XCTAssertTrue(healerEffects.contains("HEAL_TO_BARRIER"))
        let party = [
            Combatant(id: "C_WITCH", maxHP: 500, attack: 1, defense: 0, effectIDs: poisonEffects),
            Combatant(id: "C_APPRENTICE", maxHP: 500, attack: 10, defense: 0, effectIDs: healerEffects),
            Combatant(id: "C_SMITH", maxHP: 500, attack: 1, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 500, attack: 1, defense: 0)
        ]
        let foe = Combatant(id: "FOE", maxHP: 100_000, attack: 10, defense: 0)
        let result = try CombatSimulator.run(party: party, enemies: [foe], seed: 9, maxTicks: 10)
        XCTAssertTrue(result.events.contains { $0.kind == "poison_burst" })
        XCTAssertTrue(result.events.contains { $0.kind == "heal_barrier" && $0.amount > 0 })
    }

    func testGatherSettlesAllWholeElapsedWork() async throws {
        let start = Date(timeIntervalSince1970: 100_000)
        let catalog = GameCatalog(version: "audit", regions: [RegionDefinition(id: "R1", name: "one", enemyIDs: [], gatherMaterialIDs: ["m1"], workSeconds: 300)], enemies: [], gear: [], research: [])
        var state = GameSnapshot(lastClaimAt: start, activeRegionID: "R1", gatherTargetMaterialID: "m1")
        state.unlockedRegionIDs.insert("R1")
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        _ = try await engine.dispatch(.gather(resourceID: "m1", now: start.addingTimeInterval(3_600)), operationID: UUID(), expectedRevision: 0)
        let after = await engine.snapshot()
        XCTAssertEqual(after.materials["m1"], 12, "60 minutes at five minutes per unit commits all twelve units")
        XCTAssertEqual(after.lastClaimAt, start.addingTimeInterval(3_600))
        XCTAssertEqual(after.offlineRemainderSeconds, 0)
    }

    func testOfflineWorkIsCreditedToRegionSelectedAfterElapsedTime() async throws {
        let start = Date(timeIntervalSince1970: 100_000)
        let regions = [
            RegionDefinition(id: "R1", name: "one", enemyIDs: [], gatherMaterialIDs: ["m1"], xpPerWork: 1, workSeconds: 300),
            RegionDefinition(id: "R2", name: "two", enemyIDs: [], gatherMaterialIDs: ["m2"], xpPerWork: 4, workSeconds: 600)
        ]
        let catalog = GameCatalog(version: "audit", regions: regions, enemies: [], gear: [], research: [])
        let state = GameSnapshot(unlockedRegionIDs: ["R1", "R2"], lastClaimAt: start, activeRegionID: "R1", gatherTargetMaterialID: "m1")
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        _ = try await engine.dispatch(.startExpeditionAt(regionID: "R2", now: start.addingTimeInterval(1_800)), operationID: UUID(), expectedRevision: 0)
        _ = try await engine.claimOffline(now: start.addingTimeInterval(3_600), operationID: UUID(), expectedRevision: 1)
        let after = await engine.snapshot()
        XCTAssertEqual(after.materials["m1"], 6, "pre-switch time is settled to the previous region")
        XCTAssertEqual(after.materials["m2"], 3, "only post-switch time is credited to R2")
        XCTAssertEqual(after.characterXP["C_WITCH"], 18, "XP uses each region's own rate on its own time window")
    }

    func testWeakAutomaticPartyCanLoseAndReplayIsDeterministic() throws {
        let party = [
            Combatant(id: "C_WITCH", maxHP: 8, attack: 0, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 8, attack: 0, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 8, attack: 0, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 8, attack: 0, defense: 0)
        ]
        let enemy = Combatant(id: "FOE", maxHP: 10_000, attack: 20, defense: 0, actionPattern: "multiHit")
        let first = try CombatSimulator.run(party: party, enemies: [enemy], seed: 91, maxTicks: 20)
        let replay = try CombatSimulator.run(party: party, enemies: [enemy], seed: 91, maxTicks: 20)
        XCTAssertFalse(first.won)
        XCTAssertTrue(first.remainingPartyHP.values.allSatisfy { $0 == 0 })
        XCTAssertEqual(first, replay)
    }

    func testQualityAndResearchAffectCombat() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        func makeState(highQuality: Bool) -> GameSnapshot {
            var state = GameSnapshot.newGame(catalog: catalog)
            let old = state.gear[0]
            state.gear[0] = GearInstance(id: old.id, definitionID: old.definitionID, ownerID: old.ownerID, protected: true,
                enhancement: highQuality ? 10 : 0, refinement: highQuality ? 10 : 0,
                latentEffectID: highQuality ? "LATENT_POWER_TEST" : nil, qualityID: highQuality ? "Q4" : "Q0",
                affixIDs: highQuality ? ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"] : [])
            return state
        }
        let low = try GameEngine(catalog: catalog, saves: SaveRepository(initial: makeState(highQuality: false)))
        let high = try GameEngine(catalog: catalog, saves: SaveRepository(initial: makeState(highQuality: true)))
        for engine in [low, high] {
            _ = try await engine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 12345), operationID: UUID(), expectedRevision: 0)
        }
        let lowResult = await low.snapshot().lastCombatResult
        let highResult = await high.snapshot().lastCombatResult
        XCTAssertNotEqual(lowResult, highResult)
        _ = try await high.dispatch(.completeResearch("RS_THEORY_1"), operationID: UUID(), expectedRevision: 1)
        let before = await high.snapshot().lastCombatResult
        _ = try await high.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 12345), operationID: UUID(), expectedRevision: 2)
        let after = await high.snapshot().lastCombatResult
        XCTAssertNotEqual(before, after, "research completion should affect the subsequent battle")
    }
}
