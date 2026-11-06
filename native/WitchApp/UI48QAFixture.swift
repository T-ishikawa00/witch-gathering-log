import Foundation

/// Synthetic, in-memory save states for isolated UI48 capture and interaction QA.
/// The caller must pass an already-validated UI48QALaunchGate before invoking this factory.
@MainActor
enum UI48QAFixture {
    enum FixtureError: Error {
        case unknownKind(String)
        case missingInitialRegion
        case missingInitialGatherTarget
    }

    static func make(catalog: GameCatalog,
                     runtime: GameRuntimeConfigurationR098,
                     kind: String) async throws -> GameSnapshot {
        guard ["fresh", "full", "empty", "many", "gathering", "frontier"].contains(kind) else {
            throw FixtureError.unknownKind(kind)
        }

        var state = try runtime.makeNewSnapshot()
        guard let initialRegion = catalog.regions.first(where: { $0.id == state.activeRegionID })
                ?? catalog.regions.first else { throw FixtureError.missingInitialRegion }
        guard let initialMaterial = initialRegion.gatherMaterialIDs.first else {
            throw FixtureError.missingInitialGatherTarget
        }

        // Fresh saves keep the canonical R098 shape. GameModel's established
        // R169 fresh-save preparation commits the shared-work marker and clock.
        if kind == "fresh" { return state }

        state.activeRegionID = initialRegion.id
        state.gatherTargetMaterialID = initialMaterial
        state.partyWorkTargetR144 = .gather(initialMaterial)
        state.lastClaimAt = Date()
        state.offlineRemainderSeconds = 0
        state.mockPurchaseRecords = [:]
        state.pendingPurchaseIDs = []
        state.localStoreKitQARecords = [:]
        state.localStoreKitQAOwnedProductIDs = []
        state.localAdSkipEntitledForQA = false
        state.gearLoadoutsR342 = nil

        switch kind {
        case "empty":
            state.gear = []
            state.equippedGearIDs = [:]
            state.gearLoadoutsR342 = nil
            state.trackedRecipeID = nil
            state.ownedCosmeticIDs = []
            state.ownedFurnitureIDs = []
            state.placedFurnitureIDs = []
            state.currency["ticket_paid_mock"] = 0

        case "many":
            appendGear(to: &state, catalog: catalog, count: 600)
            state.materials = Dictionary(uniqueKeysWithValues: catalog.materialIDs.map { ($0, 250) })
            state.currency["coin"] = 25_000

        case "gathering":
            state.lastClaimAt = Date().addingTimeInterval(-3_600)

        case "frontier":
            // Synthetic pre-boss setup for real unlock/challenge interaction QA.
            // The boss clear and next-region unlock must still be earned through
            // the ordinary battle command; never used by a normal play save.
            state.unlockedRegionIDs = [initialRegion.id]
            state.completedEncounterIDs = Set(catalog.enemies.filter {
                $0.regionID == initialRegion.id && !$0.boss
            }.map(\.id))
            for actor in state.partyActorIDs { state.characterXP[actor] = 20_000 }
            for index in state.gear.indices {
                state.gear[index].qualityID = "Q4"
                state.gear[index].enhancement = 5
            }

        case "full":
            state.ownedCosmeticIDs = Set(catalog.appearances.map(\.id))
            state.ownedFurnitureIDs = Set(catalog.furnitureIDs)
            state.unlockedRegionIDs = Set(catalog.regions.map(\.id))
            state.completedEncounterIDs = Set(catalog.enemies.map(\.id))
            state.completedResearchIDs = []
            state.materials = Dictionary(uniqueKeysWithValues: catalog.materialIDs.map { ($0, 2_000) })
            // Refinement dust is a legacy Core material outside catalog.materialIDs.
            // Supply it only in this explicit isolated full-feature fixture.
            state.materials["refine_dust"] = 2_000
            state.currency["coin"] = 25_000
            state.currency["ticket_free"] = max(state.currency["ticket_free", default: 0], 5)
            state.currency["ticket_paid_mock"] = 0
            state.gearComparisonSeen = true
            state.craftedGearOnce = true
            state.gachaUnlocked = true
            state.trackedRecipeID = catalog.recipes.first(where: { $0.kind == "craft_new" })?.id
            appendGear(to: &state, catalog: catalog, count: max(catalog.gear.count * 2, 24))

        default:
            break
        }

        return state
    }

    private static func appendGear(to state: inout GameSnapshot,
                                   catalog: GameCatalog,
                                   count: Int) {
        guard !catalog.gear.isEmpty, count > 0 else { return }
        var instances = state.gear
        let quality = ["Q0", "Q1", "Q2", "Q3", "Q4"]

        for index in 0..<count {
            let definition = catalog.gear[index % catalog.gear.count]
            instances.append(GearInstance(
                definitionID: definition.id,
                ownerID: nil,
                protected: false,
                enhancement: index % 4,
                refinement: index % 3,
                qualityID: quality[index % quality.count]
            ))
        }
        state.gear = instances
    }
}
