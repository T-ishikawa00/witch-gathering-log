import Foundation

/// Shared schema builder used by the SpriteKit observer and the host contract
/// test. The raw expected roots retain their full action contract elsewhere;
/// summary rows intentionally contain only the identity pair validated by the
/// independent Python consumer.
struct EquipmentMotionTraceRootSummary {
    let validatedPairs: [[String: String]]
    let missingPairs: [[String: String]]
    let status: String

    var payloadFields: [String: Any] {
        ["validatedPartyCastRoots": validatedPairs,
         "missingPartyCastRoots": missingPairs,
         "partyCastValidationStatus": status]
    }

    static func key(actorID: String, rootActionID: String) -> String {
        actorID + "\u{1f}" + rootActionID
    }

    static func make(expectedRoots: [[String: String]], validatedRootKeys: Set<String>,
                     expectedActors: Set<String>) -> EquipmentMotionTraceRootSummary {
        let pairs = expectedRoots.compactMap { row -> (actor: String, root: String)? in
            guard let actor = row["actorID"], !actor.isEmpty,
                  let root = row["rootActionID"], !root.isEmpty else { return nil }
            return (actor, root)
        }
        let uniquePairs = Array(Set(pairs.map { key(actorID: $0.actor, rootActionID: $0.root) }))
            .compactMap { key -> (actor: String, root: String)? in
                guard let separator = key.firstIndex(of: "\u{1f}") else { return nil }
                return (String(key[..<separator]), String(key[key.index(after: separator)...]))
            }
            .sorted { left, right in
                left.actor == right.actor ? left.root < right.root : left.actor < right.actor
            }
        let validated = uniquePairs.filter { validatedRootKeys.contains(key(actorID: $0.actor, rootActionID: $0.root)) }
        let missing = uniquePairs.filter { !validatedRootKeys.contains(key(actorID: $0.actor, rootActionID: $0.root)) }
        let rootedActors = Set(uniquePairs.map(\.actor))
        let validatedActors = Set(validated.map(\.actor))
        let status = rootedActors == expectedActors && validatedActors == expectedActors
            ? "PASS_AT_LEAST_ONE_ROOTED_CAST_PER_ACTOR"
            : "INCOMPLETE_CAST_EVENT_OR_TRANSITION"
        return EquipmentMotionTraceRootSummary(
            validatedPairs: validated.map { ["actorID": $0.actor, "rootActionID": $0.root] },
            missingPairs: missing.map { ["actorID": $0.actor, "rootActionID": $0.root] },
            status: status)
    }
}
