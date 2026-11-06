import Foundation

/// Art scope from the R4 gear visual plan. Candidate art mappings do not change this classification.
public enum GearVisualScope: String, Codable, Sendable, Equatable {
    case iconAndLaterAttachment = "ICON_AND_LATER_ATTACHMENT"
    case iconAndSmallDetailOnly = "ICON_AND_SMALL_DETAIL_ONLY"
    case iconOnlyAttachmentBlocked = "ICON_ONLY_ATTACHMENT_BLOCKED"
    case unapprovedOutsideR4 = "UNAPPROVED_OUTSIDE_R4_SCOPE"
}

/// Read-only projection for inventory/character rendering. It deliberately separates equipment
/// instance art from the independently owned/selected wardrobe appearance.
public struct GearAppearanceProjection: Sendable, Equatable {
    public let gearInstanceID: UUID
    public let gearID: String
    public let actorID: String
    public let slot: String
    public let isEquipped: Bool
    public let iconAssetID: String
    public let visualScope: GearVisualScope
    /// Candidate sprite attached by the gear instance, when an explicit per-ID mapping exists.
    public let gearAttachmentAssetID: String?
    /// Separately selected, owned weapon appearance. This can visually override a mapped weapon.
    public let selectedWeaponAppearanceID: String?
    /// Sprite key for the weapon slot after applying the independent cosmetic override.
    public let resolvedWeaponSpriteAssetID: String?

    public init(gearInstanceID: UUID, gearID: String, actorID: String, slot: String, isEquipped: Bool, iconAssetID: String, visualScope: GearVisualScope, gearAttachmentAssetID: String?, selectedWeaponAppearanceID: String?, resolvedWeaponSpriteAssetID: String?) {
        self.gearInstanceID = gearInstanceID
        self.gearID = gearID
        self.actorID = actorID
        self.slot = slot
        self.isEquipped = isEquipped
        self.iconAssetID = iconAssetID
        self.visualScope = visualScope
        self.gearAttachmentAssetID = gearAttachmentAssetID
        self.selectedWeaponAppearanceID = selectedWeaponAppearanceID
        self.resolvedWeaponSpriteAssetID = resolvedWeaponSpriteAssetID
    }
}

public extension GameCatalog {
    /// Projects one snapshot-owned gear instance into the smallest R4-supported visual contract.
    /// It does not infer sprite attachments from inventory icons or from a gear's stats/effects.
    func gearAppearanceProjection(for instance: GearInstance, actorID: String, in snapshot: GameSnapshot) -> GearAppearanceProjection? {
        guard let stored = snapshot.gear.first(where: { $0.id == instance.id }),
              stored.definitionID == instance.definitionID,
              let definition = gear.first(where: { $0.id == stored.definitionID }),
              definition.actorIDs.contains(actorID),
              stored.ownerID == nil || stored.ownerID == actorID else { return nil }

        let isEquipped = stored.ownerID == actorID && snapshot.equippedGearIDs["\(actorID)|\(definition.slot)"] == stored.id
        let scope = Self.r4VisualScope(for: definition.id, slot: definition.slot)
        let gearAttachment = isEquipped ? Self.candidateGearAttachmentAssetID[definition.id] : nil

        let selectedWeapon: String? = {
            guard definition.slot == "weapon",
                  let selected = snapshot.selectedWeaponAppearanceIDs[actorID],
                  snapshot.ownedCosmeticIDs.contains(selected),
                  appearances.contains(where: { $0.id == selected && $0.kind == "weapon" && $0.actorIDs.contains(actorID) }) else { return nil }
            return selected
        }()

        // Candidate staff appearances use their appearance IDs as art keys. Gear stats stay unchanged.
        let resolvedWeapon = isEquipped && definition.slot == "weapon"
            ? (selectedWeapon ?? gearAttachment)
            : nil

        return GearAppearanceProjection(
            gearInstanceID: stored.id,
            gearID: definition.id,
            actorID: actorID,
            slot: definition.slot,
            isEquipped: isEquipped,
            iconAssetID: "ICO_\(definition.id)",
            visualScope: scope,
            gearAttachmentAssetID: gearAttachment,
            selectedWeaponAppearanceID: selectedWeapon,
            resolvedWeaponSpriteAssetID: resolvedWeapon
        )
    }

    private static func r4VisualScope(for gearID: String, slot: String) -> GearVisualScope {
        if ["EQ_F_BODY_01", "EQ_F_HAND_01", "EQ_F_FEET_01", "EQ_F_RING_01"].contains(gearID) { return .unapprovedOutsideR4 }
        if gearID == "EQ_S_01" { return .iconOnlyAttachmentBlocked }
        if ["body", "hands", "hand", "feet", "amulet", "ring"].contains(slot) { return .iconAndSmallDetailOnly }
        if ["weapon", "book", "catalyst"].contains(slot) { return .iconAndLaterAttachment }
        return .unapprovedOutsideR4
    }

    /// Explicit image-generated candidate mappings for the five witch-staff IDs. Other mappings
    /// need authored and reviewed asset evidence; never use an inventory icon as a worn sprite.
    private static let candidateGearAttachmentAssetID: [String: String] = [
        "EQ_W_01": "STAFF_EQ_W_01",
        "EQ_W_P1": "STAFF_EQ_W_P1",
        "EQ_W_P2": "STAFF_EQ_W_P2",
        "EQ_W_G1": "STAFF_EQ_W_G1",
        "EQ_W_G2": "STAFF_EQ_W_G2"
    ]
}
