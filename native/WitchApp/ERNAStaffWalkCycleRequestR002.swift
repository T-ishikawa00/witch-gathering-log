import Foundation

/// Unique isolated walk-only request. It uses the existing `gear-*` QAScenarios
/// fixture, but it is intentionally distinct from the full-battle R040 request.
struct ERNAStaffWalkCycleRequestR002: Equatable {
    static let flag = "--qa-erna-staff-walk-cycle="
    static let gears: Set<String> = ["EQ_W_01", "EQ_W_P1", "EQ_W_P2", "EQ_W_G1", "EQ_W_G2"]
    static let costumes: Set<String> = ["standard", "travel"]
    let gearID: String
    let costume: String
    let fixture: String
    let saveKey: String

    enum Failure: String, Error, Equatable {
        case missingIsolation, missingPersistence, existingSaveLoaded, duplicateOrMissingRequest
        case unsupportedGearOrCostume, fixtureMismatch, duplicateOrMissingSaveKey
        case unsafeSaveKey, conflictingQAMode, saveKeyAlreadyUsed
    }

    static func parse(arguments: [String], fixture: String?, saveKey: String?,
                      existingSaveLoaded: Bool, outputDirectory: URL) -> Result<ERNAStaffWalkCycleRequestR002, Failure> {
        guard arguments.filter({ $0 == "--qa-isolated" }).count == 1 else { return .failure(.missingIsolation) }
        guard arguments.filter({ $0 == "--qa-persist-fixture" }).count == 1 else { return .failure(.missingPersistence) }
        guard !existingSaveLoaded else { return .failure(.existingSaveLoaded) }
        guard !arguments.contains("--qa-erna-staff-full-battle") &&
              !arguments.contains(where: { $0.hasPrefix("--qa-erna-staff-motion=") }) else { return .failure(.conflictingQAMode) }
        let requests = arguments.filter { $0.hasPrefix(flag) }
        guard requests.count == 1 else { return .failure(.duplicateOrMissingRequest) }
        let pair = String(requests[0].dropFirst(flag.count)).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard pair.count == 2, gears.contains(pair[0]), costumes.contains(pair[1]) else { return .failure(.unsupportedGearOrCostume) }
        let expectedFixture = "gear-\(pair[0])-\(pair[1])"
        let fixtureArgs = arguments.filter { $0.hasPrefix("--qa-fixture=") }
        guard fixtureArgs.count == 1, fixture == expectedFixture,
              fixtureArgs[0] == "--qa-fixture=" + expectedFixture else { return .failure(.fixtureMismatch) }
        let keyArgs = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard let saveKey, keyArgs.count == 1,
              arguments.contains("--qa-save-key=" + saveKey) else { return .failure(.duplicateOrMissingSaveKey) }
        guard saveKey.utf8.count >= 12, saveKey.utf8.count <= 64,
              saveKey.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 }) else { return .failure(.unsafeSaveKey) }
        let allowed = Set(["--qa-isolated", "--qa-persist-fixture", requests[0], fixtureArgs[0], keyArgs[0]])
        if arguments.contains(where: { ($0.hasPrefix("--qa-") || $0.hasPrefix("--art-audit")) && !allowed.contains($0) }) {
            return .failure(.conflictingQAMode)
        }
        let prefix = "erna_walk_cycle_\(saveKey)_"
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
        guard !existing.contains(where: { $0.hasPrefix(prefix) }) else { return .failure(.saveKeyAlreadyUsed) }
        return .success(.init(gearID: pair[0], costume: pair[1], fixture: expectedFixture, saveKey: saveKey))
    }
}
