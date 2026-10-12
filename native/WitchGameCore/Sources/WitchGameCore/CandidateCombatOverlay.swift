import Foundation

/// Explicitly injected local candidate rules. This is development-only data,
/// separate from the persisted catalog and snapshot schemas.
public struct CandidateCombatOverlay: Sendable, Equatable {
    public let id: String
    public let status: String
    public let targetEnemyID: String
    public let actionPattern: String
    public let magnetParameters: MagnetMechanicParameters

    public init(id: String, status: String, targetEnemyID: String,
                actionPattern: String, magnetParameters: MagnetMechanicParameters) {
        self.id = id
        self.status = status
        self.targetEnemyID = targetEnemyID
        self.actionPattern = actionPattern
        self.magnetParameters = magnetParameters
    }

    public static let r014LocalCandidate = CandidateCombatOverlay(
        id: "R014_MAGNET_MARK_STRIKE",
        status: "UNAPPROVED_TEST_OVERLAY",
        targetEnemyID: "E_R03_04",
        actionPattern: "magnetMarkStrike",
        magnetParameters: MagnetMechanicParameters(markWindowMs: 800,
            strikeWindupMs: 1_200, strikeCoefficientBP: 12_500)
    )

    public func applies(to enemyID: String) -> Bool { enemyID == targetEnemyID }
}
