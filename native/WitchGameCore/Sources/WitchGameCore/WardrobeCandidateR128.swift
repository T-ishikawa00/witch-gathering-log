import Foundation

/// R128 local candidate catalog extension and actor-scoped appearance routing.
/// Candidate rows remain unapproved and not for sale. They are available only
/// under the legacy isolated QA gate or the explicit R169 development capability.
public enum WardrobeCandidateCatalogR128 {
    public static func enabled(arguments: [String], developmentEnabled: Bool = false) -> Bool {
        if developmentEnabled { return true }
        let saveKey = arguments.first(where: { $0.hasPrefix("--qa-save-key=") })
            .map { String($0.dropFirst("--qa-save-key=".count)) }
        return arguments.contains("--qa-isolated") &&
        UUID(uuidString: saveKey ?? "") != nil &&
        arguments.contains(WardrobeCandidateResolverR128.flag) &&
        arguments.contains("--qa-luna-mantle-r097") &&
        arguments.contains("--qa-luna-mantle-offsets-r127") &&
        arguments.contains("--qa-noir-neckwear-r124")
    }

    public static func extending(_ base: GameCatalog) throws -> GameCatalog {
        let additions = [
            AppearanceDefinition(
                id: WardrobeCandidateResolverR128.lunaID,
                kind: "costume",
                actorIDs: ["C_APPRENTICE"],
                status: "UNAPPROVED_LOCAL_QA_CANDIDATE_NOT_FOR_SALE"),
            AppearanceDefinition(
                id: WardrobeCandidateResolverR128.noirID,
                kind: "accessory",
                actorIDs: ["C_FAMILIAR"],
                status: "UNAPPROVED_LOCAL_QA_CANDIDATE_NOT_FOR_SALE")
        ]
        guard Set(base.appearances.map(\.id)).isDisjoint(with: additions.map(\.id)) else {
            throw CoreError.invalidCatalog("R128 candidate appearance ID collides with bundled catalog")
        }
        let candidate = GameCatalog(
            version: base.version + "+R128_LOCAL_CANDIDATES",
            regions: base.regions, enemies: base.enemies, gear: base.gear,
            research: base.research, materialIDs: base.materialIDs,
            materialAvailabilityGates: base.materialAvailabilityGates,
            recipes: base.recipes, actorIDs: base.actorIDs, challenges: base.challenges,
            researchEffects: base.researchEffects, appearances: base.appearances + additions,
            furnitureIDs: base.furnitureIDs, dailyFreeTicketGrant: base.dailyFreeTicketGrant,
            authority: base.authority, gearAttackBonuses: base.gearAttackBonuses,
            gearHPBonuses: base.gearHPBonuses, gearDefenseBonuses: base.gearDefenseBonuses,
            gachaOddsBasisPoints: base.gachaOddsBasisPoints)
        try candidate.validate()
        guard candidate.gear.map(\.id) == base.gear.map(\.id),
              candidate.authority == base.authority,
              candidate.gearAttackBonuses == base.gearAttackBonuses,
              candidate.gearHPBonuses == base.gearHPBonuses,
              candidate.gearDefenseBonuses == base.gearDefenseBonuses,
              candidate.gachaOddsBasisPoints == base.gachaOddsBasisPoints,
              candidate.dailyFreeTicketGrant == base.dailyFreeTicketGrant else {
            throw CoreError.invalidCatalog("R128 may extend appearances only")
        }
        return candidate
    }
}


/// Resolver for explicit local appearance candidates. This is not a commerce,
/// unlock, or default-appearance policy. Callers validate ownership through
/// GameEngine and pass the QA gate or the R169 development capability.
public enum WardrobeCandidateResolverR128 {
    public static let flag = "--qa-wardrobe-candidate-r128"
    public static let lunaID = "LUNA_MANTLE_CANDIDATE_R128"
    public static let lunaValue = "LUNA_MANTLE_GREEN_WORK_MANTLE_CANDIDATE"
    public static let noirID = "NOIR_NECKWEAR_MOSS_R001"
    public static let lunaSceneKey = "WARDROBE_CANDIDATE_LUNA_R128"
    public static let noirSceneKey = "WARDROBE_CANDIDATE_NOIR_R128"
    public static let lunaAppearanceKey = "LUNA_MANTLE_R097"
    public static let lunaBooklessRenderValue = "LUNA_MANTLE_GREEN_WORK_MANTLE_CANDIDATE"

    public static func iconAssetID(for id: String) -> String? {
        switch id {
        case lunaID: return "LUNA_MANTLE_BODY_LAYER_R001"
        case noirID: return noirID
        default: return nil
        }
    }

    /// Only persisted, owned, correctly scoped selections create scene metadata.
    /// This function is intentionally separate from the selected save dictionary.
    public static func sceneMetadata(
        base: [String: String], selectedByActor: [String: String], ownedIDs: Set<String>,
        catalog: GameCatalog, arguments: [String], developmentEnabled: Bool = false
    ) -> [String: String] {
        var result = base
        result.removeValue(forKey: lunaSceneKey)
        result.removeValue(forKey: noirSceneKey)
        result.removeValue(forKey: lunaAppearanceKey)
        guard WardrobeCandidateCatalogR128.enabled(arguments: arguments, developmentEnabled: developmentEnabled) else { return result }
        if selectedByActor["C_APPRENTICE"] == lunaID, ownedIDs.contains(lunaID),
           catalog.appearances.contains(where: { $0.id == lunaID && $0.kind == "costume" && $0.actorIDs.contains("C_APPRENTICE") }) {
            let gearID = base["APPRENTICE_EQUIPPED_WEAPON_ID"]
            if gearID == nil || gearID?.isEmpty == true {
                result[lunaSceneKey] = lunaID
                result[lunaAppearanceKey] = lunaBooklessRenderValue
            } else if ["EQ_A_01", "EQ_A_02", "EQ_A_03"].contains(gearID ?? "") {
                result[lunaSceneKey] = lunaID
                result[lunaAppearanceKey] = lunaValue
            }
        }
        if selectedByActor["C_FAMILIAR"] == noirID, ownedIDs.contains(noirID),
           catalog.appearances.contains(where: { $0.id == noirID && $0.kind == "accessory" && $0.actorIDs.contains("C_FAMILIAR") }) {
            result[noirSceneKey] = noirID
        }
        return result
    }

    public enum LunaRoute: Equatable {
        case disabled
        case unselected
        case unsupportedActorOrCatalog
        case supportedBookRoute
        case embeddedReadingRoute
        case emptyBookSlot
        case unsupportedWeapon
        case inconsistentBookPresentation
        case unknownBodyFrame
    }

    /// Preview maps to the selected actor, unlike R094's original C_WITCH-only
    /// costume projection. It never mutates the snapshot or writes a save.
    public static func preview(
        base: [String: String], actorID: String, appearanceID: String,
        kind: String, enabled: Bool
    ) -> [String: String] {
        var result = base
        guard enabled, appearanceID == lunaID || appearanceID == noirID else { return result }
        switch (actorID, appearanceID, kind) {
        case ("C_APPRENTICE", lunaID, "costume"):
            let gearID = base["APPRENTICE_EQUIPPED_WEAPON_ID"]
            if gearID == nil || gearID?.isEmpty == true {
                result[lunaSceneKey] = lunaID
                result[lunaAppearanceKey] = lunaBooklessRenderValue
            } else if ["EQ_A_01", "EQ_A_02", "EQ_A_03"].contains(gearID ?? "") {
                result[lunaSceneKey] = lunaID
                result[lunaAppearanceKey] = lunaValue
            }
        case ("C_FAMILIAR", noirID, "accessory"):
            result[noirSceneKey] = noirID
        default: break
        }
        return result
    }

    /// LUNA dispatch distinguishes the standard book renderer, embedded-book
    /// reading art, and bookless clips. Unknown gear/frame IDs fail closed.
    public static func lunaRoute(
        enabled: Bool, selectedID: String?, owned: Bool, actorID: String,
        catalogAllowsActor: Bool, equippedBookGearID: String?,
        bodyAssetID: String, localFrameIndex: Int,
        bookNodePresent: Bool, palmNodePresent: Bool
    ) -> LunaRoute {
        guard enabled else { return .disabled }
        guard selectedID != nil else { return .unselected }
        guard actorID == "C_APPRENTICE", selectedID == lunaID, owned, catalogAllowsActor else {
            return .unsupportedActorOrCatalog
        }
        let known = Set(["EQ_A_01", "EQ_A_02", "EQ_A_03"])
        if let gearID = equippedBookGearID, !gearID.isEmpty, !known.contains(gearID) {
            return .unsupportedWeapon
        }
        if bodyAssetID.hasPrefix("LUNA_READING__") {
            guard let readingIndex = lunaReadingIndex(bodyAssetID), readingIndex == localFrameIndex else {
                return .unknownBodyFrame
            }
            // The authored reading texture contains its book; reading hands are
            // a separate scene-level crop, so it intentionally has no book/palm
            // children on the body sprite.
            guard !bookNodePresent && !palmNodePresent else { return .inconsistentBookPresentation }
            return .embeddedReadingRoute
        }
        if let gearID = equippedBookGearID, !gearID.isEmpty {
            guard bookNodePresent && palmNodePresent else { return .inconsistentBookPresentation }
            return .supportedBookRoute
        }
        guard !bookNodePresent && !palmNodePresent else { return .inconsistentBookPresentation }
        guard let poseIndex = lunaPoseIndex(bodyAssetID), poseIndex == localFrameIndex else { return .unknownBodyFrame }
        // R127 registered all three execute paths, including attack_04 frame 1.
        // Continuous motion quality remains a separate review from held-frame routing.
        return .emptyBookSlot
    }

    /// Exact reading body frames are a separate authored presentation: book art
    /// is baked into the texture and hands are rendered in a scene-level crop.
    public static func lunaReadingIndex(_ assetID: String) -> Int? {
        // Accept only the canonical four IDs; Int(String) also accepts forms such
        // as "+0" and whitespace that are not registered asset identities.
        for index in 0...3 where assetID == "LUNA_READING__\(index)" {
            return index
        }
        return nil
    }

    /// The candidate is intentionally restricted to the exact body paths covered
    /// by R127's 27-frame bookless map; frame index must be checked separately.
    public static func lunaPoseIndex(_ path: String) -> Int? {
        for index in 0...8 {
            if path == "GeneratedArt/PartyWalk/LUNA__walk_\(index).png" { return index }
            let ordinal = String(format: "%02d", index)
            if path == "GeneratedArt/PartyRest/LUNA__rest_\(ordinal).png" ||
               path == "GeneratedArt/PartyAttack/LUNA__attack_\(ordinal).png" { return index % 3 }
        }
        return nil
    }

    /// NOIR uses the explicit R003 body path registration whitelist. Motion and
    /// appearance checks remain separate from the accessory's visual approval.
    public static func noirBodyPathSupported(_ path: String) -> Bool {
        let rest = (0...8).map { "GeneratedArt/PartyRest/NOIR__rest_\(String(format: "%02d", $0)).png" }
        let attack = (0...8).map { "GeneratedArt/PartyAttack/NOIR__attack_\(String(format: "%02d", $0)).png" }
        let walk = [0] + Array(2...8)
        let walking = walk.map { "GeneratedArt/PartyWalk/NOIR__walk_\($0).png" }
        return Set(rest + attack + walking).contains(path)
    }
}

