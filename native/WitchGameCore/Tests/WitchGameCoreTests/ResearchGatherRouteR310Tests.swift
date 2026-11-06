import XCTest
@testable import WitchGameCore

final class ResearchGatherRouteR310Tests: XCTestCase {
    func testAvailableRouteReportsCurrentDeficitWithoutChangingSnapshot() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let state = try profile.makeNewSnapshot()
        let (research, materialID, regionID) = try availableCase(profile: profile, state: state)
        let before = state
        let route = ResearchGatherHandoffR310(researchID: research.id, materialID: materialID, regionID: regionID)
        let preview = try XCTUnwrap(ResearchGatherRouteR310.resolve(route, catalog: profile.catalog, state: state))
        XCTAssertEqual(preview.route, route)
        XCTAssertEqual(preview.researchName, research.name)
        XCTAssertEqual(preview.regionName, profile.catalog.regions.first { $0.id == regionID }?.name)
        XCTAssertEqual(preview.missing, research.cost[materialID, default: 0] - state.materials[materialID, default: 0])
        XCTAssertEqual(state, before, "Route preview must not alter progression, target, clock, or any other snapshot field")
    }

    func testLockedRegionAndUnmetSourceGateAreNotRoutable() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let state = try profile.makeNewSnapshot()
        let (research, materialID, regionID) = try availableCase(profile: profile, state: state)
        var regionLocked = state
        regionLocked.unlockedRegionIDs.remove(regionID)
        XCTAssertNil(ResearchGatherRouteR310.resolve(.init(researchID: research.id, materialID: materialID, regionID: regionID), catalog: profile.catalog, state: regionLocked))

        let gated = try gatedCase(profile: profile, state: state)
        XCTAssertNil(ResearchGatherRouteR310.resolve(.init(researchID: gated.research.id, materialID: gated.materialID, regionID: gated.regionID), catalog: profile.catalog, state: gated.state))
    }

    func testCompletedSufficientAndStaleShortageRoutesAreRejected() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let state = try profile.makeNewSnapshot()
        let (research, materialID, regionID) = try availableCase(profile: profile, state: state)
        let route = ResearchGatherHandoffR310(researchID: research.id, materialID: materialID, regionID: regionID)

        var completed = state
        completed.completedResearchIDs.insert(research.id)
        XCTAssertNil(ResearchGatherRouteR310.resolve(route, catalog: profile.catalog, state: completed))

        var sufficient = state
        sufficient.materials[materialID] = research.cost[materialID, default: 0]
        XCTAssertNil(ResearchGatherRouteR310.resolve(route, catalog: profile.catalog, state: sufficient))

        var stale = state
        stale.materials[materialID] = research.cost[materialID, default: 0] + 1
        XCTAssertNil(ResearchGatherRouteR310.resolve(route, catalog: profile.catalog, state: stale))
    }

    func testUnknownAndKnownButUnsourcedMaterialsFailClosed() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let state = try profile.makeNewSnapshot()
        let regionID = try XCTUnwrap(state.activeRegionID)
        let (knownResearch, knownMaterial, knownRegion) = try availableCase(profile: profile, state: state)
        let knownRoute = ResearchGatherHandoffR310(researchID: knownResearch.id, materialID: knownMaterial, regionID: knownRegion)
        XCTAssertNil(ResearchGatherRouteR310.resolve(knownRoute, catalog: nil, state: state))
        XCTAssertNil(ResearchGatherRouteR310.resolve(.init(researchID: "R310_UNKNOWN_RESEARCH", materialID: knownMaterial, regionID: knownRegion), catalog: profile.catalog, state: state))
        XCTAssertNil(ResearchGatherRouteR310.resolve(.init(researchID: knownResearch.id, materialID: "M_R310_MISMATCH", regionID: knownRegion), catalog: profile.catalog, state: state))
        XCTAssertNil(ResearchGatherRouteR310.resolve(.init(researchID: knownResearch.id, materialID: knownMaterial, regionID: "R310_UNKNOWN_REGION"), catalog: profile.catalog, state: state))
        let unknown = ResearchDefinition(id: "R310_UNKNOWN_MATERIAL", name: "Unknown", cost: ["M_R310_UNKNOWN": 1], effectID: "unused")
        let unknownCatalog = copy(profile.catalog, research: [unknown], materialIDs: profile.catalog.materialIDs)
        XCTAssertNil(ResearchGatherRouteR310.resolve(.init(researchID: unknown.id, materialID: "M_R310_UNKNOWN", regionID: regionID), catalog: unknownCatalog, state: state))

        let unsourced = ResearchDefinition(id: "R310_UNSOURCED_MATERIAL", name: "Unsourced", cost: ["M_R310_UNSOURCED": 1], effectID: "unused")
        let unsourcedCatalog = copy(profile.catalog, research: [unsourced], materialIDs: profile.catalog.materialIDs + ["M_R310_UNSOURCED"])
        XCTAssertNil(ResearchGatherRouteR310.resolve(.init(researchID: unsourced.id, materialID: "M_R310_UNSOURCED", regionID: regionID), catalog: unsourcedCatalog, state: state))
    }

    func testResearchBossGateDoesNotHideAnOtherwiseAvailableMaterialSource() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let state = try profile.makeNewSnapshot()
        let (research, materialID, regionID) = try availableCase(profile: profile, state: state)
        let lockedGate = "G_R05_B"
        XCTAssertFalse(state.completedEncounterIDs.contains("B_R05_B"))
        let originalRecipe = try XCTUnwrap(profile.catalog.recipes.first { $0.id == research.id },
            "The catalog must model the separate unlock gate used by ResearchView")
        let recipes = profile.catalog.recipes.map { recipe in
            recipe.id == research.id
                ? RecipeDefinition(id: recipe.id, outputGearID: recipe.outputGearID, costs: recipe.costs,
                    status: recipe.status, kind: recipe.kind, dustCost: recipe.dustCost,
                    parentTemplateID: recipe.parentTemplateID, gateID: lockedGate,
                    qualityFrom: recipe.qualityFrom, qualityTo: recipe.qualityTo)
                : recipe
        }
        XCTAssertNotEqual(originalRecipe.gateID, lockedGate)
        let catalog = copy(profile.catalog, recipes: recipes)
        let preview = ResearchGatherRouteR310.resolve(.init(researchID: research.id, materialID: materialID, regionID: regionID), catalog: catalog, state: state)
        XCTAssertNotNil(preview, "Source access must remain independent from the study's separate boss gate")
    }

    private func availableCase(profile: GameRuntimeConfigurationR098, state: GameSnapshot) throws -> (ResearchDefinition, String, String) {
        for research in profile.catalog.research {
            for requirement in ResearchMaterialGuidanceR280.project(catalog: profile.catalog, state: state, research: research) {
                guard case .regions(let sources) = requirement.availability,
                      let source = sources.first(where: { if case .available = $0.status { return true }; return false }) else { continue }
                return (research, requirement.materialID, source.regionID)
            }
        }
        throw NSError(domain: "ResearchGatherRouteR310Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "No actual catalog research source is available in the fresh profile"])
    }

    private func gatedCase(profile: GameRuntimeConfigurationR098, state: GameSnapshot) throws -> (research: ResearchDefinition, materialID: String, regionID: String, state: GameSnapshot) {
        for research in profile.catalog.research {
            for requirement in ResearchMaterialGuidanceR280.project(catalog: profile.catalog, state: state, research: research) {
                guard case .regions(let sources) = requirement.availability,
                      let source = sources.first(where: { if case .sourceGateLocked = $0.status { return true }; return false }),
                      let gate = profile.catalog.materialAvailabilityGates[requirement.materialID], gate != "G_START" else { continue }
                let parts = gate.split(separator: "_")
                guard parts.count == 3, parts[0] == "G" else { continue }
                var gatedState = state
                gatedState.unlockedRegionIDs.insert(source.regionID)
                gatedState.completedEncounterIDs.remove("B_\(parts[1])_\(parts[2])")
                return (research, requirement.materialID, source.regionID, gatedState)
            }
        }
        throw NSError(domain: "ResearchGatherRouteR310Tests", code: 2, userInfo: [NSLocalizedDescriptionKey: "No actual catalog source-gated research material was found"])
    }

    private func copy(_ c: GameCatalog, research: [ResearchDefinition]? = nil,
                      materialIDs: [String]? = nil, recipes: [RecipeDefinition]? = nil) -> GameCatalog {
        GameCatalog(version: c.version, regions: c.regions, enemies: c.enemies,
            gear: c.gear, research: research ?? c.research, materialIDs: materialIDs ?? c.materialIDs,
            materialAvailabilityGates: c.materialAvailabilityGates, recipes: recipes ?? c.recipes,
            actorIDs: c.actorIDs, challenges: c.challenges, researchEffects: c.researchEffects,
            appearances: c.appearances, furnitureIDs: c.furnitureIDs,
            dailyFreeTicketGrant: c.dailyFreeTicketGrant, authority: c.authority,
            gearAttackBonuses: c.gearAttackBonuses, gearHPBonuses: c.gearHPBonuses,
            gearDefenseBonuses: c.gearDefenseBonuses, gachaOddsBasisPoints: c.gachaOddsBasisPoints)
    }
}
