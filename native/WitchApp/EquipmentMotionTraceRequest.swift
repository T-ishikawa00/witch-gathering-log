import Foundation

/// Foundation-only launch contract for the isolated AIRA S03 motion observer.
/// This parser is the single source of truth for enabling the candidate trace.
struct EquipmentMotionTraceRequest {
    static let fixtureID = "details-C_SMITH-03"
    static let gearID = "EQ_S_03"
    static let actorID = "AIRA"
    static let schema = "equipment-motion-trace-r002"
    static let fullBattleSchema = "equipment-motion-trace-r004"
    static let fullBattleFlag = "--qa-party-cast-full-battle"
    static let syntheticDash2Flag = "--qa-party-cast-synthetic-dash2"
    static let syntheticDash2TailR047Flag = "--qa-party-cast-synthetic-dash2-tail-r047"
    static let r6PreviewPrefix = "--qa-r6-preview="
    static let syntheticEncounterID = "E_R01_01"

    enum CaptureScope: String {
        case fivePhase = "five_phase_sequence"
        case fullBattleParty = "full_battle_party_casts"

        var stopsWhenFivePhaseSequenceCompletes: Bool { self == .fivePhase }
    }

    let fixture: String
    let encounterID: String
    let saveKey: String
    let captureScope: CaptureScope

    enum Failure: String, Error {
        case missingIsolation, wrongFixture, missingOrDuplicateGearFlag
        case missingOrDuplicateEncounter, encounterMismatch, missingOrDuplicateSaveKey
        case unsafeSaveKey, conflictingQAMode, saveKeyAlreadyUsed, existingSaveLoaded
        case syntheticPreviewRequiresFullBattleR6Route, conflictingEncounterRoute
    }

    static func parse(arguments: [String], actualEncounterID: String,
                      outputDirectory: URL, existingSaveLoaded: Bool = false) -> Result<EquipmentMotionTraceRequest, Failure> {
        guard arguments.contains("--qa-isolated") else { return .failure(.missingIsolation) }
        guard !existingSaveLoaded else { return .failure(.existingSaveLoaded) }
        let fixtureArgs = arguments.filter { $0.hasPrefix("--qa-fixture=") }
        guard fixtureArgs.count == 1,
              String(fixtureArgs[0].dropFirst("--qa-fixture=".count)) == fixtureID else {
            return .failure(.wrongFixture)
        }
        let gearArgs = arguments.filter { $0.hasPrefix("--qa-equipment-motion-trace=") }
        guard gearArgs.count == 1,
              String(gearArgs[0].dropFirst("--qa-equipment-motion-trace=".count)) == gearID else {
            return .failure(.missingOrDuplicateGearFlag)
        }
        let encounterArgs = arguments.filter { $0.hasPrefix("--qa-encounter=") }
        let r6PreviewArgs = arguments.filter { $0.hasPrefix(r6PreviewPrefix) }
        guard encounterArgs.count <= 1, r6PreviewArgs.count <= 1,
              encounterArgs.count + r6PreviewArgs.count == 1 else {
            return .failure(encounterArgs.count == 1 && r6PreviewArgs.count == 1 ? .conflictingEncounterRoute : .missingOrDuplicateEncounter)
        }
        let encounterID: String
        if let arg = encounterArgs.first {
            encounterID = String(arg.dropFirst("--qa-encounter=".count))
        } else if let arg = r6PreviewArgs.first {
            encounterID = String(arg.dropFirst(r6PreviewPrefix.count))
        } else { return .failure(.missingOrDuplicateEncounter) }
        guard !encounterID.isEmpty, encounterID == actualEncounterID else { return .failure(.encounterMismatch) }
        let keyArgs = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard keyArgs.count == 1 else { return .failure(.missingOrDuplicateSaveKey) }
        let saveKey = String(keyArgs[0].dropFirst("--qa-save-key=".count))
        guard isSafe(saveKey) else { return .failure(.unsafeSaveKey) }

        // This visual trace is exclusive. Other QA modes can change pose, actor
        // lifecycle, encounter playback, or scene composition and are rejected.
        let fullBattleArgs = arguments.filter { $0 == fullBattleFlag }
        guard fullBattleArgs.count <= 1 else { return .failure(.conflictingQAMode) }
        let captureScope: CaptureScope = fullBattleArgs.isEmpty ? .fivePhase : .fullBattleParty
        let syntheticArgs = arguments.filter { $0 == syntheticDash2Flag || $0 == syntheticDash2TailR047Flag }
        guard syntheticArgs.count <= 1 else { return .failure(.conflictingQAMode) }
        let isSyntheticDash2 = !syntheticArgs.isEmpty
        if isSyntheticDash2 {
            if syntheticArgs[0] == syntheticDash2TailR047Flag,
               !arguments.contains("--qa-persist-fixture") { return .failure(.conflictingQAMode) }
            guard captureScope == .fullBattleParty,
                  r6PreviewArgs.count == 1,
                  encounterID == syntheticEncounterID else {
                return .failure(.syntheticPreviewRequiresFullBattleR6Route)
            }
        }
        var allowedQAFlags: Set<String> = [
            "--qa-isolated", "--qa-persist-fixture",
            "--qa-fixture=" + fixtureID,
            "--qa-equipment-motion-trace=" + gearID,
            "--qa-encounter=" + encounterID,
            "--qa-save-key=" + saveKey,
        ]
        if captureScope == .fullBattleParty { allowedQAFlags.insert(fullBattleFlag) }
        if !syntheticArgs.isEmpty {
            allowedQAFlags.insert(syntheticArgs[0])
            allowedQAFlags.insert(r6PreviewPrefix + encounterID)
        } else if !r6PreviewArgs.isEmpty {
            allowedQAFlags.insert(r6PreviewPrefix + encounterID)
        }
        for argument in arguments where argument.hasPrefix("--qa-") || argument.hasPrefix("--art-audit") {
            if allowedQAFlags.contains(argument) { continue }
            if argument.hasPrefix("--qa-character-growth-bp=") {
                // Full-battle evidence is intended to describe the pinned
                // default combat configuration. Keep the legacy five-phase
                // visual-only trace behavior unchanged.
                if captureScope == .fullBattleParty { return .failure(.conflictingQAMode) }
                continue
            }
            return .failure(.conflictingQAMode)
        }

        let prefix = "equipment_motion_\(saveKey)_"
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
        guard !existing.contains(where: { $0.hasPrefix(prefix) || $0.hasPrefix("r043_\(saveKey)_") || $0.hasPrefix("r047_\(saveKey)_") }) else { return .failure(.saveKeyAlreadyUsed) }
        return .success(EquipmentMotionTraceRequest(fixture: fixtureID, encounterID: encounterID,
                                                    saveKey: saveKey, captureScope: captureScope))
    }

    static func isSafe(_ value: String) -> Bool {
        guard (12...64).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 }
    }
}
