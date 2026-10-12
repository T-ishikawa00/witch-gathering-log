import Foundation

/// Presentation contract for events produced by `R6TimelineSimulator` only.
/// The older tick-based `CombatSimulator` has a separate event vocabulary and
/// is intentionally not inferred here.
public enum R6CombatPresentationSemantics {
    public enum Kind: String, Sendable, Equatable {
        case damage
        case healing
        case barrier
        case annotation
        case other
    }

    private static let damageEvents: Set<String> = [
        "direct", "smith_hammer", "poison_seed", "enemy_hit", "heal_followup",
        "poison_tick", "dot_tick", "chase", "counter", "reflect", "enemy_reflect_projectile"
    ]
    private static let healingEvents: Set<String> = [
        "heal", "enemy_support", "lamp_support", "enemy_heal_cycle", "enemy_regen"
    ]
    private static let barrierEvents: Set<String> = [
        "barrier", "heal_barrier", "barrier_absorb", "smith_cover_barrier"
    ]

    public static func classify(_ eventKind: String) -> Kind {
        if damageEvents.contains(eventKind) { return .damage }
        if healingEvents.contains(eventKind) { return .healing }
        if barrierEvents.contains(eventKind) { return .barrier }
        // This event mirrors the qualifying burst damage; applying both events
        // as HP changes would subtract the same attack twice.
        if eventKind == "poison_burst" { return .annotation }
        return .other
    }

    /// Signed HP change for one R6 event: negative is damage, positive is heal.
    /// Returns nil for barriers, status/telegraph events, and annotations.
    public static func hpDelta(for event: CombatEvent) -> Int? {
        switch classify(event.kind) {
        case .damage: return -max(0, event.amount)
        case .healing: return max(0, event.amount)
        case .barrier, .annotation, .other: return nil
        }
    }

    /// Replays presentation HP from initial entity HP. Every entity is clamped
    /// to 0...maximumHP; omitted maxima default to its initial HP. Unknown
    /// targets and non-HP events leave the map unchanged.
    public static func replay(events: [CombatEvent], initialHP: [String: Int],
                              maximumHP: [String: Int] = [:]) -> [String: Int] {
        var hp = initialHP.mapValues { value in max(0, value) }
        for id in Array(hp.keys) {
            let maximum = max(0, maximumHP[id] ?? initialHP[id] ?? 0)
            hp[id] = min(maximum, hp[id] ?? 0)
        }
        for event in events {
            guard let delta = hpDelta(for: event), let current = hp[event.targetID] else { continue }
            let maximum = max(0, maximumHP[event.targetID] ?? initialHP[event.targetID] ?? current)
            if delta >= 0 {
                hp[event.targetID] = current + min(delta, maximum - current)
            } else {
                hp[event.targetID] = current - min(current, -delta)
            }
        }
        return hp
    }
}
