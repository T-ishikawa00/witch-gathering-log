import Foundation

/// A transient, presentation-only warning derived from one enemy's combat events.
/// `targetID == "party"` represents a party-wide warning; otherwise it is one
/// of the explicitly supplied party IDs. This value is not persisted.
/// Reduces the ordinary ordered R6 event stream to at most one current enemy
/// attack warning. It only annotates events; it never changes combat results.
public struct BattleTargetWarningR299: Sendable, Equatable {
    public struct Warning: Sendable, Equatable {
        public let sourceID: String
        public let rootActionID: String
        public let targetID: String
        public let isPartyWide: Bool

        public init(sourceID: String, rootActionID: String, targetID: String, isPartyWide: Bool) {
            self.sourceID = sourceID
            self.rootActionID = rootActionID
            self.targetID = targetID
            self.isPartyWide = isPartyWide
        }
    }

    public private(set) var current: Warning?

    private let allowedEnemyIDs: Set<String>
    private let partyIDs: Set<String>
    private let initialEnemyHP: [String: Int]
    private var currentEnemyHP: [String: Int]

    public init(initialEnemyHP: [String: Int], partyIDs: Set<String>) {
        let validEnemyHP = initialEnemyHP.filter {
            !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.key != "party" && $0.value > 0
        }
        self.allowedEnemyIDs = Set(validEnemyHP.keys)
        self.initialEnemyHP = validEnemyHP
        self.currentEnemyHP = validEnemyHP
        self.partyIDs = Set(partyIDs.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "party"
        })
        self.current = nil
    }

    /// Consumes exactly one event in source order. Cover redirection intentionally
    /// leaves the authored aim unchanged; the first matching enemy hit closes it.
    public mutating func consume(_ event: CombatEvent) {
        applyEnemyHPChange(from: event)

        switch event.kind {
        case "enemy_telegraph", "telegraph_heavy", "telegraph_aoe":
            guard allowedEnemyIDs.contains(event.sourceID),
                  (currentEnemyHP[event.sourceID] ?? 0) > 0,
                  let root = nonempty(event.rootActionID),
                  isValidTarget(event.targetID) else { return }
            current = Warning(
                sourceID: event.sourceID,
                rootActionID: root,
                targetID: event.targetID,
                isPartyWide: event.targetID == "party"
            )

        case "enemy_hit":
            guard let warning = current,
                  event.sourceID == warning.sourceID,
                  event.rootActionID == warning.rootActionID else { return }
            current = nil

        case "cast_interrupt":
            guard let warning = current,
                  event.targetID == warning.sourceID,
                  event.rootActionID == warning.rootActionID else { return }
            current = nil

        default:
            // Includes enemy_cast_start: its target is a root-action placeholder,
            // not a party recipient. It is not a telegraph.
            break
        }
    }

    public mutating func reset() {
        current = nil
    }

    private func isValidTarget(_ targetID: String) -> Bool {
        targetID == "party" || partyIDs.contains(targetID)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private mutating func applyEnemyHPChange(from event: CombatEvent) {
        guard let current = currentEnemyHP[event.targetID],
              let delta = R6CombatPresentationSemantics.hpDelta(for: event) else { return }
        let maximum = max(0, initialEnemyHP[event.targetID] ?? current)
        let next: Int
        if delta < 0 {
            next = current - min(current, -delta)
        } else {
            next = current + min(delta, maximum - current)
        }
        currentEnemyHP[event.targetID] = next
        if current > 0, next == 0, self.current?.sourceID == event.targetID {
            self.current = nil
        }
    }
}
