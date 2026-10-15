import Foundation

/// Read-only source guidance for unmet permanent-research material costs.
/// It uses the same catalog gate projection as normal gather selection; it never selects a target.
enum ResearchMaterialGuidanceR280 {
    enum SourceStatus {
        case available
        case regionLocked
        case sourceGateLocked

        var label: String {
            switch self {
            case .available: "採集できます"
            case .regionLocked: "地域未解放"
            case .sourceGateLocked: "採集条件未達"
            }
        }
    }

    struct Source: Identifiable {
        let regionID: String
        let regionName: String
        let status: SourceStatus
        var id: String { regionID }
    }

    enum Availability {
        case unknownMaterial
        case noGatherRegion
        case regions([Source])
    }

    struct Requirement: Identifiable {
        let materialID: String
        let missing: Int
        let availability: Availability
        var id: String { materialID }
    }

    static func project(catalog: GameCatalog?, state: GameSnapshot,
                        research: ResearchDefinition) -> [Requirement] {
        guard let catalog, !state.completedResearchIDs.contains(research.id) else { return [] }
        return research.cost.keys.sorted().compactMap { materialID in
            let required = research.cost[materialID, default: 0]
            guard required > 0 else { return nil }
            let owned = max(0, state.materials[materialID, default: 0])
            guard owned < required else { return nil }
            let missing = required - owned
            guard catalog.materialIDs.contains(materialID) else {
                return Requirement(materialID: materialID, missing: missing, availability: .unknownMaterial)
            }
            let regions = catalog.regions.filter { $0.gatherMaterialIDs.contains(materialID) }
            guard !regions.isEmpty else {
                return Requirement(materialID: materialID, missing: missing, availability: .noGatherRegion)
            }
            let sources = regions.map { region -> Source in
                let available = catalog.availableGatherMaterialIDs(
                    in: region.id,
                    unlockedRegionIDs: state.unlockedRegionIDs,
                    completedEncounterIDs: state.completedEncounterIDs
                ).contains(materialID)
                let status: SourceStatus = available ? .available :
                    (state.unlockedRegionIDs.contains(region.id) ? .sourceGateLocked : .regionLocked)
                return Source(regionID: region.id, regionName: region.name, status: status)
            }
            return Requirement(materialID: materialID, missing: missing, availability: .regions(sources))
        }
    }
}
