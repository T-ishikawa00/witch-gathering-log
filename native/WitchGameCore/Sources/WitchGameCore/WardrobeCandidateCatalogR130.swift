import Foundation

/// One additive, local R130 candidate. The base catalog and R128 gate are untouched.
public enum WardrobeCandidateCatalogR130 {
    public static let flag = "--qa-aira-apron-r130"
    public static let appearanceID = "AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130"
    public static let sceneKey = "WARDROBE_CANDIDATE_AIRA_R130"
    public static let iconID = "AIRA__rest_00"

    public static func enabled(arguments: [String], developmentEnabled: Bool = false) -> Bool {
        developmentEnabled || (WardrobeCandidateCatalogR128.enabled(arguments: arguments) && arguments.contains(flag))
    }

    public static func extending(_ r128Catalog: GameCatalog) throws -> GameCatalog {
        guard !r128Catalog.appearances.contains(where: { $0.id == appearanceID }) else {
            throw CoreError.invalidCatalog("R130 AIRA candidate appearance ID already exists")
        }
        let appearance = AppearanceDefinition(id: appearanceID, kind: "costume", actorIDs: ["C_SMITH"],
            status: "UNAPPROVED_LOCAL_QA_CANDIDATE_NOT_FOR_SALE")
        let result = GameCatalog(version: r128Catalog.version + "+R130_AIRA_CANDIDATE",
            regions: r128Catalog.regions, enemies: r128Catalog.enemies, gear: r128Catalog.gear,
            research: r128Catalog.research, materialIDs: r128Catalog.materialIDs,
            materialAvailabilityGates: r128Catalog.materialAvailabilityGates, recipes: r128Catalog.recipes,
            actorIDs: r128Catalog.actorIDs, challenges: r128Catalog.challenges,
            researchEffects: r128Catalog.researchEffects, appearances: r128Catalog.appearances + [appearance],
            furnitureIDs: r128Catalog.furnitureIDs, dailyFreeTicketGrant: r128Catalog.dailyFreeTicketGrant,
            authority: r128Catalog.authority, gearAttackBonuses: r128Catalog.gearAttackBonuses,
            gearHPBonuses: r128Catalog.gearHPBonuses, gearDefenseBonuses: r128Catalog.gearDefenseBonuses,
            gachaOddsBasisPoints: r128Catalog.gachaOddsBasisPoints)
        try result.validate()
        guard result.gear.map(\.id) == r128Catalog.gear.map(\.id),
              result.authority == r128Catalog.authority,
              result.gearAttackBonuses == r128Catalog.gearAttackBonuses,
              result.gearHPBonuses == r128Catalog.gearHPBonuses,
              result.gearDefenseBonuses == r128Catalog.gearDefenseBonuses,
              result.gachaOddsBasisPoints == r128Catalog.gachaOddsBasisPoints,
              result.dailyFreeTicketGrant == r128Catalog.dailyFreeTicketGrant else {
            throw CoreError.invalidCatalog("R130 may append one appearance only")
        }
        return result
    }

    public static func sceneMetadata(base: [String: String], selectedByActor: [String: String],
                                     ownedIDs: Set<String>, catalog: GameCatalog,
                                     arguments: [String], developmentEnabled: Bool = false) -> [String: String] {
        var result = base
        result.removeValue(forKey: sceneKey)
        guard enabled(arguments: arguments, developmentEnabled: developmentEnabled), selectedByActor["C_SMITH"] == appearanceID,
              ownedIDs.contains(appearanceID),
              catalog.appearances.contains(where: { $0.id == appearanceID && $0.kind == "costume" && $0.actorIDs.contains("C_SMITH") }) else { return result }
        result[sceneKey] = appearanceID
        return result
    }

    public static func preview(base: [String: String], actorID: String, appearanceID: String,
                               kind: String, enabled: Bool) -> [String: String] {
        var result = base
        result.removeValue(forKey: sceneKey)
        guard enabled, actorID == "C_SMITH", appearanceID == self.appearanceID, kind == "costume" else { return result }
        result[sceneKey] = self.appearanceID
        return result
    }
}
