import Foundation

/// Explicitly synthetic UI fixtures for the recipe-goal candidate. Never used by
/// ordinary launch and never described as earned progression evidence.
enum RecipeGoalQAFixtureR037 {
    enum Scenario: String, Codable, CaseIterable {
        case lockedTrackClear = "locked-track-clear"
        case craftReady = "craft-ready"
        case evolveReady = "evolve-ready"
        case gatherShortage = "gather-shortage"

        var recipeID: String {
            switch self {
            case .lockedTrackClear: "RC_EQ_W_P1"
            case .craftReady: "RC_EQ_BODY_01"
            case .evolveReady: "RC_EQ_W_G1"
            case .gatherShortage: "RC_EQ_BODY_01"
            }
        }

        var classification: String { "SYNTHETIC_QA_FIXTURE_NOT_EARNED" }
    }

    struct Receipt: Encodable {
        let schema = "recipe-goal-fixture-r037-v2"
        let saveKey: String
        let scenario: Scenario
        let classification: String
        let recipeID: String
        let parentGearID: String?
        let outputGearID: String
        let syntheticInputs: [String: String]
        let recipeCosts: [String: Int]
        let dustCost: Int
        let materialID: String?
        let regionID: String?
        let requiredCount: Int
        let workSeconds: Int?
        let xpPerWork: Int?
        let dustPerWork: Int?
        // Preserve the legacy ISO-8601 field above for R037/R039 consumers.
        // This versioned JSON string is a second exact snapshot representation using
        // Foundation default seconds-since-reference-date Date encoding.
        let baselineSnapshotEncoding: String = "foundation-json-secondsSinceReferenceDate-v1"
        let baselineSnapshotCanonicalJSON: String
        let baselineSnapshot: GameSnapshot
    }

    struct Request: Equatable {
        let scenario: Scenario
        let saveKey: String
    }

    /// Accept only the one isolated recipe-goal fixture route. This candidate
    /// deliberately rejects co-launched audit/StoreKit/combat QA modes.
    static func request(arguments: [String]) throws -> Request {
        func exactlyOnce(_ value: String) -> Bool { arguments.filter { $0 == value }.count == 1 }
        guard exactlyOnce("--qa-isolated"),
              exactlyOnce("--qa-fixture=recipe-goal-r037"),
              exactlyOnce("--qa-persist-fixture"),
              exactlyOnce("--qa-recipe-goal-baseline") else {
            throw CoreError.invalidCommand("recipe-goal UI QA requires the exact isolated persisted-fixture contract")
        }
        let scenarioArguments = arguments.filter { $0.hasPrefix("--qa-recipe-goal=") }
        let scenarioValue = scenarioArguments.count == 1
            ? String(scenarioArguments[0].dropFirst("--qa-recipe-goal=".count)) : nil
        guard let scenarioValue, let scenario = Scenario(rawValue: scenarioValue) else {
            throw CoreError.invalidCommand("recipe-goal UI QA scenario is missing or unsupported")
        }
        let saveKeyArguments = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        let saveKey = saveKeyArguments.count == 1
            ? String(saveKeyArguments[0].dropFirst("--qa-save-key=".count)) : nil
        let safe = try NSRegularExpression(pattern: "^recipe-goal-r037-[A-Fa-f0-9-]{36}$")
        guard let saveKey,
              safe.firstMatch(in: saveKey, range: NSRange(saveKey.startIndex..., in: saveKey)) != nil,
              UUID(uuidString: String(saveKey.dropFirst("recipe-goal-r037-".count))) != nil else {
            throw CoreError.invalidCommand("recipe-goal UI QA requires a unique UUID save key")
        }
        let allowedQAArguments: Set<String> = [
            "--qa-isolated", "--qa-fixture=recipe-goal-r037", "--qa-persist-fixture",
            "--qa-recipe-goal-baseline"
        ]
        let qaArguments = arguments.filter { $0.hasPrefix("--qa-") }
        guard qaArguments.allSatisfy({
            allowedQAArguments.contains($0) || $0 == "--qa-recipe-goal=" + scenarioValue
                || $0 == "--qa-save-key=" + saveKey
        }) else {
            throw CoreError.invalidCommand("recipe-goal UI QA cannot run with another QA mode")
        }
        guard !arguments.contains(where: {
            $0.hasPrefix("--art-audit") || $0.hasPrefix("--xcode-local-storekit-qa")
        }) else {
            throw CoreError.invalidCommand("recipe-goal UI QA conflicts with another isolated UI mode")
        }
        return Request(scenario: scenario, saveKey: saveKey)
    }

    static func make(catalog: GameCatalog,
                     policy: CandidateLatentSlotPolicyR003,
                     scenario: Scenario) throws -> GameSnapshot {
        let expectedKind = scenario == .craftReady || scenario == .gatherShortage ? "craft_new" : "evolve_in_place"
        guard let recipe = catalog.recipes.first(where: { $0.id == scenario.recipeID }),
              recipe.kind == expectedKind else {
            throw CoreError.invalidCommand("recipe-goal QA fixture recipe contract mismatch")
        }
        var state = try GameSnapshot.newCandidateGame(catalog: catalog, candidateLatentPolicy: policy)
        state.lastClaimAt = Date()
        state.trackedRecipeID = nil
        state.completedEncounterIDs.removeAll()
        state.materials = [:]

        switch scenario {
        case .lockedTrackClear:
            // An owned W01 parent is available, but its R02 gate and costs are not.
            guard recipe.parentTemplateID == "EQ_W_01",
                  state.gear.contains(where: { $0.definitionID == recipe.parentTemplateID }) else {
                throw CoreError.invalidCommand("locked recipe fixture lacks its authored starter parent")
            }
        case .gatherShortage:
            // The R01 gate is explicitly synthetic; gathering itself is not seeded.
            // The Core availability projection and setGatherTargetAt command still
            // validate the target through the normal catalog gates.
            state.completedEncounterIDs.insert("B_R01_A")
            guard recipe.id == "RC_EQ_BODY_01",
                  recipe.costs["M_R01_G3"] ?? 0 > 0,
                  state.unlockedRegionIDs.contains("R01"),
                  catalog.availableGatherMaterialIDs(in: "R01",
                    unlockedRegionIDs: state.unlockedRegionIDs,
                    completedEncounterIDs: state.completedEncounterIDs).contains("M_R01_G3"),
                  let region = catalog.regions.first(where: { $0.id == "R01" }),
                  let alternate = region.gatherMaterialIDs.first(where: { $0 != "M_R01_G3" }) else {
                throw CoreError.invalidCommand("gather fixture requires unlocked R01 source and distinct initial target")
            }
            state.activeRegionID = "R01"
            state.gatherTargetMaterialID = alternate
            state.trackedRecipeID = recipe.id
            state.materials = [:]
        case .craftReady, .evolveReady:
            // Seed only the catalog recipe's exact costs and the existing gate.
            if let gateID = recipe.gateID, gateID != "G_START" {
                let pieces = gateID.split(separator: "_")
                guard pieces.count == 3, pieces[0] == "G" else {
                    throw CoreError.invalidCommand("recipe-goal fixture cannot resolve catalog gate")
                }
                state.completedEncounterIDs.insert("B_\(pieces[1])_\(pieces[2])")
            }
            state.materials = recipe.costs
            if recipe.dustCost > 0 { state.materials["refine_dust"] = recipe.dustCost }
            if scenario == .evolveReady {
                guard let parent = recipe.parentTemplateID,
                      state.gear.contains(where: { $0.definitionID == parent }) else {
                    throw CoreError.invalidCommand("evolution fixture lacks its authored starter parent")
                }
            }
        }
        return state
    }

    static func receiptData(scenario: Scenario, saveKey: String, catalog: GameCatalog,
                            state: GameSnapshot) throws -> Data {
        let safe = try NSRegularExpression(pattern: "^recipe-goal-r037-[A-Fa-f0-9-]{36}$")
        guard safe.firstMatch(in: saveKey, range: NSRange(saveKey.startIndex..., in: saveKey)) != nil,
              UUID(uuidString: String(saveKey.dropFirst("recipe-goal-r037-".count))) != nil else {
            throw CoreError.invalidCommand("fixture receipt requires its unique QA save key")
        }
        guard let recipe = catalog.recipes.first(where: { $0.id == scenario.recipeID }) else {
            throw CoreError.invalidCommand("fixture receipt recipe is missing from catalog")
        }
        let inputs: [String: String] = [
            "resourceSeed": scenario == .lockedTrackClear ? "none" : (scenario == .gatherShortage ? "empty_synthetic_shortage" : "exact_catalog_costs_only"),
            "gateSeed": scenario == .lockedTrackClear ? "not_completed" : (scenario == .gatherShortage ? "synthetic_completed:B_R01_A" : (recipe.gateID ?? "none")),
            "gearSeed": scenario == .evolveReady ? (recipe.parentTemplateID ?? "missing") : "normal_candidate_new_game_inventory",
            "evolveParentUUID": scenario == .evolveReady ? "10000000-0000-4000-8000-000000000001" : "none",
            "earnedClaim": "false",
            "gatherSource": scenario == .gatherShortage ? "R01|M_R01_G3|boss_gate_synthetic;gather_material_not_seeded" : "none"
        ]
        let canonicalEncoder = JSONEncoder()
        canonicalEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let canonicalSnapshotData = try canonicalEncoder.encode(state)
        guard let canonicalSnapshotJSON = String(data: canonicalSnapshotData, encoding: .utf8) else {
            throw CoreError.invalidCommand("fixture canonical snapshot is not UTF-8 JSON")
        }
        return try JSONEncoder.recipeGoalSorted.encode(
            Receipt(saveKey: saveKey, scenario: scenario, classification: scenario.classification,
                    recipeID: scenario.recipeID, parentGearID: recipe.parentTemplateID,
                    outputGearID: recipe.outputGearID ?? "",
                    syntheticInputs: inputs,
                    recipeCosts: recipe.costs, dustCost: recipe.dustCost,
                    materialID: scenario == .gatherShortage ? "M_R01_G3" : nil,
                    regionID: scenario == .gatherShortage ? "R01" : nil,
                    requiredCount: scenario == .gatherShortage ? (recipe.costs["M_R01_G3"] ?? 0) : 0,
                    workSeconds: scenario == .gatherShortage ? catalog.regions.first(where: { $0.id == "R01" })?.workSeconds : nil,
                    xpPerWork: scenario == .gatherShortage ? catalog.regions.first(where: { $0.id == "R01" })?.xpPerWork : nil,
                    dustPerWork: scenario == .gatherShortage ? catalog.regions.first(where: { $0.id == "R01" })?.dustPerWork : nil,
                    baselineSnapshotCanonicalJSON: canonicalSnapshotJSON,
                    baselineSnapshot: state))
    }
}

private extension JSONEncoder {
    static var recipeGoalSorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
