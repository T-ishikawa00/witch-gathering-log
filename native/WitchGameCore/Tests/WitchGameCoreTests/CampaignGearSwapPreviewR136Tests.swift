import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

final class CampaignGearSwapPreviewR136Tests: XCTestCase {
    private let seed: UInt64 = 136_001

    func testAvailableTargetsAndPrerequisitesUseActiveUnlockedRegion() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let state = try profile.makeNewSnapshot()
        let engine = try profile.makeEngine(saves: SaveRepository(initial: state))
        let region = try XCTUnwrap(profile.catalog.regions.first(where: { $0.id == state.activeRegionID }))
        let listed = engine.availableCampaignGearTrialEnemiesR136(snapshot: state)
        XCTAssertEqual(listed.map(\.id), region.enemyIDs.filter { id in
            profile.catalog.enemies.first(where: { $0.id == id })?.prerequisiteEncounterID == nil
        })
        XCTAssertFalse(listed.isEmpty)
        let gated = try XCTUnwrap(profile.catalog.enemies.first(where: {
            $0.regionID == region.id && $0.prerequisiteEncounterID != nil
        }))
        XCTAssertFalse(listed.contains(where: { $0.id == gated.id }))
        var cleared = state
        cleared.completedEncounterIDs.insert(try XCTUnwrap(gated.prerequisiteEncounterID))
        XCTAssertTrue(engine.availableCampaignGearTrialEnemiesR136(snapshot: cleared).contains(where: { $0.id == gated.id }))

        var locked = state
        locked.unlockedRegionIDs.remove(region.id)
        XCTAssertTrue(engine.availableCampaignGearTrialEnemiesR136(snapshot: locked).isEmpty)
        var noRegion = state
        noRegion.activeRegionID = nil
        XCTAssertTrue(engine.availableCampaignGearTrialEnemiesR136(snapshot: noRegion).isEmpty)
    }

    func testCampaignPreviewMatchesActualEquipAndEncounterAndPreservesSaveBytes() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        var state = try profile.makeNewSnapshot()
        // Controlled reachable R03 state selects the real R014 overlay target,
        // so parity covers the campaign magnet/action-pattern branch as well.
        state.activeRegionID = "R03"
        state.unlockedRegionIDs.insert("R03")
        state.completedEncounterIDs.insert("B_R02_B")
        let enemy = try XCTUnwrap(profile.catalog.enemies.first(where: { $0.id == "E_R03_04" }))
        let gearID = try addGear("EQ_W_G1", to: &state, profile: profile)
        let root = try outputRoot()
        let directory = root.appendingPathComponent("campaign_preview_" + UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let previewURL = directory.appendingPathComponent("preview-save.json")
        let actualURL = directory.appendingPathComponent("actual-save.json")
        try writeInitialSave(state, to: previewURL)
        try writeInitialSave(state, to: actualURL)
        let previewSaves = try SaveRepository(initial: state, fileURL: previewURL)
        let actualSaves = try SaveRepository(initial: state, fileURL: actualURL)
        let previewEngine = try profile.makeEngine(saves: previewSaves)
        let actualEngine = try profile.makeEngine(saves: actualSaves)
        let bytesBefore = try Data(contentsOf: previewURL)
        let stateBefore = await previewSaves.snapshot()

        let preview = try previewEngine.previewCampaignGearSwapR136(enemyID: enemy.id,
            actorID: "C_WITCH", selectedGearID: gearID, seed: seed, snapshot: state)
        XCTAssertEqual(preview.enemyID, enemy.id)
        XCTAssertEqual(preview.slot, "weapon")
        XCTAssertEqual(preview.seed, seed)
        XCTAssertFalse(preview.result.events.isEmpty)
        XCTAssertEqual(GearSwapCombatSummaryR131.make(from: preview).ticks, preview.result.ticks)
        XCTAssertEqual(try Data(contentsOf: previewURL), bytesBefore,
                       "Campaign preview must not rewrite even receipt-bearing save bytes")
        let afterPreview = await previewSaves.snapshot()
        XCTAssertEqual(afterPreview, stateBefore)
        XCTAssertEqual(try Data(contentsOf: previewURL), bytesBefore)

        let equipped = try await actualEngine.dispatch(.equip(gearID: gearID, actorID: "C_WITCH"),
            operationID: UUID(), expectedRevision: state.revision)
        _ = try await actualEngine.dispatch(.resolveEncounter(enemyID: enemy.id, seed: seed),
            operationID: UUID(), expectedRevision: equipped.revision)
        let actualSnapshot = await actualSaves.snapshot()
        let actual = try XCTUnwrap(actualSnapshot.lastCombatResult)
        XCTAssertEqual(preview.result, actual,
            "Preview must match the actual campaign dispatcher with same snapshot, gear, seed, and runtime configuration")
    }

    func testUnknownLockedWrongRegionAndPrerequisiteTargetsFailClosed() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let state = try profile.makeNewSnapshot()
        let gearID = try XCTUnwrap(state.equippedGearIDs["C_WITCH|weapon"])
        let engine = try profile.makeEngine(saves: SaveRepository(initial: state))
        XCTAssertThrowsError(try engine.previewCampaignGearSwapR136(enemyID: "NO_SUCH_ENEMY",
            actorID: "C_WITCH", selectedGearID: gearID, seed: seed, snapshot: state)) {
            XCTAssertEqual($0 as? CampaignGearTrialErrorR136, .unknownEnemy)
        }
        let otherRegionEnemy = try XCTUnwrap(profile.catalog.enemies.first(where: { $0.regionID != state.activeRegionID }))
        XCTAssertThrowsError(try engine.previewCampaignGearSwapR136(enemyID: otherRegionEnemy.id,
            actorID: "C_WITCH", selectedGearID: gearID, seed: seed, snapshot: state)) {
            XCTAssertEqual($0 as? CampaignGearTrialErrorR136, .enemyOutsideActiveRegion)
        }
        var locked = state
        let otherRegion = try XCTUnwrap(profile.catalog.regions.first(where: { $0.id == otherRegionEnemy.regionID }))
        locked.activeRegionID = otherRegion.id
        locked.unlockedRegionIDs.remove(otherRegion.id)
        XCTAssertThrowsError(try engine.previewCampaignGearSwapR136(enemyID: otherRegionEnemy.id,
            actorID: "C_WITCH", selectedGearID: gearID, seed: seed, snapshot: locked)) {
            XCTAssertEqual($0 as? CampaignGearTrialErrorR136, .activeRegionLocked)
        }
        let gated = try XCTUnwrap(profile.catalog.enemies.first(where: {
            $0.regionID == state.activeRegionID && $0.prerequisiteEncounterID != nil
        }))
        let requiredEncounter = try XCTUnwrap(gated.prerequisiteEncounterID)
        XCTAssertThrowsError(try engine.previewCampaignGearSwapR136(enemyID: gated.id,
            actorID: "C_WITCH", selectedGearID: gearID, seed: seed, snapshot: state)) {
            XCTAssertEqual($0 as? CampaignGearTrialErrorR136, .prerequisiteNotCleared(requiredEncounter))
        }
    }

    func testEmptyGearSlotAndUnassignedOwnedGearArePreviewable() async throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        var state = try profile.makeNewSnapshot()
        let enemy = try XCTUnwrap(profile.catalog.enemies.first(where: {
            $0.regionID == state.activeRegionID && $0.prerequisiteEncounterID == nil
        }))
        let gearID = try addGear("EQ_AMU_01", to: &state, profile: profile)
        let key = "C_WITCH|amulet"
        XCTAssertNil(state.equippedGearIDs[key])
        let engine = try profile.makeEngine(saves: SaveRepository(initial: state))
        let before = state
        let preview = try engine.previewCampaignGearSwapR136(enemyID: enemy.id,
            actorID: "C_WITCH", selectedGearID: gearID, seed: seed, snapshot: state)
        XCTAssertNil(preview.currentGearID)
        XCTAssertEqual(preview.slot, "amulet")
        let after = await engine.snapshot()
        XCTAssertEqual(after, before)
    }

    private func addGear(_ definitionID: String, to state: inout GameSnapshot,
                         profile: GameRuntimeConfigurationR098) throws -> UUID {
        let id = UUID()
        let latent = try profile.latentPolicy.generateNewInstanceSlots(templateID: definitionID,
            joinedActorIDs: Set(state.partyActorIDs), operationID: id, domainSalt: "r136-campaign-preview")
        state.gear.append(GearInstance(id: id, definitionID: definitionID, ownerID: nil,
                                       candidateLatentSlots: latent))
        return id
    }

    private func writeInitialSave(_ state: GameSnapshot, to url: URL) throws {
        let recovery = SaveRecoveryStatus(source: .memory, loadedGeneration: 0, loadedRevision: state.revision,
            rejectedPrimaryRevision: nil, rejectedPrimaryByteCount: nil, preservedRejectedPrimaryFilename: nil)
        let encoded = try SaveDocumentCodec.encode(snapshot: state, receipts: [:], generation: 0,
            recoveryStatus: recovery, preserving: nil, priorModelledData: nil)
        try encoded.data.write(to: url, options: .withoutOverwriting)
    }

    private func outputRoot() throws -> URL {
        if let raw = ProcessInfo.processInfo.environment["WITCH_R136_OUTPUT_ROOT"] {
            guard raw.hasPrefix("/"), URL(fileURLWithPath: raw).path == raw else {
                throw NSError(domain: "R136", code: 2, userInfo: [NSLocalizedDescriptionKey: "output root must be an absolute canonical path"])
            }
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        // Keep the focused XCTest usable in an ordinary `swift test` run.
        // A unique parent prevents fixture/output collisions across runs.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("witch-r136-campaign-trial-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
