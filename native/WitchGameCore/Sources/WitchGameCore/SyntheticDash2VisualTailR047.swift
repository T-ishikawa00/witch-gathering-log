import Foundation

/// Isolated visual-QA projection of a real R043 synthetic Core result.
/// The full donor result is retained by the caller; this value contains only
/// the event prefix through NOIR's second dash impact and carries no rewards.
public enum SyntheticDash2VisualTailR047 {
    public static let schema = "synthetic-dash2-visual-tail-r047"
    public static let actorID = "C_FAMILIAR"
    public static let rootActionID = "C_FAMILIAR:SK_F_DASH:2"
    public static let actionID = "dash"
    public static let impactKind = "direct"
    public static let tailMilliseconds = 1_200

    public struct Plan: Sendable, Equatable {
        public let fullDonorEventCount: Int
        public let targetCastStartIndex: Int
        public let targetImpactIndex: Int
        public let targetCastStartTimestampMs: Int
        public let targetImpactTimestampMs: Int
        public let playback: CombatResult
        public let tailMilliseconds: Int
        public let schema: String
    }

    public enum PlanError: Error, Equatable {
        case missingOrDuplicateTargetStart
        case missingOrDuplicateTargetImpact
        case impactBeforeStart
        case wrongTargetOrActor
        case nonmonotonicPrefix
        case donorNotFullerThanPrefix
    }

    public static func makePlan(from donor: CombatResult) throws -> Plan {
        let starts = donor.events.indices.filter { index in
            let event = donor.events[index]
            return event.kind == "cast_start" && event.sourceID == actorID
                && event.targetID == actionID && event.rootActionID == rootActionID
        }
        guard starts.count == 1, let startIndex = starts.first else {
            throw PlanError.missingOrDuplicateTargetStart
        }
        let impacts = donor.events.indices.filter { index in
            let event = donor.events[index]
            return event.kind == impactKind && event.sourceID == actorID
                && donor.initialEnemyHP[event.targetID] != nil
                && event.rootActionID == rootActionID
        }
        guard impacts.count == 1, let impactIndex = impacts.first else {
            throw PlanError.missingOrDuplicateTargetImpact
        }
        guard impactIndex > startIndex else { throw PlanError.impactBeforeStart }
        guard donor.events.count > impactIndex + 1 else { throw PlanError.donorNotFullerThanPrefix }
        let start = donor.events[startIndex]
        let impact = donor.events[impactIndex]
        guard start.targetID == actionID,
              (start.timestampMs ?? start.tick * 1_000) <= (impact.timestampMs ?? impact.tick * 1_000) else {
            throw PlanError.wrongTargetOrActor
        }

        let prefix = Array(donor.events[...impactIndex])
        var previous = Int.min
        for event in prefix {
            let time = event.timestampMs ?? event.tick * 1_000
            guard time >= previous else { throw PlanError.nonmonotonicPrefix }
            previous = time
        }

        // Recompute presentation HP for the prefix. Never pair prefix events
        // with the donor's later full-result HP, which would leak future damage.
        let initialHP = donor.initialPartyHP.merging(donor.initialEnemyHP) { _, enemy in enemy }
        let finalHP = R6CombatPresentationSemantics.replay(events: prefix, initialHP: initialHP,
                                                           maximumHP: initialHP)
        let partyHP = finalHP.filter { donor.initialPartyHP[$0.key] != nil }
        let enemyHP = finalHP.filter { donor.initialEnemyHP[$0.key] != nil }
        let playback = CombatResult(won: false,
                                    ticks: prefix.map(\.tick).max() ?? 0,
                                    events: prefix,
                                    remainingPartyHP: partyHP,
                                    initialPartyHP: donor.initialPartyHP,
                                    initialEnemyHP: donor.initialEnemyHP,
                                    remainingEnemyHP: enemyHP,
                                    entityPresentation: donor.entityPresentation)
        return Plan(fullDonorEventCount: donor.events.count,
                    targetCastStartIndex: startIndex,
                    targetImpactIndex: impactIndex,
                    targetCastStartTimestampMs: start.timestampMs ?? start.tick * 1_000,
                    targetImpactTimestampMs: impact.timestampMs ?? impact.tick * 1_000,
                    playback: playback,
                    tailMilliseconds: tailMilliseconds,
                    schema: schema)
    }
}
