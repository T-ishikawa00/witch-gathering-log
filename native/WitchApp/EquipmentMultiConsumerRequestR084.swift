import Foundation

/// Isolated-only selector for the three fixed 53-consumer continuity variants.
/// It never creates ownership; QAScenarios may use this ID only to construct a
/// clearly synthetic render fixture in a fresh QA save.
struct EquipmentMultiConsumerRequestR084 {
    static let schema = "equipment-multi-consumer-r084-v1"
    static let flagPrefix = "--qa-equipment-detail-batch-r084="
    static let showcaseFlagPrefix = "--qa-equipment-detail-showcase-r084="
    static let fixturePrefix = "equipment-multi-r084-"
    static let encounterID = "E_R01_01"
    static let formalActors: [(core: String, sprite: String)] = [
        ("C_WITCH", "ERNA"), ("C_APPRENTICE", "LUNA"),
        ("C_SMITH", "AIRA"), ("C_FAMILIAR", "NOIR")
    ]
    static let accessorySlots = ["body", "hands", "feet", "amulet", "ring"]

    struct Variant {
        let id: String
        let tier: String
        let smithHammer: String?
        var fixtureID: String { EquipmentMultiConsumerRequestR084.fixturePrefix + String(id.suffix(2)) }
        var consumers: [(owner: String, sprite: String, gearID: String, slot: String)] {
            var rows: [(String,String,String,String)] = []
            for actor in EquipmentMultiConsumerRequestR084.formalActors where actor.core != "C_FAMILIAR" {
                for slot in EquipmentMultiConsumerRequestR084.accessorySlots {
                    rows.append((actor.core, actor.sprite, "EQ_\(slotPrefix(slot))_\(tier)", slot))
                }
            }
            rows.append(("C_FAMILIAR", "NOIR", "EQ_AMU_\(tier)", "amulet"))
            rows.append(("C_FAMILIAR", "NOIR", "EQ_F_\(tier)", "weapon"))
            if let smithHammer { rows.append(("C_SMITH", "AIRA", smithHammer, "weapon")) }
            return rows
        }
        private func slotPrefix(_ slot: String) -> String {
            switch slot {
        case "body": return "BODY"
        case "hands": return "HAND"
        case "feet": return "FEET"
        case "amulet": return "AMU"
        default: return "RING"
        }
        }
    }

    static let variants: [String: Variant] = [
        "loadout_variant_01": .init(id: "loadout_variant_01", tier: "01", smithHammer: "EQ_S_02"),
        "loadout_variant_02": .init(id: "loadout_variant_02", tier: "02", smithHammer: "EQ_S_03"),
        "loadout_variant_03": .init(id: "loadout_variant_03", tier: "03", smithHammer: nil)
    ]
    static func expectedCount(_ id: String) -> Int? {
        switch id {
        case "loadout_variant_01", "loadout_variant_02": return 18
        case "loadout_variant_03": return 17
        default: return nil
        }
    }

    enum Failure: String, Error {
        case notIsolated, existingSave, duplicateOrUnknownVariant, wrongFixture
        case invalidSaveKey, wrongEncounter, conflictingMode, missingPersistFixture
    }

    let variant: Variant
    let saveKey: String
    let encounterID: String
    let evidenceMode: String

    static func parse(arguments: [String], existingSaveLoaded: Bool) -> Result<Self, Failure> {
        guard arguments.contains("--qa-isolated") else { return .failure(.notIsolated) }
        guard !existingSaveLoaded else { return .failure(.existingSave) }
        let battleSelectors = arguments.filter { $0.hasPrefix(flagPrefix) }
        let showcaseSelectors = arguments.filter { $0.hasPrefix(showcaseFlagPrefix) }
        guard battleSelectors.count + showcaseSelectors.count == 1 else { return .failure(.duplicateOrUnknownVariant) }
        let showcase = !showcaseSelectors.isEmpty
        let selected = showcase ? showcaseSelectors[0] : battleSelectors[0]
        let selectorPrefix = showcase ? showcaseFlagPrefix : flagPrefix
        guard let variant = variants[String(selected.dropFirst(selectorPrefix.count))] else {
            return .failure(.duplicateOrUnknownVariant)
        }
        guard arguments.filter({ $0 == "--qa-fixture=" + variant.fixtureID }).count == 1,
              arguments.filter({ $0.hasPrefix("--qa-fixture=") }).count == 1 else { return .failure(.wrongFixture) }
        guard arguments.filter({ $0 == "--qa-persist-fixture" }).count == 1 else { return .failure(.missingPersistFixture) }
        let keys = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard keys.count == 1 else { return .failure(.invalidSaveKey) }
        let key = String(keys[0].dropFirst("--qa-save-key=".count))
        guard UUID(uuidString: key) != nil else { return .failure(.invalidSaveKey) }
        let encounters = arguments.filter { $0.hasPrefix("--qa-encounter=") }
        let hasFullBattle = arguments.contains("--qa-party-cast-full-battle")
        if showcase {
            guard encounters.isEmpty, !hasFullBattle else { return .failure(.conflictingMode) }
        } else {
            guard encounters.count == 1, encounters[0] == "--qa-encounter=" + encounterID,
                  hasFullBattle else { return .failure(.wrongEncounter) }
        }
        let allowed: Set<String> = ["--qa-isolated", "--qa-persist-fixture", "--qa-save-key=" + key,
                                     "--qa-fixture=" + variant.fixtureID,
                                     flagPrefix + variant.id, showcaseFlagPrefix + variant.id,
                                     "--qa-encounter=" + encounterID, "--qa-party-cast-full-battle"]
        for arg in arguments where arg.hasPrefix("--qa-") || arg.hasPrefix("--art-audit") {
            if allowed.contains(arg) || arg.hasPrefix("--qa-load-delay-ms=") { continue }
            return .failure(.conflictingMode)
        }
        return .success(.init(variant: variant, saveKey: key, encounterID: encounterID,
                              evidenceMode: showcase ? "forced_render_showcase" : "natural_full_battle"))
    }
}
