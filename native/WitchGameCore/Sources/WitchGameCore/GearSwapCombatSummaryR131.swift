import Foundation

/// A compact, no-reward description of a preview. Event observations are reported
/// as counts only; this type deliberately does not infer gear causality or sum
/// prevented damage/healing from event payloads.
public struct GearSwapCombatSummaryR131: Codable, Sendable, Equatable {
    public let won: Bool
    public let ticks: Int
    public let initialPartyHP: [String: Int]
    public let remainingPartyHP: [String: Int]
    public let downedPartyActorIDs: [String]
    public let initialEnemyHP: [String: Int]
    public let remainingEnemyHP: [String: Int]
    public let eventKindCounts: [String: Int]
    public let selectedActorSourceEventKindCounts: [String: Int]
    public let selectedActorTargetEventKindCounts: [String: Int]
    public let eventAttribution: String

    public static func make(from preview: GearSwapCombatPreviewR131) -> Self {
        make(result: preview.result, actorID: preview.actorID)
    }

    /// Campaign overload keeps the real campaign enemy identity in its own preview
    /// type and shares only observed combat-result aggregation.
    public static func make(from preview: CampaignGearSwapPreviewR136) -> Self {
        make(result: preview.result, actorID: preview.actorID)
    }

    private static func make(result: CombatResult, actorID: String) -> Self {
        let events = result.events
        func counts(_ events: [CombatEvent]) -> [String: Int] {
            Dictionary(grouping: events.map(\.kind), by: { $0 }).mapValues(\.count)
        }
        return Self(
            won: result.won,
            ticks: result.ticks,
            initialPartyHP: result.initialPartyHP,
            remainingPartyHP: result.remainingPartyHP,
            downedPartyActorIDs: result.remainingPartyHP.filter { $0.value <= 0 }.map(\.key).sorted(),
            initialEnemyHP: result.initialEnemyHP,
            remainingEnemyHP: result.remainingEnemyHP,
            eventKindCounts: counts(events),
            selectedActorSourceEventKindCounts: counts(events.filter { $0.sourceID == actorID }),
            selectedActorTargetEventKindCounts: counts(events.filter { $0.targetID == actorID }),
            eventAttribution: "OBSERVED_EVENTS_ONLY_NO_GEAR_CAUSALITY"
        )
    }
}
