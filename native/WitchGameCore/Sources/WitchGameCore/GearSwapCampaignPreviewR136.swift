import Foundation

/// Read-only campaign gear trial. `enemyID` is a campaign enemy ID, never a challenge ID.
public struct CampaignGearSwapPreviewR136: Sendable, Equatable {
    public let enemyID: String
    public let actorID: String
    public let currentGearID: UUID?
    public let selectedGearID: UUID
    public let slot: String
    public let seed: UInt64
    public let result: CombatResult

    public init(enemyID: String, actorID: String, currentGearID: UUID?, selectedGearID: UUID,
                slot: String, seed: UInt64, result: CombatResult) {
        self.enemyID = enemyID
        self.actorID = actorID
        self.currentGearID = currentGearID
        self.selectedGearID = selectedGearID
        self.slot = slot
        self.seed = seed
        self.result = result
    }
}

public enum CampaignGearTrialErrorR136: Error, Equatable {
    case unknownEnemy
    case activeRegionUnavailable
    case activeRegionLocked
    case enemyOutsideActiveRegion
    case enemyNotListedInActiveRegion
    case prerequisiteNotCleared(String)
}
