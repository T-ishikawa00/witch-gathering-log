import Foundation
import XCTest
@testable import WitchGameCore

final class EquipmentLoadoutsR342Tests: XCTestCase {
    private func profile() throws -> GameRuntimeConfigurationR098 {
        try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
    }

    private func makeEngine(_ snapshot: GameSnapshot, runtime: GameRuntimeConfigurationR098? = nil) throws -> (SaveRepository, GameEngine) {
        let resolved = try runtime ?? profile()
        let saves = try SaveRepository(initial: snapshot)
        return (saves, try resolved.makeEngine(saves: saves))
    }

    private func retainedTestDirectory() throws -> URL {
        let env = ProcessInfo.processInfo.environment["WITCH_R342_TEST_OUTPUT"] ?? ""
        let root = URL(fileURLWithPath: env, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard root.path.hasPrefix("/"), FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue, root.resolvingSymlinksInPath().path == root.path,
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw NSError(domain: "WITCH_R342_TEST_OUTPUT", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Set WITCH_R342_TEST_OUTPUT to an existing real directory"])
        }
        let child = root.appendingPathComponent("r342-" + UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        return child
    }

    private func operation(_ value: String) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: value))
    }

    func testLegacySnapshotOmitsPayloadAndExactVersionRoundTrips() throws {
        let runtime = try profile()
        let legacy = try runtime.makeNewSnapshot()
        XCTAssertNil(legacy.gearLoadoutsR342)
        let legacyData = try JSONEncoder().encode(legacy)
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        XCTAssertNil(legacyObject["gearLoadoutsR342"])
        XCTAssertNil(try JSONDecoder().decode(GameSnapshot.self, from: legacyData).gearLoadoutsR342)

        let slot = try XCTUnwrap(legacy.equippedGearIDs["C_WITCH|weapon"])
        let payload = GearLoadoutsR342(first: GearLoadoutR342(gearByActorSlot: ["C_WITCH|weapon": slot]))
        var withLoadout = legacy
        withLoadout.gearLoadoutsR342 = payload
        let recovery = SaveRecoveryStatus(source: .memory, loadedGeneration: 0, loadedRevision: 0,
            rejectedPrimaryRevision: nil, rejectedPrimaryByteCount: nil, preservedRejectedPrimaryFilename: nil)
        let envelope = try SaveDocumentCodec.encode(snapshot: withLoadout, receipts: [:], generation: 0,
            recoveryStatus: recovery, preserving: nil, priorModelledData: nil)
        XCTAssertNoThrow(try SaveDocumentCodec.decode(envelope.data),
                         "Only the exact R342 futureVersion path is admitted")
        XCTAssertEqual(try JSONDecoder().decode(GearLoadoutsR342.self,
            from: JSONEncoder().encode(payload)).loadout(for: .first), payload.loadout(for: .first))

        var unknownPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope.data) as? [String: Any])
        var unknownPayloadSnapshot = try XCTUnwrap(unknownPayload["snapshot"] as? [String: Any])
        var unknownPayloadBody = try XCTUnwrap(unknownPayloadSnapshot["gearLoadoutsR342"] as? [String: Any])
        unknownPayloadBody["unknownFutureSlot"] = ["gearByActorSlot": ["C_WITCH|weapon": slot.uuidString]]
        unknownPayloadSnapshot["gearLoadoutsR342"] = unknownPayloadBody
        unknownPayload["snapshot"] = unknownPayloadSnapshot
        unknownPayload.removeValue(forKey: "integritySHA256")
        unknownPayload["integritySHA256"] = try SaveDocumentCodec.checksum(for: unknownPayload)
        XCTAssertThrowsError(try SaveDocumentCodec.decode(JSONSerialization.data(withJSONObject: unknownPayload, options: [.sortedKeys])))

        var unknownNested = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope.data) as? [String: Any])
        var unknownNestedSnapshot = try XCTUnwrap(unknownNested["snapshot"] as? [String: Any])
        var unknownNestedPayload = try XCTUnwrap(unknownNestedSnapshot["gearLoadoutsR342"] as? [String: Any])
        var unknownLoadout = try XCTUnwrap(unknownNestedPayload["first"] as? [String: Any])
        unknownLoadout["savedDefinitionID"] = "EQ_W_01"
        unknownNestedPayload["first"] = unknownLoadout
        unknownNestedSnapshot["gearLoadoutsR342"] = unknownNestedPayload
        unknownNested["snapshot"] = unknownNestedSnapshot
        unknownNested.removeValue(forKey: "integritySHA256")
        unknownNested["integritySHA256"] = try SaveDocumentCodec.checksum(for: unknownNested)
        XCTAssertThrowsError(try SaveDocumentCodec.decode(JSONSerialization.data(withJSONObject: unknownNested, options: [.sortedKeys])))

        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope.data) as? [String: Any])
        var snapshot = try XCTUnwrap(future["snapshot"] as? [String: Any])
        var marker = try XCTUnwrap(snapshot["gearLoadoutsR342"] as? [String: Any])
        marker["futureVersion"] = 3
        snapshot["gearLoadoutsR342"] = marker
        future["snapshot"] = snapshot
        future.removeValue(forKey: "integritySHA256")
        future["integritySHA256"] = try SaveDocumentCodec.checksum(for: future)
        let futureBytes = try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
        XCTAssertThrowsError(try SaveDocumentCodec.decode(futureBytes))

        var misplaced = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope.data) as? [String: Any])
        var misplacedSnapshot = try XCTUnwrap(misplaced["snapshot"] as? [String: Any])
        misplacedSnapshot["unrelatedPayload"] = ["futureVersion": 2]
        misplaced["snapshot"] = misplacedSnapshot
        misplaced.removeValue(forKey: "integritySHA256")
        misplaced["integritySHA256"] = try SaveDocumentCodec.checksum(for: misplaced)
        let misplacedBytes = try JSONSerialization.data(withJSONObject: misplaced, options: [.sortedKeys])
        XCTAssertThrowsError(try SaveDocumentCodec.decode(misplacedBytes))
    }

    func testDirectDecoderRejectsUnknownAndNullLoadoutFields() throws {
        let id = "34200000-0000-4000-8000-000000000901"
        let valid: [String: Any] = ["gearByActorSlot": ["C_WITCH|weapon": id]]
        let validPayload: [String: Any] = ["futureVersion": 2, "first": valid]
        XCTAssertNoThrow(try JSONDecoder().decode(GearLoadoutsR342.self,
            from: JSONSerialization.data(withJSONObject: validPayload)))
        var nested = valid
        nested["savedDefinitionID"] = "EQ_W_01"
        XCTAssertThrowsError(try JSONDecoder().decode(GearLoadoutR342.self,
            from: JSONSerialization.data(withJSONObject: nested)))
        let invalid: [[String: Any]] = [
            ["futureVersion": 2, "first": valid, "unknownFutureSlot": valid],
            ["futureVersion": 2, "first": nested],
            ["futureVersion": 2, "first": valid, "second": NSNull()],
            ["futureVersion": 2],
            ["futureVersion": 3, "first": valid],
            ["futureVersion": 2, "first": ["gearByActorSlot": ["C_WITCH|weapon": id,
                                                                    "C_APPRENTICE|weapon": id]]]
        ]
        for payload in invalid {
            XCTAssertThrowsError(try JSONDecoder().decode(GearLoadoutsR342.self,
                from: JSONSerialization.data(withJSONObject: payload)))
        }
    }

    func testSaveApplyClearWholeMapAndSameOperationReplay() async throws {
        let runtime = try profile()
        var initial = try runtime.makeNewSnapshot()
        let starter = try XCTUnwrap(initial.equippedGearIDs["C_WITCH|weapon"])
        let replacement = UUID(uuidString: "34200000-0000-4000-8000-000000000001")!
        initial.gear.append(GearInstance(id: replacement, definitionID: "EQ_W_G1"))
        let directory = try retainedTestDirectory()
        let saveURL = directory.appendingPathComponent("save.json")
        let saves = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try runtime.makeEngine(saves: saves)

        let saveFirstID = try operation("34200000-0000-4000-8000-000000000101")
        let firstReceipt = try await engine.dispatch(.saveGearLoadoutR342(slot: .first),
            operationID: saveFirstID, expectedRevision: 0)
        XCTAssertEqual(firstReceipt.revision, 1)
        let afterFirstSave = await saves.snapshot()
        XCTAssertEqual(afterFirstSave.gearLoadoutsR342?.loadout(for: .first)?.gearByActorSlot["C_WITCH|weapon"], starter)

        _ = try await engine.dispatch(.equip(gearID: replacement, actorID: "C_WITCH"),
            operationID: try operation("34200000-0000-4000-8000-000000000102"), expectedRevision: 1)
        _ = try await engine.dispatch(.saveGearLoadoutR342(slot: .second),
            operationID: try operation("34200000-0000-4000-8000-000000000103"), expectedRevision: 2)
        let applyFirstID = try operation("34200000-0000-4000-8000-000000000104")
        let bothSaved = await saves.snapshot()
        let savedBytes = try Data(contentsOf: saveURL)
        let savedReopen = try SaveRepository(fileURL: saveURL)
        let savedReopenedSnapshot = await savedReopen.snapshot()
        XCTAssertEqual(savedReopenedSnapshot, bothSaved)
        XCTAssertEqual(try Data(contentsOf: saveURL), savedBytes)
        XCTAssertEqual(savedReopenedSnapshot.gearLoadoutsR342?.loadout(for: .second)?.gearByActorSlot["C_WITCH|weapon"], replacement)

        do {
            _ = try await engine.dispatch(.clearGearLoadoutR342(slot: .first),
                operationID: saveFirstID, expectedRevision: 3)
            XCTFail("Reusing one operation ID for a different command must fail")
        } catch CoreError.duplicateOperation { } catch {
            XCTFail("Unexpected operation replay error: \(error)")
        }

        _ = try await engine.dispatch(.applyGearLoadoutR342(slot: .first),
            operationID: applyFirstID, expectedRevision: 3)
        var state = await saves.snapshot()
        XCTAssertEqual(state.equippedGearIDs["C_WITCH|weapon"], starter)
        XCTAssertNil(state.gear.first(where: { $0.id == replacement })?.ownerID)
        XCTAssertEqual(state.gear.first(where: { $0.id == starter })?.ownerID, "C_WITCH")

        _ = try await engine.dispatch(.clearGearLoadoutR342(slot: .first),
            operationID: try operation("34200000-0000-4000-8000-000000000105"), expectedRevision: 4)
        state = await saves.snapshot()
        XCTAssertNil(state.gearLoadoutsR342?.loadout(for: .first))
        XCTAssertEqual(state.gearLoadoutsR342?.loadout(for: .second)?.gearByActorSlot["C_WITCH|weapon"], replacement)

        let applySecondID = try operation("34200000-0000-4000-8000-000000000106")
        let secondReceipt = try await engine.dispatch(.applyGearLoadoutR342(slot: .second),
            operationID: applySecondID, expectedRevision: 5)
        let afterApply = await saves.snapshot()
        let replay = try await engine.dispatch(.applyGearLoadoutR342(slot: .second),
            operationID: applySecondID, expectedRevision: 5)
        XCTAssertEqual(replay, secondReceipt)
        let afterReplay = await saves.snapshot()
        let replayReceipt = await saves.receipt(for: applySecondID)
        XCTAssertEqual(afterReplay, afterApply, "Same operation ID must not apply or revise twice")
        XCTAssertEqual(replayReceipt, secondReceipt)
        let clearLastID = try operation("34200000-0000-4000-8000-000000000107")
        _ = try await engine.dispatch(.clearGearLoadoutR342(slot: .second),
            operationID: clearLastID, expectedRevision: afterReplay.revision)
        let finalState = await saves.snapshot()
        XCTAssertNil(finalState.gearLoadoutsR342)
        let bytesBeforeReopen = try Data(contentsOf: saveURL)
        let reopened = try SaveRepository(fileURL: saveURL)
        let reopenedState = await reopened.snapshot()
        let reopenedReceipt = await reopened.receipt(for: clearLastID)
        XCTAssertEqual(reopenedState, finalState)
        XCTAssertEqual(reopenedReceipt?.operationID, clearLastID)
        XCTAssertEqual(try Data(contentsOf: saveURL), bytesBeforeReopen,
                       "Cold reading must not rewrite the persisted save")
    }

    func testInvalidCurrentAssignmentsFailWithoutRevisionOrReceipt() async throws {
        let runtime = try profile()
        let clean = try runtime.makeNewSnapshot()
        let starter = try XCTUnwrap(clean.equippedGearIDs["C_WITCH|weapon"])
        let malformedMaps: [[String: UUID]] = [
            ["C_WITCH|weapon": starter, "C_SMITH|weapon": starter],
            ["C_UNKNOWN|weapon": starter],
            ["C_WITCH|hat": starter]
        ]
        for (index, malformed) in malformedMaps.enumerated() {
            var state = clean
            state.equippedGearIDs = malformed
            let (saves, engine) = try makeEngine(state)
            let operationID = UUID(uuidString: String(format: "34200000-0000-4000-8000-%012d", index + 201))!
            do {
                _ = try await engine.dispatch(.saveGearLoadoutR342(slot: .first),
                    operationID: operationID, expectedRevision: 0)
                XCTFail("Malformed assignment should fail closed")
            } catch { }
            let after = await saves.snapshot()
            XCTAssertEqual(after, state)
            let receipt = await saves.receipt(for: operationID)
            XCTAssertNil(receipt)
        }
    }

    func testMissingSavedInstanceRefusesWholeApplyAndPreservesState() async throws {
        let runtime = try profile()
        var initial = try runtime.makeNewSnapshot()
        let starter = try XCTUnwrap(initial.equippedGearIDs["C_WITCH|weapon"])
        let removed = UUID(uuidString: "34200000-0000-4000-8000-000000000301")!
        let duplicate = UUID(uuidString: "34200000-0000-4000-8000-000000000302")!
        initial.gear.append(GearInstance(id: removed, definitionID: "EQ_W_G1"))
        initial.gear.append(GearInstance(id: duplicate, definitionID: "EQ_W_G1"))
        let (saves, engine) = try makeEngine(initial)

        _ = try await engine.dispatch(.equip(gearID: removed, actorID: "C_WITCH"),
            operationID: try operation("34200000-0000-4000-8000-000000000311"), expectedRevision: 0)
        _ = try await engine.dispatch(.saveGearLoadoutR342(slot: .second),
            operationID: try operation("34200000-0000-4000-8000-000000000312"), expectedRevision: 1)
        _ = try await engine.dispatch(.equip(gearID: starter, actorID: "C_WITCH"),
            operationID: try operation("34200000-0000-4000-8000-000000000313"), expectedRevision: 2)
        _ = try await engine.dispatch(.dismantle(gearID: removed),
            operationID: try operation("34200000-0000-4000-8000-000000000314"), expectedRevision: 3)
        let before = await saves.snapshot()
        let failedApplyID = try operation("34200000-0000-4000-8000-000000000315")
        do {
            _ = try await engine.dispatch(.applyGearLoadoutR342(slot: .second),
                operationID: failedApplyID, expectedRevision: before.revision)
            XCTFail("Missing instance must not partially equip the saved map")
        } catch { }
        let after = await saves.snapshot()
        let receipt = await saves.receipt(for: failedApplyID)
        XCTAssertEqual(after, before)
        XCTAssertNil(receipt)
    }

    func testApplyAllowsValidatedCurrentlyEquippedTransferBetweenEligibleActors() async throws {
        let runtime = try profile()
        let originalCatalog = runtime.catalog
        let definitionIndex = try XCTUnwrap(originalCatalog.gear.firstIndex(where: { $0.id == "EQ_W_01" }))
        let oldDefinition = originalCatalog.gear[definitionIndex]
        var modifiedGear = originalCatalog.gear
        modifiedGear[definitionIndex] = GearDefinition(id: oldDefinition.id, name: oldDefinition.name,
            rarity: oldDefinition.rarity, slot: oldDefinition.slot, effects: oldDefinition.effects,
            actorIDs: ["C_WITCH", "C_APPRENTICE"], guardChanceBonusBP: oldDefinition.guardChanceBonusBP)
        let catalog = GameCatalog(version: originalCatalog.version, regions: originalCatalog.regions,
            enemies: originalCatalog.enemies, gear: modifiedGear, research: originalCatalog.research,
            materialIDs: originalCatalog.materialIDs, materialAvailabilityGates: originalCatalog.materialAvailabilityGates,
            recipes: originalCatalog.recipes, actorIDs: originalCatalog.actorIDs, challenges: originalCatalog.challenges,
            researchEffects: originalCatalog.researchEffects, appearances: originalCatalog.appearances,
            furnitureIDs: originalCatalog.furnitureIDs, dailyFreeTicketGrant: originalCatalog.dailyFreeTicketGrant,
            authority: originalCatalog.authority, gearAttackBonuses: originalCatalog.gearAttackBonuses,
            gearHPBonuses: originalCatalog.gearHPBonuses, gearDefenseBonuses: originalCatalog.gearDefenseBonuses,
            gachaOddsBasisPoints: originalCatalog.gachaOddsBasisPoints)
        try catalog.validate()
        let initial = try runtime.makeNewSnapshot()
        let starter = try XCTUnwrap(initial.equippedGearIDs["C_WITCH|weapon"])
        let saves = try SaveRepository(initial: initial)
        let engine = try GameEngine(catalog: catalog, saves: saves,
            candidateCombatOverlay: runtime.combatOverlay, candidateCharacterGrowth: runtime.growth,
            candidateLatentPolicy: runtime.latentPolicy)
        _ = try await engine.dispatch(.saveGearLoadoutR342(slot: .first),
            operationID: try operation("34200000-0000-4000-8000-000000000401"), expectedRevision: 0)
        _ = try await engine.dispatch(.equip(gearID: starter, actorID: "C_APPRENTICE"),
            operationID: try operation("34200000-0000-4000-8000-000000000402"), expectedRevision: 1)
        _ = try await engine.dispatch(.saveGearLoadoutR342(slot: .second),
            operationID: try operation("34200000-0000-4000-8000-000000000403"), expectedRevision: 2)
        _ = try await engine.dispatch(.applyGearLoadoutR342(slot: .first),
            operationID: try operation("34200000-0000-4000-8000-000000000404"), expectedRevision: 3)
        let result = await saves.snapshot()
        XCTAssertEqual(result.equippedGearIDs["C_WITCH|weapon"], starter)
        XCTAssertEqual(result.equippedGearIDs["C_APPRENTICE|weapon"],
                       initial.equippedGearIDs["C_APPRENTICE|weapon"],
                       "Applying the whole original set restores the apprentice's original weapon too")
        XCTAssertEqual(result.gear.first(where: { $0.id == starter })?.ownerID, "C_WITCH")
    }

    func testApplyKeepsCurrentEvolvedDefinitionAndEnhancementForSavedUUID() async throws {
        let runtime = try profile()
        var initial = try runtime.makeNewSnapshot()
        initial.materials["M_R01_BA"] = 1
        initial.materials["M_R01_BB"] = 1
        initial.materials["M_R01_G3"] = 16
        initial.completedEncounterIDs.insert("B_R01_B")
        initial.materials["refine_dust"] = 10
        let starter = try XCTUnwrap(initial.equippedGearIDs["C_WITCH|weapon"])
        let (saves, engine) = try makeEngine(initial, runtime: runtime)
        _ = try await engine.dispatch(.saveGearLoadoutR342(slot: .first),
            operationID: try operation("34200000-0000-4000-8000-000000000411"), expectedRevision: 0)
        _ = try await engine.dispatch(.evolveGear(gearID: starter, recipeID: "RC_EQ_W_G1"),
            operationID: try operation("34200000-0000-4000-8000-000000000412"), expectedRevision: 1)
        _ = try await engine.dispatch(.enhance(gearID: starter),
            operationID: try operation("34200000-0000-4000-8000-000000000413"), expectedRevision: 2)
        let beforeApplySnapshot = await saves.snapshot()
        let currentBeforeApply = try XCTUnwrap(beforeApplySnapshot.gear.first(where: { $0.id == starter }))
        _ = try await engine.dispatch(.applyGearLoadoutR342(slot: .first),
            operationID: try operation("34200000-0000-4000-8000-000000000414"), expectedRevision: 3)
        let afterApplySnapshot = await saves.snapshot()
        let currentAfterApply = try XCTUnwrap(afterApplySnapshot.gear.first(where: { $0.id == starter }))
        XCTAssertEqual(currentAfterApply, currentBeforeApply,
            "Loadout stores only UUID assignments; current evolved/enhanced instance data must remain authoritative")
        XCTAssertEqual(currentAfterApply.definitionID, "EQ_W_G1")
        XCTAssertEqual(currentAfterApply.enhancement, 1)
        XCTAssertEqual(currentAfterApply.investmentDust, 5)
    }

    func testInvalidStoredLatentPayloadRefusesApplyAtomically() async throws {
        let runtime = try profile()
        var initial = try runtime.makeNewSnapshot()
        let starter = try XCTUnwrap(initial.equippedGearIDs["C_WITCH|weapon"])
        let invalidID = UUID(uuidString: "34200000-0000-4000-8000-000000000501")!
        let invalidSlots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "UNKNOWN_AFFIX", rawQ: 500),
            CandidateLatentSlotR003(affixID: "UNKNOWN_AFFIX_2", rawQ: 500),
            CandidateLatentSlotR003(affixID: "UNKNOWN_AFFIX_3", rawQ: 500)])
        initial.gear.append(GearInstance(id: invalidID, definitionID: "EQ_W_G1", candidateLatentSlots: invalidSlots))
        initial.gearLoadoutsR342 = GearLoadoutsR342(second: GearLoadoutR342(gearByActorSlot: [
            "C_WITCH|weapon": invalidID]))
        let saves = try SaveRepository(initial: initial)
        let engine = try GameEngine(catalog: runtime.catalog, saves: saves,
            candidateCombatOverlay: runtime.combatOverlay, candidateCharacterGrowth: runtime.growth,
            candidateLatentPolicy: runtime.latentPolicy)
        let before = await saves.snapshot()
        let op = try operation("34200000-0000-4000-8000-000000000502")
        do {
            _ = try await engine.dispatch(.applyGearLoadoutR342(slot: .second), operationID: op, expectedRevision: before.revision)
            XCTFail("Invalid stored latent data must be refused")
        } catch { }
        let after = await saves.snapshot()
        let receipt = await saves.receipt(for: op)
        XCTAssertEqual(after, before)
        XCTAssertNil(receipt)
        XCTAssertEqual(after.equippedGearIDs["C_WITCH|weapon"], starter)
        XCTAssertFalse(after.equippedGearIDs.values.contains(invalidID))
    }

}
