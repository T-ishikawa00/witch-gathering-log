import Foundation

/// QA-only gate for the ACT_B_R04_B localized full-texture gait candidate.
enum DragonGaitR038QA {
    static let flag = "--qa-dragon-gait-r038"
    static func isLegacyEnabled(arguments: [String]) -> Bool {
        arguments.contains("--qa-isolated") && arguments.contains(flag) &&
        !arguments.contains(DragonDistalLegR007QA.flag)
    }
    static func isEnabled(arguments: [String]) -> Bool {
        isLegacyEnabled(arguments: arguments) || DragonDistalLegR007QA.isEnabled(arguments: arguments) ||
            DragonFourLegStanceR064QA.isEnabled(arguments: arguments)
    }
    /// The old R004 full mesh, R038 localized warp, and R007 mask rig are exclusive.
    static func enablesR004(arguments: [String]) -> Bool {
        arguments.contains("--qa-isolated") &&
        arguments.contains("--qa-dragon-mesh-r004") &&
        !arguments.contains(flag) && !arguments.contains(DragonDistalLegR007QA.flag)
    }
}

enum DragonDistalLegR007QA {
    static let flag = "--qa-dragon-distal-leg-r007"
    static func isEnabled(arguments: [String]) -> Bool {
        #if targetEnvironment(simulator)
        let target = arguments.contains("--art-audit=ACT_B_R04_B")
        let hasSaveKey = arguments.contains { $0.hasPrefix("--qa-save-key=") }
        return arguments.contains("--qa-isolated") && arguments.contains(flag) &&
            arguments.contains("--qa-dragon-gait-r038-sequence-probe") && target && hasSaveKey &&
            !arguments.contains(DragonGaitR038QA.flag) &&
            !arguments.contains("--qa-dragon-mesh-r004") &&
            !arguments.contains("--qa-dragon-mesh-pause-probe")
        #else
        return false
        #endif
    }
}
