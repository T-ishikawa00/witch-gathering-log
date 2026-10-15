import Foundation

/// Read-only continuation cues derived from the existing campaign, challenge,
/// and tracked-recipe state. This adds no goal, reward, or saved progression.
public enum PostClearGoalProjectionR122 {
    public enum ChallengeAvailability: Equatable, Sendable {
        case locked
        case available
        case cleared
    }

    public struct Challenge: Equatable, Sendable, Identifiable {
        public let id: String
        public let availability: ChallengeAvailability
    }

    public struct Summary: Equatable, Sendable {
        public let campaignCleared: Int
        public let campaignTotal: Int
        public let campaignComplete: Bool
        public let challenges: [Challenge]
        public let challengesCleared: Int
        public let trackedRecipe: RecipeGoalProjectionR035.Goal?
    }

    public static func project(catalog: GameCatalog, state: GameSnapshot) -> Summary {
        let campaignTotal = catalog.enemies.count
        let campaignCleared = catalog.enemies.reduce(into: 0) { count, enemy in
            if state.completedEncounterIDs.contains(enemy.id) { count += 1 }
        }
        let challenges = catalog.challenges.map { definition -> Challenge in
            let clearID = "CHALLENGE_CLEAR|\(definition.id)"
            let availability: ChallengeAvailability
            if state.completedEncounterIDs.contains(clearID) {
                availability = .cleared
            } else if gateIsCleared(definition.unlockGate, completedEncounterIDs: state.completedEncounterIDs) {
                availability = .available
            } else {
                availability = .locked
            }
            return Challenge(id: definition.id, availability: availability)
        }
        let clearedIDs = Set(challenges.filter { $0.availability == .cleared }.map(\.id))
        return Summary(campaignCleared: campaignCleared, campaignTotal: campaignTotal,
                       campaignComplete: campaignTotal > 0 && campaignCleared == campaignTotal,
                       challenges: challenges, challengesCleared: clearedIDs.count,
                       trackedRecipe: RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: state))
    }

    private static func gateIsCleared(_ gateID: String, completedEncounterIDs: Set<String>) -> Bool {
        if gateID == "G_START" { return true }
        let parts = gateID.split(separator: "_")
        guard parts.count == 3, parts[0] == "G" else { return false }
        return completedEncounterIDs.contains("B_\(parts[1])_\(parts[2])")
    }
}
