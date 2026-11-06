import Foundation

/// Read-only collection/identity projection for the existing Q4 quality.
/// This does not create a new gear family, choose a desired template, or mutate a save.
public struct GearLegendaryCollectionProjectionR384: Equatable, Sendable {
    public enum Route: Equatable, Sendable {
        public enum Period: Equatable, Sendable { case newPeriod, inFlight, followingPeriod }
        case profileDisabled
        case unknownTemplate
        case noActiveRegion
        case regionLocked(String)
        case actorNotJoined
        case craftedDiscoveryRequired
        case recipeGatesRequired([String])
        case eligible(regionID: String, localPoolMember: Bool, period: Period)
    }

    public struct OwnedInstance: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let qualityID: String
        /// Present only when the persisted R350 acquisition record joins this exact UUID.
        public let naturalSourceRegionID: String?
        public var isLegendary: Bool { qualityID == "Q4" }
    }

    public struct QualityFact: Equatable, Sendable {
        public let qualityID: String
        public let label: String
        public let activeLatentSlots: Int?
        public let minimumEffectiveRawQ: Int?
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String { templateID }
        public let templateID: String
        public let name: String
        public let slot: String
        /// The canonical effect IDs declared by the existing gear definition.
        public let typeEffectIDs: [String]
        public let ownedInstances: [OwnedInstance]
        public let route: Route
        public var isQ4Template: Bool { ownedInstances.contains(where: \.isLegendary) }
    }

    public let policyEnabled: Bool
    /// This is the R350 policy identity, not the enclosing runtime-profile identity.
    public let policyID: String
    public let policyFingerprint: String
    public let runtimeProfileID: String
    public let activeRegionID: String?
    public let qualityFacts: [QualityFact]
    public let entries: [Entry]
    /// Unique existing templates with at least one exact owned Q4 instance; no target count is implied.
    public var ownedQ4TemplateCount: Int { entries.filter(\.isQ4Template).count }

    public static func make(
        catalog: GameCatalog,
        state: GameSnapshot,
        policyEnabled: Bool,
        policyID: String = NaturalGearDiscoveryPolicyR350.policyID,
        policyFingerprint: String = NaturalGearDiscoveryPolicyR350().policyFingerprint,
        runtimeProfileID: String = "unavailable",
        latentPolicy: CandidateLatentSlotPolicyR003?
    ) -> Self {
        let q3 = qualityFact("Q3", label: "UR", latentPolicy: latentPolicy)
        let q4 = qualityFact("Q4", label: "LR", latentPolicy: latentPolicy)
        let definitions = Dictionary(catalog.gear.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let naturalRecords = Dictionary(
            state.naturalGearDiscoveryR350?.acquisitionRecords.map { ($0.gearInstanceID, $0) } ?? [],
            uniquingKeysWith: { first, _ in first })
        let ownedByTemplate = Dictionary(grouping: state.gear, by: \.definitionID)
        let poolIDs = Set(NaturalGearDiscoveryPolicyR350.regionPools.values.flatMap { $0 })
        // Include exact owned Q4 templates even if a future/corrupt catalog no longer lists them.
        let q4OwnedIDs = Set(state.gear.filter { $0.qualityID == "Q4" }.map(\.definitionID))
        let templateIDs = poolIDs.union(q4OwnedIDs).sorted()
        let evolvedOutputs = Set(catalog.recipes.filter { $0.kind == "evolve_in_place" }.compactMap(\.outputGearID))
        let discoveredCrafted = state.naturalGearDiscoveryR350?.discoveredCraftedTemplateIDs ?? []

        let entries = templateIDs.map { templateID -> Entry in
            let owned = (ownedByTemplate[templateID] ?? []).map { item in
                OwnedInstance(id: item.id, qualityID: item.qualityID,
                    naturalSourceRegionID: naturalRecords[item.id]?.templateID == item.definitionID
                        ? naturalRecords[item.id]?.sourceRegionID : nil)
            }.sorted {
                if $0.qualityID != $1.qualityID { return $0.qualityID < $1.qualityID }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let definition = definitions[templateID] else {
                return Entry(templateID: templateID, name: templateID, slot: "unknown",
                             typeEffectIDs: [], ownedInstances: owned, route: .unknownTemplate)
            }
            let nextPeriodRoute = routeStatus(
                templateID: templateID, definition: definition, catalog: catalog, state: state,
                policyEnabled: policyEnabled, evolvedOutputs: evolvedOutputs,
                discoveredCrafted: discoveredCrafted, period: .newPeriod)
            let route: Route
            if policyEnabled, let ledger = state.naturalGearDiscoveryR350,
               ledger.workUnitsIntoDrop > 0, let pinned = ledger.pinnedPool {
                if pinned.localEligibleTemplateIDs.contains(templateID) {
                    route = .eligible(regionID: pinned.regionID, localPoolMember: true, period: .inFlight)
                } else if pinned.globalEligibleTemplateIDs.contains(templateID) {
                    route = .eligible(regionID: pinned.regionID, localPoolMember: false, period: .inFlight)
                } else if case .eligible(let regionID, let localPoolMember, _) = nextPeriodRoute {
                    route = .eligible(regionID: regionID, localPoolMember: localPoolMember, period: .followingPeriod)
                } else {
                    route = nextPeriodRoute
                }
            } else {
                route = nextPeriodRoute
            }
            return Entry(templateID: templateID, name: definition.name, slot: definition.slot,
                         typeEffectIDs: definition.effects, ownedInstances: owned, route: route)
        }
        return Self(policyEnabled: policyEnabled, policyID: policyID,
                    policyFingerprint: policyFingerprint, runtimeProfileID: runtimeProfileID,
                    activeRegionID: state.activeRegionID,
                    qualityFacts: [q3, q4], entries: entries)
    }

    private static func qualityFact(
        _ qualityID: String,
        label: String,
        latentPolicy: CandidateLatentSlotPolicyR003?
    ) -> QualityFact {
        let slots: Int?
        let floor: Int?
        if let latentPolicy {
            slots = try? latentPolicy.activeSlotCount(qualityID: qualityID)
            floor = try? latentPolicy.effectiveQ(rawQ: 0, qualityID: qualityID)
        } else {
            slots = nil
            floor = nil
        }
        return QualityFact(qualityID: qualityID, label: label,
                           activeLatentSlots: slots, minimumEffectiveRawQ: floor)
    }

    private static func routeStatus(
        templateID: String,
        definition: GearDefinition,
        catalog: GameCatalog,
        state: GameSnapshot,
        policyEnabled: Bool,
        evolvedOutputs: Set<String>,
        discoveredCrafted: Set<String>,
        period: Route.Period
    ) -> Route {
        guard policyEnabled else { return .profileDisabled }
        guard definition.actorIDs.isEmpty || definition.actorIDs.contains(where: state.partyActorIDs.contains) else {
            return .actorNotJoined
        }
        if evolvedOutputs.contains(templateID), !discoveredCrafted.contains(templateID) {
            return .craftedDiscoveryRequired
        }
        let recipes = catalog.recipes.filter { $0.outputGearID == templateID }
        if !recipes.isEmpty {
            let routeRecipes = recipes.filter {
                $0.kind != "evolve_in_place" || discoveredCrafted.contains(templateID)
            }
            let openRecipeExists = routeRecipes.contains { recipe in
                guard let gateID = recipe.gateID else { return true }
                return gateIsCleared(gateID, completedEncounterIDs: state.completedEncounterIDs)
            }
            if !openRecipeExists {
                let required = Array(Set(routeRecipes.compactMap(\.gateID))).sorted()
                return .recipeGatesRequired(required)
            }
        }
        guard let regionID = state.activeRegionID else { return .noActiveRegion }
        guard state.unlockedRegionIDs.contains(regionID),
              NaturalGearDiscoveryPolicyR350.regionPools[regionID] != nil else {
            return .regionLocked(regionID)
        }
        return .eligible(regionID: regionID,
            localPoolMember: NaturalGearDiscoveryPolicyR350.regionPools[regionID, default: []].contains(templateID),
            period: period)
    }

    private static func gateIsCleared(_ gateID: String, completedEncounterIDs: Set<String>) -> Bool {
        if gateID == "G_START" { return true }
        let parts = gateID.split(separator: "_")
        guard parts.count == 3, parts[0] == "G" else { return false }
        return completedEncounterIDs.contains("B_\(parts[1])_\(parts[2])")
    }
}
