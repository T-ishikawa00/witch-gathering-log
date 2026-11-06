import Foundation

/// Local Simulator comparison policy for normal battle-entry observation.
/// This changes only the ACT_B_R04_B presentation backend; it does not issue
/// gameplay commands or alter battle timing/economy. A non-Simulator build
/// always keeps the legacy path.
enum DragonNormalEntryBackendR068 {
    enum Selection: String {
        case r064LocalDefaultCandidate
        case r064ExplicitQACandidate
        case legacyIsolatedBaseline
        case legacyExistingOverride
        case invalidRequest
        case unaffected
    }

    static let legacyBaselineFlag = "--qa-dragon-fourleg-r064-legacy-baseline"
    private static let actorID = "ACT_B_R04_B"
    private static let mutuallyExclusiveModes = [
        "--qa-dragon-gait-r038",
        "--qa-dragon-distal-leg-r007",
        "--qa-dragon-mesh-r004",
        "--qa-dragon-mesh-pause-probe",
        "--qa-loop-boundary-trace",
        "--qa-dragon-grounded-entry-r005"
    ]

    static func select(arguments: [String], isSimulator: Bool, actorID: String,
                       explicitR064RequestValid: Bool) -> Selection {
        guard isSimulator, actorID == self.actorID else { return .unaffected }

        let baselineCount = arguments.filter { $0 == legacyBaselineFlag }.count
        if baselineCount > 0 {
            let keys = arguments.filter { $0.hasPrefix("--qa-save-key=") }
            let key = keys.first.map { String($0.dropFirst("--qa-save-key=".count)) } ?? ""
            let keySuffix = key.hasPrefix("r068-") ? String(key.dropFirst("r068-".count)) : ""
            let validKey = UUID(uuidString: keySuffix) != nil
            let strictIsolatedEntry = arguments.filter { $0 == "--qa-isolated" }.count == 1 &&
                arguments.filter { $0 == "--qa-battle-entry-trace" }.count == 1 &&
                keys.count == 1 && validKey
            let conflicting = arguments.contains("--qa-dragon-fourleg-r064") ||
                mutuallyExclusiveModes.contains(where: arguments.contains)
            return baselineCount == 1 && strictIsolatedEntry && !conflicting
                ? .legacyIsolatedBaseline : .invalidRequest
        }

        if arguments.contains("--qa-dragon-fourleg-r064") {
            return explicitR064RequestValid ? .r064ExplicitQACandidate : .invalidRequest
        }

        if mutuallyExclusiveModes.contains(where: arguments.contains) {
            return .legacyExistingOverride
        }
        return .r064LocalDefaultCandidate
    }
}
