import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

final class GearSwapCombatPreviewR131Tests: XCTestCase {
    private let challenges = ["CH_R03_02", "CH_R05_01", "CH_R05_03"]
    private let seeds: [UInt64] = [100049, 100069, 100089]

    func testThreeChallengesThreeSeedsAreReadOnlyAndPaired() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        var state = try profile.makeNewSnapshot()
        // Synthetic test fixture: unlocks the catalog's real G_R05_B gate using
        // its real encounter key. No command or reward is simulated for this setup.
        state.completedEncounterIDs.insert("B_R05_B")
        let poisonID = try addOwnedGear("EQ_W_P1", owner: "C_WITCH", to: &state, profile: profile,
                                        uuid: "13100000-0000-4000-8000-000000000001")
        let wardID = try addOwnedGear("EQ_W_G1", owner: "C_WITCH", to: &state, profile: profile,
                                      uuid: "13100000-0000-4000-8000-000000000002")
        let witchWeaponKey = "C_WITCH|weapon"
        let starterID = try XCTUnwrap(state.equippedGearIDs[witchWeaponKey])
        let outputRoot = try requiredOutputRoot()
        let directory = outputRoot.appendingPathComponent("synthetic_fixture_" + UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let saveURL = directory.appendingPathComponent("preview-save.json")
        state.revision = 1
        let baselineBytes = try canonicalBytes(state)
        let receiptID = try XCTUnwrap(UUID(uuidString: "13100000-0000-4000-8000-000000000099"))
        let receipt = CommandReceipt(operationID: receiptID, revision: 1,
                                     result: "preexisting-test-receipt", requestFingerprint: "r131")
        let recovery = SaveRecoveryStatus(source: .memory, loadedGeneration: 0, loadedRevision: 1,
                                          rejectedPrimaryRevision: nil, rejectedPrimaryByteCount: nil,
                                          preservedRejectedPrimaryFilename: nil)
        let persisted = try SaveDocumentCodec.encode(snapshot: state, receipts: [receiptID: receipt], generation: 0,
                                                      recoveryStatus: recovery, preserving: nil, priorModelledData: nil)
        try persisted.data.write(to: saveURL, options: .atomic)
        let saves = try SaveRepository(initial: state, fileURL: saveURL)
        let engine = try profile.makeEngine(saves: saves)
        let persistedBefore = try Data(contentsOf: saveURL)
        let receiptBeforePreview = await saves.receipt(for: receiptID)
        XCTAssertEqual(receiptBeforePreview, receipt)

        for challengeID in challenges {
            for seed in seeds {
                let starter = try engine.previewChallengeGearSwapR131(
                    challengeID: challengeID, actorID: "C_WITCH", selectedGearID: starterID,
                    seed: seed, snapshot: state)
                let poison = try engine.previewChallengeGearSwapR131(
                    challengeID: challengeID, actorID: "C_WITCH", selectedGearID: poisonID,
                    seed: seed, snapshot: state)
                let ward = try engine.previewChallengeGearSwapR131(
                    challengeID: challengeID, actorID: "C_WITCH", selectedGearID: wardID,
                    seed: seed, snapshot: state)
                let repeatedStarter = try engine.previewChallengeGearSwapR131(
                    challengeID: challengeID, actorID: "C_WITCH", selectedGearID: starterID,
                    seed: seed, snapshot: state)

                XCTAssertEqual(starter.challengeID, challengeID)
                XCTAssertEqual(poison.challengeID, challengeID)
                XCTAssertEqual(ward.challengeID, challengeID)
                XCTAssertEqual([starter.seed, poison.seed, ward.seed], [seed, seed, seed])
                XCTAssertEqual(starter.currentGearID, starterID)
                XCTAssertEqual(poison.currentGearID, starterID)
                XCTAssertEqual(ward.currentGearID, starterID)
                XCTAssertEqual(poison.selectedGearID, poisonID)
                XCTAssertEqual(ward.selectedGearID, wardID)
                XCTAssertEqual(starter.result, repeatedStarter.result,
                               "Same snapshot, gear and seed must produce the same result")
                XCTAssertGreaterThanOrEqual(starter.result.ticks, 0)
                XCTAssertGreaterThanOrEqual(poison.result.ticks, 0)
                XCTAssertGreaterThanOrEqual(ward.result.ticks, 0)
                XCTAssertFalse(starter.result.events.isEmpty)
                XCTAssertFalse(poison.result.events.isEmpty)
                XCTAssertFalse(ward.result.events.isEmpty)

                let unchanged = await saves.snapshot()
                let receiptAfterPreview = await saves.receipt(for: receiptID)
                XCTAssertEqual(try canonicalBytes(unchanged), baselineBytes)
                XCTAssertEqual(try Data(contentsOf: saveURL), persistedBefore,
                               "Preview must preserve snapshot and receipt bytes exactly")
                XCTAssertEqual(receiptAfterPreview, receipt)
            }
        }
        let fixtureEvidence = directory.appendingPathComponent("fixture_receipt.json")
        let evidence: [String: Any] = [
            "schema": "r131-synthetic-fixture-preservation-v1",
            "fixturePath": saveURL.path,
            "fixtureSHA256": digest(try Data(contentsOf: saveURL)),
            "fixtureBytes": (try Data(contentsOf: saveURL)).count,
            "receiptID": receiptID.uuidString.lowercased(),
            "revision": 1,
            "retained": true
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys, .prettyPrinted])
            .write(to: fixtureEvidence, options: .withoutOverwriting)
    }

    func testSummaryReportsObservedEventsWithoutGearAttributionOrTotals() throws {
        let raw = CombatResult(won: true, ticks: 4, events: [
            CombatEvent(tick: 1, kind: "poison_tick", sourceID: "C_WITCH", targetID: "enemy", amount: 11),
            CombatEvent(tick: 2, kind: "barrier_absorb", sourceID: "enemy", targetID: "C_WITCH", amount: 9)
        ], remainingPartyHP: ["C_WITCH": 70], initialPartyHP: ["C_WITCH": 80],
           initialEnemyHP: ["enemy": 100], remainingEnemyHP: ["enemy": 89])
        let preview = GearSwapCombatPreviewR131(challengeID: "CH_R03_02", actorID: "C_WITCH",
            currentGearID: UUID(), selectedGearID: UUID(), slot: "weapon", seed: 7, result: raw)
        let summary = GearSwapCombatSummaryR131.make(from: preview)
        XCTAssertEqual(summary.eventKindCounts, ["poison_tick": 1, "barrier_absorb": 1])
        XCTAssertEqual(summary.selectedActorSourceEventKindCounts, ["poison_tick": 1])
        XCTAssertEqual(summary.selectedActorTargetEventKindCounts, ["barrier_absorb": 1])
        XCTAssertEqual(summary.eventAttribution, "OBSERVED_EVENTS_ONLY_NO_GEAR_CAUSALITY")
        let serialized = try JSONSerialization.jsonObject(with: canonicalBytes(summary)) as? [String: Any]
        XCTAssertNotNil(serialized?["eventKindCounts"])
        XCTAssertNil(serialized?["gearEffectCounts"])
        XCTAssertNil(serialized?["preventedDamage"])
        XCTAssertNil(serialized?["healingTotal"])
    }

    func testLockedChallengeAndUnownedOrIncompatibleSelectionFailClosed() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        var state = try profile.makeNewSnapshot()
        let starterID = try XCTUnwrap(state.equippedGearIDs["C_WITCH|weapon"])
        let incompatibleID = try addOwnedGear("EQ_F_01", owner: "C_WITCH", to: &state, profile: profile,
                                            uuid: "13100000-0000-4000-8000-000000000003")
        let wrongOwnerID = try addOwnedGear("EQ_W_G1", owner: "C_FAMILIAR", to: &state, profile: profile,
                                            uuid: "13100000-0000-4000-8000-000000000004")
        let compatibleButElsewhereID = try addOwnedGear("EQ_W_P1", owner: "C_WITCH", to: &state, profile: profile,
                                                        uuid: "13100000-0000-4000-8000-000000000005")
        let saves = try SaveRepository(initial: state)
        let engine = try profile.makeEngine(saves: saves)
        let baseline = try canonicalBytes(state)

        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: "CH_R99_99", actorID: "C_WITCH", selectedGearID: starterID,
            seed: seeds[0], snapshot: unlocked(state))) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .unknownChallenge) }
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: starterID,
            seed: seeds[0], snapshot: state)) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .challengeLocked) }
        let missingID = UUID(uuidString: "13100000-0000-4000-8000-000000000099")!
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: missingID,
            seed: seeds[0], snapshot: unlocked(state))) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .missingOrDuplicateGear(missingID)) }
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: wrongOwnerID,
            seed: seeds[0], snapshot: unlocked(state))) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .wrongGearOwner(wrongOwnerID)) }
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: incompatibleID,
            seed: seeds[0], snapshot: unlocked(state))) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .gearNotUsableByActor(incompatibleID)) }
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_UNKNOWN", selectedGearID: starterID,
            seed: seeds[0], snapshot: unlocked(state))) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .actorNotInParty) }
        var emptySlot = unlocked(state); emptySlot.equippedGearIDs.removeValue(forKey: "C_WITCH|weapon")
        let emptySlotPreview = try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: starterID,
            seed: seeds[0], snapshot: emptySlot)
        XCTAssertNil(emptySlotPreview.currentGearID)
        XCTAssertEqual(emptySlotPreview.slot, "weapon")
        var duplicate = unlocked(state); duplicate.gear.append(try XCTUnwrap(duplicate.gear.first(where: { $0.id == starterID })))
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: starterID,
            seed: seeds[0], snapshot: duplicate)) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .missingOrDuplicateGear(starterID)) }
        var malformedEquipment = unlocked(state)
        malformedEquipment.equippedGearIDs["C_FAMILIAR|weapon"] = compatibleButElsewhereID
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: compatibleButElsewhereID,
            seed: seeds[0], snapshot: malformedEquipment)) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .selectedGearEquippedElsewhere(compatibleButElsewhereID)) }
        var slotMismatch = unlocked(state)
        let amuletID = try addOwnedGear("EQ_AMU_01", owner: "C_WITCH", to: &slotMismatch, profile: profile,
                                        uuid: "13100000-0000-4000-8000-000000000006")
        slotMismatch.equippedGearIDs["C_WITCH|amulet"] = starterID
        XCTAssertThrowsError(try engine.previewChallengeGearSwapR131(
            challengeID: challenges[0], actorID: "C_WITCH", selectedGearID: amuletID,
            seed: seeds[0], snapshot: slotMismatch)) { XCTAssertEqual($0 as? GearSwapCombatPreviewErrorR131, .wrongGearSlot) }
        let unchanged = await saves.snapshot()
        XCTAssertEqual(try canonicalBytes(unchanged), baseline)
    }

    func testNilOwnedCandidateAndEmptyGeneralGearSlotArePreviewable() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        var state = try profile.makeNewSnapshot()
        state.completedEncounterIDs.insert("B_R05_B")
        let nilOwnedWeapon = try addOwnedGear("EQ_W_G1", owner: nil, to: &state, profile: profile,
                                               uuid: "13100000-0000-4000-8000-000000000011")
        let nilOwnedAmulet = try addOwnedGear("EQ_AMU_01", owner: nil, to: &state, profile: profile,
                                               uuid: "13100000-0000-4000-8000-000000000012")
        let saves = try SaveRepository(initial: state)
        let engine = try profile.makeEngine(saves: saves)
        let before = try canonicalBytes(state)
        let weapon = try engine.previewChallengeGearSwapR131(challengeID: challenges[0], actorID: "C_WITCH",
            selectedGearID: nilOwnedWeapon, seed: seeds[0], snapshot: state)
        XCTAssertEqual(weapon.currentGearID, state.equippedGearIDs["C_WITCH|weapon"])
        XCTAssertEqual(weapon.slot, "weapon")
        var emptyAmulet = state
        emptyAmulet.equippedGearIDs.removeValue(forKey: "C_WITCH|amulet")
        let amulet = try engine.previewChallengeGearSwapR131(challengeID: challenges[0], actorID: "C_WITCH",
            selectedGearID: nilOwnedAmulet, seed: seeds[0], snapshot: emptyAmulet)
        XCTAssertNil(amulet.currentGearID)
        XCTAssertEqual(amulet.slot, "amulet")
        let unchanged = await saves.snapshot()
        XCTAssertEqual(try canonicalBytes(unchanged), before)
    }

    func testBothUnassignedCandidatesAndActualEquipResolveMatch() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        var state = try profile.makeNewSnapshot()
        state.completedEncounterIDs.insert("B_R05_B")
        let firstID = try addOwnedGear("EQ_W_P1", owner: nil, to: &state, profile: profile,
                                       uuid: "13100000-0000-4000-8000-000000000021")
        let secondID = try addOwnedGear("EQ_W_G1", owner: nil, to: &state, profile: profile,
                                        uuid: "13100000-0000-4000-8000-000000000022")
        let slot = "C_WITCH|weapon"
        let currentID = try XCTUnwrap(state.equippedGearIDs[slot])
        let previewSaves = try SaveRepository(initial: state)
        let actualSaves = try SaveRepository(initial: state)
        let previewEngine = try profile.makeEngine(saves: previewSaves)
        let actualEngine = try profile.makeEngine(saves: actualSaves)
        let baseline = try canonicalBytes(state)
        let preview = try previewEngine.previewChallengeGearSwapR131(challengeID: challenges[0], actorID: "C_WITCH",
            selectedGearID: firstID, seed: seeds[1], snapshot: state)
        XCTAssertEqual(preview.currentGearID, currentID)
        let comparison = try previewEngine.previewChallengeGearSwapR131(challengeID: challenges[0], actorID: "C_WITCH",
            selectedGearID: secondID, seed: seeds[1], snapshot: state)
        XCTAssertEqual(comparison.currentGearID, currentID)
        let previewAfter = await previewSaves.snapshot()
        XCTAssertEqual(try canonicalBytes(previewAfter), baseline)

        let equip = try await actualEngine.dispatch(.equip(gearID: firstID, actorID: "C_WITCH"),
            operationID: UUID(), expectedRevision: state.revision)
        _ = try await actualEngine.dispatch(.resolveChallenge(challengeID: challenges[0], seed: seeds[1]),
            operationID: UUID(), expectedRevision: equip.revision)
        let actualAfter = await actualSaves.snapshot()
        let actualResult = try XCTUnwrap(actualAfter.lastCombatResult)
        XCTAssertEqual(preview.result, actualResult,
                       "Preview must match the real equip then challenge resolution for identical baseline/config/seed")
        XCTAssertEqual(actualAfter.equippedGearIDs[slot], firstID)
        XCTAssertEqual(actualAfter.gear.first(where: { $0.id == firstID })?.ownerID, "C_WITCH")
        XCTAssertNil(actualAfter.gear.first(where: { $0.id == currentID })?.ownerID)
    }

    func testEmptyActorEligibilityListMeansUniversalAsInRuntimeEquip() {
        let universal = GearDefinition(id: "TEST_UNIVERSAL", name: "universal", rarity: "C", slot: "amulet", effects: [], actorIDs: [])
        XCTAssertTrue(GearSwapCombatPreviewR131.isUsableByActorR131(universal, actorID: "C_WITCH"))
        XCTAssertTrue(GearSwapCombatPreviewR131.isUsableByActorR131(universal, actorID: "C_FAMILIAR"))
        let restricted = GearDefinition(id: "TEST_RESTRICTED", name: "restricted", rarity: "C", slot: "weapon", effects: [], actorIDs: ["C_WITCH"])
        XCTAssertFalse(GearSwapCombatPreviewR131.isUsableByActorR131(restricted, actorID: "C_FAMILIAR"))
    }

    func testUniversalCatalogGearMatchesActualEquipAndResolve() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let catalog = try catalogWithUniversalAmulet(profile.catalog)
        let id = UUID(uuidString: "13100000-0000-4000-8000-000000000031")!
        var state = try profile.makeNewSnapshot()
        state.completedEncounterIDs.insert("B_R05_B")
        let slots = try profile.latentPolicy.generateNewInstanceSlots(templateID: "EQ_AMU_01",
            joinedActorIDs: Set(state.partyActorIDs), operationID: id, domainSalt: "r131-universal-test")
        state.gear.append(GearInstance(id: id, definitionID: "EQ_AMU_01", ownerID: nil,
                                       candidateLatentSlots: slots))
        XCTAssertNil(state.equippedGearIDs["C_WITCH|amulet"])
        let previewSaves = try SaveRepository(initial: state)
        let actualSaves = try SaveRepository(initial: state)
        func engine(_ saves: SaveRepository) throws -> GameEngine {
            try GameEngine(catalog: catalog, saves: saves, candidateCombatOverlay: profile.combatOverlay,
                           candidateCharacterGrowth: profile.growth, candidateLatentPolicy: profile.latentPolicy)
        }
        let previewEngine = try engine(previewSaves)
        let actualEngine = try engine(actualSaves)
        let preview = try previewEngine.previewChallengeGearSwapR131(challengeID: challenges[0], actorID: "C_WITCH",
            selectedGearID: id, seed: seeds[2], snapshot: state)
        XCTAssertNil(preview.currentGearID)
        XCTAssertEqual(preview.slot, "amulet")
        let equip = try await actualEngine.dispatch(.equip(gearID: id, actorID: "C_WITCH"),
            operationID: UUID(), expectedRevision: state.revision)
        _ = try await actualEngine.dispatch(.resolveChallenge(challengeID: challenges[0], seed: seeds[2]),
            operationID: UUID(), expectedRevision: equip.revision)
        let actualSnapshot = await actualSaves.snapshot()
        let actual = try XCTUnwrap(actualSnapshot.lastCombatResult)
        XCTAssertEqual(preview.result, actual)
    }

    private func unlocked(_ input: GameSnapshot) -> GameSnapshot {
        var copy = input
        copy.completedEncounterIDs.insert("B_R05_B")
        return copy
    }

    private func addOwnedGear(_ definitionID: String, owner: String?, to state: inout GameSnapshot,
                              profile: GameRuntimeConfigurationR098, uuid: String) throws -> UUID {
        let id = try XCTUnwrap(UUID(uuidString: uuid))
        let slots = try profile.latentPolicy.generateNewInstanceSlots(
            templateID: definitionID, joinedActorIDs: Set(state.partyActorIDs),
            operationID: id, domainSalt: "r131-preview-test")
        state.gear.append(GearInstance(id: id, definitionID: definitionID, ownerID: owner,
                                       candidateLatentSlots: slots))
        return id
    }

    private func canonicalBytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func catalogWithUniversalAmulet(_ catalog: GameCatalog) throws -> GameCatalog {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(catalog)) as? [String: Any])
        var copy = object
        var gears = try XCTUnwrap(copy["gear"] as? [[String: Any]])
        let index = try XCTUnwrap(gears.firstIndex(where: { $0["id"] as? String == "EQ_AMU_01" }))
        gears[index]["actorIDs"] = [String]()
        copy["gear"] = gears
        return try JSONDecoder().decode(GameCatalog.self, from: JSONSerialization.data(withJSONObject: copy))
    }


    private func requiredOutputRoot() throws -> URL {
        let raw: String
        if let configured = ProcessInfo.processInfo.environment["WITCH_R131_R002_OUTPUT_ROOT"] {
            raw = configured
        } else {
            // Standalone test runs retain their own fresh fixture directory.
            let retained = FileManager.default.temporaryDirectory.appendingPathComponent("witch-r131-fixtures-" + UUID().uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: false)
            raw = retained.path
        }
        guard raw.hasPrefix("/"), URL(fileURLWithPath: raw).path == raw else {
            throw NSError(domain: "R131", code: 2, userInfo: [NSLocalizedDescriptionKey: "output root must be canonical absolute path"])
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
