import Foundation

/// Isolated request contract for one ERNA weapon/costume pair.
/// Existing QAScenarios already builds `gear-EQ_W_…-standard|travel` fixtures.
struct ERNAStaffMotionTraceRequestR040 {
    static let flag = "--qa-erna-staff-motion="
    static let fullBattleFlag = "--qa-erna-staff-full-battle"
    static let acceptedGearIDs: Set<String> = ["EQ_W_01", "EQ_W_P1", "EQ_W_P2", "EQ_W_G1", "EQ_W_G2"]
    static let acceptedCostumes: Set<String> = ["standard", "travel"]

    let gearID: String
    let costume: String
    let fixture: String
    let encounterID: String
    let saveKey: String

    enum Failure: String, Error {
        case missingIsolation, missingPersistence, missingOrDuplicateRequest
        case unsupportedGear, unsupportedCostume, fixtureMismatch
        case missingOrDuplicateEncounter, encounterMismatch
        case missingOrDuplicateSaveKey, unsafeSaveKey, existingSaveLoaded, saveKeyAlreadyUsed
        case conflictingQAMode
    }

    static func parse(arguments: [String], actualEncounterID: String,
                      outputDirectory: URL, existingSaveLoaded: Bool = false) -> Result<ERNAStaffMotionTraceRequestR040, Failure> {
        guard arguments.filter({ $0 == "--qa-isolated" }).count == 1 else { return .failure(.missingIsolation) }
        guard arguments.filter({ $0 == "--qa-persist-fixture" }).count == 1 else { return .failure(.missingPersistence) }
        guard arguments.filter({ $0 == fullBattleFlag }).count == 1 else { return .failure(.conflictingQAMode) }
        guard !existingSaveLoaded else { return .failure(.existingSaveLoaded) }
        let requests = arguments.filter { $0.hasPrefix(flag) }
        guard requests.count == 1 else { return .failure(.missingOrDuplicateRequest) }
        let raw = String(requests[0].dropFirst(flag.count)).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard raw.count == 2, acceptedGearIDs.contains(raw[0]) else { return .failure(.unsupportedGear) }
        guard acceptedCostumes.contains(raw[1]) else { return .failure(.unsupportedCostume) }
        let fixture = "gear-\(raw[0])-\(raw[1])"
        let fixtureArgs = arguments.filter { $0.hasPrefix("--qa-fixture=") }
        guard fixtureArgs.count == 1, String(fixtureArgs[0].dropFirst("--qa-fixture=".count)) == fixture else { return .failure(.fixtureMismatch) }
        let encounterArgs = arguments.filter { $0.hasPrefix("--qa-encounter=") }
        guard encounterArgs.count == 1 else { return .failure(.missingOrDuplicateEncounter) }
        let encounter = String(encounterArgs[0].dropFirst("--qa-encounter=".count))
        guard !encounter.isEmpty, encounter == actualEncounterID else { return .failure(.encounterMismatch) }
        let keyArgs = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard keyArgs.count == 1 else { return .failure(.missingOrDuplicateSaveKey) }
        let key = String(keyArgs[0].dropFirst("--qa-save-key=".count))
        guard key.utf8.count >= 12, key.utf8.count <= 64,
              key.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 }) else {
            return .failure(.unsafeSaveKey)
        }
        let allowed = Set(["--qa-isolated", "--qa-persist-fixture", fullBattleFlag, requests[0], fixtureArgs[0], encounterArgs[0], keyArgs[0]])
        if arguments.contains(where: { ($0.hasPrefix("--qa-") || $0.hasPrefix("--art-audit")) && !allowed.contains($0) }) {
            return .failure(.conflictingQAMode)
        }
        let prefix = "erna_staff_\(key)_"
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
        guard !existing.contains(where: { $0.hasPrefix(prefix) }) else { return .failure(.saveKeyAlreadyUsed) }
        return .success(.init(gearID: raw[0], costume: raw[1], fixture: fixture,
                              encounterID: encounter, saveKey: key))
    }
}
