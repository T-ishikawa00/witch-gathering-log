import Foundation
import XCTest
@testable import WitchGameCore

final class CandidateLatentAcquisitionIntegrationR005Tests: XCTestCase {
    private var catalog: GameCatalog!
    private var policy: CandidateLatentSlotPolicyR003!

    override func setUpWithError() throws {
        catalog = try GameCatalog.bundledTestOverlay()
        policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
    }

    func testLegacyGearDecodeAndEncodeKeepCandidatePayloadAbsent() throws {
        let id = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let source: [String: Any] = ["id": id.uuidString, "definitionID": "EQ_W_01",
                                     "latentEffectID": "LATENT_POWER_TEST", "qualityID": "Q3",
                                     "affixIDs": ["AFFIX_POWER_TEST"]]
        let decoded = try JSONDecoder().decode(GearInstance.self, from: JSONSerialization.data(withJSONObject: source))
        XCTAssertNil(decoded.candidateLatentSlots)
        XCTAssertEqual(decoded.latentEffectID, "LATENT_POWER_TEST")
        let encoded = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["candidateLatentSlots"], "legacy decode must not synthesize a payload field")
        XCTAssertEqual(object["latentEffectID"] as? String, "LATENT_POWER_TEST")
    }

    func testExplicitNewCandidateGameSeedsOnlyNewStarterInstances() throws {
        let legacy = GameSnapshot.newGame(catalog: catalog)
        XCTAssertTrue(legacy.gear.allSatisfy { $0.candidateLatentSlots == nil })

        let candidate = try GameSnapshot.newCandidateGame(catalog: catalog, candidateLatentPolicy: policy)
        XCTAssertEqual(candidate.gear.count, legacy.gear.count)
        XCTAssertTrue(candidate.gear.allSatisfy { $0.candidateLatentSlots?.slots.count == 3 })
        for item in candidate.gear {
            let slots = try XCTUnwrap(item.candidateLatentSlots)
            try policy.validateNewInstanceSlots(templateID: item.definitionID,
                                                joinedActorIDs: Set(candidate.partyActorIDs), slots: slots)
        }
        let candidateAgain = try GameSnapshot.newCandidateGame(catalog: catalog, candidateLatentPolicy: policy)
        XCTAssertEqual(candidate.gear.map(\.candidateLatentSlots), candidateAgain.gear.map(\.candidateLatentSlots))
        XCTAssertEqual(candidate.gear.map(\.id), legacy.gear.map(\.id), "starter identity is stable; only explicit candidate creation adds latent payload")
    }

    func testCandidateCombatProjectionUsesQualityForLatentSlotsOnlyAndLeavesLegacyRouteAlone() throws {
        let slots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 1000),
            CandidateLatentSlotR003(affixID: "AF_DEF", rawQ: 1000),
            CandidateLatentSlotR003(affixID: "AF_WARD", rawQ: 1000)
        ])
        func item(_ quality: String, payload: CandidateLatentSlotsR003?) -> GearInstance {
            GearInstance(definitionID: "EQ_W_01", ownerID: "C_WITCH", enhancement: 10,
                         latentEffectID: "LATENT_POWER_TEST", candidateLatentSlots: payload,
                         qualityID: quality, affixIDs: ["AFFIX_POWER_TEST"])
        }
        let q0 = try catalog.projectCandidateCombatantR005(for: "C_WITCH", with: [item("Q0", payload: slots)],
                                                        candidateLatentPolicy: policy)
        let q4 = try catalog.projectCandidateCombatantR005(for: "C_WITCH", with: [item("Q4", payload: slots)],
                                                        candidateLatentPolicy: policy)
        XCTAssertEqual(q0.combatant.attack, 18)
        XCTAssertEqual(q4.combatant.attack, 18,
                       "candidate quality must unlock/floor slots, not multiply main gear stats")
        XCTAssertGreaterThan(q4.combatant.maxHP, q0.combatant.maxHP,
                             "Q4 activates the stored HP slot and applies its candidate percentage")
        XCTAssertFalse(q4.combatant.effectIDs.contains("AFFIX_POWER_TEST"))
        XCTAssertFalse(q4.combatant.effectIDs.contains("LATENT_POWER_TEST"))
        XCTAssertEqual(try XCTUnwrap(q4.latent).modifiers.critChanceBP, 500)

        let legacyQ0 = catalog.projectCombatant(for: "C_WITCH", with: [item("Q0", payload: nil)])
        let legacyQ4 = catalog.projectCombatant(for: "C_WITCH", with: [item("Q4", payload: nil)])
        XCTAssertEqual(legacyQ0.attack, 28)
        XCTAssertEqual(legacyQ4.attack, 29,
                       "legacy nil-payload quality and aliases stay on the historical route")
        XCTAssertTrue(legacyQ4.effectIDs.contains("AFFIX_POWER_TEST"))
        XCTAssertTrue(legacyQ4.effectIDs.contains("LATENT_POWER_TEST"))
    }

    func testPolicyDoesNotSwitchAllLegacyLoadoutsToCandidateCombatantMode() throws {
        let snapshot = GameSnapshot.newGame(catalog: catalog)
        XCTAssertTrue(snapshot.gear.allSatisfy { $0.candidateLatentSlots == nil })
        for actorID in ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"] {
            let legacy = catalog.projectCombatant(for: actorID, with: snapshot.gear,
                                                  completedResearchIDs: snapshot.completedResearchIDs)
            let candidateAdapter = try catalog.projectCandidateCombatantR005(
                for: actorID, with: snapshot.gear,
                completedResearchIDs: snapshot.completedResearchIDs,
                candidateLatentPolicy: policy)
            XCTAssertEqual(candidateAdapter.combatant, legacy, "legacy projection changed for \\(actorID)")
            XCTAssertNil(candidateAdapter.latent, "all-nil legacy loadout must not select the new timeline modifier branch")
        }
    }

    func testCraftCommandPersistsDeterministicQ2PayloadAndSameOperationIsIdempotent() async throws {
        let url = tempSaveURL("craft")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.materials = ["M_R01_G1": 100, "M_R01_G2": 100, "M_R01_E2": 100,
                             "refine_dust": 100]
        let store = try SaveRepository(initial: initial, fileURL: url)
        let game = try GameEngine(catalog: catalog, saves: store, candidateLatentPolicy: policy)
        let op = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        let receipt = try await game.dispatch(.craftRecipe("RC_EQ_W_01"), operationID: op, expectedRevision: 0)
        let after = await game.snapshot()
        let item = try XCTUnwrap(after.gear.first(where: { $0.definitionID == "EQ_W_01" && $0.id != initial.gear[0].id }))
        let slots = try XCTUnwrap(item.candidateLatentSlots)
        XCTAssertEqual(item.qualityID, "Q2")
        XCTAssertEqual(slots.slots.count, 3)
        XCTAssertTrue(slots.slots.allSatisfy { $0.rawQ >= 250 })
        try policy.validateCraftNewCandidate(templateID: item.definitionID,
                                             joinedActorIDs: Set(after.partyActorIDs), slots: slots)

        let retry = try await game.dispatch(.craftRecipe("RC_EQ_W_01"), operationID: op, expectedRevision: 0)
        XCTAssertEqual(retry, receipt)
        let retrySnapshot = await game.snapshot()
        XCTAssertEqual(retrySnapshot.gear.filter { $0.definitionID == "EQ_W_01" }.count,
                       initial.gear.filter { $0.definitionID == "EQ_W_01" }.count + 1)

        let reopened = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        let reread = await reopened.snapshot()
        let saved = try XCTUnwrap(reread.gear.first(where: { $0.id == item.id }))
        XCTAssertEqual(saved.candidateLatentSlots, slots)
        XCTAssertEqual(reread.revision, receipt.revision)
    }

    func testPromotionPreservesCandidateSlotsAndExistingLegacyIDWithoutReroll() async throws {
        let initialSlots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 321),
            CandidateLatentSlotR003(affixID: "AF_POWER", rawQ: 654),
            CandidateLatentSlotR003(affixID: "AF_DIRECT", rawQ: 987)
        ])
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.completedEncounterIDs.formUnion(["B_R01_A", "B_R01_B", "B_R02_B", "B_R04_B"])
        initial.materials["refine_dust"] = 10_000
        initial.gear[0].qualityID = "Q0"
        initial.gear[0].candidateLatentSlots = initialSlots
        initial.gear[0].latentEffectID = "LATENT_POWER_TEST"
        let store = try SaveRepository(initial: initial)
        let game = try GameEngine(catalog: catalog, saves: store, candidateLatentPolicy: policy)
        var revision: Int64 = 0
        for _ in 0..<4 {
            let receipt = try await game.dispatch(.promoteQuality(gearID: initial.gear[0].id),
                                                  operationID: UUID(), expectedRevision: revision)
            revision = receipt.revision
        }
        let promotedSnapshot = await game.snapshot()
        let promoted = try XCTUnwrap(promotedSnapshot.gear.first)
        XCTAssertEqual(promoted.qualityID, "Q4")
        XCTAssertEqual(promoted.candidateLatentSlots, initialSlots)
        XCTAssertEqual(promoted.latentEffectID, "LATENT_POWER_TEST")
    }

    func testCompatibleEvolutionPreservesSlotsAndInvalidEvolutionIsAtomic() async throws {
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.completedEncounterIDs.insert("B_R01_B")
        initial.materials = ["M_R01_G1": 100, "M_R01_G2": 100, "M_R01_G3": 100,
                             "M_R01_BA": 2, "M_R01_BB": 2, "refine_dust": 100]
        let sourceSlots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 321),
            CandidateLatentSlotR003(affixID: "AF_POWER", rawQ: 654),
            CandidateLatentSlotR003(affixID: "AF_WARD", rawQ: 987)
        ])
        initial.gear[0].candidateLatentSlots = sourceSlots
        initial.gear[0].latentEffectID = "legacy-kept"
        let store = try SaveRepository(initial: initial)
        let game = try GameEngine(catalog: catalog, saves: store, candidateLatentPolicy: policy)
        let recipe = try XCTUnwrap(catalog.recipes.first(where: { $0.parentTemplateID == "EQ_W_01" && $0.outputGearID == "EQ_W_G1" }))
        let success = try await game.dispatch(.evolveGear(gearID: initial.gear[0].id, recipeID: recipe.id),
                                              operationID: UUID(), expectedRevision: 0)
        let evolvedSnapshot = await game.snapshot()
        let evolved = try XCTUnwrap(evolvedSnapshot.gear.first)
        XCTAssertEqual(evolved.definitionID, "EQ_W_G1")
        XCTAssertEqual(evolved.candidateLatentSlots, sourceSlots)
        XCTAssertEqual(evolved.latentEffectID, "legacy-kept")
        XCTAssertEqual(success.revision, 1)

        var invalidInitial = GameSnapshot.newGame(catalog: catalog)
        invalidInitial.completedEncounterIDs.insert("B_R01_B")
        invalidInitial.materials = initial.materials
        invalidInitial.gear[0].candidateLatentSlots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 321),
            CandidateLatentSlotR003(affixID: "AF_DOT", rawQ: 654),
            CandidateLatentSlotR003(affixID: "AF_WARD", rawQ: 987)
        ])
        let url = tempSaveURL("evolve-reject")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let invalidStore = try SaveRepository(initial: invalidInitial, fileURL: url)
        let invalidGame = try GameEngine(catalog: catalog, saves: invalidStore, candidateLatentPolicy: policy)
        let checkpoint = try await invalidGame.dispatch(.protect(gearID: invalidInitial.gear[0].id, protected: true),
                                                        operationID: UUID(), expectedRevision: 0)
        let invalidBefore = await invalidGame.snapshot()
        let beforeBytes = try Data(contentsOf: url)
        let rejectedOperationID = UUID(uuidString: "20000000-0000-4000-8000-000000000099")!
        let receiptBefore = await invalidStore.receipt(for: rejectedOperationID)
        XCTAssertNil(receiptBefore)
        do {
            _ = try await invalidGame.dispatch(.evolveGear(gearID: invalidInitial.gear[0].id, recipeID: recipe.id),
                                               operationID: rejectedOperationID, expectedRevision: checkpoint.revision)
            XCTFail("incompatible stored affix should reject evolution")
        } catch CandidateLatentPolicyErrorR003.incompatibleEvolution("AF_DOT") {
            // Expected; the transaction closure throws before spending or mutation persists.
        }
        let invalidAfter = await invalidGame.snapshot()
        XCTAssertEqual(invalidAfter, invalidBefore)
        XCTAssertEqual(invalidAfter.revision, checkpoint.revision)
        XCTAssertEqual(try Data(contentsOf: url), beforeBytes)
        let receiptAfter = await invalidStore.receipt(for: rejectedOperationID)
        XCTAssertNil(receiptAfter, "rejected invalid evolution must not write an operation receipt")
    }

    private func tempSaveURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("latent-r005-\(name)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("save.json")
    }
}
