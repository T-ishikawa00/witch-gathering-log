import Foundation

/// Selects the comparison partner for an inventory item without changing inventory or equipment.
/// The app supplies the IDs that pass its actor-specific latent-slot usability checks.
public enum GearComparisonPartnerSelectionR210 {
    public static func selectCounterpart(
        itemID: UUID,
        actorID: String,
        gear: [GearInstance],
        definitions: [GearDefinition],
        equippedGearIDs: [String: UUID],
        usableGearIDs: Set<UUID>
    ) -> UUID? {
        let selectedMatches = gear.filter { $0.id == itemID }
        guard selectedMatches.count == 1,
              let selected = selectedMatches.first,
              usableGearIDs.contains(itemID),
              let selectedDefinition = definitions.first(where: { $0.id == selected.definitionID }),
              selectedDefinition.actorIDs.isEmpty || selectedDefinition.actorIDs.contains(actorID)
        else { return nil }

        let slotKey = "\(actorID)|\(selectedDefinition.slot)"
        func isEligible(_ candidate: GearInstance) -> Bool {
            guard candidate.id != itemID,
                  candidate.ownerID == nil || candidate.ownerID == actorID,
                  usableGearIDs.contains(candidate.id),
                  let definition = definitions.first(where: { $0.id == candidate.definitionID }),
                  definition.slot == selectedDefinition.slot,
                  definition.actorIDs.isEmpty || definition.actorIDs.contains(actorID)
            else { return false }
            return true
        }

        // The actually equipped counterpart is the most relevant comparison, but only
        // when its UUID resolves to exactly one compatible inventory instance.
        if let equippedID = equippedGearIDs[slotKey],
           equippedID != itemID,
           gear.filter({ $0.id == equippedID }).count == 1,
           let equipped = gear.first(where: { $0.id == equippedID }),
           isEligible(equipped) {
            return equippedID
        }

        // If comparing the equipped item itself, or if its pointer is absent/stale,
        // choose a deterministic alternative by quality, development levels, then IDs.
        let qualityRank = ["Q0": 0, "Q1": 1, "Q2": 2, "Q3": 3, "Q4": 4]
        return gear.filter(isEligible).sorted { lhs, rhs in
            let leftQuality = qualityRank[lhs.qualityID, default: -1]
            let rightQuality = qualityRank[rhs.qualityID, default: -1]
            if leftQuality != rightQuality { return leftQuality > rightQuality }
            if lhs.enhancement != rhs.enhancement { return lhs.enhancement > rhs.enhancement }
            if lhs.refinement != rhs.refinement { return lhs.refinement > rhs.refinement }
            if lhs.definitionID != rhs.definitionID { return lhs.definitionID < rhs.definitionID }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first?.id
    }
}
