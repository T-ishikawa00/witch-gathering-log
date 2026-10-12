import Foundation

/// Pure presentation contract for holding a party actor on its authored
/// anticipate pose. It uses only the already-produced battle event sequence;
/// it does not invent durations or consult simulator-private windup values.
struct PartyCastHoldLifecycle {
    struct Event: Equatable {
        let kind: String
        let sourceID: String
        let targetID: String
        let rootActionID: String?
    }

    struct CastRoot: Hashable {
        let actorID: String
        let rootActionID: String
    }

    enum Terminal: Equatable {
        case commit(eventKind: String)
        case interruption(eventRootActionID: String?)
        case battleDeath
    }

    private(set) var plannedTerminals: [CastRoot: Terminal] = [:]
    private(set) var pendingRoots: [String: String] = [:]

    init() {}

    /// Maps public event action labels to the event kind emitted by the
    /// simulator when that action commits. Unknown actions are deliberately
    /// ineligible, so a tell without a known terminal cannot create an
    /// indefinite hold.
    static let commitKindByAction: [String: String] = [
        "basic": "direct",
        "burst": "direct",
        "dash": "direct",
        "hammer": "smith_hammer",
        "seed": "poison_seed",
        "mark": "mark",
        "heal": "heal",
        "ward": "barrier",
        "guard": "cover_stance"
    ]

    init(events: [Event], partyActorIDs: Set<String>, defeatedPartyActorIDs: Set<String> = []) {
        var startCounts: [CastRoot: Int] = [:]
        for event in events where event.kind == "cast_start" && partyActorIDs.contains(event.sourceID) {
            guard let root = event.rootActionID, !root.isEmpty else { continue }
            startCounts[CastRoot(actorID: event.sourceID, rootActionID: root), default: 0] += 1
        }
        for (index, event) in events.enumerated() where event.kind == "cast_start" {
            guard partyActorIDs.contains(event.sourceID),
                  let root = event.rootActionID, !root.isEmpty,
                  let commitKind = Self.commitKindByAction[event.targetID] else { continue }
            let request = CastRoot(actorID: event.sourceID, rootActionID: root)
            guard startCounts[request] == 1 else { continue }
            let nextCastStart = events.indices.dropFirst(index + 1).first {
                events[$0].kind == "cast_start" && events[$0].sourceID == event.sourceID
            } ?? events.endIndex
            let following = events[(index + 1)..<nextCastStart]
            let firstTerminal = following.first {
                ($0.kind == commitKind && $0.sourceID == event.sourceID && $0.rootActionID == root)
                || ($0.kind == "cast_interrupt" && $0.targetID == event.sourceID && !partyActorIDs.contains($0.sourceID))
            }
            if let terminal = firstTerminal, terminal.kind == commitKind {
                plannedTerminals[request] = .commit(eventKind: commitKind)
            } else if let terminal = firstTerminal, terminal.kind == "cast_interrupt" {
                // Current R6 events identify the enemy action root here, not
                // the interrupted party cast root. The actor-target link and
                // event order are therefore the available causal evidence.
                plannedTerminals[request] = .interruption(eventRootActionID: terminal.rootActionID)
            } else if nextCastStart == events.endIndex && defeatedPartyActorIDs.contains(event.sourceID) {
                // A zero-HP result is the only death terminal represented by
                // CombatResult today. Runtime damage/HP handling clears sooner.
                plannedTerminals[request] = .battleDeath
            }
        }
    }

    func canHold(actorID: String, rootActionID: String) -> Bool {
        plannedTerminals[CastRoot(actorID: actorID, rootActionID: rootActionID)] != nil
    }

    @discardableResult
    mutating func begin(actorID: String, rootActionID: String, qaPoseHeld: Bool) -> Bool {
        // A new start supersedes any stale presentation hold for this actor;
        // the simulator allows only one active cast per party actor.
        pendingRoots.removeValue(forKey: actorID)
        guard !qaPoseHeld, canHold(actorID: actorID, rootActionID: rootActionID) else { return false }
        pendingRoots[actorID] = rootActionID
        return true
    }

    @discardableResult
    mutating func commit(actorID: String, rootActionID: String, eventKind: String) -> Bool {
        guard pendingRoots[actorID] == rootActionID,
              plannedTerminals[CastRoot(actorID: actorID, rootActionID: rootActionID)] == .commit(eventKind: eventKind) else { return false }
        pendingRoots.removeValue(forKey: actorID)
        return true
    }

    @discardableResult
    mutating func interrupt(actorID: String, terminalEventRootActionID: String?) -> Bool {
        guard let castRoot = pendingRoots[actorID],
              plannedTerminals[CastRoot(actorID: actorID, rootActionID: castRoot)] == .interruption(eventRootActionID: terminalEventRootActionID) else { return false }
        pendingRoots.removeValue(forKey: actorID)
        return true
    }

    @discardableResult
    mutating func hit(actorID: String) -> Bool {
        pendingRoots.removeValue(forKey: actorID) != nil
    }

    @discardableResult
    mutating func clear(actorID: String, rootActionID: String? = nil) -> Bool {
        guard let pending = pendingRoots[actorID], rootActionID == nil || pending == rootActionID else { return false }
        pendingRoots.removeValue(forKey: actorID)
        return true
    }

    mutating func clearAll() { pendingRoots.removeAll() }
    func isHoldingAnticipate(actorID: String, state: String) -> Bool {
        state == "anticipate" && pendingRoots[actorID] != nil
    }
}
