import Foundation

/// Strict argument gate for UI48 simulator QA. It does not mutate saves or enable
/// candidate economy behavior; the application remains responsible for refusing
/// these arguments outside Simulator before opening any save namespace.
public enum UI48QALaunchGate {
    private static let fixtures: Set<String> = ["full", "empty", "many", "gathering", "fresh", "frontier"]

    public static func isValid(arguments: [String]) -> Bool {
        var args = arguments
        if let first = args.first, !first.hasPrefix("-") { args.removeFirst() }

        var seen = Set<String>()
        var hasUI48 = false
        var hasIsolated = false
        var hasSaveKey = false

        for argument in args {
            // XCTest injects single-dash system arguments. Double-dash options
            // are application QA controls and must match this allowlist.
            if argument.hasPrefix("-") && !argument.hasPrefix("--") { continue }
            guard argument.hasPrefix("--") else { return false }

            if argument == "--ui48-qa" {
                guard seen.insert("ui48").inserted else { return false }
                hasUI48 = true
            } else if argument == "--qa-isolated" {
                guard seen.insert("isolated").inserted else { return false }
                hasIsolated = true
            } else if argument.hasPrefix("--qa-save-key=") {
                guard seen.insert("save-key").inserted else { return false }
                let value = String(argument.dropFirst("--qa-save-key=".count))
                guard let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value else { return false }
                hasSaveKey = true
            } else if argument == "--qa-readback-save" {
                guard seen.insert("readback").inserted else { return false }
            } else if argument == "--ui48-craft-observe" {
                guard seen.insert("craft-observe").inserted else { return false }
            } else if argument.hasPrefix("--ui48-screen=") {
                guard seen.insert("screen").inserted else { return false }
                let value = String(argument.dropFirst("--ui48-screen=".count))
                guard let screen = Int(value), (1...48).contains(screen), String(screen) == value else { return false }
            } else if argument.hasPrefix("--ui48-fixture=") {
                guard seen.insert("fixture").inserted else { return false }
                let value = String(argument.dropFirst("--ui48-fixture=".count))
                guard fixtures.contains(value) else { return false }
            } else {
                // This also rejects every other --qa flag and unknown --ui48 flag.
                return false
            }
        }

        return hasUI48 && hasIsolated && hasSaveKey
    }
}
