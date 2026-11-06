import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Reproducible candidate-only, command-driven 90 virtual-day progression run.
/// It uses a fresh snapshot and isolated file-backed save, reopens that save at
/// every day boundary, and never seeds combat wins or grants inventory directly.
final class ProgressionE2ERunnerTests: XCTestCase {
    private struct Action: Encodable {
        let sequence: Int, day: Int
        let atEpoch: Int64
        let command: String
        let outcome: String
        let receipt: String?
        let revision: Int64?
        let seed: UInt64?
        let resourceDelta: [String: Int]?
    }
    private struct Day: Encodable {
        let day: Int, epoch: Int64, activeRegion: String?
        let unlockedRegions: [String], campaignClears: Int, challengeClears: Int
        let gearInstances: Int, equippedSlots: Int, tickets: Int, dust: Int
        let materialUnits: Int, partyXP: Int, candidateGrowthLevels: [String: Int]?, saveSHA256: String
    }
    private struct Summary: Encodable {
        let schema: String, approval: String, seed: UInt64, candidateOverlayID: String
        let investmentStrategy: String, gearTierPolicy: String
        let candidateGrowthProfile: String, finalCandidateGrowthLevels: [String: Int]?
        let virtualClock: String, loginPolicy: String, battlePolicy: String
        let catalogVersion: String, catalogSHA256: String, sourceFilesSHA256: String
        let actionLogSHA256: String, finalSaveSHA256: String
        let semanticStateSHA256: String
        let reportArtifact: String, actionLogArtifact: String, finalSaveArtifact: String
        let checkpointSnapshots: [String: String]
        let actions: Int, successfulCommands: Int, failedCommands: Int
        let gathers: Int, crafts: Int, evolutions: Int, enhancements: Int
        let refinements: Int, qualityPromotions: Int, summons: Int, dismantles: Int
        let campaignAttempts: Int, campaignWins: Int, campaignDefeats: Int
        let eR0304Encounters: Int, eR0304MarkEvents: Int, eR0304Hits: Int, eR0304CandidateHits: Int
        let farmAttempts: Int, farmWins: Int, farmDefeats: Int
        let challengeAttempts: Int, challengeWins: Int, challengeDefeats: Int
        let firstCampaignClearDay: Int?, allChallengesClearDay: Int?
        let unresolvedEnemies: [String], unresolvedChallenges: [String]
        let finalRevision: Int64, finalGearInstances: Int, finalEquippedSlots: Int
        let finalInventoryTemplates: [String], finalMaterialBalances: [String: Int]
        let dailyRows: [Day]
        let constraints: [String]
    }

    func testFreshSaveToNinetyDayCampaignAndChallengeProgression() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let candidateMode = ProcessInfo.processInfo.environment["WITCH_E2E_CANDIDATE_OVERLAY"] == "r014"
        let candidateOverlay = candidateMode ? CandidateCombatOverlay.r014LocalCandidate : nil
        let growthProfile: CandidateCharacterGrowth?
        let growthProfileTag: String
        if let configured = ProcessInfo.processInfo.environment["WITCH_E2E_GROWTH_BP"] {
            guard let bp = Int(configured), [0, 250, 500, 750, 1_000, 2_500, 10_000].contains(bp) else {
                throw NSError(domain: "ProgressionE2E", code: 2, userInfo: [NSLocalizedDescriptionKey: "WITCH_E2E_GROWTH_BP must be one of 0, 250, 500, 750, 1000, 2500, 10000"])
            }
            growthProfile = CandidateCharacterGrowth(strengthBP: bp)
            growthProfileTag = growthProfile!.id
        } else {
            growthProfile = nil
            growthProfileTag = "NONE"
        }
        let investmentStrategy = ProcessInfo.processInfo.environment["WITCH_E2E_INVESTMENT_STRATEGY"] ?? "free_ward"
        guard ["passive_control", "free_ward", "free_poison"].contains(investmentStrategy) else {
            throw NSError(domain: "ProgressionE2E", code: 3, userInfo: [NSLocalizedDescriptionKey: "WITCH_E2E_INVESTMENT_STRATEGY must be passive_control, free_ward, or free_poison"])
        }
        let gearTierPolicy = ProcessInfo.processInfo.environment["WITCH_E2E_GEAR_TIER_POLICY"] ?? "legacy_first"
        guard ["legacy_first", "nondecreasing_highest"].contains(gearTierPolicy) else {
            throw NSError(domain: "ProgressionE2E", code: 4, userInfo: [NSLocalizedDescriptionKey: "WITCH_E2E_GEAR_TIER_POLICY must be legacy_first or nondecreasing_highest"])
        }
        let overlayTag = "\(candidateMode ? "r014" : "control")_\(growthProfileTag.lowercased())_\(investmentStrategy)_\(gearTierPolicy)"
        let baseSeed: UInt64 = 0x5749544348453245
        let seed: UInt64
        if let configured = ProcessInfo.processInfo.environment["WITCH_E2E_SEED"] {
            if configured.hasPrefix("0x"), let value = UInt64(configured.dropFirst(2), radix: 16) { seed = value }
            else if let value = UInt64(configured) { seed = value }
            else { throw NSError(domain: "ProgressionE2E", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid WITCH_E2E_SEED: \(configured)"]) }
        } else { seed = baseSeed }
        let epoch: Int64 = 1_792_000_000
        let fm = FileManager.default
        let runID = UUID().uuidString
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("witch-progression-e2e-r003-\(overlayTag)-\(seed)-\(runID)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WITCH_E2E_OUTPUT"] ?? root.appendingPathComponent("report.json").path)
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let checkpointDirectory = output.deletingLastPathComponent().appendingPathComponent("combat_checkpoints", isDirectory: true)
        let seedTag = String(seed, radix: 16, uppercase: false)
        let actionURL = output.deletingLastPathComponent().appendingPathComponent("progression_actions_seed_\(seedTag).json")
        let saveArtifactURL = output.deletingLastPathComponent().appendingPathComponent("qa_final_save_seed_\(seedTag).json")
        let sourceURL = output.deletingLastPathComponent().appendingPathComponent("source_sha256.txt")
        let outputFiles = [output, output.deletingPathExtension().appendingPathExtension("md"), actionURL, saveArtifactURL, sourceURL]
        guard outputFiles.allSatisfy({ !fm.fileExists(atPath: $0.path) }),
              !fm.fileExists(atPath: checkpointDirectory.path) else {
            throw NSError(domain: "ProgressionE2E", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "refusing to overwrite prior E2E artifacts"])
        }
        try fm.createDirectory(at: checkpointDirectory, withIntermediateDirectories: false)
        var checkpointArtifacts: [String: String] = [:]
        let saveURL = root.appendingPathComponent("save.json")
        let initial = GameSnapshot.newGame(catalog: catalog)
        XCTAssertEqual(initial.gear.count, 4, "only canonical starter gear should exist at start")
        XCTAssertEqual(initial.unlockedRegionIDs, [catalog.regions.first!.id])
        var store = try SaveRepository(initial: initial, fileURL: saveURL)
        var game = try GameEngine(catalog: catalog, saves: store, candidateCombatOverlay: candidateOverlay,
                                  candidateCharacterGrowth: growthProfile)
        var actions: [Action] = []
        var dailyRows: [Day] = []
        var sequence = 0
        var successes = 0, failures = 0
        var gathers = 0, crafts = 0, evolutions = 0, enhancements = 0, refinements = 0, promotions = 0, summons = 0
        var dismantles = 0
        var campaignAttempts = 0, campaignWins = 0, campaignDefeats = 0
        var eR0304Encounters = 0, eR0304MarkEvents = 0, eR0304Hits = 0, eR0304CandidateHits = 0
        var farmAttempts = 0, farmWins = 0, farmDefeats = 0
        var challengeAttempts = 0, challengeWins = 0, challengeDefeats = 0
        var firstCampaignClearDay: Int?, allChallengesClearDay: Int?
        var bossAClearDayByRegion: [String: Int] = [:]
        var smithBodyCrafted = false

        func nextOperationID() -> UUID {
            sequence += 1
            return UUID(uuidString: String(format: "57495443-0000-4000-8000-%012llx", UInt64(sequence)))!
        }
        func commandSeed(_ command: GameCommand) -> UInt64? {
            switch command {
            case .resolveEncounter(_, let value), .resolveChallenge(_, let value), .mockSummon(_, _, _, let value): return value
            default: return nil
            }
        }
        func resourceDelta(_ before: GameSnapshot, _ after: GameSnapshot) -> [String: Int] {
            var result: [String: Int] = [:]
            for (prefix, lhs, rhs) in [("material", before.materials, after.materials), ("currency", before.currency, after.currency)] {
                for key in Set(lhs.keys).union(rhs.keys).sorted() {
                    let delta = rhs[key, default: 0] - lhs[key, default: 0]
                    if delta != 0 { result["\(prefix):\(key)"] = delta }
                }
            }
            return result
        }
        func stableReceipt(_ input: String) -> String {
            let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
            let ns = input as NSString
            return regex.stringByReplacingMatches(in: input, range: NSRange(location: 0, length: ns.length), withTemplate: "<instance-uuid>")
        }
        func record(_ command: GameCommand, label: String, day: Int, at: Int64) async -> String? {
            let before = await store.snapshot()
            do {
                let receipt = try await game.dispatch(command, operationID: nextOperationID(), expectedRevision: before.revision)
                successes += 1
                if case .resolveEncounter(let enemyID, _) = command, enemyID == "E_R03_04" {
                    eR0304Encounters += 1
                    let battle = await store.snapshot().lastCombatResult
                    let events = battle?.events ?? []
                    eR0304MarkEvents += events.filter { $0.sourceID == enemyID && $0.kind == "enemy_magnet_mark" }.count
                    let hits = events.filter { $0.sourceID == enemyID && $0.kind == "enemy_hit" }
                    eR0304Hits += hits.count
                    eR0304CandidateHits += hits.filter { $0.diagnostics?["candidateMagnetCoefficientBP"] == 12_500 }.count
                }
                let after = await store.snapshot()
                actions.append(Action(sequence: sequence, day: day, atEpoch: at, command: label,
                                      outcome: "committed", receipt: stableReceipt(receipt.result), revision: receipt.revision,
                                      seed: commandSeed(command), resourceDelta: resourceDelta(before, after)))
                return receipt.result
            } catch {
                failures += 1
                actions.append(Action(sequence: sequence, day: day, atEpoch: at, command: label,
                                      outcome: "rejected: \(error.localizedDescription)", receipt: nil, revision: nil,
                                      seed: commandSeed(command), resourceDelta: nil))
                return nil
            }
        }
        func recordOfflineClaim(day: Int, at: Int64) async {
            let before = await store.snapshot()
            do {
                let receipt = try await game.claimOffline(now: Date(timeIntervalSince1970: TimeInterval(at)),
                    operationID: nextOperationID(), expectedRevision: before.revision)
                successes += 1
                let after = await store.snapshot()
                actions.append(Action(sequence: sequence, day: day, atEpoch: at, command: "claimOffline",
                                      outcome: "committed", receipt: stableReceipt(receipt.result), revision: receipt.revision,
                                      seed: nil, resourceDelta: resourceDelta(before, after)))
            } catch {
                failures += 1
                actions.append(Action(sequence: sequence, day: day, atEpoch: at, command: "claimOffline",
                                      outcome: "rejected: \(error.localizedDescription)", receipt: nil, revision: nil,
                                      seed: nil, resourceDelta: nil))
            }
        }
        func gateIsClear(_ gate: String?, _ state: GameSnapshot) -> Bool {
            guard let gate, gate != "G_START" else { return true }
            let p = gate.split(separator: "_")
            guard p.count == 3 else { return false }
            return state.completedEncounterIDs.contains("B_\(p[1])_\(p[2])")
        }
        func recipeAffordable(_ recipe: RecipeDefinition, _ state: GameSnapshot) -> Bool {
            gateIsClear(recipe.gateID, state) && recipe.costs.allSatisfy { state.materials[$0.key, default: 0] >= $0.value }
                && state.materials["refine_dust", default: 0] >= recipe.dustCost
        }
        func currentGear(_ actor: String, _ slot: String, _ state: GameSnapshot) -> GearInstance? {
            guard let id = state.equippedGearIDs["\(actor)|\(slot)"] else { return nil }
            return state.gear.first(where: { $0.id == id })
        }

        // Spend only catalog recipes and successful command rewards. Current build
        // pursues Witch ward, apprentice healing support, Smith guard, familiar chase.
        func runInvestmentPolicy(day: Int, at: Int64) async {
            var state = await store.snapshot()
            if investmentStrategy == "passive_control" { return }
            let roles: [(String, [String])] = investmentStrategy == "free_poison" ? [
                ("C_WITCH", ["EQ_W_P1", "EQ_W_P2"]),
                ("C_APPRENTICE", ["EQ_A_02", "EQ_A_03"]),
                ("C_SMITH", ["EQ_S_02", "EQ_S_03"]),
                ("C_FAMILIAR", ["EQ_F_02", "EQ_F_03"])
            ] : [
                ("C_WITCH", ["EQ_W_G1", "EQ_W_G2"]),
                ("C_APPRENTICE", ["EQ_A_02", "EQ_A_03"]),
                ("C_SMITH", ["EQ_S_02", "EQ_S_03"]),
                ("C_FAMILIAR", ["EQ_F_02", "EQ_F_03"])
            ]
            for (actor, targets) in roles {
                for target in targets {
                    let state = await store.snapshot()
                    guard let equipped = currentGear(actor, "weapon", state),
                          let recipe = catalog.recipes.first(where: { $0.kind == "evolve_in_place" && $0.outputGearID == target && $0.parentTemplateID == equipped.definitionID }),
                          recipeAffordable(recipe, state) else { continue }
                    if await record(.evolveGear(gearID: equipped.id, recipeID: recipe.id), label: "evolve:\(recipe.id)", day: day, at: at) != nil { evolutions += 1 }
                }
            }
            // Craft/equip one missing defensive slot per actor when the real recipe is affordable.
            for actor in initial.partyActorIDs {
                for slot in ["body", "hands", "hand", "feet", "amulet", "ring"] where currentGear(actor, slot, await store.snapshot()) == nil {
                    let state = await store.snapshot()
                    let candidates = catalog.recipes.filter { recipe in
                        guard recipe.kind == "craft_new", let outputID = recipe.outputGearID,
                              let definition = catalog.gear.first(where: { $0.id == outputID }) else { return false }
                        return definition.slot == slot && (definition.actorIDs.isEmpty || definition.actorIDs.contains(actor)) && recipeAffordable(recipe, state)
                    }
                    guard let recipe = candidates.first else { continue }
                    if await record(.craftRecipe(recipe.id), label: "craft:\(recipe.id)", day: day, at: at) != nil {
                        crafts += 1
                        let newState = await store.snapshot()
                        if let item = newState.gear.last(where: { $0.definitionID == recipe.outputGearID && $0.ownerID == nil }) {
                            _ = await record(.equip(gearID: item.id, actorID: actor), label: "equip:\(actor):\(item.definitionID)", day: day, at: at)
                        }
                    }
                }
            }
            state = await store.snapshot()
            for (actor, _) in roles {
                guard let item = currentGear(actor, "weapon", state) else { continue }
                if item.enhancement < 3,
                   let recipe = catalog.recipes.first(where: { $0.id == "ENHANCE_\(item.enhancement + 1)" }), recipeAffordable(recipe, state) {
                    if await record(.enhance(gearID: item.id), label: "enhance:\(actor):+\(item.enhancement + 1)", day: day, at: at) != nil { enhancements += 1 }
                }
                state = await store.snapshot()
                if let current = state.gear.first(where: { $0.id == item.id }), current.refinement < 2,
                   state.materials["refine_dust", default: 0] >= 5 {
                    if await record(.refine(gearID: current.id), label: "refine:\(actor)", day: day, at: at) != nil { refinements += 1 }
                }
                state = await store.snapshot()
                if let current = state.gear.first(where: { $0.id == item.id }), ["Q0", "Q1"].contains(current.qualityID) {
                    let recipeID = current.qualityID == "Q0" ? "QUALITY_Q0_Q1" : "QUALITY_Q1_Q2"
                    if let recipe = catalog.recipes.first(where: { $0.id == recipeID }), recipeAffordable(recipe, state),
                       await record(.promoteQuality(gearID: current.id), label: "promote:\(actor):\(recipeID)", day: day, at: at) != nil { promotions += 1 }
                }
            }
            // Only acquire the tutorial's first non-free weapon through the real recipe,
            // then use the game's actual same-slot comparison gate.
            state = await store.snapshot()
            if !state.gearComparisonSeen,
               let recipe = catalog.recipes.first(where: { $0.id == "RC_EQ_W_01" }), recipeAffordable(recipe, state),
               await record(.craftRecipe(recipe.id), label: "onboarding-craft:\(recipe.id)", day: day, at: at) != nil {
                crafts += 1
                let afterCraft = await store.snapshot()
                if let crafted = afterCraft.gear.last(where: { $0.definitionID == "EQ_W_01" && $0.id != initial.gear[0].id }) {
                    _ = await record(.equip(gearID: crafted.id, actorID: "C_WITCH"), label: "onboarding-equip:C_WITCH", day: day, at: at)
                    _ = await record(.markGearComparisonSeen(firstGearID: initial.gear[0].id, secondGearID: crafted.id), label: "onboarding-compare", day: day, at: at)
                }
            }
            // Equip a gacha-acquired target item only when it is the next intended
            // role upgrade; never inject items or bypass the catalog pool. The
            // nondecreasing_highest selector is an explicit test-only comparator.
            state = await store.snapshot()
            let roleQualityRank = ["Q0": 0, "Q1": 1, "Q2": 2, "Q3": 3, "Q4": 4]
            for (actor, targets) in roles {
                guard let held = currentGear(actor, "weapon", state) else { continue }
                let target: String?
                if gearTierPolicy == "nondecreasing_highest" {
                    let heldStage = targets.firstIndex(of: held.definitionID) ?? -1
                    target = targets.enumerated().reversed().first(where: { index, output in
                        index >= heldStage && state.gear.contains(where: { $0.definitionID == output })
                    })?.element
                } else {
                    target = targets.first(where: { output in state.gear.contains(where: { $0.definitionID == output }) })
                }
                guard let target,
                      catalog.gear.first(where: { $0.id == target })?.actorIDs.contains(actor) == true else { continue }
                let best: GearInstance?
                if gearTierPolicy == "nondecreasing_highest" {
                    best = state.gear.enumerated().filter { $0.element.definitionID == target }.sorted { lhs, rhs in
                        let lq = roleQualityRank[lhs.element.qualityID, default: 0], rq = roleQualityRank[rhs.element.qualityID, default: 0]
                        if lq != rq { return lq > rq }
                        if lhs.element.enhancement != rhs.element.enhancement { return lhs.element.enhancement > rhs.element.enhancement }
                        if lhs.element.refinement != rhs.element.refinement { return lhs.element.refinement > rhs.element.refinement }
                        return lhs.offset < rhs.offset
                    }.first?.element
                } else {
                    guard held.definitionID != target else { continue }
                    best = state.gear.last(where: { $0.definitionID == target })
                }
                guard let best, best.id != held.id else { continue }
                _ = await record(.equip(gearID: best.id, actorID: actor), label: "equip-target:\(actor):\(target)", day: day, at: at)
                state = await store.snapshot()
            }
            // A free daily summon is real candidate gameplay; use the whole catalog pool.
            state = await store.snapshot()
            if state.gachaUnlocked, state.currency["ticket_free", default: 0] >= 5 {
                let result = await record(.mockSummon(poolDefinitionIDs: catalog.gear.map(\.id), count: 5,
                    costCurrencyID: "ticket_free", seed: seed &+ UInt64(day)), label: "free-summon-x5", day: day, at: at)
                if result != nil { summons += 5 }
            }
            // Fill otherwise-empty slots from earned inventory using a transparent
            // quality-first policy. This invokes the same equip command as UI.
            state = await store.snapshot()
            let qualityRank = ["Q0": 0, "Q1": 1, "Q2": 2, "Q3": 3, "Q4": 4]
            for actor in initial.partyActorIDs {
                for slot in ["body", "hands", "hand", "feet", "amulet", "ring"] {
                    state = await store.snapshot()
                    if actor == "C_SMITH", slot == "body", !smithBodyCrafted { continue }
                    guard currentGear(actor, slot, state) == nil,
                          let candidate = state.gear.filter({ item in
                              guard let definition = catalog.gear.first(where: { $0.id == item.definitionID }) else { return false }
                              return !state.equippedGearIDs.values.contains(item.id)
                                  && definition.slot == slot && (definition.actorIDs.isEmpty || definition.actorIDs.contains(actor))
                          }).max(by: { qualityRank[$0.qualityID, default: 0] < qualityRank[$1.qualityID, default: 0] }) else { continue }
                    _ = await record(.equip(gearID: candidate.id, actorID: actor), label: "equip-empty-slot:\(actor):\(slot):\(candidate.definitionID)", day: day, at: at)
                }
            }
            // Keep repeated low-quality pulls from producing a 400+ item bag.
            // The engine itself decides whether an instance is safe to dismantle.
            while true {
                state = await store.snapshot()
                let equipped = Set(state.equippedGearIDs.values)
                guard let disposable = state.gear.first(where: { item in
                    !item.protected && !equipped.contains(item.id)
                        && state.gear.filter({ $0.definitionID == item.definitionID }).count > 1
                }) else { break }
                if await record(.dismantle(gearID: disposable.id), label: "dismantle-safe-duplicate:\(disposable.definitionID)", day: day, at: at) != nil {
                    dismantles += 1
                } else { break }
            }
        }

        for day in 1...90 {
            let dayStart = epoch + Int64(day - 1) * 86_400
            let dayEnd = dayStart + 86_400
            var state = await store.snapshot()
            if !state.gachaUnlocked { /* no daily grant before the actual tutorial gate */ }
            else { _ = await record(.dailyClaim(now: Date(timeIntervalSince1970: TimeInterval(dayStart))), label: "daily-claim", day: day, at: dayStart) }

            // One login/day: claim 24 virtual hours in separately settled eligible
            // resource windows. Only resources the catalog gates currently expose are used.
            guard let regionID = state.activeRegionID else { XCTFail("no active region"); return }
            let startRegionWasComplete = catalog.regions.first(where: { $0.id == regionID })?.enemyIDs.allSatisfy { state.completedEncounterIDs.contains($0) } ?? false
            if state.lastClaimAt == nil || state.activeRegionID != regionID {
                _ = await record(.startExpeditionAt(regionID: regionID, now: Date(timeIntervalSince1970: TimeInterval(dayStart))), label: "start-expedition:\(regionID)", day: day, at: dayStart)
            }
            var available = await game.availableGatherMaterials(in: regionID)
            if available.isEmpty {
                _ = await record(.startExpeditionAt(regionID: regionID, now: Date(timeIntervalSince1970: TimeInterval(dayStart))), label: "retry-expedition:\(regionID)", day: day, at: dayStart)
                available = await game.availableGatherMaterials(in: regionID)
            }
            if !available.isEmpty {
                let segment = Int64(86_400 / available.count)
                var cursor = dayStart
                for material in available {
                    state = await store.snapshot()
                    if state.gatherTargetMaterialID != material {
                        _ = await record(.setGatherTargetAt(resourceID: material, now: Date(timeIntervalSince1970: TimeInterval(cursor))), label: "gather-target:\(material)", day: day, at: cursor)
                    }
                    cursor += segment
                    if await record(.gather(resourceID: material, now: Date(timeIntervalSince1970: TimeInterval(cursor))), label: "gather:\(material)", day: day, at: cursor) != nil { gathers += 1 }
                }
                if cursor < dayEnd { await recordOfflineClaim(day: day, at: dayEnd) }
            }

            await runInvestmentPolicy(day: day, at: dayEnd)
            state = await store.snapshot()
            if state.gachaUnlocked {
                // Uncommon but required to demonstrate the actual catalog research command.
                for research in catalog.research where !state.completedResearchIDs.contains(research.id) {
                    guard gateIsClear(catalog.recipes.first(where: { $0.id == research.id })?.gateID, state),
                          research.cost.allSatisfy({ state.materials[$0.key, default: 0] >= $0.value }) else { continue }
                    _ = await record(.completeResearch(research.id), label: "research:\(research.id)", day: day, at: dayEnd)
                    state = await store.snapshot()
                }
            }

            if !state.completedEncounterIDs.contains("B_R05_B") {
                var battlesToday = 0
                while battlesToday < 3 {
                    state = await store.snapshot()
                    guard let active = state.activeRegionID,
                          let region = catalog.regions.first(where: { $0.id == active }),
                          let next = region.enemyIDs.first(where: { !state.completedEncounterIDs.contains($0) }) else { break }
                    if next.hasSuffix("_B"), next.hasPrefix("B_"),
                       bossAClearDayByRegion[state.activeRegionID ?? ""] == day { break }
                    campaignAttempts += 1
                    let result = await record(.resolveEncounter(enemyID: next, seed: seed &+ UInt64(day * 101 + battlesToday)),
                                              label: "campaign-encounter:\(next)", day: day, at: dayEnd)
                    battlesToday += 1
                    if result?.hasPrefix("VICTORY:") == true {
                        campaignWins += 1
                        if next == "B_R05_B", firstCampaignClearDay == nil { firstCampaignClearDay = day }
                        if next.hasSuffix("_A"), next.hasPrefix("B_") { bossAClearDayByRegion[state.activeRegionID ?? ""] = day }
                    }
                    else if result?.hasPrefix("DEFEAT:") == true { campaignDefeats += 1; break }
                    else { break }
                }
                // Candidate adaptive-ward economy policy: stay in the forest after
                // its campaign clear and use actual repeat encounters to earn the
                // E_R01_02 drop required by the first body recipe. This exposes the
                // enemy-drop bottleneck instead of manufacturing crafting inputs.
                state = await store.snapshot()
                if state.activeRegionID == "R01",
                   state.completedEncounterIDs.contains("B_R01_B"),
                   state.equippedGearIDs["C_SMITH|body"] == nil {
                    for farmIndex in 0..<3 {
                        state = await store.snapshot()
                        if state.materials["M_R01_E2", default: 0] >= 8 { break }
                        farmAttempts += 1
                        let farm = await record(.resolveEncounter(enemyID: "E_R01_02", seed: seed &+ UInt64(90_000 + day * 17 + farmIndex)),
                                                label: "farm-drop:E_R01_02", day: day, at: dayEnd)
                        if farm?.hasPrefix("VICTORY:") == true { farmWins += 1 }
                        else if farm?.hasPrefix("DEFEAT:") == true { farmDefeats += 1; break }
                        else { break }
                    }
                    state = await store.snapshot()
                    if !smithBodyCrafted, let bodyRecipe = catalog.recipes.first(where: { $0.id == "RC_EQ_BODY_01" }), recipeAffordable(bodyRecipe, state),
                       await record(.craftRecipe(bodyRecipe.id), label: "farm-goal-craft:\(bodyRecipe.id)", day: day, at: dayEnd) != nil {
                        crafts += 1
                        let afterBody = await store.snapshot()
                        if let body = afterBody.gear.last(where: { $0.definitionID == "EQ_BODY_01" && $0.ownerID == nil }) {
                            smithBodyCrafted = await record(.equip(gearID: body.id, actorID: "C_SMITH"), label: "farm-goal-equip:C_SMITH:EQ_BODY_01", day: day, at: dayEnd) != nil
                        }
                    }
                }
                // Re-evaluate the actual party after drops and boss-gated resources
                // arrive; e.g. the ward evolution is a command, never pre-granted.
                await runInvestmentPolicy(day: day, at: dayEnd)
                state = await store.snapshot()
                if let regionID = state.activeRegionID,
                   let index = catalog.regions.firstIndex(where: { $0.id == regionID }),
                   !catalog.regions[index].enemyIDs.contains(where: { !state.completedEncounterIDs.contains($0) }),
                   startRegionWasComplete,
                   (regionID != "R01" || state.equippedGearIDs["C_SMITH|body"] != nil),
                   catalog.regions.indices.contains(index + 1), state.unlockedRegionIDs.contains(catalog.regions[index + 1].id) {
                    let nextRegion = catalog.regions[index + 1].id
                    _ = await record(.startExpeditionAt(regionID: nextRegion, now: Date(timeIntervalSince1970: TimeInterval(dayEnd))),
                                     label: "advance-expedition:\(nextRegion)", day: day, at: dayEnd)
                }
            } else {
                var attempts = 0
                while attempts < 3 {
                    state = await store.snapshot()
                    guard let challenge = catalog.challenges.first(where: { !state.completedEncounterIDs.contains("CHALLENGE_CLEAR|\($0.id)") }) else {
                        allChallengesClearDay = allChallengesClearDay ?? day
                        break
                    }
                    challengeAttempts += 1
                    let result = await record(.resolveChallenge(challengeID: challenge.id, seed: seed &+ UInt64(day * 1_009 + attempts)),
                                              label: "challenge:\(challenge.id)", day: day, at: dayEnd)
                    attempts += 1
                    if result?.contains("SIMULATED_VICTORY") == true { challengeWins += 1 }
                    else if result?.contains("SIMULATED_DEFEAT") == true { challengeDefeats += 1; break }
                    else { break }
                }
                state = await store.snapshot()
                if catalog.challenges.allSatisfy({ state.completedEncounterIDs.contains("CHALLENGE_CLEAR|\($0.id)") }) {
                    allChallengesClearDay = allChallengesClearDay ?? day
                }
            }

            // Actual durable save reopen and equality check at every virtual day boundary.
            let beforeReopen = await store.snapshot()
            store = try SaveRepository(fileURL: saveURL)
            game = try GameEngine(catalog: catalog, saves: store, candidateCombatOverlay: candidateOverlay,
                                  candidateCharacterGrowth: growthProfile)
            let afterReopen = await store.snapshot()
            XCTAssertEqual(afterReopen, beforeReopen, "save/reopen changed snapshot on day \(day)")
            let saveData = try Data(contentsOf: saveURL)
            if [1, 7, 14, 21, 30, 90].contains(day) {
                let checkpointName = String(format: "snapshot_day_%02d.json", day)
                let checkpointURL = checkpointDirectory.appendingPathComponent(checkpointName)
                let checkpointEncoder = JSONEncoder()
                checkpointEncoder.outputFormatting = [.sortedKeys]
                let checkpointData = try checkpointEncoder.encode(afterReopen)
                try checkpointData.write(to: checkpointURL, options: .atomic)
                checkpointArtifacts["day_\(day)"] = checkpointURL.path
            }
            dailyRows.append(Day(day: day, epoch: dayEnd, activeRegion: afterReopen.activeRegionID,
                unlockedRegions: afterReopen.unlockedRegionIDs.sorted(),
                campaignClears: afterReopen.completedEncounterIDs.filter { !$0.hasPrefix("CHALLENGE_CLEAR|") }.count,
                challengeClears: afterReopen.completedEncounterIDs.filter { $0.hasPrefix("CHALLENGE_CLEAR|") }.count,
                gearInstances: afterReopen.gear.count, equippedSlots: afterReopen.equippedGearIDs.count,
                tickets: afterReopen.currency["ticket_free", default: 0], dust: afterReopen.materials["refine_dust", default: 0],
                materialUnits: afterReopen.materials.values.reduce(0, +),
                partyXP: afterReopen.characterXP.values.reduce(0, +),
                candidateGrowthLevels: growthProfile.map { _ in Dictionary(uniqueKeysWithValues: afterReopen.characterXP.map { ($0.key, CandidateCharacterGrowth.progress(totalXP: $0.value).level) }) },
                saveSHA256: SHA256.hash(data: saveData).map { String(format: "%02x", $0) }.joined()))
        }

        let finalState = await store.snapshot()
        let enemies = catalog.enemies.map(\.id)
        let challenges = catalog.challenges.map(\.id)
        let unresolvedEnemies = enemies.filter { !finalState.completedEncounterIDs.contains($0) }
        let unresolvedChallenges = challenges.filter { !finalState.completedEncounterIDs.contains("CHALLENGE_CLEAR|\($0)") }
        let sourceRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WITCH_SOURCE_ROOT"] ?? FileManager.default.currentDirectoryPath)
        let sourcePaths = ["Package.swift", "Sources/WitchGameCore/Domain.swift", "Sources/WitchGameCore/CombatSimulator.swift", "Sources/WitchGameCore/R6TimelineSimulator.swift", "Sources/WitchGameCore/CandidateCombatOverlay.swift", "Sources/WitchGameCore/CandidateCharacterGrowth.swift", "Sources/WitchGameCore/GameEngine.swift", "Sources/WitchGameCore/SaveRepository.swift", "Sources/WitchGameCore/Resources/catalog_overlay.json", "Tests/WitchGameCoreTests/ProgressionE2ERunnerTests.swift"]
        var sourceDigests: [(String, String)] = []
        for relative in sourcePaths {
            let url = sourceRoot.appendingPathComponent(relative)
            let bytes = try Data(contentsOf: url)
            sourceDigests.append((relative, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()))
        }
        let sourceDigestText = sourceDigests.map { "\($0.0) \($0.1)" }.joined(separator: "\n") + "\n"
        let sourceHash = SHA256.hash(data: Data(sourceDigestText.utf8)).map { String(format: "%02x", $0) }.joined()
        let catalogURL = sourceRoot.appendingPathComponent("Sources/WitchGameCore/Resources/catalog_overlay.json")
        let catalogHash = SHA256.hash(data: try Data(contentsOf: catalogURL)).map { String(format: "%02x", $0) }.joined()
        let actionData = try JSONEncoder().encode(actions)
        let actionHash = SHA256.hash(data: actionData).map { String(format: "%02x", $0) }.joined()
        let finalSave = try Data(contentsOf: saveURL)
        let finalSaveHash = SHA256.hash(data: finalSave).map { String(format: "%02x", $0) }.joined()
        let stableEncoder = JSONEncoder()
        stableEncoder.outputFormatting = [.sortedKeys]
        let encodedSnapshot = try stableEncoder.encode(finalState)
        let snapshotObject = try JSONSerialization.jsonObject(with: encodedSnapshot)
        var uuidLabels: [String: String] = [:]
        var nextUUIDLabel = 1
        let uuidPattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        let uuidRegex = try NSRegularExpression(pattern: uuidPattern)
        func normalizeIDs(_ value: Any) -> Any {
            if let map = value as? [String: Any] {
                var normalized: [String: Any] = [:]
                for key in map.keys.sorted() { normalized[key] = normalizeIDs(map[key]!) }
                return normalized
            }
            if let array = value as? [Any] { return array.map(normalizeIDs) }
            guard let string = value as? String else { return value }
            let matches = uuidRegex.matches(in: string, range: NSRange(location: 0, length: (string as NSString).length))
            guard !matches.isEmpty else { return string }
            let mutable = NSMutableString(string: string)
            var replacements: [(NSRange, String)] = []
            let sourceString = string as NSString
            for match in matches {
                let rawID = sourceString.substring(with: match.range).lowercased()
                let label: String
                if let existing = uuidLabels[rawID] { label = existing }
                else { label = String(format: "UUID_REF_%05d", nextUUIDLabel); uuidLabels[rawID] = label; nextUUIDLabel += 1 }
                replacements.append((match.range, label))
            }
            for (range, replacement) in replacements.reversed() { mutable.replaceCharacters(in: range, with: replacement) }
            return mutable as String
        }
        let normalizedState = normalizeIDs(snapshotObject)
        let normalizedStateData = try JSONSerialization.data(withJSONObject: normalizedState, options: [.sortedKeys, .fragmentsAllowed])
        let semanticStateHash = SHA256.hash(data: normalizedStateData).map { String(format: "%02x", $0) }.joined()
        let summary = Summary(schema: "actual_gameengine_progression_e2e_r003_growth_profiles", approval: "UNAPPROVED_TEST_OVERLAY",
            seed: seed, candidateOverlayID: candidateMode ? CandidateCombatOverlay.r014LocalCandidate.id : "NONE",
            investmentStrategy: investmentStrategy, gearTierPolicy: gearTierPolicy,
            candidateGrowthProfile: growthProfileTag,
            finalCandidateGrowthLevels: growthProfile.map { _ in Dictionary(uniqueKeysWithValues: finalState.characterXP.map { ($0.key, CandidateCharacterGrowth.progress(totalXP: $0.value).level) }) },
            virtualClock: "90 virtual UTC day epochs; the test script issues multiple gather target/settlement commands across eligible materials within each day; this is not a literal human-login cadence",
            loginPolicy: "free/no-ad test inputs; scripted within-day gather target changes and settlements, not a measured one-login UI routine",
            battlePolicy: "up to 3 current progression encounters or challenges per day; next command chosen from actual persisted completion state; failed battle stops that day's attempts",
            catalogVersion: catalog.version, catalogSHA256: catalogHash, sourceFilesSHA256: sourceHash,
            actionLogSHA256: actionHash, finalSaveSHA256: finalSaveHash, semanticStateSHA256: semanticStateHash,
            reportArtifact: output.path, actionLogArtifact: actionURL.path, finalSaveArtifact: saveArtifactURL.path,
            checkpointSnapshots: checkpointArtifacts,
            actions: actions.count, successfulCommands: successes, failedCommands: failures,
            gathers: gathers, crafts: crafts, evolutions: evolutions, enhancements: enhancements,
            refinements: refinements, qualityPromotions: promotions, summons: summons,
            dismantles: dismantles,
            campaignAttempts: campaignAttempts, campaignWins: campaignWins, campaignDefeats: campaignDefeats,
            eR0304Encounters: eR0304Encounters, eR0304MarkEvents: eR0304MarkEvents,
            eR0304Hits: eR0304Hits, eR0304CandidateHits: eR0304CandidateHits,
            farmAttempts: farmAttempts, farmWins: farmWins, farmDefeats: farmDefeats,
            challengeAttempts: challengeAttempts, challengeWins: challengeWins, challengeDefeats: challengeDefeats,
            firstCampaignClearDay: firstCampaignClearDay, allChallengesClearDay: allChallengesClearDay,
            unresolvedEnemies: unresolvedEnemies, unresolvedChallenges: unresolvedChallenges,
            finalRevision: finalState.revision, finalGearInstances: finalState.gear.count,
            finalEquippedSlots: finalState.equippedGearIDs.count,
            finalInventoryTemplates: Array(Set(finalState.gear.map(\.definitionID))).sorted(),
            finalMaterialBalances: finalState.materials, dailyRows: dailyRows,
            constraints: ["No initial Q4 gear or injected inventory.", "Investment strategy opt-in axis: \(investmentStrategy); passive_control skips the targeted investment/gacha routine and is a passive control, free_ward uses the existing adaptive ward path, free_poison pursues Witch poison gear using only affordable catalog recipes; the run report records successful evolutions separately and may show zero. Both active strategies use identical scripted virtual-day inputs; no paid/ad grant.", "No initial Q4 gear or injected inventory.", "All battles and rewards use GameEngine.dispatch.", "Only successful battle receipts unlock encounters and regions.", "Each day the file-backed save is decoded into a fresh SaveRepository and snapshot-equality checked.", "Build investment policy is selected only by WITCH_E2E_INVESTMENT_STRATEGY; default free_ward preserves the prior E2E behavior. passive_control is intentionally a passive no-investment control, not a representative active player. R014 is enabled only by WITCH_E2E_CANDIDATE_OVERLAY=r014 and is re-injected after each save reopen; control is default nil.", "Candidate character growth is opt-in via WITCH_E2E_GROWTH_BP; absent means no growth injection. It changes only derived battle base stats, not saved XP, enemy stats, or R6 reference fixtures.", "All catalog and balance values remain unapproved test overlay; simulated challenge wins do not mean Human playtest or formal acceptance."])
        let reportData = try JSONEncoder().encode(summary)
        try reportData.write(to: output, options: .atomic)
        try actionData.write(to: actionURL, options: .atomic)
        try finalSave.write(to: saveArtifactURL, options: .atomic)
        try Data((sourceDigestText + "aggregate " + sourceHash + "\n").utf8).write(to: sourceURL, options: .atomic)
        let markdown = """
        # 90-Day Actual-Command Progression Run R002

        - Status: `UNAPPROVED_TEST_OVERLAY`; no formal gameplay or monetization approval.
        - Reproduction seed: `\(seed)` (`0x\(seedTag)`).
        - Candidate mechanics: `\(candidateMode ? CandidateCombatOverlay.r014LocalCandidate.id : "none; default engine configuration")`.
        - Catalog: `\(catalog.version)`; SHA-256 `\(catalogHash)`.
        - Clock: 90 virtual UTC day epochs; the deterministic script changes gather targets and settles eligible materials in multiple intra-day windows. This is not a literal one-login-per-day model.
        - Policy: free/no-ads, up to three campaign encounters or challenges/day, `\(investmentStrategy)`, real craft/equip/investment commands, and engine-validated duplicate salvage.
        - Result: campaign `\(campaignWins)/\(enemies.count)`; challenges `\(challengeWins)/\(challenges.count)`; first full campaign clear day `\(firstCampaignClearDay.map { String($0) } ?? "not reached")`; all challenges cleared day `\(allChallengesClearDay.map { String($0) } ?? "not reached")`.
        - Commands: `\(actions.count)` committed, `\(failures)` rejected; gathers `\(gathers)`, crafts `\(crafts)`, evolutions `\(evolutions)`, enhancements `\(enhancements)`, refinements `\(refinements)`, quality promotions `\(promotions)`, free summons `\(summons)`, duplicate dismantles `\(dismantles)`.
        - Enemy-drop farming: `\(farmWins)/\(farmAttempts)` wins; actual `M_R01_E2` drops were used to craft `EQ_BODY_01` and equip Smith.
        - E_R03_04: `\(eR0304Encounters)` real encounter dispatches, `\(eR0304MarkEvents)` magnet marks, `\(eR0304Hits)` enemy-hit events, `\(eR0304CandidateHits)` hits carrying the R014 coefficient diagnostic.
        - Save integrity: file-backed repository reopen and full snapshot equality passed after all 90 days. Final save SHA-256 `\(finalSaveHash)`.
        - UUID-normalized semantic state SHA-256: `\(semanticStateHash)` (run-local artifact digest, not a cross-run deterministic digest).
        - Action log SHA-256: `\(actionHash)`.
        - Core/catalog/runner source hash: `\(sourceHash)`.

        ## Evidence

        - Machine report: `\(output.lastPathComponent)`
        - Command log: `\(actionURL.lastPathComponent)`
        - Final isolated QA save: `\(saveArtifactURL.lastPathComponent)`
        - Per-file source hashes: `\(sourceURL.lastPathComponent)`

        This is a seeded local simulation using `GameEngine.dispatch`. It does not represent human playtesting, production-server authority, platform purchase/ad delivery, or formal acceptance of catalog values.
        """
        try Data(markdown.utf8).write(to: output.deletingPathExtension().appendingPathExtension("md"), options: .atomic)
        print("PROGRESSION_E2E_REPORT,\(output.path),seed=\(seed),actions=\(actions.count),campaign=\(campaignWins)/\(enemies.count),challenges=\(challengeWins)/\(challenges.count),days=\(dailyRows.count)")
        print("PROGRESSION_E2E_ACTIONS,\(actionURL.path),sha256=\(actionHash)")
        print("PROGRESSION_E2E_SAVE,\(saveURL.path),sha256=\(finalSaveHash)")
        XCTAssertEqual(dailyRows.count, 90)
        XCTAssertEqual(finalState.partyActorIDs.count, 4)
    }
}
