import Foundation

/// A complete mapping for every slot occupied in the source party snapshot.
/// Values are actual owned GearInstance UUIDs; this type does not create items.
public struct OwnedPartyLoadoutR181: Sendable, Equatable {
    public let id: String
    public let gearByActorSlot: [String: UUID]

    public init(id: String, gearByActorSlot: [String: UUID]) {
        self.id = id
        self.gearByActorSlot = gearByActorSlot
    }
}

public struct OwnedPartyLoadoutPreviewR181: Sendable, Equatable {
    public let challengeID: String
    public let loadoutID: String
    public let seed: UInt64
    public let gearByActorSlot: [String: UUID]
    public let result: CombatResult
}

public enum OwnedPartyLoadoutPreviewErrorR181: Error, Equatable {
    case unknownChallenge
    case challengeLocked
    case exactlyTwoLoadoutsRequired
    case duplicateOrEmptyLoadoutID
    case occupiedSlotSetMismatch
    case malformedSlotKey(String)
    case missingOrDuplicateGear(UUID)
    case duplicateGearAssignment(UUID)
    case wrongGearOwner(UUID)
    case wrongGearSlot(UUID)
    case gearNotUsableByActor(UUID)
}
