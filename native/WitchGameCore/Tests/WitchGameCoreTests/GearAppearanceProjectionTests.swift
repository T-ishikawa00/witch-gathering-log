import XCTest
@testable import WitchGameCore

final class GearAppearanceProjectionTests: XCTestCase {
    func testBaseBranchStaffMapsToCandidateSpriteOnlyWhenEquipped() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let instance = GearInstance(definitionID: "EQ_W_01", ownerID: "C_WITCH")
        var snapshot = GameSnapshot(gear: [instance], equippedGearIDs: ["C_WITCH|weapon": instance.id])

        let projection = try XCTUnwrap(catalog.gearAppearanceProjection(for: instance, actorID: "C_WITCH", in: snapshot))
        XCTAssertTrue(projection.isEquipped)
        XCTAssertEqual(projection.iconAssetID, "ICO_EQ_W_01")
        XCTAssertEqual(projection.visualScope, .iconAndLaterAttachment)
        XCTAssertEqual(projection.gearAttachmentAssetID, "STAFF_EQ_W_01")
        XCTAssertEqual(projection.resolvedWeaponSpriteAssetID, "STAFF_EQ_W_01")

        snapshot.equippedGearIDs.removeValue(forKey: "C_WITCH|weapon")
        let unequipped = try XCTUnwrap(catalog.gearAppearanceProjection(for: instance, actorID: "C_WITCH", in: snapshot))
        XCTAssertFalse(unequipped.isEquipped)
        XCTAssertNil(unequipped.gearAttachmentAssetID)
        XCTAssertNil(unequipped.resolvedWeaponSpriteAssetID)
    }

    func testFourAdvancedWitchStaffMappingsResolveAndRemainCosmeticIndependent() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let ids = ["EQ_W_P1", "EQ_W_P2", "EQ_W_G1", "EQ_W_G2"]
        for gearID in ids {
            let item = GearInstance(definitionID: gearID, ownerID: "C_WITCH")
            var snapshot = GameSnapshot(gear: [item], equippedGearIDs: ["C_WITCH|weapon": item.id])
            let normal = try XCTUnwrap(catalog.gearAppearanceProjection(for: item, actorID: "C_WITCH", in: snapshot))
            XCTAssertEqual(normal.gearAttachmentAssetID, "STAFF_\(gearID)")
            XCTAssertEqual(normal.resolvedWeaponSpriteAssetID, "STAFF_\(gearID)")
            snapshot.ownedCosmeticIDs.insert("STAFF_MOON")
            snapshot.selectedWeaponAppearanceIDs["C_WITCH"] = "STAFF_MOON"
            let overridden = try XCTUnwrap(catalog.gearAppearanceProjection(for: item, actorID: "C_WITCH", in: snapshot))
            XCTAssertEqual(overridden.gearID, gearID)
            XCTAssertEqual(overridden.gearAttachmentAssetID, "STAFF_\(gearID)")
            XCTAssertEqual(overridden.selectedWeaponAppearanceID, "STAFF_MOON")
            XCTAssertEqual(overridden.resolvedWeaponSpriteAssetID, "STAFF_MOON")
        }
    }

    func testOwnedWeaponAppearanceOverridesSpriteWithoutChangingGearIdentity() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let instance = GearInstance(definitionID: "EQ_W_01", ownerID: "C_WITCH")
        var snapshot = GameSnapshot(gear: [instance], equippedGearIDs: ["C_WITCH|weapon": instance.id])
        snapshot.ownedCosmeticIDs.insert("STAFF_MOON")
        snapshot.selectedWeaponAppearanceIDs["C_WITCH"] = "STAFF_MOON"

        let projection = try XCTUnwrap(catalog.gearAppearanceProjection(for: instance, actorID: "C_WITCH", in: snapshot))
        XCTAssertEqual(projection.gearID, "EQ_W_01")
        XCTAssertEqual(projection.gearAttachmentAssetID, "STAFF_EQ_W_01")
        XCTAssertEqual(projection.selectedWeaponAppearanceID, "STAFF_MOON")
        XCTAssertEqual(projection.resolvedWeaponSpriteAssetID, "STAFF_MOON")
    }

    func testOtherWeaponsDoNotInferWornSpriteFromTheirInventoryIcon() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let instance = GearInstance(definitionID: "EQ_A_01", ownerID: "C_APPRENTICE")
        let snapshot = GameSnapshot(gear: [instance], equippedGearIDs: ["C_APPRENTICE|weapon": instance.id])

        let projection = try XCTUnwrap(catalog.gearAppearanceProjection(for: instance, actorID: "C_APPRENTICE", in: snapshot))
        XCTAssertEqual(projection.visualScope, .iconAndLaterAttachment)
        XCTAssertEqual(projection.iconAssetID, "ICO_EQ_A_01")
        XCTAssertNil(projection.gearAttachmentAssetID)
        XCTAssertNil(projection.resolvedWeaponSpriteAssetID)
    }

    func testR4SmallDetailAndHammerBlockedScopesAreExplicit() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let body = GearInstance(definitionID: "EQ_BODY_02", ownerID: "C_WITCH")
        let hammer = GearInstance(definitionID: "EQ_S_01", ownerID: "C_SMITH")
        let bodyProjection = try XCTUnwrap(catalog.gearAppearanceProjection(for: body, actorID: "C_WITCH", in: GameSnapshot(gear: [body])))
        let hammerProjection = try XCTUnwrap(catalog.gearAppearanceProjection(for: hammer, actorID: "C_SMITH", in: GameSnapshot(gear: [hammer])))
        XCTAssertEqual(bodyProjection.visualScope, .iconAndSmallDetailOnly)
        XCTAssertNil(bodyProjection.gearAttachmentAssetID)
        XCTAssertEqual(hammerProjection.visualScope, .iconOnlyAttachmentBlocked)
        XCTAssertNil(hammerProjection.gearAttachmentAssetID)
    }

    func testProjectionRejectsWrongOwnerActorAndNonSnapshotInstances() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let instance = GearInstance(definitionID: "EQ_W_01", ownerID: "C_WITCH")
        let snapshot = GameSnapshot(gear: [instance])
        XCTAssertNil(catalog.gearAppearanceProjection(for: instance, actorID: "C_SMITH", in: snapshot))
        XCTAssertNil(catalog.gearAppearanceProjection(for: GearInstance(definitionID: "EQ_W_01", ownerID: "C_WITCH"), actorID: "C_WITCH", in: snapshot))
    }

    func testAllTwentyNineR4GearTypesUseOnlyDocumentedVisualScopes() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let proposals = Set(["EQ_F_BODY_01", "EQ_F_HAND_01", "EQ_F_FEET_01", "EQ_F_RING_01"])
        let r4 = catalog.gear.filter { !proposals.contains($0.id) }
        XCTAssertEqual(r4.count, 29)
        var mappedIDs = Set<String>()
        for definition in r4 {
            let actorID = try XCTUnwrap(definition.actorIDs.first)
            let item = GearInstance(definitionID: definition.id, ownerID: actorID)
            let slotKey = "\(actorID)|\(definition.slot)"
            let snapshot = GameSnapshot(gear: [item], equippedGearIDs: [slotKey: item.id])
            let projection = try XCTUnwrap(catalog.gearAppearanceProjection(for: item, actorID: actorID, in: snapshot))
            if projection.gearAttachmentAssetID != nil { mappedIDs.insert(definition.id) }
            if definition.id == "EQ_S_01" {
                XCTAssertEqual(projection.visualScope, .iconOnlyAttachmentBlocked)
            } else if ["body", "hands", "feet", "amulet", "ring"].contains(definition.slot) {
                XCTAssertEqual(projection.visualScope, .iconAndSmallDetailOnly)
            } else {
                XCTAssertEqual(projection.visualScope, .iconAndLaterAttachment)
            }
        }
        XCTAssertEqual(mappedIDs, ["EQ_W_01", "EQ_W_P1", "EQ_W_P2", "EQ_W_G1", "EQ_W_G2"], "only the five authored witch-staff candidates have explicit per-instance attachment mappings")
    }

    func testCatGearRemainsOutsideFormalR4VisualScope() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let instance = GearInstance(definitionID: "EQ_F_BODY_01", ownerID: "C_FAMILIAR")
        let projection = try XCTUnwrap(catalog.gearAppearanceProjection(for: instance, actorID: "C_FAMILIAR", in: GameSnapshot(gear: [instance])))
        XCTAssertEqual(projection.visualScope, .unapprovedOutsideR4)
        XCTAssertNil(projection.gearAttachmentAssetID)
    }
}
