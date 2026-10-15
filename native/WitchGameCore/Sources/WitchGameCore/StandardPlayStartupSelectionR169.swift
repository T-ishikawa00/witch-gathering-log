import Foundation

/// Selects between ordinary R098 gameplay, the existing isolated R146 QA route,
/// and an explicitly compiled local development route. It never changes runtime data.
public enum StandardPlayStartupSelectionR169 {
    public enum Mode: String, Sendable, Equatable {
        case ordinaryR098
        case isolatedQAR146
        case standardPlayR169

        public var usesSharedPartyWork: Bool { self != .ordinaryR098 }
        public var saveNamespace: String {
            self == .standardPlayR169 ? "Witch03to05DevelopmentR169" : "Witch03to05R1"
        }
    }

    public enum SelectionError: Error, Equatable {
        case qaArgumentsInStandardDevelopmentBuild
    }

    /// A recovered previous generation is an existing save even if primary is absent.
    public static func requiresExistingTarget(recoverySource: SaveRecoveryStatus.Source) -> Bool {
        recoverySource != .memory
    }

    public static func resolve(developmentBuildEnabled: Bool,
                               isolatedR146GateEnabled: Bool,
                               arguments: [String]) throws -> Mode {
        if developmentBuildEnabled {
            guard !isolatedR146GateEnabled,
                  !arguments.contains(where: { $0.hasPrefix("--qa") }) else {
                throw SelectionError.qaArgumentsInStandardDevelopmentBuild
            }
            return .standardPlayR169
        }
        return isolatedR146GateEnabled ? .isolatedQAR146 : .ordinaryR098
    }
}
