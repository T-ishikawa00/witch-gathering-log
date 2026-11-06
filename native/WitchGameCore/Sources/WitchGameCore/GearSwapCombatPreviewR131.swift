import Foundation

/// No-reward comparison of an already-owned item against its current slot.
/// `currentGearID == nil` means the actor has no item equipped in that slot.
public struct GearSwapCombatPreviewR131: Sendable, Equatable {
    public let challengeID: String
    public let actorID: String
    public let currentGearID: UUID?
    public let selectedGearID: UUID
    public let slot: String
    public let seed: UInt64
    public let result: CombatResult

    static func isUsableByActorR131(_ definition: GearDefinition, actorID: String) -> Bool {
        definition.actorIDs.isEmpty || definition.actorIDs.contains(actorID)
    }

    public init(challengeID: String, actorID: String, currentGearID: UUID?,
                selectedGearID: UUID, slot: String, seed: UInt64, result: CombatResult) {
        self.challengeID = challengeID
        self.actorID = actorID
        self.currentGearID = currentGearID
        self.selectedGearID = selectedGearID
        self.slot = slot
        self.seed = seed
        self.result = result
    }
}

public enum GearSwapCombatPreviewErrorR131: Error, Equatable {
    case unknownChallenge
    case challengeLocked
    case actorNotInParty
    case missingOrDuplicateGear(UUID)
    case wrongGearOwner(UUID)
    case wrongGearSlot
    case gearNotUsableByActor(UUID)
    case selectedGearEquippedElsewhere(UUID)
}

