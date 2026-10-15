import Foundation

/// A transient route from an unmet permanent-research cost to one catalog source.
/// Resolving this value is read-only; it does not change a gather target or settle work.
public struct ResearchGatherHandoffR310: Equatable, Sendable {
    public let researchID: String
    public let materialID: String
    public let regionID: String

    public init(researchID: String, materialID: String, regionID: String) {
        self.researchID = researchID
        self.materialID = materialID
        self.regionID = regionID
    }
}

/// Resolves a proposed research-to-gather route against the current catalog and snapshot.
/// Source availability is delegated to R280 so preview and normal gather selection share rules.
public enum ResearchGatherRouteR310 {
    public struct Preview: Equatable, Sendable {
        public let route: ResearchGatherHandoffR310
        public let researchName: String
        public let regionName: String
        public let missing: Int

        public init(route: ResearchGatherHandoffR310, researchName: String,
                    regionName: String, missing: Int) {
            self.route = route
            self.researchName = researchName
            self.regionName = regionName
            self.missing = missing
        }
    }

    /// Returns a preview only when the exact research/material/region route is currently valid.
    /// A research's own boss gate is intentionally independent of material-source availability.
    public static func resolve(_ route: ResearchGatherHandoffR310,
                               catalog: GameCatalog?, state: GameSnapshot) -> Preview? {
        guard let catalog,
              !route.researchID.isEmpty, !route.materialID.isEmpty, !route.regionID.isEmpty,
              !state.completedResearchIDs.contains(route.researchID) else { return nil }
        let researches = catalog.research.filter { $0.id == route.researchID }
        guard researches.count == 1, let research = researches.first else { return nil }
        let requirements = ResearchMaterialGuidanceR280.project(
            catalog: catalog, state: state, research: research
        ).filter { $0.materialID == route.materialID }
        guard requirements.count == 1, let requirement = requirements.first,
              requirement.missing > 0,
              case .regions(let sources) = requirement.availability else { return nil }
        let matchingSources = sources.filter { $0.regionID == route.regionID }
        guard matchingSources.count == 1, let source = matchingSources.first,
              case .available = source.status else { return nil }
        return Preview(route: route, researchName: research.name,
                       regionName: source.regionName, missing: requirement.missing)
    }
}
