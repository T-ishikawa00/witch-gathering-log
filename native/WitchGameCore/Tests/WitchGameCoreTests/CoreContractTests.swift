import XCTest
@testable import WitchGameCore

final class CoreContractTests: XCTestCase {
    func testGachaBoundedSamplerRejectsModuloRemainderRangeAndIsDeterministic() {
        var first = GachaSeedGenerator(seed: 0xBADC0FFEE)
        var replay = GachaSeedGenerator(seed: 0xBADC0FFEE)
        var counts = Array(repeating: 0, count: 10_000)
        for _ in 0..<100_000 {
            let draw = Int(first.bounded(10_000))
            XCTAssertEqual(draw, Int(replay.bounded(10_000)))
            XCTAssertTrue((0..<10_000).contains(draw))
            counts[draw] += 1
        }
        XCTAssertTrue(counts.allSatisfy { $0 > 0 })
        let chiSquared = counts.reduce(0.0) { total, observed in
            let delta = Double(observed) - 10.0
            return total + delta * delta / 10.0
        }
        XCTAssertLessThan(chiSquared, 11_000, "gross modulo bias or poor deterministic sample distribution")
    }

    func testLocalAdWorkAccrualUsesActualEightHourBlocksAndSixOpportunityCap() async throws {
        let region = RegionDefinition(id: "R01", name: "Forest", enemyIDs: [], gatherMaterialIDs: ["wood"], xpPerWork: 16, dustPerWork: 16, workSeconds: 300)
        let catalog = GameCatalog(version: "ad-test", regions: [region], enemies: [], gear: [], research: [])
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        var initial = GameSnapshot(unlockedRegionIDs: ["R01"], lastClaimAt: epoch, partyActorIDs: ["C_WITCH"], activeRegionID: "R01", gatherTargetMaterialID: "wood")
        initial.materials["wood"] = 0
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        _ = try await game.claimOffline(now: epoch.addingTimeInterval(7.9 * 3600), operationID: UUID(), expectedRevision: 0)
        var snapshot = await game.snapshot()
        XCTAssertTrue(snapshot.localAdRewardOpportunities.isEmpty)
        _ = try await game.claimOffline(now: epoch.addingTimeInterval(8 * 3600), operationID: UUID(), expectedRevision: 1)
        snapshot = await game.snapshot()
        XCTAssertEqual(snapshot.localAdRewardOpportunities.count, 1)
        let first = try XCTUnwrap(snapshot.localAdRewardOpportunities["ADWORK_1"])
        XCTAssertEqual(first.baseXPByActor["C_WITCH"], 1_536)
        XCTAssertEqual(first.baseDust, 1_536)
        XCTAssertEqual(first.rewardXPByActor["C_WITCH"], 96)
        XCTAssertEqual(first.rewardDust, 96)

        let capGame = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        _ = try await capGame.claimOffline(now: epoch.addingTimeInterval(72 * 3600), cap: 72 * 3600, operationID: UUID(), expectedRevision: 0)
        snapshot = await capGame.snapshot()
        XCTAssertEqual(snapshot.localAdRewardOpportunities.count, 6)
        XCTAssertEqual(snapshot.localAdWorkBlockSeconds, 0)
        XCTAssertEqual(snapshot.materials["wood"], 576, "caller-supplied cap cannot bypass the shared 48-hour collection cap")
        _ = try await capGame.dispatch(.recordMockRewardedAdAttempt(opportunityID: "ADWORK_1", result: .simulate(sessionID: "cap-claim", outcome: .completed)), operationID: UUID(), expectedRevision: 1)
        snapshot = await capGame.snapshot()
        XCTAssertEqual(snapshot.localAdRewardOpportunities.count, 5)
        _ = try await capGame.claimOffline(now: epoch.addingTimeInterval(80 * 3600), operationID: UUID(), expectedRevision: 2)
        snapshot = await capGame.snapshot()
        XCTAssertEqual(snapshot.localAdRewardOpportunities.count, 6, "the seventh unclaimed opportunity must wait until a slot is available")
    }

    func testLocalAdCancellationFailureAndDuplicateCallbacksNeverGrantTwice() async throws {
        let opportunity = LocalAdRewardOpportunity(id: "ADWORK_1", baseXPByActor: ["C_WITCH": 31], baseDust: 31, createdAt: Date(timeIntervalSince1970: 100))
        let initial = GameSnapshot(localAdRewardOpportunities: [opportunity.id: opportunity])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-ad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let store = try SaveRepository(initial: initial, fileURL: url)
        let game = try GameEngine(catalog: .bundledTestOverlay(), saves: store)
        let cancelID = UUID()
        _ = try await game.dispatch(.recordMockRewardedAdAttempt(opportunityID: opportunity.id, result: .simulate(sessionID: "cancel", outcome: .cancelled)), operationID: cancelID, expectedRevision: 0)
        var snapshot = await game.snapshot()
        XCTAssertEqual(snapshot.characterXP["C_WITCH", default: 0], 0)
        XCTAssertEqual(snapshot.materials["refine_dust", default: 0], 0)
        XCTAssertNotNil(snapshot.localAdRewardOpportunities[opportunity.id], "cancel leaves opportunity available")
        let failID = UUID()
        _ = try await game.dispatch(.recordMockRewardedAdAttempt(opportunityID: opportunity.id, result: .simulate(sessionID: "fail", outcome: .failed)), operationID: failID, expectedRevision: 1)
        snapshot = await game.snapshot()
        XCTAssertNotNil(snapshot.localAdRewardOpportunities[opportunity.id], "provider failure leaves opportunity available")

        let successID = UUID()
        let receipt = try await game.dispatch(.recordMockRewardedAdAttempt(opportunityID: opportunity.id, result: .simulate(sessionID: "success", outcome: .completed)), operationID: successID, expectedRevision: 2)
        snapshot = await game.snapshot()
        XCTAssertEqual(snapshot.characterXP["C_WITCH"], 1) // 31/16, with 15/16 carried forward
        XCTAssertEqual(snapshot.localAdXPFractionalCarry["C_WITCH"], 15)
        XCTAssertEqual(snapshot.materials["refine_dust"], 1)
        XCTAssertEqual(snapshot.localAdDustFractionalCarry, 15)
        XCTAssertNil(snapshot.localAdRewardOpportunities[opportunity.id])
        let duplicate = try await game.dispatch(.recordMockRewardedAdAttempt(opportunityID: opportunity.id, result: .simulate(sessionID: "success", outcome: .completed)), operationID: UUID(), expectedRevision: snapshot.revision)
        XCTAssertTrue(duplicate.result.contains("duplicate"))
        let afterDuplicate = await game.snapshot()
        XCTAssertEqual(afterDuplicate.characterXP["C_WITCH"], 1)
        let inMemoryReceipt = await store.receipt(for: successID)
        XCTAssertEqual(inMemoryReceipt, receipt)

        let reloaded = try SaveRepository(fileURL: url)
        let persisted = await reloaded.snapshot()
        XCTAssertEqual(persisted.localAdAttemptRecords["success"]?.rewardXPByActor["C_WITCH"], 1)
        let persistedReceipt = await reloaded.receipt(for: successID)
        XCTAssertEqual(persistedReceipt, receipt)
    }

    func testLocalAdSkipRequiresQAEntitlementAndMatchesCompletedReward() async throws {
        let opportunity = LocalAdRewardOpportunity(id: "ADWORK_1", baseXPByActor: ["C_WITCH": 80], baseDust: 48, createdAt: Date(timeIntervalSince1970: 100))
        var watched = GameSnapshot(localAdRewardOpportunities: [opportunity.id: opportunity])
        watched.localAdXPFractionalCarry["C_WITCH"] = 8
        watched.localAdDustFractionalCarry = 8
        var skipped = watched
        skipped.localAdSkipEntitledForQA = true
        let catalog = try GameCatalog.bundledTestOverlay()
        let watchedGame = try GameEngine(catalog: catalog, saves: SaveRepository(initial: watched))
        let skipGame = try GameEngine(catalog: catalog, saves: SaveRepository(initial: skipped))
        _ = try await watchedGame.dispatch(.recordMockRewardedAdAttempt(opportunityID: opportunity.id, result: .simulate(sessionID: "watch", outcome: .completed)), operationID: UUID(), expectedRevision: 0)
        _ = try await skipGame.dispatch(.claimMockAdSkip(opportunityID: opportunity.id), operationID: UUID(), expectedRevision: 0)
        let watchState = await watchedGame.snapshot(), skipState = await skipGame.snapshot()
        XCTAssertEqual(watchState.characterXP, skipState.characterXP)
        XCTAssertEqual(watchState.materials, skipState.materials)
        XCTAssertEqual(watchState.localAdXPFractionalCarry, skipState.localAdXPFractionalCarry)
        XCTAssertEqual(watchState.localAdDustFractionalCarry, skipState.localAdDustFractionalCarry)
        XCTAssertEqual(watchState.currency, skipState.currency)
        XCTAssertEqual(watchState.gear, skipState.gear, "optional ad rewards never grant gear")

        let unauthorized = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot(localAdRewardOpportunities: [opportunity.id: opportunity])))
        do { _ = try await unauthorized.dispatch(.claimMockAdSkip(opportunityID: opportunity.id), operationID: UUID(), expectedRevision: 0); XCTFail("QA skip entitlement bypass") }
        catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") } }
    }

    func testEvolutionWardReplacesSeedOnActualGameEngineCombatPath() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let recipe = try XCTUnwrap(catalog.recipes.first(where: { $0.id == "RC_EQ_W_G1" }))
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.completedEncounterIDs.formUnion(["B_R01_A", "B_R01_B"])
        for (material, amount) in recipe.costs { initial.materials[material] = amount }
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        let before = await game.snapshot()
        let witchWeapon = try XCTUnwrap(before.gear.first(where: { $0.definitionID == "EQ_W_01" }))
        _ = try await game.dispatch(.evolveGear(gearID: witchWeapon.id, recipeID: recipe.id), operationID: UUID(), expectedRevision: before.revision)
        let evolved = await game.snapshot()
        let evolvedWeapon = try XCTUnwrap(evolved.gear.first(where: { $0.id == witchWeapon.id }))
        XCTAssertEqual(evolvedWeapon.definitionID, "EQ_W_G1")
        let projected = catalog.projectCombatant(for: "C_WITCH", with: [evolvedWeapon])
        XCTAssertTrue(projected.effectIDs.contains("WARD_REPLACES_SEED"))

        let afterEvolution = await game.snapshot()
        _ = try await game.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 71), operationID: UUID(), expectedRevision: afterEvolution.revision)
        let afterCombat = await game.snapshot()
        let result = try XCTUnwrap(afterCombat.lastCombatResult)
        XCTAssertFalse(result.events.contains { $0.sourceID == "C_WITCH" && $0.kind == "poison_seed" }, "evolved ward must suppress the replaced seed action")
        XCTAssertTrue(result.events.contains { $0.sourceID == "C_WITCH" && $0.kind == "barrier" }, "evolved ward must retain its threat-response action in live Engine combat")
    }

    func testNinetyDayStarterDirectOnlyPolicyExposesBossGate() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot.newGame(catalog: catalog)))
        func send(_ command: GameCommand) async throws -> CommandReceipt {
            let current = await game.snapshot()
            return try await game.dispatch(command, operationID: UUID(), expectedRevision: current.revision)
        }
        var firstAllRegionsDay: Int?
        var firstCraftDay: Int?
        var selectedRegionIndex = 0
        var day30State: GameSnapshot?
        for day in 1...90 {
            let now = epoch.addingTimeInterval(TimeInterval(day * 86_400))
            let beforeClaim = await game.snapshot()
            if beforeClaim.activeRegionID != nil {
                _ = try await game.claimOffline(now: now, operationID: UUID(), expectedRevision: beforeClaim.revision)
            }
            if day == 30 { day30State = await game.snapshot() }

            let region = catalog.regions[selectedRegionIndex]
            _ = try await send(.startExpeditionAt(regionID: region.id, now: now))
            let available = await game.availableGatherMaterials(in: region.id)
            if !available.isEmpty {
                let target = available[(day - 1) % available.count]
                _ = try await send(.setGatherTargetAt(resourceID: target, now: now))
            }
            for enemyID in region.enemyIDs {
                let state = await game.snapshot()
                guard !state.completedEncounterIDs.contains(enemyID), let enemy = catalog.enemies.first(where: { $0.id == enemyID }), enemy.prerequisiteEncounterID.map({ state.completedEncounterIDs.contains($0) }) ?? true else { continue }
                let beforeEncounter = await game.snapshot()
                let receipt = try await send(.resolveEncounter(enemyID: enemyID, seed: UInt64(day * 10_000 + (catalog.enemies.firstIndex(where: { $0.id == enemyID }) ?? 0))))
                let afterEncounter = await game.snapshot()
                if enemyID == "B_R04_B", !receipt.result.contains("VICTORY") {
                    XCTAssertFalse(afterEncounter.completedEncounterIDs.contains(enemyID), "a failed boss attempt cannot set its clear gate")
                    XCTAssertEqual(afterEncounter.materials[enemy.dropMaterialID!, default: 0], beforeEncounter.materials[enemy.dropMaterialID!, default: 0], "a failed boss attempt cannot grant its drop")
                    XCTAssertEqual(afterEncounter.currency, beforeEncounter.currency, "a failed boss attempt cannot grant currency")
                }
            }

            var state = await game.snapshot()
            if firstCraftDay == nil, let recipe = catalog.recipes.first(where: { $0.id == "RC_EQ_W_01" }), recipe.costs.allSatisfy({ state.materials[$0.key, default: 0] >= $0.value }) {
                _ = try await send(.craftRecipe(recipe.id)); firstCraftDay = day
                let crafted = await game.snapshot()
                if let newGear = crafted.gear.last { _ = try await send(.equip(gearID: newGear.id, actorID: "C_WITCH")) }
                state = await game.snapshot()
            }
            if state.craftedGearOnce && !state.gearComparisonSeen {
                let weapons = state.gear.filter { item in catalog.gear.first(where: { $0.id == item.definitionID })?.slot == "weapon" }
                if weapons.count >= 2 { _ = try await send(.markGearComparisonSeen(firstGearID: weapons[0].id, secondGearID: weapons[1].id)); state = await game.snapshot() }
            }
            if state.gachaUnlocked {
                _ = try? await send(.dailyClaim(now: now))
                state = await game.snapshot()
                if day == 4, state.currency["ticket_free", default: 0] >= 5 {
                    _ = try await send(.mockSummon(poolDefinitionIDs: catalog.gear.map(\.id), count: 5, costCurrencyID: "ticket_free", seed: 4_202_610))
                }
            }
            state = await game.snapshot()
            if state.unlockedRegionIDs.count == catalog.regions.count, firstAllRegionsDay == nil { firstAllRegionsDay = day }
            if firstCraftDay != nil, region.enemyIDs.allSatisfy(state.completedEncounterIDs.contains), selectedRegionIndex + 1 < catalog.regions.count,
               state.unlockedRegionIDs.contains(catalog.regions[selectedRegionIndex + 1].id) { selectedRegionIndex += 1 }
            if day == 30 { day30State = state }
        }
        let final = await game.snapshot()
        let thirty = try XCTUnwrap(day30State)
        let tickets30 = thirty.currency["ticket_free", default: 0]
        let tickets90 = final.currency["ticket_free", default: 0]
        let craftDay = firstCraftDay.map(String.init) ?? "NONE"
        let allRegionDay = firstAllRegionsDay.map(String.init) ?? "NONE"
        print("PROGRESSION_SWEEP,day30,regions=\(thirty.unlockedRegionIDs.count),clears=\(thirty.completedEncounterIDs.count),gear=\(thirty.gear.count),tickets=\(tickets30),materials=\(thirty.materials.values.reduce(0, +))")
        print("PROGRESSION_SWEEP,day90,regions=\(final.unlockedRegionIDs.count),clears=\(final.completedEncounterIDs.count),gear=\(final.gear.count),tickets=\(tickets90),materials=\(final.materials.values.reduce(0, +)),firstCraftDay=\(craftDay),allRegionsDay=\(allRegionDay)")
        print("PROGRESSION_SWEEP,missing=\(Set(catalog.enemies.map(\.id)).subtracting(final.completedEncounterIDs).sorted().joined(separator: ","))")
        XCTAssertEqual(final.unlockedRegionIDs, Set(["R01", "R02", "R03", "R04"]), "the starter/direct-only baseline stalls at the measured R04 boss gate")
        let missing = Set(catalog.enemies.map(\.id)).subtracting(final.completedEncounterIDs)
        XCTAssertEqual(missing, ["B_R04_B", "E_R05_01", "E_R05_02", "E_R05_03", "E_R05_04", "B_R05_A", "B_R05_B"], "this intentionally limited policy is diagnostic, not the rich E2E progression acceptance")
        XCTAssertEqual(final.lastEncounterID, "B_R04_B")
        XCTAssertEqual(final.lastCombatResult?.won, false)
    }

    func testCampaignEnemyScaleSensitivityFromActualStartingLoadout() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let state = GameSnapshot.newGame(catalog: catalog)
        let party = state.partyActorIDs.map { actorID -> Combatant in
            let instances = state.equippedGearIDs.filter { $0.key.hasPrefix(actorID + "|") }.compactMap { _, id in state.gear.first(where: { $0.id == id }) }
            return catalog.projectCombatant(for: actorID, with: instances)
        }
        for region in catalog.regions {
            let sampleIDs: [String] = [region.enemyIDs.first].compactMap { $0 } + region.enemyIDs.filter { $0.hasSuffix("_A") || $0.hasSuffix("_B") }
            for enemyID in sampleIDs {
                guard let definition = catalog.enemies.first(where: { $0.id == enemyID }) else { continue }
                for hpScale in [1, 4, 6] {
                    for attackScale in [1, 2, 4] {
                        let enemy = Combatant(id: definition.id, maxHP: definition.hp * hpScale, attack: definition.attack * attackScale, defense: definition.defense, actionPattern: definition.actionPattern ?? "standard")
                        let result = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 100_049, maxDurationMs: 120_000)
                        let elapsed = result.events.compactMap(\.timestampMs).max() ?? 0
                        let survivors = result.remainingPartyHP.values.filter { $0 > 0 }.count
                        print("CAMPAIGN_SCALE,\(enemyID),hpScale=\(hpScale),attackScale=\(attackScale),won=\(result.won),elapsedMs=\(elapsed),survivors=\(survivors)")
                    }
                }
            }
        }
    }

    func testFinalBossGearRequirementCandidateProbe() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let boss = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "B_R05_B" }))
        let starting = GameSnapshot.newGame(catalog: catalog)
        let startingParty = starting.partyActorIDs.map { actor in
            let items = starting.equippedGearIDs.filter { $0.key.hasPrefix(actor + "|") }.compactMap { _, id in starting.gear.first(where: { $0.id == id }) }
            return catalog.projectCombatant(for: actor, with: items)
        }
        let startingResult = try R6TimelineSimulator.run(party: startingParty, enemies: [Combatant(id: boss.id, maxHP: boss.hp, attack: boss.attack, defense: boss.defense, actionPattern: boss.actionPattern ?? "standard")], seed: 100_049, maxDurationMs: 120_000)
        print("R05_GEAR_GATE,starting,won=\(startingResult.won),timeMs=\(startingResult.events.compactMap(\.timestampMs).max() ?? 0),survivors=\(startingResult.remainingPartyHP.values.filter { $0 > 0 }.count)")
        let roles: [(String, [String])] = [
            ("direct", ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"]),
            ("toxin_chase", ["EQ_W_P2", "EQ_A_01", "EQ_S_01", "EQ_F_03"]),
            ("ward_heal_counter", ["EQ_W_G2", "EQ_A_03", "EQ_S_03", "EQ_F_03"])
        ]
        for (name, templates) in roles {
            for upgraded in [false, true] {
                let party = zip(["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"], templates).map { actor, gearID in
                    let item = GearInstance(definitionID: gearID, ownerID: actor, enhancement: upgraded ? 10 : 0,
                                            qualityID: upgraded ? "Q4" : "Q0",
                                            affixIDs: upgraded ? ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"] : [])
                    return catalog.projectCombatant(for: actor, with: [item])
                }
                let foe = Combatant(id: boss.id, maxHP: boss.hp, attack: boss.attack, defense: boss.defense, actionPattern: boss.actionPattern ?? "standard")
                let result = try R6TimelineSimulator.run(party: party, enemies: [foe], seed: 100_049, maxDurationMs: 120_000)
                print("R05_GEAR_GATE,\(name),upgraded=\(upgraded),won=\(result.won),timeMs=\(result.events.compactMap(\.timestampMs).max() ?? 0),survivors=\(result.remainingPartyHP.values.filter { $0 > 0 }.count)")
            }
        }

        // Diagnostic-only reachability comparison for the bosses preceding and defining the final gear gate.
        // These legal candidate loadouts are projected by the same catalog stat API as normal combat.
        for bossID in ["B_R04_B", "B_R05_A", "B_R05_B"] {
            let definition = try XCTUnwrap(catalog.enemies.first(where: { $0.id == bossID }))
            let reachablePreR04Builds: [(String, [String])] = [
                ("reachable_ward_heal", ["EQ_W_G1", "EQ_A_02", "EQ_S_02", "EQ_F_02"]),
                ("reachable_poison", ["EQ_W_P1", "EQ_A_02", "EQ_S_02", "EQ_F_02"])
            ]
            for (name, templates) in [("starter", ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"])] + roles + reachablePreR04Builds {
                for upgraded in [false, true] {
                    let party = zip(["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"], templates).map { actor, gearID in
                        let item = GearInstance(definitionID: gearID, ownerID: actor, enhancement: upgraded ? 10 : 0,
                                                qualityID: upgraded ? "Q4" : "Q0",
                                                affixIDs: upgraded ? ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"] : [])
                        return catalog.projectCombatant(for: actor, with: [item])
                    }
                    let foe = Combatant(id: definition.id, maxHP: definition.hp, attack: definition.attack,
                                        defense: definition.defense, actionPattern: definition.actionPattern ?? "standard")
                    let result = try R6TimelineSimulator.run(party: party, enemies: [foe], seed: 100_049, maxDurationMs: 120_000)
                    print("BOSS_BUILD_REACHABILITY,\(bossID),build=\(name),upgraded=\(upgraded),won=\(result.won),elapsedMs=\(result.events.compactMap(\.timestampMs).max() ?? 0),survivors=\(result.remainingPartyHP.values.filter { $0 > 0 }.count)")
                }
            }
        }
    }

    func testCandidateFourCharacterBuildSetsAreCoEquippableAndPreserveTemplateEffects() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let candidates = [
            ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"],
            ["EQ_W_P2", "EQ_A_01", "EQ_S_01", "EQ_F_03"],
            ["EQ_W_G1", "EQ_A_03", "EQ_S_03", "EQ_F_03"]
        ]
        for set in candidates {
            XCTAssertEqual(set.count, 4)
            let definitions = try set.map { id -> GearDefinition in
                try XCTUnwrap(catalog.gear.first(where: { $0.id == id }))
            }
            let actorSlots = definitions.compactMap { definition in
                definition.actorIDs.first.map { $0 + "|" + definition.slot }
            }
            XCTAssertEqual(actorSlots.count, 4)
            XCTAssertEqual(Set(actorSlots).count, 4, "candidate set must not collide on a character slot")
            for definition in definitions {
                let actor = try XCTUnwrap(definition.actorIDs.first)
                let item = GearInstance(definitionID: definition.id, ownerID: actor)
                let projection = catalog.projectCombatant(for: actor, with: [item])
                XCTAssertTrue(Set(definition.effects).isSubset(of: projection.effectIDs), "(definition.id) effects must survive the shared combat projection")
            }
        }
    }

    func testTenPersonaNinetyDayActualCommandSweep() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        struct Persona {
            let name: String; let targetGear: String?; let invest: String; let gatherSuffix: String?
            var grantDay: Int? = nil; var grantTickets: Int = 0; var repeatEveryDays: Int = 0; var repeatTickets: Int = 0
            var adTicketsPerDay: Int = 0; var qaProductID: String? = nil; var cosmeticID: String? = nil; var furnitureID: String? = nil; var adaptiveBuild: [String]? = nil
        }
        let personas = [
            Persona(name: "free_no_ads", targetGear: nil, invest: "none", gatherSuffix: nil),
            Persona(name: "small_one_off_pack", targetGear: "EQ_W_P2", invest: "enhance", gatherSuffix: "G1", grantDay: 14, grantTickets: 10, qaProductID: "CANDIDATE_PACK_ONEOFF"),
            Persona(name: "ad_skip_only", targetGear: nil, invest: "none", gatherSuffix: nil, grantDay: 7, qaProductID: "CANDIDATE_AD_SKIP"),
            Persona(name: "cosmetic_only", targetGear: nil, invest: "none", gatherSuffix: nil, grantDay: 7, qaProductID: "CANDIDATE_COSMETIC", cosmeticID: "ERNA_TRAVEL"),
            Persona(name: "furniture_only", targetGear: nil, invest: "none", gatherSuffix: nil, grantDay: 7, qaProductID: "CANDIDATE_FURNITURE", furnitureID: "FURN_DESK_BOTANICAL"),
            Persona(name: "small_pack_user", targetGear: "EQ_W_G2", invest: "quality", gatherSuffix: "G3", repeatEveryDays: 30, repeatTickets: 5, qaProductID: "CANDIDATE_SMALL_PACK"),
            Persona(name: "recurring_small", targetGear: "EQ_S_03", invest: "refine", gatherSuffix: "G2", repeatEveryDays: 30, repeatTickets: 10, qaProductID: "CANDIDATE_RECURRING_SMALL"),
            Persona(name: "high_collector", targetGear: "EQ_F_03", invest: "enhance", gatherSuffix: "G4", repeatEveryDays: 30, repeatTickets: 50, qaProductID: "CANDIDATE_HIGH_COLLECTOR"),
            Persona(name: "rewarded_ad_engaged", targetGear: nil, invest: "research", gatherSuffix: "G1", adTicketsPerDay: 1),
            Persona(name: "adaptive_free_ward_build", targetGear: nil, invest: "evolve", gatherSuffix: "G3", adaptiveBuild: ["EQ_W_G1", "EQ_A_03", "EQ_S_03", "EQ_F_03"])
        ]
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(catalog.furnitureIDs.contains("FURN_DESK_BOTANICAL"), "furniture-only persona needs a valid catalog item")
        var jsonRows: [[String: Any]] = []
        for dailyFreeTickets in [1, 3] {
          for loginsPerDay in [1, 3] {
           for seedBase in [17, 91, 404] {
          for (personaIndex, persona) in personas.enumerated() {
            let personaCatalog = catalog.withDailyFreeTicketGrant(dailyFreeTickets)
            let game = try GameEngine(catalog: personaCatalog, saves: SaveRepository(initial: GameSnapshot.newGame(catalog: personaCatalog)))
            func send(_ command: GameCommand) async throws -> CommandReceipt {
                let state = await game.snapshot()
                return try await game.dispatch(command, operationID: UUID(), expectedRevision: state.revision)
            }
            var regionIndex = 0
            var day30: GameSnapshot?
            let targetTemplate = persona.adaptiveBuild?.first ?? persona.targetGear ?? "EQ_W_P2"
            let buildSet: [String] = persona.adaptiveBuild ?? ((targetTemplate == "EQ_W_G2" || targetTemplate == "EQ_W_G1" || targetTemplate == "EQ_S_03")
                ? ["EQ_W_G1", "EQ_A_03", "EQ_S_03", "EQ_F_03"]
                : ((targetTemplate == "EQ_W_P2" || targetTemplate == "EQ_F_03")
                    ? ["EQ_W_P2", "EQ_A_01", "EQ_S_01", "EQ_F_03"]
                    : ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"]))
            var firstTargetTemplateDay: Int?
            var firstTargetQ4Day: Int?
            var firstAnyQ4Day: Int?
            var firstTargetTwoAffixesDay: Int?
            var firstBuildReadyDay: Int?
            var firstCraftDay: Int?
            var firstEvolutionDay: Int?
            var successfulEvolutions = 0
            var gachaTargetChanges = 0
            var firstGachaDay: Int?
            var firstR02Day: Int?
            for day in 1...90 {
              let dayStart = epoch.addingTimeInterval(TimeInterval(day * 86_400))
              for sessionIndex in 0..<loginsPerDay {
                let isFirstSession = sessionIndex == 0
                let now = dayStart.addingTimeInterval(TimeInterval(sessionIndex) * 86_400 / TimeInterval(loginsPerDay))
                let purchaseGrant = (persona.grantDay == day ? persona.grantTickets : 0) + (persona.repeatEveryDays > 0 && day.isMultiple(of: persona.repeatEveryDays) ? persona.repeatTickets : 0)
                if isFirstSession && (purchaseGrant > 0 || (persona.grantDay == day && persona.cosmeticID != nil) || (persona.grantDay == day && persona.furnitureID != nil) || (persona.grantDay == day && persona.name == "ad_skip_only")) {
                    let store = game.saves
                    let prior = await store.snapshot()
                    let transactionID = "candidate-\(persona.name)-\(dailyFreeTickets)-\(loginsPerDay)-\(seedBase)-day-\(day)"
                    let productID = persona.qaProductID ?? "CANDIDATE_UNNAMED"
                    _ = try await store.transact(expectedRevision: prior.revision, operationID: UUID(), requestFingerprint: "UNAPPROVED_PERSONA_INPUT|\(transactionID)") { snapshot in
                        snapshot.localStoreKitQARecords[transactionID] = LocalStoreKitQARecord(productID: productID, kind: .purchase, transactionID: transactionID, recordedAt: now)
                        snapshot.localStoreKitQAOwnedProductIDs.insert(productID)
                        if purchaseGrant > 0 { snapshot.currency["ticket_paid_mock", default: 0] += purchaseGrant }
                        return "UNAPPROVED_TEST_OVERLAY persona purchase assumption"
                    }
                    if let cosmeticID = persona.cosmeticID { _ = try await send(.setCosmetic(cosmeticID, owned: true)) }
                    if let furnitureID = persona.furnitureID { _ = try await send(.setFurniture(furnitureID, owned: true)) }
                }
                if isFirstSession && persona.adTicketsPerDay > 0 {
                    let store = game.saves
                    let prior = await store.snapshot()
                    _ = try await store.transact(expectedRevision: prior.revision, operationID: UUID(), requestFingerprint: "UNAPPROVED_AD_REWARD|\(persona.name)|\(day)") { snapshot in
                        snapshot.currency["ticket_free", default: 0] += persona.adTicketsPerDay
                        return "UNAPPROVED_TEST_OVERLAY rewarded ad assumption"
                    }
                }
                var state = await game.snapshot()
                if state.activeRegionID != nil { _ = try await game.claimOffline(now: now, operationID: UUID(), expectedRevision: state.revision) }
                let region = catalog.regions[regionIndex]
                _ = try await send(.startExpeditionAt(regionID: region.id, now: now))
                let available = await game.availableGatherMaterials(in: region.id)
                if !available.isEmpty {
                    let onboardingNeed = !(await game.snapshot()).craftedGearOnce && region.id == "R01"
                    let onboardingSuffix = day.isMultiple(of: 2) ? "G2" : "G1"
                    let desiredSuffix = onboardingNeed ? onboardingSuffix : (persona.adaptiveBuild == nil ? persona.gatherSuffix : Optional("G3"))
                    let preferred = available.first(where: { material in desiredSuffix.map { $0 == String(material.suffix(2)) } ?? false })
                    let material = preferred ?? available[(day + personaIndex) % available.count]
                    _ = try await send(.setGatherTargetAt(resourceID: material, now: now))
                }
                var battlesToday = 0
                for enemyID in region.enemyIDs {
                    state = await game.snapshot()
                    guard !state.completedEncounterIDs.contains(enemyID), let enemy = catalog.enemies.first(where: { $0.id == enemyID }), enemy.prerequisiteEncounterID.map({ state.completedEncounterIDs.contains($0) }) ?? true else { continue }
                    _ = try await send(.resolveEncounter(enemyID: enemyID, seed: UInt64(seedBase * 1_000_000 + (personaIndex + 1) * 100_000 + day * 100)))
                    battlesToday += 1
                    if battlesToday >= 1 { break }
                }
                state = await game.snapshot()
                if !state.craftedGearOnce, let recipe = catalog.recipes.first(where: { $0.id == "RC_EQ_W_01" }), recipe.costs.allSatisfy({ state.materials[$0.key, default: 0] >= $0.value }) {
                    _ = try await send(.craftRecipe(recipe.id))
                    state = await game.snapshot()
                    if let newItem = state.gear.last { _ = try await send(.equip(gearID: newItem.id, actorID: "C_WITCH")) }
                    state = await game.snapshot()
                    let weapons = state.gear.filter { item in catalog.gear.first(where: { definition in definition.id == item.definitionID })?.slot == "weapon" }
                    if weapons.count >= 2, !state.gearComparisonSeen { _ = try await send(.markGearComparisonSeen(firstGearID: weapons[0].id, secondGearID: weapons[1].id)) }
                }
                state = await game.snapshot()
                let summonTarget = persona.adaptiveBuild?.first(where: { template in !state.gear.contains(where: { $0.definitionID == template }) }) ?? persona.targetGear
                if let target = summonTarget, state.gearComparisonSeen {
                    if state.gachaPity.targetTemplateID != target { _ = try await send(.setGachaTarget(templateID: target)); gachaTargetChanges += 1 }
                    state = await game.snapshot()
                    if state.currency["ticket_free", default: 0] >= 5 { _ = try await send(.mockSummon(poolDefinitionIDs: catalog.gear.map(\.id), count: 5, costCurrencyID: "ticket_free", seed: UInt64(seedBase * 1_000_000 + personaIndex * 10_000 + day))) }
                } else if state.gachaUnlocked, state.currency["ticket_free", default: 0] >= 5 {
                    _ = try await send(.mockSummon(poolDefinitionIDs: catalog.gear.map(\.id), count: 5, costCurrencyID: "ticket_free", seed: UInt64(seedBase * 1_000_000 + personaIndex * 10_000 + day)))
                }
                state = await game.snapshot()
                if state.gachaUnlocked, state.currency["ticket_paid_mock", default: 0] > 0 {
                    let drawCount = min(5, state.currency["ticket_paid_mock", default: 0])
                    _ = try await send(.mockSummon(poolDefinitionIDs: catalog.gear.map(\.id), count: drawCount, costCurrencyID: "ticket_paid_mock", seed: UInt64(seedBase * 1_000_000 + 900_000 + personaIndex * 10_000 + day)))
                }
                state = await game.snapshot()
                if let adaptiveBuild = persona.adaptiveBuild {
                    for template in adaptiveBuild {
                        guard let actor = catalog.gear.first(where: { $0.id == template })?.actorIDs.first,
                              let item = state.gear.last(where: { $0.definitionID == template }) else { continue }
                        _ = try? await send(.equip(gearID: item.id, actorID: actor))
                        state = await game.snapshot()
                    }
                } else if let target = persona.targetGear, let item = state.gear.last(where: { $0.definitionID == target }), let actor = catalog.gear.first(where: { $0.id == target })?.actorIDs.first, state.partyActorIDs.contains(actor) {
                    _ = try? await send(.equip(gearID: item.id, actorID: actor))
                }
                state = await game.snapshot()
                let investmentTarget = persona.adaptiveBuild?.first(where: { template in !state.gear.contains(where: { $0.definitionID == template }) }) ?? persona.targetGear
                if persona.invest == "enhance", let id = state.gear.first(where: { $0.definitionID == investmentTarget })?.id { _ = try? await send(.enhance(gearID: id)) }
                if persona.invest == "refine", let id = state.gear.first(where: { $0.definitionID == investmentTarget })?.id { _ = try? await send(.refine(gearID: id)) }
                if persona.invest == "quality", let id = state.gear.first(where: { $0.definitionID == investmentTarget })?.id { _ = try? await send(.promoteQuality(gearID: id)) }
                if persona.invest == "evolve", let id = state.gear.first(where: { $0.definitionID == "EQ_W_01" })?.id,
                   (try? await send(.evolveGear(gearID: id, recipeID: "RC_EQ_W_G1"))) != nil {
                    successfulEvolutions += 1
                    if firstEvolutionDay == nil { firstEvolutionDay = day }
                }
                if persona.invest == "research", let research = catalog.research.first(where: { !state.completedResearchIDs.contains($0.id) && $0.cost.allSatisfy({ state.materials[$0.key, default: 0] >= $0.value }) }) { _ = try? await send(.completeResearch(research.id)) }
                if state.gachaUnlocked { _ = try? await send(.dailyClaim(now: now)) }
                state = await game.snapshot()
                let targetInstances = state.gear.filter { $0.definitionID == targetTemplate }
                let usefulAffixes: Set<String> = ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]
                if firstTargetTemplateDay == nil, !targetInstances.isEmpty { firstTargetTemplateDay = day }
                if firstTargetQ4Day == nil, targetInstances.contains(where: { $0.qualityID == "Q4" }) { firstTargetQ4Day = day }
                if firstAnyQ4Day == nil, state.gear.contains(where: { $0.qualityID == "Q4" }) { firstAnyQ4Day = day }
                if firstTargetTwoAffixesDay == nil, targetInstances.contains(where: { Set($0.affixIDs).intersection(usefulAffixes).count >= 2 }) { firstTargetTwoAffixesDay = day }
                let fullBuildReady = buildSet.allSatisfy { template in
                    guard let definition = catalog.gear.first(where: { $0.id == template }), let actor = definition.actorIDs.first,
                          let item = state.gear.first(where: { $0.definitionID == template && $0.ownerID == actor && state.equippedGearIDs[actor + "|" + definition.slot] == $0.id }) else { return false }
                    let projection = personaCatalog.projectCombatant(for: actor, with: [item], completedResearchIDs: state.completedResearchIDs)
                    return Set(definition.effects).isSubset(of: projection.effectIDs)
                }
                if firstBuildReadyDay == nil, fullBuildReady { firstBuildReadyDay = day }
                if firstCraftDay == nil, state.craftedGearOnce { firstCraftDay = day }
                if firstGachaDay == nil, state.gachaUnlocked { firstGachaDay = day }
                if firstR02Day == nil, state.unlockedRegionIDs.contains("R02") { firstR02Day = day }
                if region.enemyIDs.allSatisfy(state.completedEncounterIDs.contains), regionIndex + 1 < catalog.regions.count,
                   state.unlockedRegionIDs.contains(catalog.regions[regionIndex + 1].id) { regionIndex += 1 }
              }
              if day == 30 { day30 = await game.snapshot() }
            }
            let final = await game.snapshot(), mid = try XCTUnwrap(day30)
            let clears30 = mid.completedEncounterIDs.intersection(Set(catalog.enemies.map(\.id))).count
            let clears90 = final.completedEncounterIDs.intersection(Set(catalog.enemies.map(\.id))).count
            let levels = final.gear.map(\.enhancement).reduce(0, +), quality = final.gear.filter { $0.qualityID != "Q0" }.count
            let refinements = final.gear.map(\.refinement).reduce(0, +), research = final.completedResearchIDs.count
            let targetItems = final.gear.filter { $0.definitionID == targetTemplate }
            let targetDefinition = catalog.gear.first(where: { $0.id == targetTemplate })
            let targetActor = targetDefinition?.actorIDs.first ?? "C_WITCH"
            let targetSlot = targetDefinition?.slot ?? "weapon"
            let targetQ4 = targetItems.contains(where: { $0.qualityID == "Q4" })
            let targetTwoAffixes = targetItems.contains(where: { Set($0.affixIDs).intersection(["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]).count >= 2 })
            let targetPieceEquipped = targetItems.contains(where: { $0.ownerID == targetActor && final.equippedGearIDs[targetActor + "|" + targetSlot] == $0.id })
            let buildPieces: [[String: Any]] = buildSet.compactMap { template in
                guard let definition = catalog.gear.first(where: { $0.id == template }), let actor = definition.actorIDs.first,
                      let item = final.gear.first(where: { $0.definitionID == template && $0.ownerID == actor && final.equippedGearIDs[actor + "|" + definition.slot] == $0.id }) else { return nil }
                let projection = catalog.projectCombatant(for: actor, with: [item], completedResearchIDs: final.completedResearchIDs)
                return ["templateID": template, "actorID": actor, "slot": definition.slot, "qualityID": item.qualityID, "affixIDs": item.affixIDs, "requiredEffects": definition.effects, "effectsSatisfied": Set(definition.effects).isSubset(of: projection.effectIDs)]
            }
            let fullBuildReady = buildPieces.count == buildSet.count && buildPieces.allSatisfy { $0["effectsSatisfied"] as? Bool == true }
            let allBuildPiecesQ4 = fullBuildReady && buildPieces.allSatisfy { $0["qualityID"] as? String == "Q4" }
            let distinctTemplates = Set(final.gear.map(\.definitionID)).count
            let duplicateCandidates = Dictionary(grouping: final.gear.filter { !$0.protected }, by: \.definitionID).values.reduce(0) { $0 + max(0, $1.count - 1) }
            let stock = final.materials.filter { $0.value > 0 }
            let furnitureOwned = final.ownedFurnitureIDs.contains("FURN_DESK_BOTANICAL")
            let buildSetEffects: [[String: Any]] = buildSet.compactMap { id -> [String: Any]? in
                guard let definition = catalog.gear.first(where: { $0.id == id }) else { return nil }
                return ["templateID": id, "candidateEffects": definition.effects]
            }
            let milestones: [String: Any] = [
                "firstTargetTemplateDay": firstTargetTemplateDay as Any? ?? NSNull(),
                "firstTargetQ4SameInstanceDay": firstTargetQ4Day as Any? ?? NSNull(),
                "firstAnyQ4Day": firstAnyQ4Day as Any? ?? NSNull(),
                "firstTargetTwoAffixesSameInstanceDay": firstTargetTwoAffixesDay as Any? ?? NSNull(),
                "firstTargetBuildReadyDay": firstBuildReadyDay as Any? ?? NSNull(),
                "firstCraftDay": firstCraftDay as Any? ?? NSNull(),
                "firstEvolutionDay": firstEvolutionDay as Any? ?? NSNull(),
                "firstGachaDay": firstGachaDay as Any? ?? NSNull(),
                "firstR02UnlockDay": firstR02Day as Any? ?? NSNull()
            ]
            let d30DuplicateCandidates = Dictionary(grouping: mid.gear.filter { !$0.protected }, by: \.definitionID).values.reduce(0) { $0 + max(0, $1.count - 1) }
            let d30Target = mid.gear.filter { $0.definitionID == targetTemplate }
            var d30: [String: Any] = [:]
            d30["clearedEnemies"] = clears30
            d30["unlockedRegions"] = mid.unlockedRegionIDs.count
            d30["gearInstances"] = mid.gear.count
            d30["uniqueTemplates"] = Set(mid.gear.map(\.definitionID)).count
            d30["candidateDuplicateSalvageCount"] = d30DuplicateCandidates
            d30["positiveMaterialKinds"] = mid.materials.filter { $0.value > 0 }.count
            d30["materialsTotal"] = mid.materials.values.reduce(0, +)
            d30["targetTemplateOwned"] = !d30Target.isEmpty
            d30["targetQ4SameInstance"] = d30Target.contains(where: { $0.qualityID == "Q4" })
            d30["targetTwoAffixesSameInstance"] = d30Target.contains(where: { Set($0.affixIDs).intersection(["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]).count >= 2 })
            d30["firstEvolutionReached"] = firstEvolutionDay.map { $0 <= 30 } ?? false
            d30["fullDesiredBuildReady"] = firstBuildReadyDay.map { $0 <= 30 } ?? false
            let d90: [String: Any] = [
                "clearedEnemies": clears90, "unlockedRegions": final.unlockedRegionIDs.count,
                "gearInstances": final.gear.count, "uniqueTemplates": distinctTemplates,
                "enhancementLevelsTotal": levels, "nonBaseQualityInstances": quality,
                "refinementLevelsTotal": refinements, "evolvedWardStaves": successfulEvolutions,
                "finalGachaTarget": final.gachaPity.targetTemplateID as Any? ?? NSNull(), "gachaTargetChanges": gachaTargetChanges,
                "candidateDuplicateSalvageCount": duplicateCandidates, "positiveMaterialKinds": stock.count,
                "unspentMaterialsByID": stock, "unspentMaterialTotal": stock.values.reduce(0, +),
                "targetTemplateOwned": !targetItems.isEmpty, "targetQ4SameInstance": targetQ4,
                "targetTwoAffixesSameInstance": targetTwoAffixes, "targetPieceEquipped": targetPieceEquipped,
                "fullDesiredBuildReady": fullBuildReady, "allDesiredBuildPiecesQ4": allBuildPiecesQ4,
                "desiredBuildPieces": buildPieces, "furnitureOwned": furnitureOwned,
                "ownedCosmetics": final.ownedCosmeticIDs.count, "paidMockTicketsLeft": final.currency["ticket_paid_mock", default: 0],
                "freeTicketsLeft": final.currency["ticket_free", default: 0], "researchRanks": research
            ]
            let row: [String: Any] = [
                "authority": "UNAPPROVED_TEST_OVERLAY", "seed": seedBase, "dailyFreeTickets": dailyFreeTickets,
                "loginsPerDay": loginsPerDay, "totalLogins": 90 * loginsPerDay, "persona": persona.name,
                "targetTemplate": targetTemplate, "desiredBuildSet": buildSet, "desiredBuildSetEffects": buildSetEffects,
                "milestones": milestones, "d30": d30, "d90": d90
            ]
            jsonRows.append(row)
            print("PERSONA_SWEEP,seed=\(seedBase),activity=\(loginsPerDay),daily=\(dailyFreeTickets),\(persona.name),d30=\(clears30)/30,r\(mid.unlockedRegionIDs.count),gear\(mid.gear.count),d90=\(clears90)/30,r\(final.unlockedRegionIDs.count),gear\(final.gear.count),templates=\(distinctTemplates),surplusCandidates=\(duplicateCandidates),firstTarget=\(firstTargetTemplateDay.map(String.init) ?? "NOT_REACHED"),targetQ4=\(firstTargetQ4Day.map(String.init) ?? "NOT_REACHED"),anyQ4=\(firstAnyQ4Day.map(String.init) ?? "NOT_REACHED"),2affix=\(firstTargetTwoAffixesDay.map(String.init) ?? "NOT_REACHED"),build=\(firstBuildReadyDay.map(String.init) ?? "NOT_REACHED")")
          }
           }
          }
        }
        let report: [String: Any] = ["schemaVersion": 1, "status": "UNAPPROVED_TEST_OVERLAY", "method": "actual GameEngine commands; independent axes for 90 days, 1 or 3 login sessions per day, one encounter attempt per session, daily reward claimed at most once, daily free-ticket grant, and seed; includes a free adaptive target-build policy paired with the free baseline at each seed; candidate mock purchase inputs only; no prices or revenue forecasts", "targetQ4Definition": "desired template + Q4 on same instance", "twoAffixDefinition": "desired template has at least two distinct candidate affixes from POWER/VITALITY/GUARD on one instance", "buildReadyDefinition": "all four desired templates are owned, assigned to their catalog actor, and equipped in catalog slots; candidate build sets are unapproved", "personaCount": personas.count, "seedSet": [17, 91, 404], "dailyTicketSet": [1, 3], "loginSessionSet": [1, 3], "rows": jsonRows]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../docs/production/current/core/ECONOMY_SWEEP_R1.json").standardizedFileURL
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
    }

    func testOperationIDIsIdempotentAndRevisionConflictIsRejected() async throws {
        let store = try SaveRepository()
        let id = UUID()
        let first = try await store.transact(expectedRevision: 0, operationID: id) { state in state.materials["herb"] = 2; return "added" }
        let replay = try await store.transact(expectedRevision: 0, operationID: id) { _ in XCTFail("must not run on replay"); return "wrong" }
        let afterReplay = await store.snapshot()
        XCTAssertEqual(first, replay); XCTAssertEqual(afterReplay.revision, 1)
        do { _ = try await store.transact(expectedRevision: 0, operationID: UUID()) { _ in "wrong" }; XCTFail("stale revision accepted") }
        catch let error as CoreError { XCTAssertEqual(error, .revisionConflict(expected: 0, actual: 1)) }
    }

    func testSameOperationIDWithDifferentCommandPayloadIsRejected() async throws {
        let store = try SaveRepository()
        let catalog = try GameCatalog.bundledTestOverlay()
        let engine = try GameEngine(catalog: catalog, saves: store)
        let id = UUID()
        _ = try await engine.dispatch(.setCosmetic("ERNA_TRAVEL", owned: true), operationID: id, expectedRevision: 0)
        do {
            _ = try await engine.dispatch(.setCosmetic("ERNA_TRAVEL", owned: false), operationID: id, expectedRevision: 0)
            XCTFail("same operation ID accepted a different command")
        } catch let error as CoreError { XCTAssertEqual(error, .duplicateOperation) }
        let after = await engine.snapshot()
        XCTAssertTrue(after.ownedCosmeticIDs.contains("ERNA_TRAVEL"))
    }

    func testOperationFingerprintDistinguishesNilFromLiteralNoneAndActionKind() async throws {
        let store = try SaveRepository(initial: GameSnapshot(ownedCosmeticIDs: ["none"]))
        let engine = try GameEngine(catalog: GameCatalog(version: "t", regions: [], enemies: [], gear: [], research: []), saves: store)
        let id = UUID()
        _ = try await engine.dispatch(.selectCosmetic(actorID: "C_WITCH", cosmeticID: nil), operationID: id, expectedRevision: 0)
        do {
            _ = try await engine.dispatch(.selectCosmetic(actorID: "C_WITCH", cosmeticID: "none"), operationID: id, expectedRevision: 0)
            XCTFail("nil and literal none collided")
        } catch let error as CoreError { XCTAssertEqual(error, .duplicateOperation) }
    }

    func testProtectedOrEquippedGearCannotBeDismantled() async throws {
        let item = GearInstance(definitionID: "staff")
        let catalog = GameCatalog(version: "test-v1", regions: [.init(id: "forest", name: "Forest", enemyIDs: ["boar"])], enemies: [.init(id: "boar", name: "Boar", regionID: "forest", hp: 10, attack: 1, defense: 0, boss: false)], gear: [.init(id: "staff", name: "Staff", rarity: "C", slot: "weapon", effects: [])], research: [])
        let store = try SaveRepository(initial: GameSnapshot(gear: [item]))
        let game = try GameEngine(catalog: catalog, saves: store)
        _ = try await game.dispatch(.protect(gearID: item.id, protected: true), operationID: UUID(), expectedRevision: 0)
        do { _ = try await game.dispatch(.dismantle(gearID: item.id), operationID: UUID(), expectedRevision: 1); XCTFail("protected item dismantled") }
        catch let error as CoreError { XCTAssertEqual(error, .protectedGear) }
        _ = try await game.dispatch(.protect(gearID: item.id, protected: false), operationID: UUID(), expectedRevision: 1)
        _ = try await game.dispatch(.equip(gearID: item.id, actorID: "C_WITCH"), operationID: UUID(), expectedRevision: 2)
        do { _ = try await game.dispatch(.dismantle(gearID: item.id), operationID: UUID(), expectedRevision: 3); XCTFail("equipped item dismantled") }
        catch let error as CoreError { XCTAssertEqual(error, .gearInUse) }
    }

    func testCostumeAndWeaponAppearanceRequireOwnedActorCompatibleVisualOnlyItems() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: .newGame(catalog: catalog)))
        let initialGear = await engine.snapshot().gear
        do {
            _ = try await engine.dispatch(.selectWeaponAppearance(actorID: "C_WITCH", appearanceID: "STAFF_MOON"), operationID: UUID(), expectedRevision: 0)
            XCTFail("unowned appearance equipped")
        } catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error \(error)") } }
        _ = try await engine.dispatch(.setCosmetic("STAFF_MOON", owned: true), operationID: UUID(), expectedRevision: 0)
        do {
            _ = try await engine.dispatch(.selectWeaponAppearance(actorID: "C_SMITH", appearanceID: "STAFF_MOON"), operationID: UUID(), expectedRevision: 1)
            XCTFail("appearance selected for unsupported actor")
        } catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error \(error)") } }
        _ = try await engine.dispatch(.selectWeaponAppearance(actorID: "C_WITCH", appearanceID: "STAFF_MOON"), operationID: UUID(), expectedRevision: 1)
        _ = try await engine.dispatch(.selectWeaponAppearance(actorID: "C_WITCH", appearanceID: nil), operationID: UUID(), expectedRevision: 2)
        _ = try await engine.dispatch(.setFurniture("FURN_DESK_BOTANICAL", owned: true), operationID: UUID(), expectedRevision: 3)
        _ = try await engine.dispatch(.placeFurniture("FURN_DESK_BOTANICAL", placed: true), operationID: UUID(), expectedRevision: 4)
        let state = await engine.snapshot()
        XCTAssertNil(state.selectedWeaponAppearanceIDs["C_WITCH"])
        XCTAssertTrue(state.placedFurnitureIDs.contains("FURN_DESK_BOTANICAL"))
        XCTAssertEqual(state.gear, initialGear, "visual appearance must not create or alter equipment")
    }

    func testCombatIsFourPersonAutomaticAndSeedDeterministic() throws {
        let party = (0..<4).map { i in Combatant(id: "ally\(i)", maxHP: 80, attack: 18, defense: 5, effectIDs: i == 0 ? ["POISON_STACK", "FAMILIAR_CHASE"] : []) }
        let enemy = [Combatant(id: "enemy", maxHP: 140, attack: 5, defense: 2)]
        let a = try CombatSimulator.run(party: party, enemies: enemy, seed: 42)
        let b = try CombatSimulator.run(party: party, enemies: enemy, seed: 42)
        XCTAssertEqual(a, b); XCTAssertTrue(a.won); XCTAssertTrue(a.events.contains(where: { $0.kind == "direct" }))
        XCTAssertEqual(CombatSimulator.authority, .unapprovedTestOverlay)
    }

    func testR6TimelineUsesMillisecondCommitsRootActionsAndRoleSkills() throws {
        let party = [
            Combatant(id: "C_WITCH", maxHP: 420, attack: 38, defense: 28, effectIDs: ["POISON_STACK", "POISON_SHATTER", "POISON_BURST_25_AT_5"]),
            Combatant(id: "C_APPRENTICE", maxHP: 360, attack: 30, defense: 26, effectIDs: ["HEAL_TO_BARRIER", "HEAL_LINK"]),
            Combatant(id: "C_SMITH", maxHP: 620, attack: 28, defense: 52, effectIDs: ["SMITH_PRESSURE"], guardChanceBP: 10_000),
            Combatant(id: "C_FAMILIAR", maxHP: 390, attack: 32, defense: 30, effectIDs: ["FAMILIAR_CHASE", "FAMILIAR_MARK_10S", "FAMILIAR_DASH_BONUS_6000BP", "FAMILIAR_CHASE_ICD_1500MS"])
        ]
        let enemy = Combatant(id: "timeline-multi", maxHP: 10_000, attack: 75, defense: 10, actionPattern: "multiHit")
        let a = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 51, maxDurationMs: 12_000)
        let b = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 51, maxDurationMs: 12_000)
        XCTAssertEqual(a, b, "integer millisecond event queue must replay deterministically")
        XCTAssertEqual(a.initialPartyHP["C_WITCH"], 420)
        XCTAssertEqual(a.initialEnemyHP[enemy.id], enemy.maxHP)
        XCTAssertNotNil(a.remainingEnemyHP[enemy.id])
        XCTAssertTrue(a.events.allSatisfy { $0.timestampMs != nil })
        XCTAssertTrue(a.events.contains(where: { $0.kind == "cast_start" }))
        let openingCasts = a.events.filter { $0.kind == "cast_start" && $0.timestampMs == 0 }.map(\.sourceID)
        XCTAssertEqual(openingCasts, ["C_SMITH", "C_WITCH", "C_FAMILIAR"], "simultaneous automatic choices preserve R6-B coordinator ordering")
        XCTAssertTrue(a.events.contains(where: { $0.kind == "mark" }), "familiar's mark is an actual cast/commit effect")
        XCTAssertTrue(a.events.contains(where: { $0.kind == "guard" }), "guard is resolved on the impact timeline")
        XCTAssertTrue(a.events.contains(where: { $0.kind == "smith_pressure" }), "eligible Smith counter stores pressure once per root")
        XCTAssertTrue(a.events.contains(where: { $0.kind == "smith_hammer" }), "stored pressure is consumed by an active cooldown action")
        XCTAssertTrue(a.events.contains(where: { $0.kind == "poison_tick" }))
        let hits = a.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == "enemy:timeline-multi:1" }
        XCTAssertEqual(hits.count, 3, "multi-hit packet must share one root ID")
        XCTAssertLessThan(hits[0].timestampMs!, hits[1].timestampMs!)
    }

    func testR6PresentationClassifiesHPEventsWithoutDoubleApplyingAnnotations() throws {
        XCTAssertEqual(R6CombatPresentationSemantics.classify("heal_followup"), .damage,
                       "follow-up is damage despite 'heal' in its event name")
        XCTAssertEqual(R6CombatPresentationSemantics.classify("enemy_heal_cycle"), .healing)
        XCTAssertEqual(R6CombatPresentationSemantics.classify("smith_cover_barrier"), .barrier)
        XCTAssertEqual(R6CombatPresentationSemantics.classify("poison_burst"), .annotation)

        let events = [
            CombatEvent(tick: 1, kind: "direct", sourceID: "C_WITCH", targetID: "enemy", amount: 30),
            CombatEvent(tick: 1, kind: "poison_burst", sourceID: "C_WITCH", targetID: "enemy", amount: 30),
            CombatEvent(tick: 1, kind: "heal_followup", sourceID: "C_APPRENTICE", targetID: "enemy", amount: 10),
            CombatEvent(tick: 1, kind: "enemy_heal_cycle", sourceID: "enemy", targetID: "ally", amount: 20),
            CombatEvent(tick: 1, kind: "smith_cover_barrier", sourceID: "C_SMITH", targetID: "C_SMITH", amount: 5),
            CombatEvent(tick: 1, kind: "dot_tick", sourceID: "enemy", targetID: "ally", amount: 99)
        ]
        XCTAssertEqual(R6CombatPresentationSemantics.hpDelta(for: events[2]), -10)
        XCTAssertNil(R6CombatPresentationSemantics.hpDelta(for: events[1]), "poison_burst annotates direct damage; it is not another HP hit")
        XCTAssertNil(R6CombatPresentationSemantics.hpDelta(for: events[4]), "a barrier changes shield, not HP")
        XCTAssertEqual(R6CombatPresentationSemantics.replay(events: events,
                                                              initialHP: ["enemy": 100, "ally": 5, "C_SMITH": 90],
                                                              maximumHP: ["enemy": 100, "ally": 10, "C_SMITH": 100]),
                       ["enemy": 60, "ally": 0, "C_SMITH": 90],
                       "damage clamps at zero, healing clamps at maximum HP, and annotations/barriers do not move HP")
        XCTAssertEqual(R6CombatPresentationSemantics.replay(events: [
            CombatEvent(tick: 0, kind: "heal", sourceID: "C_APPRENTICE", targetID: "ally", amount: Int.max)
        ], initialHP: ["ally": 1], maximumHP: ["ally": 10]), ["ally": 10], "large healing clamps without integer overflow")
        XCTAssertEqual(R6CombatPresentationSemantics.replay(events: [], initialHP: ["ally": 20], maximumHP: ["ally": 10]),
                       ["ally": 10], "initial presentation HP is also clamped to maximum")
    }

    func testR6PresentationReplayMatchesCampaignAndChallengeBattleResults() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let actorIDs = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"]
        let party = actorIDs.map { catalog.projectCombatant(for: $0, with: []) }
        var results: [CombatResult] = []
        for enemyID in ["E_R01_01", "B_R01_A", "B_R05_B"] {
            let definition = try XCTUnwrap(catalog.enemies.first(where: { $0.id == enemyID }))
            let enemy = Combatant(id: definition.id, maxHP: definition.hp, attack: definition.attack,
                                  defense: definition.defense, actionPattern: definition.actionPattern ?? "standard")
            results.append(try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 51, maxDurationMs: 35_000))
        }
        for challengeID in ["CH_R01_02", "CH_R02_01", "CH_R05_02"] {
            let scenario = try catalog.challengeCombatScenario(challengeID)
            XCTAssertEqual(Set(scenario.enemies.map(\.id)).count, scenario.enemies.count,
                           "presentation HP replay needs unique entity IDs: \(challengeID)")
            results.append(try R6TimelineSimulator.run(party: party, enemies: scenario.enemies, seed: 51,
                                                       maxDurationMs: 35_000, challengeID: challengeID,
                                                       entityPresentation: scenario.entityPresentation))
        }
        XCTAssertEqual(results.count, 6)
        for result in results {
            let initial = result.initialPartyHP.merging(result.initialEnemyHP, uniquingKeysWith: { first, _ in first })
            let actual = result.remainingPartyHP.merging(result.remainingEnemyHP, uniquingKeysWith: { first, _ in first })
            XCTAssertEqual(Set(initial.keys), Set(actual.keys))
            XCTAssertEqual(R6CombatPresentationSemantics.replay(events: result.events, initialHP: initial), actual,
                           "every R6Timeline event must replay to the battle's final HP: won=\(result.won), t=\(result.ticks)")
        }
    }

    func testCombatResultLegacyDecodeDefaultsNewHealthMaps() throws {
        let legacy = #"{"won":true,"ticks":2,"events":[],"remainingPartyHP":{"C_WITCH":10}}"#
        let result = try JSONDecoder().decode(CombatResult.self, from: Data(legacy.utf8))
        XCTAssertTrue(result.won)
        XCTAssertEqual(result.remainingPartyHP["C_WITCH"], 10)
        XCTAssertTrue(result.initialPartyHP.isEmpty)
        XCTAssertTrue(result.initialEnemyHP.isEmpty)
        XCTAssertTrue(result.remainingEnemyHP.isEmpty)
        XCTAssertTrue(result.entityPresentation.isEmpty)
    }

    func testCombatEntityPresentationSurvivesResultCodingAndCampaignMapsCatalogEnemy() async throws {
        let presentation = CombatEntityPresentation(entityID: "ADD_1", kind: "add", catalogID: "E_R01_01", label: "小型支援個体", assetKey: "E_R01_01")
        let original = CombatResult(won: false, ticks: 0, events: [], remainingPartyHP: [:], entityPresentation: ["ADD_1": presentation])
        let roundTrip = try JSONDecoder().decode(CombatResult.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(roundTrip.entityPresentation["ADD_1"], presentation)

        let catalog = try GameCatalog.bundledTestOverlay()
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot.newGame(catalog: catalog)))
        _ = try await game.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 700), operationID: UUID(), expectedRevision: 0)
        let snapshot = await game.snapshot()
        let enemy = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "E_R01_01" }))
        XCTAssertEqual(snapshot.lastCombatResult?.entityPresentation[enemy.id]?.catalogID, enemy.id)
        XCTAssertEqual(snapshot.lastCombatResult?.entityPresentation[enemy.id]?.label, enemy.name)
    }

    func testR6TimelineWardReplacementReflectsOwnBarrierAtDepthOne() throws {
        let party = [
            Combatant(id: "C_WITCH", maxHP: 1_000, attack: 100, defense: 20, effectIDs: ["BARRIER_WARD", "BARRIER_REFLECT"]),
            Combatant(id: "C_APPRENTICE", maxHP: 1_000, attack: 30, defense: 20),
            Combatant(id: "C_SMITH", maxHP: 1_000, attack: 30, defense: 20, guardChanceBP: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 1_000, attack: 30, defense: 20)
        ]
        let enemy = Combatant(id: "ward-target", maxHP: 20_000, attack: 300, defense: 5, actionPattern: "heavy")
        let result = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 11, maxDurationMs: 12_000)
        let ward = try XCTUnwrap(result.events.first(where: { $0.kind == "barrier" && $0.sourceID == "C_WITCH" }))
        let absorbed = try XCTUnwrap(result.events.first(where: { $0.kind == "barrier_absorb" && $0.sourceID == enemy.id }))
        let reflect = try XCTUnwrap(result.events.first(where: { $0.kind == "reflect" }))
        XCTAssertLessThan(ward.timestampMs!, absorbed.timestampMs!)
        XCTAssertEqual(absorbed.timestampMs, reflect.timestampMs, "reaction resolves at the same logical time")
        XCTAssertLessThan(try XCTUnwrap(result.events.firstIndex(of: absorbed)), try XCTUnwrap(result.events.firstIndex(of: reflect)))
        XCTAssertTrue(reflect.rootActionID?.hasPrefix("reflect:enemy:") == true, "reflection is depth-one and carries a child root")
    }

    func testAuthoredEnemyActionUsesSourceTelegraphAndHitOffsets() throws {
        let party = [
            Combatant(id: "C_WITCH", maxHP: 10_000, attack: 10, defense: 10),
            Combatant(id: "C_APPRENTICE", maxHP: 10_000, attack: 10, defense: 10),
            Combatant(id: "C_SMITH", maxHP: 10_000, attack: 10, defense: 10),
            Combatant(id: "C_FAMILIAR", maxHP: 10_000, attack: 10, defense: 10)
        ]
        let action = EnemyActionDefinition(id: "ROOT_VOLLEY", coefficientBP: 10_500, windupMs: 1_300,
                                           hitOffsetsMs: [0, 250, 500], recoveryMs: 2_000, restMs: 1_000)
        let enemy = Combatant(id: "fixture-boss", maxHP: 10_000_000, attack: 1_900, defense: 1_050,
                              level: 12, firstTelegraphMs: 1_800, enemyActions: [action])
        let result = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 100_049, maxDurationMs: 4_000)
        XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_telegraph" && $0.timestampMs == 1_800 }))
        let hits = result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == "enemy:fixture-boss:1" }
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits.compactMap(\.timestampMs), [3_100, 3_350, 3_600])
        XCTAssertEqual(result.initialEnemyHP[enemy.id], enemy.maxHP)
    }

    func testGearQualityAffixesAndInvestmentChangeRealBattleStats() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let base = GameSnapshot.newGame(catalog: catalog)
        let instanceID = try XCTUnwrap(base.gear.first?.id)
        var improved = base
        let index = try XCTUnwrap(improved.gear.firstIndex(where: { $0.id == instanceID }))
        improved.gear[index].qualityID = "Q4"
        improved.gear[index].enhancement = 10
        improved.gear[index].affixIDs = ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]
        improved.gear[index].latentEffectID = "LATENT_POWER_TEST"
        let enemyID = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "B_R01_A" })?.id)
        let plainEngine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: base))
        let enhancedEngine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: improved))
        _ = try await plainEngine.dispatch(.resolveEncounter(enemyID: enemyID, seed: 91), operationID: UUID(), expectedRevision: 0)
        _ = try await enhancedEngine.dispatch(.resolveEncounter(enemyID: enemyID, seed: 91), operationID: UUID(), expectedRevision: 0)
        let plainState = await plainEngine.snapshot(), enhancedState = await enhancedEngine.snapshot()
        XCTAssertNotEqual(plainState.lastCombatResult, enhancedState.lastCombatResult)
    }

    func testEvolutionRecipePreservesInstanceOwnerProtectionAndInvestment() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let recipe = try XCTUnwrap(catalog.recipes.first(where: { $0.id == "RC_EQ_W_G1" }))
        var state = GameSnapshot.newGame(catalog: catalog)
        let itemID = try XCTUnwrap(state.gear.first?.id)
        state.gear[0].investmentDust = 47
        state.gear[0].enhancement = 2
        state.completedEncounterIDs.insert("B_R01_B")
        for (id, amount) in recipe.costs { state.materials[id] = amount }
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        _ = try await game.dispatch(.evolveGear(gearID: itemID, recipeID: recipe.id), operationID: UUID(), expectedRevision: 0)
        let evolved = await game.snapshot()
        let item = try XCTUnwrap(evolved.gear.first(where: { $0.id == itemID }))
        XCTAssertEqual(item.definitionID, recipe.outputGearID)
        XCTAssertEqual(item.ownerID, "C_WITCH")
        XCTAssertTrue(item.protected)
        XCTAssertEqual(item.enhancement, 2)
        XCTAssertEqual(item.investmentDust, 47)
        for (id, amount) in recipe.costs { XCTAssertEqual(evolved.materials[id], 0, "\(id): \(amount)") }
    }

    func testGameEngineR6TimelineExecutesCandidatePoisonShatterAtFiveStacks() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var state = GameSnapshot.newGame(catalog: catalog)
        state.gear[0].definitionID = "EQ_W_P2"
        state.unlockedRegionIDs.formUnion(catalog.regions.map(\.id))
        state.completedEncounterIDs.insert("B_R05_A")
        state.activeRegionID = "R05"
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        _ = try await game.dispatch(.resolveEncounter(enemyID: "B_R05_B", seed: 100_049), operationID: UUID(), expectedRevision: 0)
        let after = await game.snapshot()
        let result = try XCTUnwrap(after.lastCombatResult)
        let burst = try XCTUnwrap(result.events.first(where: { $0.kind == "poison_burst" }))
        let priorStack = try XCTUnwrap(result.events.last(where: { $0.kind == "poison_stack" && ($0.timestampMs ?? Int.max) <= (burst.timestampMs ?? 0) }))
        XCTAssertGreaterThanOrEqual(priorStack.amount, 5)
        XCTAssertGreaterThan(burst.amount, 0)
    }

    func testChallengeCombatPreservesEachEnemiesAuthoredActionPattern() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var state = GameSnapshot.newGame(catalog: catalog)
        state.unlockedRegionIDs.formUnion(catalog.regions.map(\.id))
        state.completedEncounterIDs.formUnion(catalog.enemies.map(\.id))
        state.activeRegionID = "R01"
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        _ = try await game.dispatch(.resolveChallenge(challengeID: "CH_R01_02", seed: 88), operationID: UUID(), expectedRevision: 0)
        let after = await game.snapshot()
        let events = try XCTUnwrap(after.lastCombatResult).events
        XCTAssertTrue(events.contains(where: { $0.kind == "party_slow" && $0.sourceID == "E_R01_02" }))
        XCTAssertFalse(events.contains(where: { $0.kind == "dot_applied" && $0.sourceID == "E_R01_02" }))
        XCTAssertEqual(events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R01_03" && $0.rootActionID == "enemy:E_R01_03:1" }.count, 3)
        _ = try await game.dispatch(.resolveChallenge(challengeID: "CH_R02_03", seed: 89), operationID: UUID(), expectedRevision: 1)
        let afterAdds = await game.snapshot()
        let addWaveResult = try XCTUnwrap(afterAdds.lastCombatResult)
        XCTAssertTrue(addWaveResult.initialEnemyHP.keys.contains(where: { $0 == "CH_R02_03_ADD_1" }))
    }

    func testProvisionalChallengeMechanicsHaveObservableRuntimeEffects() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map { Combatant(id: $0, maxHP: 10_000, attack: 10, defense: 0) }
        let selfParty = party
        func run(_ challengeID: String, hp: Int = 20_000, attack: Int = 10, party: [Combatant]? = nil, duration: Int = 30_000) throws -> [CombatEvent] {
            let enemy = Combatant(id: "B_PROBE", maxHP: hp, attack: attack, defense: 0, firstTelegraphMs: 1_500)
            return try R6TimelineSimulator.run(party: party ?? selfParty, enemies: [enemy], seed: 912, maxDurationMs: duration, challengeID: challengeID).events
        }
        let slow = try run("CH_R01_02")
        XCTAssertTrue(slow.contains(where: { $0.kind == "party_slow" }))
        let interrupt = try run("CH_R03_03")
        XCTAssertTrue(interrupt.contains(where: { $0.kind == "enemy_cast_start" }))
        XCTAssertTrue(interrupt.contains(where: { $0.kind == "cast_interrupt" }))
        let strong = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map { Combatant(id: $0, maxHP: 10_000, attack: 300, defense: 0) }
        let phase = try run("CH_R03_02", hp: 5_000, attack: 1, party: strong, duration: 30_000)
        XCTAssertTrue(phase.contains(where: { $0.kind == "phase_heat" }))
        XCTAssertTrue(phase.contains(where: { $0.kind == "enemy_phase_shift" }))
        let linked = try run("CH_R04_02")
        XCTAssertTrue(linked.contains(where: { $0.kind == "enemy_buff" }))
        XCTAssertTrue(linked.contains(where: { $0.kind == "party_weaken" }))
    }

    func testAllChallengeIDsSelectDistinctMechanicPacketsInTimeline() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map { Combatant(id: $0, maxHP: 20_000, attack: 5, defense: 0) }
        let selfParty = party
        func events(_ id: String, hp: Int = 50_000, party: [Combatant]? = nil, duration: Int = 20_000) throws -> [CombatEvent] {
            let foe = Combatant(id: "FOE_\(id)", maxHP: hp, attack: 20, defense: 0, firstTelegraphMs: 1_000)
            return try R6TimelineSimulator.run(party: party ?? selfParty, enemies: [foe], seed: 443, maxDurationMs: duration, challengeID: id).events
        }
        let checks: [(String, String)] = [
            ("CH_R01_01", "telegraph_heavy"), ("CH_R01_02", "party_slow"), ("CH_R01_03", "telegraph_heavy"),
            ("CH_R02_01", "enemy_heal_cycle"), ("CH_R02_02", "enemy_armor"),
            ("CH_R03_01", "telegraph_heavy"), ("CH_R03_03", "cast_interrupt"), ("CH_R04_01", "telegraph_heavy"),
            ("CH_R04_02", "enemy_buff"), ("CH_R04_03", "telegraph_aoe"), ("CH_R05_01", "telegraph_heavy"),
            ("CH_R05_03", "challenge_combo")
        ]
        for (id, kind) in checks {
            XCTAssertTrue(try events(id).contains(where: { $0.kind == kind }), "\(id) must exercise \(kind)")
        }
        let phaseParty = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map { Combatant(id: $0, maxHP: 20_000, attack: 300, defense: 0) }
        XCTAssertTrue(try events("CH_R03_02", hp: 5_000, party: phaseParty, duration: 25_000).contains(where: { $0.kind == "enemy_phase_shift" }))
    }

    func testCandidateArmorOnlyReducesPartyDamageToEnemyAndKeepsChallengeEnemyDamageIntact() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 10_000, attack: 100, defense: 0)
        }
        let shell = try EnemyActionPreviewFixture.armorDefense()
        XCTAssertEqual(shell.entityPresentation["E_R01_04"]?.assetKey, "ACT_E_R01_04")
        let mitigations = shell.events.filter { $0.kind == "enemy_armor" && $0.sourceID == "E_R01_04" }
        XCTAssertFalse(mitigations.isEmpty, "armor cue accompanies only actual damage prevented on the enemy")
        XCTAssertTrue(mitigations.allSatisfy { $0.amount > 0 })
        for mitigation in mitigations {
            let attack = try XCTUnwrap(shell.events.first(where: { ["direct", "smith_hammer", "poison_seed"].contains($0.kind) && $0.rootActionID == mitigation.rootActionID }))
            XCTAssertEqual(mitigation.targetID, attack.sourceID, "armor cue target is the attacking ally, while source is the armored enemy")
        }
        XCTAssertTrue(mitigations.allSatisfy { !($0.rootActionID ?? "").hasPrefix("enemy:") },
                      "armor cues must be attached to an ally attack root, never an enemy outgoing-hit root")

        let mirror = Combatant(id: "B_R02_B", maxHP: 100_000, attack: 50, defense: 0,
                               actionPattern: "mirrorCycle", firstTelegraphMs: 0)
        let challenge = try R6TimelineSimulator.run(party: party, enemies: [mirror], seed: 1202,
                                                     maxDurationMs: 5_000, challengeID: "CH_R02_02")
        let ordinary = try R6TimelineSimulator.run(party: party, enemies: [mirror], seed: 1202,
                                                    maxDurationMs: 5_000)
        let challengeHits = challenge.events.filter { $0.kind == "enemy_hit" }.map { ($0.timestampMs, $0.targetID, $0.amount) }
        let ordinaryHits = ordinary.events.filter { $0.kind == "enemy_hit" }.map { ($0.timestampMs, $0.targetID, $0.amount) }
        XCTAssertEqual(challengeHits.count, ordinaryHits.count)
        for (candidate, baseline) in zip(challengeHits, ordinaryHits) {
            XCTAssertEqual(candidate.0, baseline.0)
            XCTAssertEqual(candidate.1, baseline.1)
            XCTAssertEqual(candidate.2, baseline.2, "R02 membrane defense changes damage dealt to the boss, not outgoing boss damage")
        }
        let challengeArmor = challenge.events.filter { $0.kind == "enemy_armor" }
        XCTAssertTrue(challengeArmor.contains(where: { $0.sourceID == "B_R02_B" && Set(party.map(\.id)).contains($0.targetID) && $0.amount > 0 }))
    }

    func testLampVesselCandidateSupportsGuardianInChallengeEngine() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var state = GameSnapshot.newGame(catalog: catalog)
        state.completedEncounterIDs.insert("B_R05_B")
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        _ = try await game.dispatch(.resolveChallenge(challengeID: "CH_R05_02", seed: 912), operationID: UUID(), expectedRevision: 0)
        let snapshot = await game.snapshot()
        let result = try XCTUnwrap(snapshot.lastCombatResult)
        XCTAssertTrue(result.initialEnemyHP.keys.contains(where: { $0.hasPrefix("LAMP_VESSEL") }))
        let lamp = try XCTUnwrap(result.entityPresentation.values.first(where: { $0.kind == "prop" }))
        XCTAssertEqual(lamp.assetKey, "PROP_LAMP_VESSEL")
        XCTAssertEqual(lamp.label, "灯瓶")
        XCTAssertTrue(result.events.contains(where: { $0.kind == "direct" && $0.targetID.hasPrefix("LAMP_VESSEL") }))
    }

    func testLampVesselSupportsGuardianWhenItSurvivesToAnEnemyImpact() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1_000, defense: 0)
        }
        let enemies = [
            Combatant(id: "E_R05_02", maxHP: 100_000, attack: 100, defense: 0, actionPattern: "support", firstTelegraphMs: 1_500),
            Combatant(id: "E_R05_03", maxHP: 100_000, attack: 100, defense: 0, actionPattern: "lightTransfer", firstTelegraphMs: 1_500),
            Combatant(id: "LAMP_VESSEL_CH_R05_02", maxHP: 1_000_000, attack: 0, defense: 0, actionPattern: "stationary")
        ]
        let result = try R6TimelineSimulator.run(party: party, enemies: enemies, seed: 912,
            maxDurationMs: 12_000, challengeID: "CH_R05_02")
        XCTAssertTrue(result.events.contains(where: { $0.kind == "lamp_support" && $0.sourceID == "LAMP_VESSEL_CH_R05_02" }))
    }

    func testAllFifteenChallengeProposalsRunAutoBattlesAndRewardOnlyFirstClear() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        XCTAssertEqual(catalog.challenges.count, 15)
        for challenge in catalog.challenges {
            var state = GameSnapshot.newGame(catalog: catalog)
            state.completedEncounterIDs.insert("B_R05_B")
            for i in state.gear.indices { state.gear[i].qualityID = "Q4"; state.gear[i].enhancement = 10; state.gear[i].affixIDs = ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"] }
            let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
            let challengeReceipt = try await game.dispatch(.resolveChallenge(challengeID: challenge.id, seed: 77), operationID: UUID(), expectedRevision: 0)
            XCTAssertTrue(challengeReceipt.result.contains("CHALLENGE SIMULATED_VICTORY: \(challenge.id)"), "receipt=\(challengeReceipt.result)")
            XCTAssertTrue(challengeReceipt.result.contains("designStatus=DESIGN_ONLY_NOT_PLAYTESTED"))
            let first = await game.snapshot()
            XCTAssertEqual(first.lastEncounterID, challenge.id)
            XCTAssertNotNil(first.lastCombatResult)
            XCTAssertTrue(first.lastCombatResult?.won == true, "candidate party must clear \(challenge.id): \(String(describing: first.lastCombatResult))")
            let firstKey = "CHALLENGE_CLEAR|\(challenge.id)"
            if first.completedEncounterIDs.contains(firstKey) {
                let powder = first.materials["refine_dust", default: 0]
                _ = try await game.dispatch(.resolveChallenge(challengeID: challenge.id, seed: 77), operationID: UUID(), expectedRevision: 1)
                let repeatState = await game.snapshot()
                XCTAssertEqual(repeatState.materials["refine_dust", default: 0], powder, "repeat reward for \(challenge.id)")
            }
        }
    }

    func testEnemyMultiHitSharesOneRootActionAndDefensiveEffectsResolve() throws {
        let party = [
            Combatant(id: "C_SMITH", maxHP: 10_000, attack: 16, defense: 8, effectIDs: ["SMITH_PRESSURE", "BARRIER_WARD", "BARRIER_REFLECT"], guardChanceBP: 10_000),
            Combatant(id: "C_WITCH", maxHP: 10_000, attack: 18, defense: 2, effectIDs: ["POISON_STACK", "POISON_STACK_CAP_2", "POISON_SHATTER", "POISON_BURST_25_AT_5"]),
            Combatant(id: "C_APPRENTICE", maxHP: 10_000, attack: 12, defense: 2, effectIDs: ["HEAL_TO_BARRIER", "HEAL_LINK"]),
            Combatant(id: "C_FAMILIAR", maxHP: 10_000, attack: 18, defense: 2, effectIDs: ["FAMILIAR_CHASE", "FAMILIAR_MARK_10S", "FAMILIAR_DASH_BONUS_6000BP", "FAMILIAR_CHASE_ICD_1500MS"])
        ]
        let enemy = Combatant(id: "multi", maxHP: 5_000, attack: 18, defense: 2, actionPattern: "multiHit")
        let result = try CombatSimulator.run(party: party, enemies: [enemy], seed: 23, maxTicks: 20)
        let hits = result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == "enemy:multi:1" }
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(Set(hits.compactMap(\.rootActionID)).count, 1)
        let firstRootCounters = result.events.filter { $0.kind == "smith_pressure" && $0.rootActionID == "enemy:multi:1" }
        XCTAssertEqual(firstRootCounters.count, 1, "three hits in one enemy root action increment pressure once")
        XCTAssertEqual(firstRootCounters.first?.amount, 1)
        XCTAssertEqual(result.events.filter { $0.kind == "smith_counter" && $0.rootActionID == "enemy:multi:1" }.count, 1)
        XCTAssertTrue(result.events.contains(where: { $0.kind == "smith_hammer" }), "stored eligible pressure is consumed by a cooldown-gated hammer action")
        XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_weaken" }), "hammer applies its candidate weaken effect")
        XCTAssertTrue(result.events.contains(where: { $0.kind == "smith_pressure" }))
        XCTAssertTrue(result.events.contains(where: { $0.kind == "poison_burst" }))
        XCTAssertTrue(result.events.contains(where: { $0.kind == "familiar_mark" }))
    }

    func testWardIsCastBeforeThreatAndReflectsOnlyItsOwnAbsorption() throws {
        let party = [
            Combatant(id: "C_WITCH", maxHP: 100, attack: 10, defense: 0, effectIDs: ["BARRIER_WARD", "BARRIER_REFLECT"]),
            Combatant(id: "C_APPRENTICE", maxHP: 100, attack: 1, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 100, attack: 1, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 100, attack: 1, defense: 0)
        ]
        let enemy = Combatant(id: "striker", maxHP: 5_000, attack: 60, defense: 0)
        let result = try CombatSimulator.run(party: party, enemies: [enemy], seed: 3, maxTicks: 1)
        let wardIndex = try XCTUnwrap(result.events.firstIndex(where: { $0.kind == "ward_create" }))
        let hitIndex = try XCTUnwrap(result.events.firstIndex(where: { $0.kind == "enemy_hit" }))
        XCTAssertLessThan(wardIndex, hitIndex, "ward must resolve before the predicted hit")
        XCTAssertEqual(result.events.first(where: { $0.kind == "ward_create" })?.amount, 20)
        XCTAssertEqual(result.events.first(where: { $0.kind == "barrier_absorb" })?.amount, 20)
        XCTAssertEqual(result.events.first(where: { $0.kind == "barrier_reflect" })?.amount, 10)
    }

    func testThreeCandidateGearStrategiesAgainstAllFifteenChallengeProposals() async throws {
        // Legacy name retained for the QA report; every trace now runs through GameEngine dispatch.
        let catalog = try GameCatalog.bundledTestOverlay()
        let roles: [(String, [String])] = [
            ("direct", ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"]),
            ("toxin_chase", ["EQ_W_P2", "EQ_A_01", "EQ_S_01", "EQ_F_03"]),
            ("ward_heal_counter", ["EQ_W_G2", "EQ_A_03", "EQ_S_03", "EQ_F_03"])
        ]
        let challengeIDs = catalog.challenges.map(\.id)
        for challengeID in challengeIDs {
            for (name, templateIDs) in roles {
                var state = GameSnapshot.newGame(catalog: catalog)
                state.completedEncounterIDs.insert("B_R05_B")
                for (actorID, templateID) in zip(["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"], templateIDs) {
                    guard let definition = catalog.gear.first(where: { $0.id == templateID }) else { XCTFail("missing gear \(templateID)"); continue }
                    let instanceID = UUID()
                    state.gear.append(GearInstance(id: instanceID, definitionID: templateID, ownerID: actorID, protected: true, enhancement: 10, qualityID: "Q4", affixIDs: ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]))
                    state.equippedGearIDs["\(actorID)|\(definition.slot)"] = instanceID
                }
                let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
                _ = try await game.dispatch(.resolveChallenge(challengeID: challengeID, seed: 733), operationID: UUID(), expectedRevision: 0)
                let snapshot = await game.snapshot()
                let first = try XCTUnwrap(snapshot.lastCombatResult)
                XCTAssertEqual(snapshot.lastEncounterID, challengeID)
                let expectedPresentation = try catalog.challengeCombatScenario(challengeID).entityPresentation
                for (entityID, mapping) in expectedPresentation {
                    XCTAssertEqual(first.entityPresentation[entityID], mapping, "\(challengeID) should preserve candidate render mapping")
                }
                let survivors = first.remainingPartyHP.values.filter { $0 > 0 }.count
                print("GAMEENGINE_CHALLENGE_QA,\(challengeID),\(name),won=\(first.won),timeMs=\(first.events.last?.timestampMs ?? 0),survivors=\(survivors),events=\(first.events.count)")
            }
        }
    }

    func testSixRealCatalogEnemiesPerRegionRunWithAuthoredEnemyPatterns() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map { Combatant(id: $0, maxHP: 10_000, attack: 1, defense: 0) }
        for region in catalog.regions {
            let regionalEnemies = catalog.enemies.filter { $0.regionID == region.id }
            XCTAssertEqual(regionalEnemies.count, 6, "R1 world catalog currently defines six enemies per region")
            for enemy in regionalEnemies {
                let foe = Combatant(id: enemy.id, maxHP: enemy.hp, attack: enemy.attack, defense: enemy.defense, actionPattern: enemy.actionPattern ?? "standard")
                let result = try R6TimelineSimulator.run(party: party, enemies: [foe], seed: 20261010, maxDurationMs: 10_000)
                XCTAssertEqual(result, try R6TimelineSimulator.run(party: party, enemies: [foe], seed: 20261010, maxDurationMs: 10_000))
                XCTAssertFalse(result.events.isEmpty, "no combat events for \(enemy.id)")
                switch foe.actionPattern {
                case "dot": XCTAssertTrue(result.events.contains(where: { $0.kind == "dot_applied" }), enemy.id)
                case "support": XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_support" }), enemy.id)
                case "multiHit", "multiHitRest":
                    XCTAssertEqual(result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == "enemy:\(enemy.id):1" }.count, 3, enemy.id)
                case "heavy": XCTAssertTrue(result.events.contains(where: { $0.kind == "telegraph_heavy" }), enemy.id)
                case "armor":
                    // Candidate carapace now protects the enemy from party damage only. The
                    // ordinary enemy->party action must not create a misleading armor cue.
                    XCTAssertFalse(result.events.contains(where: { event in
                        event.kind == "enemy_armor" && event.sourceID == enemy.id
                            && party.contains(where: { $0.id == event.targetID })
                    }), enemy.id)
                case "magicSupport": XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_magic_support" }), enemy.id)
                case "lightTransfer": XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_hit" }), enemy.id)
                case "seedGuardUltimate":
                    XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_seed_pressure" }),
                                  "the authored seed-pressure phase is the expected opening action for \(enemy.id)")
                case "aoe": XCTAssertTrue(result.events.contains(where: { $0.kind == "telegraph_aoe" }), enemy.id)
                case "combined": XCTAssertTrue(result.events.contains(where: { $0.kind == "telegraph_aoe" }), enemy.id)
                default: XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_hit" }), enemy.id)
                }
                print("R6_WORLD_QA,\(region.id),\(enemy.id),pattern=\(foe.actionPattern),won=\(result.won),timeMs=\(result.events.last?.timestampMs ?? 0),events=\(result.events.count)")
            }
        }
    }

    func testR4EnemyActionCandidateEventsMatchThreeArtContracts() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 20_000, attack: 1, defense: 0)
        }

        let doubleLeaf = try R6TimelineSimulator.run(party: party,
            enemies: [Combatant(id: "E_R01_03", maxHP: 100_000, attack: 100, defense: 0,
                                actionPattern: "multiHitRest", firstTelegraphMs: 1_500)],
            seed: 811, maxDurationMs: 12_000)
        let firstRoot = doubleLeaf.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == "enemy:E_R01_03:1" }
        XCTAssertEqual(firstRoot.count, 3)
        XCTAssertEqual(firstRoot.compactMap(\.timestampMs).sorted().map { $0 - firstRoot.compactMap(\.timestampMs).sorted().first! }, [0, 350, 700])
        XCTAssertTrue(doubleLeaf.events.contains(where: { $0.kind == "enemy_telegraph" && $0.sourceID == "E_R01_03" }))

        let silkSlow = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R01_02", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "slow", firstTelegraphMs: 1_500)
        ], seed: 811, maxDurationMs: 5_000)
        XCTAssertTrue(silkSlow.events.contains(where: { $0.kind == "party_slow" && $0.sourceID == "E_R01_02" }))
        XCTAssertFalse(silkSlow.events.contains(where: { $0.kind == "dot_applied" && $0.sourceID == "E_R01_02" }),
                       "silk reduces one ally's tempo; it is not a damage-over-time effect")

        let spores = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R02_01", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "drowse", firstTelegraphMs: 1_500)
        ], seed: 811, maxDurationMs: 4_000)
        XCTAssertTrue(spores.events.contains(where: { $0.kind == "telegraph_aoe" && $0.sourceID == "E_R02_01" }))
        XCTAssertEqual(Set(spores.events.filter { $0.kind == "party_drowse" }.map(\.targetID)).count, 4)
        XCTAssertFalse(spores.events.contains(where: { $0.kind == "dot_applied" && $0.sourceID == "E_R02_01" }),
                       "spore drowse is a party tempo debuff, not poison damage")

        let reflecting = try R6TimelineSimulator.run(party: [
            Combatant(id: "C_WITCH", maxHP: 100_000, attack: 1_000, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 100_000, attack: 1_000, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 100_000, attack: 1_000, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 100_000, attack: 1_000, defense: 0)
        ], enemies: [Combatant(id: "E_R02_03", maxHP: 100_000, attack: 100, defense: 0,
                               actionPattern: "reflect", firstTelegraphMs: 1_500)], seed: 811, maxDurationMs: 8_000)
        let reflected = try XCTUnwrap(reflecting.events.first(where: { $0.kind == "enemy_reflect_projectile" }))
        XCTAssertEqual(reflected.sourceID, "E_R02_03")
        XCTAssertTrue(reflecting.events.contains(where: { $0.kind == "direct" && $0.sourceID == reflected.targetID }))

        var interruptionResult: CombatResult?
        for candidateSeed in UInt64(1)...UInt64(32) where interruptionResult == nil {
            let result = try R6TimelineSimulator.run(party: party, enemies: [
                Combatant(id: "E_R03_02", maxHP: 100_000, attack: 100, defense: 0,
                          actionPattern: "interrupt", firstTelegraphMs: 0)
            ], seed: candidateSeed, maxDurationMs: 8_000)
            if result.events.contains(where: { $0.kind == "cast_interrupt" && $0.sourceID == "E_R03_02" }) {
                interruptionResult = result
            }
        }
        XCTAssertNotNil(interruptionResult, "resonance attack must interrupt an in-progress ally cast in the exercised seeds")
        XCTAssertTrue(interruptionResult?.events.contains(where: { $0.kind == "cast_interrupt" && $0.amount == 1_000 }) == true)

        var castingSlowResult: CombatResult?
        for candidateSeed in UInt64(1)...UInt64(32) where castingSlowResult == nil {
            let result = try R6TimelineSimulator.run(party: party, enemies: [
                Combatant(id: "E_R04_02", maxHP: 100_000, attack: 100, defense: 0,
                          actionPattern: "castingSlow", firstTelegraphMs: 0)
            ], seed: candidateSeed, maxDurationMs: 8_000)
            if result.events.contains(where: { $0.kind == "party_cast_slow" && $0.sourceID == "E_R04_02" }) {
                castingSlowResult = result
            }
        }
        XCTAssertNotNil(castingSlowResult, "wing gust must apply a casting-speed debuff to an ally hit during an active cast")
        XCTAssertFalse(castingSlowResult?.events.contains(where: { $0.kind == "enemy_support" && $0.sourceID == "E_R04_02" }) == true,
                       "casting wind must not invoke the healing-support fallback")

        let guardPosture = try R6TimelineSimulator.run(party: [
            Combatant(id: "C_WITCH", maxHP: 20_000, attack: 1_000, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 20_000, attack: 1_000, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 20_000, attack: 1_000, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 20_000, attack: 1_000, defense: 0)
        ], enemies: [Combatant(id: "E_R05_02", maxHP: 100_000, attack: 100, defense: 0,
                               actionPattern: "guardAlternating", firstTelegraphMs: 0)], seed: 811, maxDurationMs: 4_000)
        XCTAssertTrue(guardPosture.events.contains(where: { $0.kind == "enemy_guard_stance" && $0.sourceID == "E_R05_02" }))
        XCTAssertTrue(guardPosture.events.contains(where: { $0.kind == "enemy_guard_absorb" && $0.sourceID == "E_R05_02" }))
        XCTAssertFalse(guardPosture.events.contains(where: { $0.kind == "enemy_support" && $0.sourceID == "E_R05_02" }),
                       "R05 guard/attack stances do not fabricate a healing action")

        let regenPoison = try R6TimelineSimulator.run(party: [
            Combatant(id: "C_WITCH", maxHP: 20_000, attack: 1_000, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 20_000, attack: 1_000, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 20_000, attack: 1_000, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 20_000, attack: 1_000, defense: 0)
        ], enemies: [Combatant(id: "E_R05_04", maxHP: 100_000, attack: 100, defense: 0,
                               actionPattern: "regenPoison", firstTelegraphMs: 1_500)], seed: 811, maxDurationMs: 8_000)
        XCTAssertTrue(regenPoison.events.contains(where: { $0.kind == "enemy_regen" && $0.sourceID == "E_R05_04" && $0.amount > 0 }))
        XCTAssertTrue(regenPoison.events.contains(where: { $0.kind == "dot_applied" && $0.sourceID == "E_R05_04" }))

        let supportDisrupt = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R05_01", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "supportDisrupt", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 4_000,
           initialBarriers: Dictionary(uniqueKeysWithValues: party.map { ($0.id, (amount: 10, expiryMs: 10_000)) }))
        XCTAssertTrue(supportDisrupt.events.contains(where: { $0.kind == "support_duration_reduced" && $0.sourceID == "E_R05_01" }))

        let magicSupport = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R02_04", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "magicSupport", firstTelegraphMs: 1_500),
            Combatant(id: "SUPPORT_RECIPIENT", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "standard", firstTelegraphMs: 1_500)
        ], seed: 812, maxDurationMs: 8_000)
        let supportEvent = try XCTUnwrap(magicSupport.events.first(where: { $0.kind == "enemy_magic_support" }))
        XCTAssertEqual(supportEvent.sourceID, "E_R02_04")
        XCTAssertEqual(supportEvent.targetID, "SUPPORT_RECIPIENT")
        XCTAssertEqual(supportEvent.amount, 1_500)
        XCTAssertEqual(supportEvent.diagnostics?["duration_ms"], 5_000)
        XCTAssertFalse(magicSupport.events.contains(where: { $0.kind == "enemy_hit" && $0.sourceID == "E_R02_04" }),
                       "support arc must not be rendered as an attack impact")
        let buffedHit = try XCTUnwrap(magicSupport.events.first(where: { $0.kind == "enemy_hit" && $0.sourceID == "SUPPORT_RECIPIENT" }))
        let unbuffed = try R6TimelineSimulator.run(party: party,
            enemies: [Combatant(id: "SUPPORT_RECIPIENT", maxHP: 100_000, attack: 100, defense: 0,
                                actionPattern: "standard", firstTelegraphMs: 1_500)],
            seed: 812, maxDurationMs: 8_000)
        let unbuffedHit = try XCTUnwrap(unbuffed.events.first(where: { $0.kind == "enemy_hit" && $0.sourceID == "SUPPORT_RECIPIENT" }))
        XCTAssertGreaterThan(buffedHit.amount, unbuffedHit.amount, "magic support must change the recipient's later attack")
        let soloMagicSupport = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R02_04", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "magicSupport", firstTelegraphMs: 1_500)
        ], seed: 812, maxDurationMs: 8_000)
        XCTAssertTrue(soloMagicSupport.events.contains(where: { $0.kind == "enemy_magic_support" && $0.sourceID == $0.targetID }),
                      "solo support must self-target rather than lose its action")
        XCTAssertFalse(soloMagicSupport.events.contains(where: { $0.kind == "enemy_hit" && $0.sourceID == "E_R02_04" }))

        let lightTransfer = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R05_03", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "lightTransfer", firstTelegraphMs: 1_500),
            Combatant(id: "LIGHT_RECIPIENT", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "standard", firstTelegraphMs: 1_500)
        ], seed: 813, maxDurationMs: 8_000)
        let transfer = try XCTUnwrap(lightTransfer.events.first(where: { $0.kind == "enemy_light_transfer" }))
        XCTAssertEqual(transfer.sourceID, "E_R05_03")
        XCTAssertEqual(transfer.targetID, "LIGHT_RECIPIENT")
        let transfers = lightTransfer.events.filter { $0.kind == "enemy_light_transfer" }
        XCTAssertLessThanOrEqual(transfers.count, 2, "one transfer action may enqueue only one next tell")
        let transferTimes = transfers.compactMap(\.timestampMs)
        if transferTimes.count > 1 { XCTAssertGreaterThanOrEqual(transferTimes[1] - transferTimes[0], 3_500) }
        XCTAssertFalse(lightTransfer.events.contains(where: { $0.kind == "dot_applied" && $0.sourceID == "E_R05_03" }),
                       "energy transfer must not be mistaken for a party damage-over-time effect")
        let soloLightTransfer = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R05_03", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "lightTransfer", firstTelegraphMs: 1_500)
        ], seed: 813, maxDurationMs: 8_000)
        XCTAssertFalse(soloLightTransfer.events.contains(where: { $0.kind == "enemy_light_transfer" }),
                       "no adjacent target means no transfer event")
        XCTAssertTrue(soloLightTransfer.events.contains(where: { $0.kind == "enemy_hit" && $0.sourceID == "E_R05_03" }),
                      "solo fallback remains a normal attack")
    }

    func testR04FrostGearlingAlternatesLightAndHeavyAttacks() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R04_04", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "alternating", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 12_000)
        let heavy = result.events.filter { $0.kind == "telegraph_heavy" && $0.sourceID == "E_R04_04" }
        let normal = result.events.filter { $0.kind == "enemy_telegraph" && $0.sourceID == "E_R04_04" }
        XCTAssertGreaterThanOrEqual(heavy.count, 2)
        XCTAssertGreaterThanOrEqual(normal.count, 2)
        XCTAssertLessThan(try XCTUnwrap(normal.first?.timestampMs), try XCTUnwrap(heavy.first?.timestampMs),
                          "the first authored alternating action is the lighter strike")
        XCTAssertTrue(result.events.contains(where: { $0.kind == "enemy_hit" && $0.sourceID == "E_R04_04" }))
    }

    func testRootBoarAndAncientTreeHaveDistinctAuthoredCandidateCycles() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let boar = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R01_A", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "rootChargeCycle", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 15_000)
        let scrape = try XCTUnwrap(boar.events.first(where: { $0.kind == "enemy_scrape" }))
        let charge = try XCTUnwrap(boar.events.first(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "B_R01_A" }))
        let fatigue = try XCTUnwrap(boar.events.first(where: { $0.kind == "enemy_exhausted" }))
        XCTAssertLessThan(scrape.timestampMs!, charge.timestampMs!)
        XCTAssertLessThan(charge.timestampMs!, fatigue.timestampMs!)
        XCTAssertEqual(scrape.rootActionID, charge.rootActionID)
        XCTAssertEqual(charge.rootActionID, fatigue.rootActionID)
        XCTAssertTrue(boar.events.contains(where: { $0.kind == "enemy_hit" && $0.sourceID == "B_R01_A" && $0.rootActionID == charge.rootActionID }))

        let tree = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R01_B", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "rootBranchCycle", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 16_000)
        let roots = Dictionary(grouping: tree.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "B_R01_B" }, by: \.rootActionID)
        let firstRoot = try XCTUnwrap(roots["enemy:B_R01_B:1"])
        let secondRoot = try XCTUnwrap(roots["enemy:B_R01_B:2"])
        XCTAssertEqual(firstRoot.count, 3, "thin-root combo has three hits in one root action")
        XCTAssertTrue(tree.events.contains(where: { $0.kind == "telegraph_aoe" && $0.rootActionID == "enemy:B_R01_B:2" }),
                      "wide branch is the distinct charged area action")
        XCTAssertGreaterThanOrEqual(secondRoot.count, 1)
    }

    func testR04AllyFollowupAndShellHeavyCandidateEvents() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 500, defense: 0)
        }
        let followup = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R04_01", maxHP: 100_000, attack: 80, defense: 0,
                      actionPattern: "allyFollowup", firstTelegraphMs: 0)
        ], seed: 812, maxDurationMs: 8_000)
        let soloRoot = try XCTUnwrap(followup.events.first(where: { $0.kind == "enemy_hit" && $0.sourceID == "E_R04_01" }))
        XCTAssertEqual(followup.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R04_01" && $0.rootActionID == soloRoot.rootActionID }.count, 1,
                       "without an ally action to follow, the wolf performs its ordinary single hit")
        XCTAssertFalse(followup.events.contains(where: { $0.kind == "enemy_followup" && $0.sourceID == "E_R04_01" }),
                       "a solo enemy cannot invent a self-follow-up")

        let shell = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R04_03", maxHP: 100_000, attack: 80, defense: 0,
                      actionPattern: "shellHeavy", firstTelegraphMs: 0)
        ], seed: 812, maxDurationMs: 10_000)
        let close = try XCTUnwrap(shell.events.first(where: { $0.kind == "enemy_shell_close" }))
        let heavy = try XCTUnwrap(shell.events.first(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "E_R04_03" }))
        XCTAssertLessThan(close.timestampMs!, heavy.timestampMs!)
        XCTAssertEqual(close.rootActionID, heavy.rootActionID)
        XCTAssertTrue(shell.events.contains(where: { event in
            event.kind == "enemy_armor" && event.sourceID == "E_R04_03" && party.contains(where: { $0.id == event.targetID })
        }),
                      "closed shell reduces incoming party damage only and identifies the protected enemy")
        XCTAssertFalse(shell.events.contains(where: { $0.kind == "enemy_armor" && $0.rootActionID?.hasPrefix("enemy:E_R04_03:") == true }),
                       "the shell cue must not be attached to the enemy's outgoing heavy attack")
    }

    func testR04CliffChargeHasWindupImpactAndLongOpeningCandidateCycle() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R04_A", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "cliffCharge", firstTelegraphMs: 0)
        ], seed: 813, maxDurationMs: 15_000)
        let gather = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_wind_gather" }))
        let charge = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "B_R04_A" }))
        let opening = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_cliff_opening" }))
        XCTAssertLessThan(gather.timestampMs!, charge.timestampMs!)
        XCTAssertLessThan(charge.timestampMs!, opening.timestampMs!)
        XCTAssertEqual(gather.rootActionID, charge.rootActionID)
        XCTAssertEqual(charge.rootActionID, opening.rootActionID)
        XCTAssertEqual(opening.amount, 3_500)
        XCTAssertTrue(result.events.contains(where: { $0.kind == "direct" && $0.timestampMs! > opening.timestampMs! && $0.timestampMs! < opening.timestampMs! + 3_500 }),
                      "the vulnerable interval is an actual damage window")
    }

    func testE04FollowupReactsOnceToAnotherEnemyHitSameTargetWithoutChaining() throws {
        let result = try EnemyActionPreviewFixture.allyFollowup()
        XCTAssertEqual(result.entityPresentation["E_R04_01"]?.assetKey, "ACT_E_R04_01")
        XCTAssertEqual(result.entityPresentation["E_R04_04"]?.assetKey, "ACT_E_R04_04")
        let triggers = result.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R04_04" && $0.rootActionID == "enemy:E_R04_04:1" }
        let followHits = result.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R04_01" }
        XCTAssertEqual(triggers.count, 3, "multi-hit impacts share one triggering root")
        XCTAssertEqual(followHits.count, 1, "follower reacts once, not once per hit in a multi-hit root")
        for hit in followHits {
            let parts = hit.rootActionID!.components(separatedBy: ":followup:")
            XCTAssertEqual(parts.count, 2)
            let trigger = try XCTUnwrap(triggers.first(where: { $0.rootActionID == parts.last }))
            let cue = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_followup" && $0.rootActionID == hit.rootActionID }))
            XCTAssertEqual(cue.targetID, trigger.targetID)
            XCTAssertEqual(hit.targetID, trigger.targetID)
            XCTAssertEqual(hit.timestampMs, trigger.timestampMs! + 350)
        }
        XCTAssertFalse(followHits.contains(where: { $0.rootActionID!.contains(":followup:enemy:E_R04_01:followup:") }),
                       "follow-up actions cannot recursively trigger another follow-up")
    }

    func testR4FrontRowCandidateTargetsAssignedFrontThenFallsBackWhenCleared() throws {
        let frontIDs: Set<String> = ["C_SMITH", "C_FAMILIAR"]
        let party = [
            Combatant(id: "C_WITCH", maxHP: 100_000, attack: 0, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 100_000, attack: 0, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 1, attack: 0, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 1, attack: 0, defense: 0)
        ]
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "E_R01_01", maxHP: 1_000_000, attack: 10_000, defense: 0,
                      actionPattern: "heavy", firstTelegraphMs: 0)
        ], seed: 9_921, maxDurationMs: 14_000)
        let hits = result.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R01_01" }
        XCTAssertGreaterThanOrEqual(hits.count, 3)
        XCTAssertTrue(frontIDs.contains(hits[0].targetID), "first charge must target an eligible candidate front-row actor")
        XCTAssertTrue(frontIDs.contains(hits[1].targetID), "remaining living front-row actor is targeted before fallback")
        XCTAssertFalse(frontIDs.contains(hits[2].targetID), "once the candidate front row is down, the attack falls back to living rear actors")
        XCTAssertTrue(result.events.contains(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "E_R01_01" }))

        let healthyParty = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 0, defense: 0)
        }
        let boar = try R6TimelineSimulator.run(party: healthyParty, enemies: [
            Combatant(id: "B_R01_A", maxHP: 1_000_000, attack: 100, defense: 0,
                      actionPattern: "rootChargeCycle", firstTelegraphMs: 0)
        ], seed: 9_921, maxDurationMs: 6_000)
        let chargeHits = boar.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "B_R01_A" && $0.rootActionID == "enemy:B_R01_A:1" }
        XCTAssertEqual(chargeHits.count, 1)
        XCTAssertTrue(frontIDs.contains(try XCTUnwrap(chargeHits.first).targetID), "the boar's charge phase uses the R4 front-row candidate")

        let profileHeavy = try R6TimelineSimulator.run(party: healthyParty, enemies: [
            Combatant(id: "PROFILE_ENEMY", maxHP: 1_000_000, attack: 100, defense: 0,
                      actionPattern: "heavy", firstTelegraphMs: 0)
        ], seed: 9_921, maxDurationMs: 6_000, sourceProfileSeed: "front-row-isolation")
        let profileCandidateTag = try R6TimelineSimulator.run(party: healthyParty, enemies: [
            Combatant(id: "E_R01_01", maxHP: 1_000_000, attack: 100, defense: 0,
                      actionPattern: "heavy", firstTelegraphMs: 0)
        ], seed: 9_921, maxDurationMs: 6_000, sourceProfileSeed: "front-row-isolation")
        let profileTargets = profileHeavy.events.filter { $0.kind == "enemy_hit" }.map { ($0.timestampMs, $0.targetID, $0.amount) }
        let taggedTargets = profileCandidateTag.events.filter { $0.kind == "enemy_hit" }.map { ($0.timestampMs, $0.targetID, $0.amount) }
        XCTAssertEqual(profileTargets.count, taggedTargets.count)
        XCTAssertEqual(profileTargets.map(\.0), taggedTargets.map(\.0))
        XCTAssertEqual(profileTargets.map(\.1), taggedTargets.map(\.1), "the source-profile path retains its existing target weights")
        XCTAssertEqual(profileTargets.map(\.2), taggedTargets.map(\.2))
    }

    func testR4PincerShellMitigatesFrontOnlyAndKeepsOpenWindowDamageUnchanged() throws {
        let front = try EnemyActionPreviewFixture.pincerOrientation(side: .front)
        let flank = try EnemyActionPreviewFixture.pincerOrientation(side: .flank)
        let frontHits = front.events.filter { $0.kind == "direct" && $0.targetID == "E_R03_01" }
        let flankHits = flank.events.filter { $0.kind == "direct" && $0.targetID == "E_R03_01" }
        XCTAssertFalse(frontHits.isEmpty)
        XCTAssertEqual(frontHits.map(\.rootActionID), flankHits.map(\.rootActionID), "orientation changes damage only, not the action schedule")

        let byRootFlank = Dictionary(uniqueKeysWithValues: flankHits.compactMap { event in
            event.rootActionID.map { ($0, event) }
        })
        let protected = frontHits.filter { ($0.timestampMs ?? Int.max) < 6_000 }
        XCTAssertFalse(protected.isEmpty)
        for hit in protected {
            let openHit = try XCTUnwrap(byRootFlank[try XCTUnwrap(hit.rootActionID)])
            XCTAssertEqual(hit.amount, openHit.amount / 2)
            let armor = try XCTUnwrap(front.events.first(where: {
                $0.kind == "enemy_armor" && $0.rootActionID == hit.rootActionID
            }))
            XCTAssertEqual(armor.sourceID, "E_R03_01")
            XCTAssertEqual(armor.targetID, hit.sourceID)
            XCTAssertGreaterThan(armor.amount, 0)
        }
        XCTAssertFalse(flank.events.contains(where: { $0.kind == "enemy_armor" }),
                       "flank hits bypass the front-facing shell")

        let afterOpen = frontHits.filter { ($0.timestampMs ?? 0) >= 6_000 && ($0.timestampMs ?? 0) < 10_000 }
        XCTAssertFalse(afterOpen.isEmpty)
        for hit in afterOpen {
            XCTAssertEqual(hit.amount, try XCTUnwrap(byRootFlank[try XCTUnwrap(hit.rootActionID)]).amount,
                           "the 4-second soft interval accepts frontal damage normally")
        }
    }

    func testR02DreamMushroomBossUsesSporeDrowseAndRestCycle() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R02_A", maxHP: 100_000, attack: 50, defense: 0,
                      actionPattern: "sporeRest", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 14_000)
        let firstTell = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_aoe" && $0.sourceID == "B_R02_A" }))
        let drowse = try XCTUnwrap(result.events.first(where: { $0.kind == "party_drowse" && $0.sourceID == "B_R02_A" }))
        let rest = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_rest" && $0.sourceID == "B_R02_A" }))
        XCTAssertEqual(firstTell.rootActionID, drowse.rootActionID)
        XCTAssertEqual(drowse.rootActionID, rest.rootActionID)
        XCTAssertEqual(Set(result.events.filter { $0.kind == "party_drowse" && $0.rootActionID == firstTell.rootActionID }.map(\.targetID)).count, 4)
        let restAt = try XCTUnwrap(rest.timestampMs)
        let laterTells = result.events.filter { $0.kind == "telegraph_aoe" && $0.sourceID == "B_R02_A" && ($0.timestampMs ?? 0) > restAt }
        let nextTell = try XCTUnwrap(laterTells.first)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(nextTell.timestampMs) - restAt, 3_500,
                                    "the authored short recovery follows the spore and drowse impact")
    }

    func testR02MirrorLizardHasReflectWaterBoltAndScaleOpeningCycle() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R02_B", maxHP: 100_000, attack: 50, defense: 0,
                      actionPattern: "mirrorCycle", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 15_000)
        let stance = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_reflect_stance" && $0.sourceID == "B_R02_B" }))
        let waterBolt = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_aoe" && $0.sourceID == "B_R02_B" }))
        let opening = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_scale_opening" && $0.sourceID == "B_R02_B" }))
        let projectile = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_reflect_projectile" && $0.sourceID == "B_R02_B" }))
        XCTAssertLessThan(stance.timestampMs!, waterBolt.timestampMs!)
        XCTAssertEqual(waterBolt.rootActionID, opening.rootActionID)
        XCTAssertEqual(stance.targetID, "B_R02_B")
        XCTAssertEqual(stance.amount, 2_500)
        XCTAssertEqual(opening.amount, 3_500)
        XCTAssertGreaterThan(projectile.amount, 0)
        XCTAssertEqual(projectile.targetID, projectile.rootActionID.flatMap { root in
            result.events.first(where: { $0.kind == "direct" && $0.rootActionID == root })?.sourceID
        }, "reflection is actual delayed damage to the attacker of the triggering direct hit")
    }

    func testR4CandidateReflectProjectileIsAbsorbedByActiveBarrierBeforeHPDamage() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 10_000, attack: 1_000, defense: 0)
        }
        let enemy = Combatant(id: "E_R02_03", maxHP: 100_000, attack: 100, defense: 0,
                              actionPattern: "reflect", firstTelegraphMs: 1_500)
        func run(_ barriers: [String: (amount: Int, expiryMs: Int)]) throws -> CombatResult {
            try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 811, maxDurationMs: 8_000,
                                        initialBarriers: barriers)
        }
        let baseline = try run([:])
        let reflect = try XCTUnwrap(baseline.events.first(where: { $0.kind == "enemy_reflect_projectile" }))
        XCTAssertGreaterThan(reflect.amount, 0)

        let fullBarriers = Dictionary(uniqueKeysWithValues: party.map { ($0.id, (amount: 100_000, expiryMs: 8_000)) })
        let fullyAbsorbed = try run(fullBarriers)
        let absorbedFull = try XCTUnwrap(fullyAbsorbed.events.first(where: {
            $0.kind == "barrier_absorb" && $0.rootActionID == reflect.rootActionID
        }), "candidate reflect projectile must be absorbed by an active party barrier")
        XCTAssertEqual(absorbedFull.amount, reflect.amount)
        let fullProjectile = try XCTUnwrap(fullyAbsorbed.events.first(where: {
            $0.kind == "enemy_reflect_projectile" && $0.rootActionID == reflect.rootActionID
        }))
        XCTAssertEqual(fullProjectile.amount, 0, "only residual projectile damage may change HP")

        let partialBarriers = Dictionary(uniqueKeysWithValues: party.map { ($0.id, (amount: 100, expiryMs: 8_000)) })
        let partiallyAbsorbed = try run(partialBarriers)
        let absorbedPartial = try XCTUnwrap(partiallyAbsorbed.events.first(where: {
            $0.kind == "barrier_absorb" && $0.rootActionID == reflect.rootActionID
        }))
        let partialProjectile = try XCTUnwrap(partiallyAbsorbed.events.first(where: {
            $0.kind == "enemy_reflect_projectile" && $0.rootActionID == reflect.rootActionID
        }))
        XCTAssertEqual(absorbedPartial.amount, min(100, reflect.amount))
        XCTAssertEqual(partialProjectile.amount, max(0, reflect.amount - absorbedPartial.amount))

        let expiredBarriers = Dictionary(uniqueKeysWithValues: party.map { ($0.id, (amount: 100_000, expiryMs: 1)) })
        let expired = try run(expiredBarriers)
        XCTAssertFalse(expired.events.contains(where: {
            $0.kind == "barrier_absorb" && $0.rootActionID == reflect.rootActionID
        }), "expired barriers must not absorb a delayed projectile")
        XCTAssertEqual(expired.events.first(where: {
            $0.kind == "enemy_reflect_projectile" && $0.rootActionID == reflect.rootActionID
        })?.amount, reflect.amount)

        for result in [baseline, fullyAbsorbed, partiallyAbsorbed, expired] {
            let initial = Dictionary(uniqueKeysWithValues: party.map { ($0.id, $0.maxHP) })
            XCTAssertEqual(R6CombatPresentationSemantics.replay(events: result.events, initialHP: initial),
                           result.remainingPartyHP,
                           "barrier absorption is not an HP delta and residual reflect damage must replay exactly")
        }

        func reflectMetrics(_ result: CombatResult) -> (count: Int, absorbed: Int, hpDamage: Int) {
            let projectiles = result.events.filter { $0.kind == "enemy_reflect_projectile" }
            let roots = Set(projectiles.compactMap(\.rootActionID))
            let absorbed = result.events.filter { $0.kind == "barrier_absorb" && $0.sourceID == enemy.id && roots.contains($0.rootActionID ?? "") }
                .reduce(0) { $0 + $1.amount }
            return (projectiles.count, absorbed, projectiles.reduce(0) { $0 + $1.amount })
        }
        let baselineMetrics = reflectMetrics(baseline)
        let fullMetrics = reflectMetrics(fullyAbsorbed)
        let partialMetrics = reflectMetrics(partiallyAbsorbed)
        let expiredMetrics = reflectMetrics(expired)
        print("R4_REFLECT_BARRIER_METRICS,baseline=\(baselineMetrics.count)/absorb:\(baselineMetrics.absorbed)/hp:\(baselineMetrics.hpDamage),full=\(fullMetrics.count)/absorb:\(fullMetrics.absorbed)/hp:\(fullMetrics.hpDamage),partial=\(partialMetrics.count)/absorb:\(partialMetrics.absorbed)/hp:\(partialMetrics.hpDamage),expired=\(expiredMetrics.count)/absorb:\(expiredMetrics.absorbed)/hp:\(expiredMetrics.hpDamage)")
        XCTAssertEqual(baselineMetrics.absorbed, 0)
        XCTAssertGreaterThan(fullMetrics.absorbed, 0)
        XCTAssertEqual(fullMetrics.hpDamage, 0)
        XCTAssertGreaterThan(partialMetrics.absorbed, 0)
        XCTAssertGreaterThan(partialMetrics.hpDamage, 0)
        XCTAssertEqual(expiredMetrics.absorbed, 0)
        XCTAssertEqual(expiredMetrics.hpDamage, baselineMetrics.hpDamage)

        let sourceProfile = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 811,
                                                        maxDurationMs: 8_000, sourceProfileSeed: "fixture-r6-reflect",
                                                        initialBarriers: fullBarriers)
        XCTAssertFalse(sourceProfile.events.contains(where: { $0.kind == "enemy_reflect_projectile" }),
                       "the candidate projectile contract must not modify the immutable source-profile path")
    }

    func testR03HammerBossCombinesThreeQuickHitsThenChargedFinisherAndRest() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R03_A", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "hammerCombo", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 15_000)
        let lightTell = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_telegraph" && $0.sourceID == "B_R03_A" }))
        let firstHits = result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == lightTell.rootActionID }
        XCTAssertEqual(firstHits.count, 3)
        let heavyTell = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "B_R03_A" }))
        XCTAssertGreaterThan(try XCTUnwrap(heavyTell.timestampMs), try XCTUnwrap(lightTell.timestampMs))
        let finisher = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_hit" && $0.rootActionID == heavyTell.rootActionID }))
        let rest = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_rest" && $0.rootActionID == heavyTell.rootActionID }))
        XCTAssertEqual(finisher.timestampMs, rest.timestampMs)
        XCTAssertEqual(rest.amount, 3_500)
        XCTAssertGreaterThan(finisher.amount, firstHits[0].amount, "the charged hammer finisher must hit harder than a quick combo hit")
    }

    func testR03ForgeGuardianUsesVentStoreAndHeavyAreaRelease() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R03_B", maxHP: 100_000, attack: 50, defense: 0,
                      actionPattern: "heatCycle", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 15_000)
        let vent = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_vent" && $0.sourceID == "B_R03_B" }))
        let store = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_heat_store" && $0.sourceID == "B_R03_B" }))
        let heavyTell = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "B_R03_B" }))
        let release = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_heat_release" && $0.sourceID == "B_R03_B" }))
        let areaHits = result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == heavyTell.rootActionID }
        XCTAssertLessThan(try XCTUnwrap(vent.timestampMs), try XCTUnwrap(store.timestampMs))
        XCTAssertLessThan(try XCTUnwrap(store.timestampMs), try XCTUnwrap(heavyTell.timestampMs))
        XCTAssertEqual(heavyTell.targetID, "party")
        XCTAssertEqual(release.rootActionID, heavyTell.rootActionID)
        XCTAssertEqual(Set(areaHits.map(\.targetID)).count, 4)
        XCTAssertTrue(areaHits.allSatisfy { $0.amount == 75 }, "candidate stored-heat AoE is 150% of a normal single-target hit after area scaling")
    }

    func testR04MountainDragonUsesColdInhaleAndIceBreath() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R04_B", maxHP: 100_000, attack: 50, defense: 0,
                      actionPattern: "iceBreathCycle", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 18_000)
        let cold = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_cold_wave" && $0.sourceID == "B_R04_B" }))
        let inhale = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_breath_inhale" && $0.sourceID == "B_R04_B" }))
        let breath = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "B_R04_B" }))
        let release = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_breath_release" && $0.sourceID == "B_R04_B" }))
        XCTAssertLessThan(try XCTUnwrap(cold.timestampMs), try XCTUnwrap(inhale.timestampMs))
        XCTAssertLessThan(try XCTUnwrap(inhale.timestampMs), try XCTUnwrap(breath.timestampMs))
        XCTAssertEqual(breath.targetID, "party")
        XCTAssertEqual(breath.rootActionID, release.rootActionID)
        XCTAssertEqual(Set(result.events.filter { $0.kind == "party_frost_slow" && $0.rootActionID == cold.rootActionID }.map(\.targetID)).count, 4)
        XCTAssertEqual(result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == breath.rootActionID }.count, 4)
        let breathHitAmounts = result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == breath.rootActionID }.map(\.amount)
        XCTAssertTrue(breathHitAmounts.allSatisfy { (50...62).contains($0) }, "candidate breath loss is AoE-scaled and may be further reduced by the party's automatic guard: \(breathHitAmounts)")
    }

    func testR05PruningBossUsesComboOpeningAndAreaSweep() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R05_A", maxHP: 100_000, attack: 50, defense: 0,
                      actionPattern: "pruningCycle", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 18_000)
        let combo = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_telegraph" && $0.sourceID == "B_R05_A" }))
        XCTAssertEqual(result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == combo.rootActionID }.count, 3)
        let opening = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_ring_opening" && $0.sourceID == "B_R05_A" }))
        let area = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_aoe" && $0.sourceID == "B_R05_A" }))
        let sweep = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_ring_sweep" && $0.sourceID == "B_R05_A" }))
        XCTAssertLessThan(try XCTUnwrap(combo.timestampMs), try XCTUnwrap(opening.timestampMs))
        XCTAssertLessThan(try XCTUnwrap(opening.timestampMs), try XCTUnwrap(area.timestampMs))
        XCTAssertEqual(area.rootActionID, sweep.rootActionID)
        XCTAssertEqual(sweep.targetID, "party")
        let sweepHitAmounts = result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == area.rootActionID }.map(\.amount)
        XCTAssertTrue(sweepHitAmounts.allSatisfy { (50...75).contains($0) }, "candidate sweep loss may be reduced by the party's automatic guard: \(sweepHitAmounts)")
    }

    func testR05MoonDeerUsesSeedPressureGuardAndQuietUltimate() throws {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
        }
        let result = try R6TimelineSimulator.run(party: party, enemies: [
            Combatant(id: "B_R05_B", maxHP: 100_000, attack: 50, defense: 0,
                      actionPattern: "seedGuardUltimate", firstTelegraphMs: 0)
        ], seed: 811, maxDurationMs: 18_000)
        let pressure = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_seed_pressure" && $0.sourceID == "B_R05_B" }))
        let applied = result.events.filter { $0.kind == "dot_applied" && $0.rootActionID == pressure.rootActionID }
        XCTAssertEqual(Set(applied.map(\.targetID)).count, 4)
        XCTAssertTrue(result.events.contains(where: { $0.kind == "dot_tick" && $0.rootActionID == pressure.rootActionID }))
        let guardStance = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_guard_stance" && $0.sourceID == "B_R05_B" }))
        let ultimate = try XCTUnwrap(result.events.first(where: { $0.kind == "telegraph_heavy" && $0.sourceID == "B_R05_B" }))
        let release = try XCTUnwrap(result.events.first(where: { $0.kind == "enemy_ultimate_release" && $0.sourceID == "B_R05_B" }))
        XCTAssertLessThan(try XCTUnwrap(pressure.timestampMs), try XCTUnwrap(guardStance.timestampMs))
        XCTAssertLessThan(try XCTUnwrap(guardStance.timestampMs), try XCTUnwrap(ultimate.timestampMs))
        XCTAssertEqual(ultimate.rootActionID, release.rootActionID)
        XCTAssertEqual(ultimate.targetID, "party")
        let ultimateHitAmounts = result.events.filter { $0.kind == "enemy_hit" && $0.rootActionID == ultimate.rootActionID }.map(\.amount)
        XCTAssertTrue(ultimateHitAmounts.allSatisfy { $0 == 75 }, "candidate ultimate HP loss values: \(ultimateHitAmounts)")
    }

    func testLightTransferPreviewFixtureIsReadOnlyAndHasRenderableRecipient() throws {
        let preview = try EnemyActionPreviewFixture.lightTransfer()
        XCTAssertEqual(preview.entityPresentation["E_R05_03"]?.assetKey, "ACT_E_R05_03")
        XCTAssertEqual(preview.entityPresentation["E_R05_02"]?.assetKey, "ACT_E_R05_02")
        XCTAssertTrue(preview.events.contains(where: {
            $0.kind == "enemy_light_transfer" && $0.sourceID == "E_R05_03" && $0.targetID == "E_R05_02"
        }))
    }

    func testR05ActionPreviewFixturesExposeDistinctRendererEventsWithoutEngineCommands() throws {
        let guardResult = try EnemyActionPreviewFixture.guardPosture()
        XCTAssertTrue(guardResult.events.contains(where: { $0.kind == "enemy_guard_stance" && $0.sourceID == "E_R05_02" }))
        XCTAssertTrue(guardResult.events.contains(where: { $0.kind == "enemy_guard_absorb" && $0.amount > 0 }))

        let disruptResult = try EnemyActionPreviewFixture.supportDurationReduction()
        XCTAssertTrue(disruptResult.events.contains(where: { $0.kind == "support_duration_reduced" && $0.sourceID == "E_R05_01" }))

        let regenResult = try EnemyActionPreviewFixture.poisonRegeneration()
        let dot = try XCTUnwrap(regenResult.events.first(where: { $0.kind == "dot_applied" && $0.sourceID == "E_R05_04" }))
        let regen = try XCTUnwrap(regenResult.events.first(where: { $0.kind == "enemy_regen" && $0.sourceID == "E_R05_04" }))
        XCTAssertEqual(dot.rootActionID, regen.rootActionID)
        XCTAssertEqual(dot.timestampMs, regen.timestampMs)
        XCTAssertGreaterThan(regen.amount, 0)
        XCTAssertEqual(regen.sourceID, regen.targetID)
    }

    func testBossActionPreviewFixturesCarryStableActorAndPresentationMetadata() throws {
        let results: [(String, String, CombatResult)] = [
            ("B_R02_A", "ACT_B_R02_A", try EnemyActionPreviewFixture.dreamMushroomBoss()),
            ("B_R02_B", "ACT_B_R02_B", try EnemyActionPreviewFixture.mirrorLizardBoss()),
            ("B_R03_A", "ACT_B_R03_A", try EnemyActionPreviewFixture.hammerTrooperBoss()),
            ("B_R03_B", "ACT_B_R03_B", try EnemyActionPreviewFixture.forgeGuardianBoss()),
            ("B_R04_B", "ACT_B_R04_B", try EnemyActionPreviewFixture.mountainDragonBoss()),
            ("B_R05_A", "ACT_B_R05_A", try EnemyActionPreviewFixture.pruningMachineBoss()),
            ("B_R05_B", "ACT_B_R05_B", try EnemyActionPreviewFixture.moonDeerBoss())
        ]
        for (id, assetKey, result) in results {
            XCTAssertEqual(result.entityPresentation[id]?.catalogID, id)
            XCTAssertEqual(result.entityPresentation[id]?.assetKey, assetKey)
            XCTAssertTrue(result.events.contains(where: { $0.sourceID == id }), "fixture must produce the referenced boss events: \(id)")
        }
    }

    func testSharedStatProjectionSupportsInventoryComparison() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let empty = catalog.projectCombatant(for: "C_WITCH", with: [])
        let candidate = GearInstance(definitionID: "EQ_W_01", ownerID: "C_WITCH", enhancement: 10, refinement: 3, qualityID: "Q4", affixIDs: ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"])
        let equipped = catalog.projectCombatant(for: "C_WITCH", with: [candidate])
        XCTAssertGreaterThan(equipped.attack, empty.attack)
        XCTAssertGreaterThan(equipped.maxHP, empty.maxHP)
        XCTAssertGreaterThan(equipped.defense, empty.defense)
        XCTAssertTrue(equipped.effectIDs.contains("AFFIX_POWER_TEST"))
        let smith = catalog.projectCombatant(for: "C_SMITH", with: [GearInstance(definitionID: "EQ_S_01", ownerID: "C_SMITH")])
        XCTAssertEqual(smith.guardChanceBP, 1_500, "starter smith gear adds its candidate 500bp to the candidate 1000bp base")
    }

    func testGatherMaterialGatesMatchSourceAndRejectLockedTargets() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let initial = GameSnapshot.newGame(catalog: catalog)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        let initialAvailable = await game.availableGatherMaterials(in: "R01")
        XCTAssertEqual(initialAvailable, ["M_R01_G1", "M_R01_G2"])
        do {
            _ = try await game.dispatch(.setGatherTargetAt(resourceID: "M_R01_G3", now: Date(timeIntervalSince1970: 10)), operationID: UUID(), expectedRevision: 0)
            XCTFail("locked resin target must be rejected before the R01-A gate")
        } catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") } }
        var advanced = initial; advanced.completedEncounterIDs.insert("B_R01_A")
        let advancedGame = try GameEngine(catalog: catalog, saves: SaveRepository(initial: advanced))
        let advancedAvailable = await advancedGame.availableGatherMaterials(in: "R01")
        XCTAssertEqual(advancedAvailable, ["M_R01_G1", "M_R01_G2", "M_R01_G3", "M_R01_G4"])
    }

    func testOfflineClaimCannotAwardBossGatedMaterialFromLegacyTarget() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let now = Date(timeIntervalSince1970: 1_810_000_000)
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.activeRegionID = "R01"
        initial.gatherTargetMaterialID = "M_R01_G3" // stale/legacy selection bypassing the target API
        initial.lastClaimAt = now.addingTimeInterval(-300)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))

        _ = try await game.claimOffline(now: now, operationID: UUID(), expectedRevision: 0)
        let after = await game.snapshot()
        XCTAssertEqual(after.materials["M_R01_G1"], 1, "offline fallback uses the first currently unlocked material")
        XCTAssertNil(after.materials["M_R01_G3"], "R01 G3 remains locked until the boss gate is cleared")
        XCTAssertEqual(after.characterXP["C_WITCH"], catalog.regions.first(where: { $0.id == "R01" })?.xpPerWork)
        XCTAssertEqual(after.materials["refine_dust"], catalog.regions.first(where: { $0.id == "R01" })?.dustPerWork)
    }

    func testOfflineClaimFromLockedActiveRegionInCorruptSaveIsRejectedAtomically() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let now = Date(timeIntervalSince1970: 1_810_000_300)
        var corrupt = GameSnapshot.newGame(catalog: catalog)
        corrupt.activeRegionID = "R02"
        corrupt.gatherTargetMaterialID = "M_R02_G1"
        corrupt.unlockedRegionIDs = ["R01"]
        corrupt.lastClaimAt = now.addingTimeInterval(-3_600)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: corrupt))

        do {
            _ = try await game.claimOffline(now: now, operationID: UUID(), expectedRevision: corrupt.revision)
            XCTFail("offline claim must not award from a locked active region in a malformed save")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let after = await game.snapshot()
        XCTAssertEqual(after, corrupt, "rejected gate violation must not advance revision or partially award XP/materials")
    }

    func testOfflineClaimRejectsRewardOverflowAtomically() async throws {
        let now = Date(timeIntervalSince1970: 1_810_000_300)
        let catalog = try GameCatalog.bundledTestOverlay()
        var corrupt = GameSnapshot.newGame(catalog: catalog)
        corrupt.activeRegionID = "R01"
        corrupt.gatherTargetMaterialID = "M_R01_G1"
        corrupt.materials["M_R01_G1"] = Int.max
        corrupt.lastClaimAt = now.addingTimeInterval(-300)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: corrupt))

        do {
            _ = try await game.claimOffline(now: now, operationID: UUID(), expectedRevision: corrupt.revision)
            XCTFail("overflowing material reward must be rejected")
        } catch let error as CoreError {
            guard case .invalidCommand(let message) = error else { return XCTFail("unexpected error: \(error)") }
            XCTAssertTrue(message.contains("overflow"))
        }
        let after = await game.snapshot()
        XCTAssertEqual(after, corrupt, "overflow must not persist partial material, XP, dust, or time changes")
    }

    func testOfflineClaimRejectsNonFiniteCommandTimestampAndLimits() async throws {
        let now = Date(timeIntervalSince1970: 1_810_000_300)
        let region = RegionDefinition(id: "R", name: "R", enemyIDs: [], gatherMaterialIDs: ["m"], workSeconds: 300)
        let catalog = GameCatalog(version: "finite-time", regions: [region], enemies: [], gear: [], research: [])
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.lastClaimAt = now.addingTimeInterval(-300)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        for (timestamp, cap) in [(Date(timeIntervalSince1970: .infinity), 1_000.0), (now, .infinity)] {
            do {
                _ = try await game.claimOffline(now: timestamp, cap: cap, operationID: UUID(), expectedRevision: 0)
                XCTFail("non-finite timestamp/cap must be rejected")
            } catch let error as CoreError {
                guard case .invalidCommand(let message) = error else { return XCTFail("unexpected error: \(error)") }
                XCTAssertTrue(message.contains("finite"))
            }
        }
        let after = await game.snapshot()
        XCTAssertEqual(after, initial)
    }

    func testOfflineClaimRejectsUnboundedUnitCountAndCorruptRemainder() async throws {
        let now = Date(timeIntervalSince1970: 1_810_000_300)
        let region = RegionDefinition(id: "R", name: "R", enemyIDs: [], gatherMaterialIDs: ["m"], workSeconds: 300)
        let catalog = GameCatalog(version: "bounded-units", regions: [region], enemies: [], gear: [], research: [])
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.lastClaimAt = now.addingTimeInterval(-300)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        do {
            _ = try await game.claimOffline(now: now, secondsPerUnit: Double.leastNonzeroMagnitude, operationID: UUID(), expectedRevision: 0)
            XCTFail("unit count that cannot fit Int must be rejected")
        } catch let error as CoreError {
            guard case .invalidCommand(let message) = error else { return XCTFail("unexpected error: \(error)") }
            XCTAssertTrue(message.contains("unit count"))
        }

        var badRemainder = initial
        badRemainder.offlineRemainderSeconds = .greatestFiniteMagnitude
        let badGame = try GameEngine(catalog: catalog, saves: SaveRepository(initial: badRemainder))
        do {
            _ = try await badGame.claimOffline(now: now, operationID: UUID(), expectedRevision: 0)
            XCTFail("corrupt saved remainder must be rejected")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterBadRemainder = await badGame.snapshot()
        XCTAssertEqual(afterBadRemainder, badRemainder)
    }

    func testGatheringSettlesOldTargetAtSwitchAndPaysAllWholeUnits() async throws {
        let now = Date(timeIntervalSince1970: 400_000)
        let region = RegionDefinition(id: "R1", name: "Test forest", enemyIDs: [], gatherMaterialIDs: ["leaf_a", "leaf_b"], xpPerWork: 3, dustPerWork: 2, workSeconds: 300)
        let catalog = GameCatalog(version: "test", regions: [region], enemies: [], gear: [], research: [], actorIDs: ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"])
        let state = GameSnapshot(unlockedRegionIDs: ["R1"], lastClaimAt: now, activeRegionID: "R1", gatherTargetMaterialID: "leaf_a")
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: state))
        _ = try await game.dispatch(.setGatherTargetAt(resourceID: "leaf_b", now: now.addingTimeInterval(900)), operationID: UUID(), expectedRevision: 0)
        let afterSwitch = await game.snapshot()
        XCTAssertEqual(afterSwitch.materials["leaf_a"], 3, "old target receives all completed units before switch")
        XCTAssertEqual(afterSwitch.characterXP["C_WITCH"], 9)
        XCTAssertEqual(afterSwitch.materials["refine_dust"], 6)
        XCTAssertEqual(afterSwitch.gatherTargetMaterialID, "leaf_b")
        _ = try await game.dispatch(.gather(resourceID: "leaf_b", now: now.addingTimeInterval(1_500)), operationID: UUID(), expectedRevision: 1)
        let afterGather = await game.snapshot()
        XCTAssertEqual(afterGather.materials["leaf_b"], 2, "direct gather pays every whole unit, not one per callback")
        XCTAssertEqual(afterGather.characterXP["C_WITCH"], 15)
        XCTAssertEqual(afterGather.materials["refine_dust"], 10)
    }

    func testExpeditionSelectionInitializesNilGatheringBaselineWithoutAward() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let region = RegionDefinition(id: "R", name: "R", enemyIDs: [], gatherMaterialIDs: ["m1", "m2"], workSeconds: 300)
        let catalog = GameCatalog(version: "baseline", regions: [region], enemies: [], gear: [], research: [], actorIDs: ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"])
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.activeRegionID = "R"; initial.gatherTargetMaterialID = "m1"; initial.unlockedRegionIDs = ["R"]
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        _ = try await game.dispatch(.startExpeditionAt(regionID: "R", now: now), operationID: UUID(), expectedRevision: 0)
        let baseline = await game.snapshot()
        XCTAssertEqual(baseline.lastClaimAt, now)
        XCTAssertTrue(baseline.materials.isEmpty, "initializing time must not award resources")
        _ = try await game.claimOffline(now: now.addingTimeInterval(600), operationID: UUID(), expectedRevision: baseline.revision)
        let accrued = await game.snapshot()
        XCTAssertEqual(accrued.materials["m1"], 2, "the first full interval after baseline must not be lost")
        _ = try await game.dispatch(.startExpeditionAt(regionID: "R", now: now.addingTimeInterval(900)), operationID: UUID(), expectedRevision: accrued.revision)
        let sameRegion = await game.snapshot()
        XCTAssertEqual(sameRegion.materials["m1"], 2, "same-region reselect must not settle or duplicate already paid time")
        XCTAssertEqual(sameRegion.lastClaimAt, now.addingTimeInterval(600), "same-region reselect preserves the active accrual baseline")
        _ = try await game.claimOffline(now: now.addingTimeInterval(1_200), operationID: UUID(), expectedRevision: sameRegion.revision)
        let afterSameRegionClaim = await game.snapshot()
        XCTAssertEqual(afterSameRegionClaim.materials["m1"], 4, "same-region reselect must not discard elapsed work")
    }

    func testOfflineClaimHasHardCapAndDoesNotGrantVictory() async throws {
        let now = Date(timeIntervalSince1970: 200_000)
        let region = RegionDefinition(id: "forest", name: "Forest", enemyIDs: [], gatherMaterialIDs: ["forest_herb"], xpPerWork: 2, dustPerWork: 1, workSeconds: 300)
        let store = try SaveRepository(initial: GameSnapshot(lastClaimAt: now.addingTimeInterval(-100 * 3600), activeRegionID: "forest", gatherTargetMaterialID: "forest_herb"))
        let catalog = GameCatalog(version: "test", regions: [region], enemies: [], gear: [], research: [])
        let game = try GameEngine(catalog: catalog, saves: store)
        let receipt = try await game.claimOffline(now: now, operationID: UUID(), expectedRevision: 0)
        XCTAssertTrue(receipt.result.contains("capSeconds=172800")); XCTAssertTrue(receipt.result.contains("no combat victory inferred"))
        let snapshot = await game.snapshot()
        XCTAssertEqual(snapshot.materials["forest_herb"], 576)
        XCTAssertEqual(snapshot.materials["refine_dust"], 576)
        XCTAssertEqual(snapshot.characterXP["C_WITCH"], 1_152)
    }

    func testAtomicSaveSurvivesRepositoryRecreation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-core-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let first = try SaveRepository(fileURL: url)
        _ = try await first.transact(expectedRevision: 0, operationID: UUID()) { $0.materials["moss"] = 7; return "saved" }
        let reopened = try SaveRepository(fileURL: url)
        let state = await reopened.snapshot()
        XCTAssertEqual(state.materials["moss"], 7)
        XCTAssertEqual(state.revision, 1)
    }

    func testExhaustedOrNegativeSaveRevisionFailsClosedWithoutRunningMutation() async throws {
        for revision in [Int64.max, -1] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-invalid-revision-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
            let source = "{\"snapshot\":{\"revision\":\(revision),\"materials\":{\"moss\":4}}}"
            try Data(source.utf8).write(to: url)
            let store = try SaveRepository(fileURL: url)
            let initial = await store.snapshot()
            do {
                _ = try await store.transact(expectedRevision: revision, operationID: UUID()) { state in
                    XCTFail("invalid revision must be rejected before command mutation")
                    state.materials["moss"] = 999
                    return "unexpected"
                }
                XCTFail("invalid revision \(revision) unexpectedly accepted")
            } catch let error as CoreError {
                guard case .invalidCommand(let message) = error else { return XCTFail("unexpected error: \(error)") }
                XCTAssertTrue(message.contains("revision"))
            }
            let after = await store.snapshot()
            XCTAssertEqual(after, initial, "failed revision guard must preserve state")
            let reopened = try SaveRepository(fileURL: url)
            let diskState = await reopened.snapshot()
            XCTAssertEqual(diskState, initial, "rejected write must preserve original disk JSON state")
        }
    }

    func testCorruptSaveIsRejectedWithoutResettingPlayerData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        try Data("{not a save}".utf8).write(to: url)
        XCTAssertThrowsError(try SaveRepository(fileURL: url))
    }

    func testLegacySaveFieldsDefaultWithoutDiscardingExistingValues() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let legacy = #"{"snapshot":{"revision":7,"materials":{"moss":4},"gear":[{"id":"10000000-0000-4000-8000-000000000001","definitionID":"EQ_W_01","enhancement":2}],"unlockedRegionIDs":["R01"],"gachaPity":{"drawsSinceTop":12,"drawsSinceMid":3,"targetTemplateID":"EQ_W_01"}}}"#
        try Data(legacy.utf8).write(to: url)
        let store = try SaveRepository(fileURL: url)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.revision, 7)
        XCTAssertEqual(snapshot.materials["moss"], 4)
        XCTAssertEqual(snapshot.gear.first?.qualityID, "Q0")
        XCTAssertEqual(snapshot.gear.first?.enhancement, 2)
        XCTAssertEqual(snapshot.localStoreKitQARecords, [:])
        XCTAssertEqual(snapshot.localStoreKitQAOwnedProductIDs, [])
        XCTAssertFalse(snapshot.localAdSkipEntitledForQA)
        XCTAssertEqual(snapshot.localAdWorkBlockSeconds, 0)
        XCTAssertEqual(snapshot.localAdRewardOpportunities, [:])
        XCTAssertEqual(snapshot.localAdAttemptRecords, [:])
        XCTAssertEqual(snapshot.gachaPity.drawsSinceTop, 12)
        XCTAssertEqual(snapshot.gachaPity.drawsSinceMid, 3)
        XCTAssertEqual(snapshot.gachaPity.targetTemplateID, "EQ_W_01")
        XCTAssertFalse(snapshot.gachaPity.guaranteeTargetOnNextTop, "older saves default the newly introduced target guarantee to false")
    }

    func testFailedMutationDoesNotPersistPartialChanges() async throws {
        let store = try SaveRepository()
        do {
            _ = try await store.transact(expectedRevision: 0, operationID: UUID()) { state in
                state.materials["herb"] = 99
                throw CoreError.insufficientResource("atomic rollback")
            }
            XCTFail("failed transaction unexpectedly committed")
        } catch let error as CoreError { XCTAssertEqual(error, .insufficientResource("atomic rollback")) }
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.revision, 0)
        XCTAssertNil(snapshot.materials["herb"])
    }

    func testClockMovingBackwardGrantsNoOfflineItems() async throws {
        let later = Date(timeIntervalSince1970: 10_000)
        let region = RegionDefinition(id: "forest", name: "Forest", enemyIDs: [], gatherMaterialIDs: ["forest_herb"], workSeconds: 300)
        let store = try SaveRepository(initial: GameSnapshot(lastClaimAt: later, activeRegionID: "forest", gatherTargetMaterialID: "forest_herb"))
        let game = try GameEngine(catalog: .init(version: "t", regions: [region], enemies: [], gear: [], research: []), saves: store)
        _ = try await game.claimOffline(now: later.addingTimeInterval(-60), operationID: UUID(), expectedRevision: 0)
        let state = await game.snapshot()
        XCTAssertNil(state.materials["forest_herb"])
        XCTAssertEqual(state.lastClaimAt, later)
    }

    func testMockSummonIsSeededAndPaidLedgerRemainsMockOnly() async throws {
        let catalog = GameCatalog(version: "overlay", regions: [], enemies: [], gear: [
            GearDefinition(id: "g1", name: "One", rarity: "C", slot: "weapon", effects: []),
            GearDefinition(id: "g2", name: "Two", rarity: "C", slot: "weapon", effects: [])
        ], research: [])
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot(currency: ["ticket_paid_mock": 2], gachaUnlocked: true)))
        let command = GameCommand.mockSummon(poolDefinitionIDs: ["g2", "g1"], count: 1, costCurrencyID: "ticket_paid_mock", seed: 55)
        let receipt = try await game.dispatch(command, operationID: UUID(), expectedRevision: 0)
        let state = await game.snapshot()
        XCTAssertTrue(receipt.result.contains("MOCK_ONLY")); XCTAssertEqual(state.gear.count, 1)
        XCTAssertEqual(state.currency["ticket_paid_mock"], 1)
        XCTAssertFalse(state.pendingPurchaseIDs.count > 0)
    }

    func testFreeSummonRetryReturnsReceiptWithoutDuplicatingLootOrSpendingTicketsTwice() async throws {
        let catalog = GameCatalog(version: "retry", regions: [], enemies: [], gear: [
            GearDefinition(id: "g1", name: "One", rarity: "C", slot: "weapon", effects: []),
            GearDefinition(id: "g2", name: "Two", rarity: "C", slot: "weapon", effects: [])
        ], research: [])
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot(currency: ["ticket_free": 5], gachaUnlocked: true)))
        let op = UUID()
        let command = GameCommand.mockSummon(poolDefinitionIDs: ["g1", "g2"], count: 5, costCurrencyID: "ticket_free", seed: 777)
        let first = try await game.dispatch(command, operationID: op, expectedRevision: 0)
        let retry = try await game.dispatch(command, operationID: op, expectedRevision: 0)
        let after = await game.snapshot()
        XCTAssertEqual(retry, first)
        XCTAssertEqual(after.revision, 1)
        XCTAssertEqual(after.gear.count, 5)
        XCTAssertEqual(after.currency["ticket_free"], 0)
    }

    func testMockPurchaseLedgerHandlesPendingInterruptedCancelledRestoredRefundedRevokedAndDuplicates() async throws {
        let engine = try GameEngine(catalog: GameCatalog(version: "t", regions: [], enemies: [], gear: [], research: []), saves: SaveRepository())
        var revision: Int64 = 0
        func run(_ command: GameCommand) async throws {
            _ = try await engine.dispatch(command, operationID: UUID(), expectedRevision: revision)
            revision += 1
        }
        try await run(.recordMockPurchase(transactionID: "tx1", productID: "starter"))
        try await run(.recordMockPurchase(transactionID: "tx1", productID: "starter")) // duplicate callback, one ledger row
        try await run(.updateMockPurchase(transactionID: "tx1", productID: "starter", status: .interrupted))
        try await run(.updateMockPurchase(transactionID: "tx1", productID: "starter", status: .cancelled))
        try await run(.recordMockPurchase(transactionID: "tx2", productID: "starter"))
        try await run(.restoreMockPurchase(transactionID: "tx2", productID: "starter"))
        try await run(.recordMockPurchase(transactionID: "tx3", productID: "coins"))
        try await run(.updateMockPurchase(transactionID: "tx3", productID: "coins", status: .refunded))
        try await run(.recordMockPurchase(transactionID: "tx4", productID: "skin"))
        try await run(.updateMockPurchase(transactionID: "tx4", productID: "skin", status: .revoked))
        let state = await engine.snapshot()
        XCTAssertEqual(state.mockPurchaseRecords.count, 4)
        XCTAssertEqual(state.mockPurchaseRecords["tx1"]?.status, .cancelled)
        XCTAssertEqual(state.mockPurchaseRecords["tx2"]?.status, .restored)
        XCTAssertEqual(state.mockPurchaseRecords["tx3"]?.status, .refunded)
        XCTAssertEqual(state.mockPurchaseRecords["tx4"]?.status, .revoked)
        XCTAssertTrue(state.pendingPurchaseIDs.isEmpty)
        XCTAssertEqual(state.currency["ticket_paid_mock"], 0, "mock receipt must not grant purchased currency")
        do {
            _ = try await engine.dispatch(.updateMockPurchase(transactionID: "tx1", productID: "starter", status: .restored), operationID: UUID(), expectedRevision: revision)
            XCTFail("cancelled transaction was resurrected")
        } catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error \(error)") } }
    }

    func testGachaTopPityKeepsTargetAndInstanceQualityLatentProtection() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let target = catalog.gear[0].id
        let pity = GachaPityState(drawsSinceTop: 99, drawsSinceMid: 19, targetTemplateID: target, guaranteeTargetOnNextTop: true)
        let initial = GameSnapshot(currency: ["ticket_free": 1], gachaUnlocked: true, gachaPity: pity)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial))
        let receipt = try await game.dispatch(.mockSummon(poolDefinitionIDs: catalog.gear.map(\.id), count: 1, costCurrencyID: "ticket_free", seed: 12), operationID: UUID(), expectedRevision: 0)
        XCTAssertTrue(receipt.result.contains("base quality odds before pity"))
        XCTAssertTrue(receipt.result.contains("Q4 pity at 100 rolls"))
        XCTAssertTrue(receipt.result.contains("Q3 minimum on 20th consecutive Q0-Q2 roll"))
        let state = await game.snapshot(); let pulled = try XCTUnwrap(state.gear.last)
        XCTAssertEqual(pulled.definitionID, target); XCTAssertEqual(pulled.qualityID, "Q4")
        XCTAssertEqual(pulled.affixIDs.count, 3); XCTAssertNotNil(pulled.latentEffectID); XCTAssertTrue(pulled.protected)
        XCTAssertEqual(state.gachaPity.drawsSinceTop, 0); XCTAssertFalse(state.gachaPity.guaranteeTargetOnNextTop)
    }

    func testGachaTargetOutsideSelectedPoolIsRejectedWithoutSpending() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let target = try XCTUnwrap(catalog.gear.first(where: { $0.id == "EQ_W_P2" }))
        let pool = try XCTUnwrap(catalog.gear.first(where: { $0.id == "EQ_W_01" }))
        let pity = GachaPityState(drawsSinceTop: 99, targetTemplateID: target.id, guaranteeTargetOnNextTop: true)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot(currency: ["ticket_free": 1], gachaUnlocked: true, gachaPity: pity)))
        do {
            _ = try await game.dispatch(.mockSummon(poolDefinitionIDs: [pool.id], count: 1, costCurrencyID: "ticket_free", seed: 3), operationID: UUID(), expectedRevision: 0)
            XCTFail("off-pool target was awarded")
        } catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error \(error)") } }
        let state = await game.snapshot()
        XCTAssertEqual(state.currency["ticket_free"], 1)
        XCTAssertTrue(state.gear.isEmpty)
    }

    func testSelectingSameGachaTargetPreservesExistingTopGuarantee() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let target = try XCTUnwrap(catalog.gear.first(where: { $0.id == "EQ_W_01" }))
        let alternative = try XCTUnwrap(catalog.gear.first(where: { $0.id == "EQ_W_P2" }))
        let pity = GachaPityState(drawsSinceTop: 42, targetTemplateID: target.id, guaranteeTargetOnNextTop: true)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot(gachaUnlocked: true, gachaPity: pity)))
        _ = try await game.dispatch(.setGachaTarget(templateID: target.id), operationID: UUID(), expectedRevision: 0)
        var state = await game.snapshot()
        XCTAssertTrue(state.gachaPity.guaranteeTargetOnNextTop)
        XCTAssertEqual(state.gachaPity.drawsSinceTop, 42)
        _ = try await game.dispatch(.setGachaTarget(templateID: alternative.id), operationID: UUID(), expectedRevision: 1)
        state = await game.snapshot()
        XCTAssertFalse(state.gachaPity.guaranteeTargetOnNextTop, "changing target keeps the documented candidate reset semantics")
        XCTAssertEqual(state.gachaPity.targetTemplateID, alternative.id)
    }

    func testCatalogRejectsBrokenReferences() throws {
        let catalog = GameCatalog(version: "invalid", regions: [.init(id: "r", name: "R", enemyIDs: ["missing"])], enemies: [], gear: [], research: [])
        XCTAssertThrowsError(try catalog.validate())
    }

    func testBundledOverlayHasFiveRegionsThirtyEnemiesAndThirtyThreeGearTypes() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        XCTAssertEqual(catalog.regions.count, 5); XCTAssertEqual(catalog.enemies.count, 30)
        XCTAssertEqual(catalog.gear.count, 33); XCTAssertEqual(catalog.recipes.count, 69); XCTAssertEqual(Set(catalog.recipes.map(\.id)).count, 69)
        XCTAssertEqual(catalog.research.count, 5); XCTAssertEqual(catalog.challenges.count, 15)
        XCTAssertEqual(catalog.research.count, 5) // The 15-challenge set is not in this catalog.
        XCTAssertEqual(catalog.gachaOddsBasisPoints.values.reduce(0, +), 10_000)
        XCTAssertEqual(catalog.gachaOddsBasisPoints, ["Q0": 3_500, "Q1": 4_000, "Q2": 2_000, "Q3": 400, "Q4": 100])
        let initial = GameSnapshot.newGame(catalog: catalog)
        XCTAssertEqual(initial.partyActorIDs, ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"])
        XCTAssertEqual(initial.unlockedRegionIDs, [catalog.regions[0].id])
        XCTAssertEqual(initial.gear.count, 4)
    }

    func testForestBattleCommitsRewardAndCombatLogInOneRevision() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let store = try SaveRepository(initial: GameSnapshot.newGame(catalog: catalog))
        let game = try GameEngine(catalog: catalog, saves: store)
        let enemy = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "E_R01_01" }))
        let before = await game.snapshot()
        let receipt = try await game.dispatch(.resolveEncounter(enemyID: enemy.id, seed: 123), operationID: UUID(), expectedRevision: before.revision)
        let after = await game.snapshot()
        XCTAssertTrue(receipt.result.contains("VICTORY")); XCTAssertEqual(after.revision, 1)
        XCTAssertEqual(after.lastEncounterID, enemy.id); XCTAssertEqual(after.lastCombatResult?.won, true)
        XCTAssertEqual(after.materials[enemy.dropMaterialID!], 1); XCTAssertEqual(after.currency["coin"], 2)
    }

    func testBattleOperationReplayIsIdempotentButNewOperationCanFarmAgain() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let store = try SaveRepository(initial: GameSnapshot.newGame(catalog: catalog))
        let game = try GameEngine(catalog: catalog, saves: store)
        let enemy = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "E_R01_01" }))
        let firstOperation = UUID()
        let first = try await game.dispatch(.resolveEncounter(enemyID: enemy.id, seed: 123), operationID: firstOperation, expectedRevision: 0)
        let afterFirst = await game.snapshot()
        XCTAssertTrue(first.result.contains("VICTORY"))
        XCTAssertEqual(afterFirst.materials[enemy.dropMaterialID!], 1)
        XCTAssertEqual(afterFirst.currency["coin"], 2)

        let replay = try await game.dispatch(.resolveEncounter(enemyID: enemy.id, seed: 123), operationID: firstOperation, expectedRevision: 0)
        let afterReplay = await game.snapshot()
        XCTAssertEqual(replay, first, "same operation ID and payload must return the original encounter receipt")
        XCTAssertEqual(afterReplay.revision, afterFirst.revision)
        XCTAssertEqual(afterReplay.materials[enemy.dropMaterialID!], 1)
        XCTAssertEqual(afterReplay.currency["coin"], 2)

        let second = try await game.dispatch(.resolveEncounter(enemyID: enemy.id, seed: 123), operationID: UUID(), expectedRevision: afterReplay.revision)
        let afterSecondOperation = await game.snapshot()
        XCTAssertTrue(second.result.contains("VICTORY"))
        XCTAssertEqual(afterSecondOperation.revision, afterReplay.revision + 1)
        XCTAssertEqual(afterSecondOperation.materials[enemy.dropMaterialID!], 2, "a fresh operation ID is a repeat battle and grants one additional drop")
        XCTAssertEqual(afterSecondOperation.currency["coin"], 4)
    }

    func testGachaRequiresTutorialAndDailyRewardIsFiveWithClockGuard() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let gated = try GameEngine(catalog: catalog, saves: SaveRepository(initial: GameSnapshot.newGame(catalog: catalog)))
        let pool = catalog.gear.map(\.id)
        do { _ = try await gated.dispatch(.mockSummon(poolDefinitionIDs: pool, count: 5, costCurrencyID: "ticket_free", seed: 9), operationID: UUID(), expectedRevision: 0); XCTFail("gacha bypassed onboarding") }
        catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error \(error)") } }
        let ready = GameSnapshot.newGame(catalog: catalog)
        var state = ready; state.craftedGearOnce = true
        let first = try XCTUnwrap(state.gear.first(where: { item in catalog.gear.first(where: { $0.id == item.definitionID })?.slot == "weapon" }))
        let second = GearInstance(definitionID: "EQ_W_01")
        state.gear.append(second)
        let store = try SaveRepository(initial: state); let engine = try GameEngine(catalog: catalog, saves: store)
        _ = try await engine.dispatch(.markGearComparisonSeen(firstGearID: first.id, secondGearID: second.id), operationID: UUID(), expectedRevision: 0)
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await engine.dispatch(.dailyClaim(now: firstDay), operationID: UUID(), expectedRevision: 1)
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.currency["ticket_free"], 10)
        do { _ = try await engine.dispatch(.dailyClaim(now: firstDay.addingTimeInterval(-86400)), operationID: UUID(), expectedRevision: 2); XCTFail("backward date granted a daily claim") }
        catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error \(error)") } }
    }

    func testAllFiveRegionBossGatesAdvanceOnlyAfterPriorBossVictory() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        // Artificial combat-ready setup isolates unlock-gate state transitions from balance.
        // It is not a reachable starting loadout and is not used as progression evidence.
        var combatReady = GameSnapshot.newGame(catalog: catalog)
        for index in combatReady.gear.indices {
            combatReady.gear[index].enhancement = 10
            combatReady.gear[index].qualityID = "Q4"
            combatReady.gear[index].affixIDs = ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]
        }
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: combatReady))
        var revision: Int64 = 0
        do { _ = try await game.dispatch(.startExpedition(regionID: "R02"), operationID: UUID(), expectedRevision: 0); XCTFail("locked region opened") }
        catch let error as CoreError { guard case .invalidCommand = error else { return XCTFail("unexpected error \(error)") } }
        for index in catalog.regions.indices {
            let region = catalog.regions[index]
            let current = await game.snapshot()
            XCTAssertTrue(current.unlockedRegionIDs.contains(region.id))
            _ = try await game.dispatch(.startExpedition(regionID: region.id), operationID: UUID(), expectedRevision: revision); revision += 1
            let firstBoss = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "B_\(region.id)_A" }))
            let clearA = try await game.dispatch(.resolveEncounter(enemyID: firstBoss.id, seed: 7), operationID: UUID(), expectedRevision: revision); revision += 1
            XCTAssertTrue(clearA.result.contains("VICTORY"), "\(firstBoss.id): \(clearA.result)")
            let finalBoss = try XCTUnwrap(catalog.enemies.first(where: { $0.id == "B_\(region.id)_B" }))
            let clearB = try await game.dispatch(.resolveEncounter(enemyID: finalBoss.id, seed: 7), operationID: UUID(), expectedRevision: revision); revision += 1
            XCTAssertTrue(clearB.result.contains("VICTORY"), "\(finalBoss.id): \(clearB.result)")
        }
        let final = await game.snapshot()
        XCTAssertEqual(final.unlockedRegionIDs, Set(catalog.regions.map(\.id)))
    }

    func testSeparateRepositoriesUseDiskRevisionCAS() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-cas-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let first = try SaveRepository(fileURL: url), second = try SaveRepository(fileURL: url)
        _ = try await first.transact(expectedRevision: 0, operationID: UUID()) { $0.materials["a"] = 1; return "ok" }
        do { _ = try await second.transact(expectedRevision: 0, operationID: UUID()) { $0.materials["b"] = 1; return "bad" }; XCTFail("stale repository instance overwrote current save") }
        catch let error as CoreError { XCTAssertEqual(error, .revisionConflict(expected: 0, actual: 1)) }
        let final = try SaveRepository(fileURL: url)
        let finalState = await final.snapshot()
        XCTAssertEqual(finalState.materials["a"], 1)
    }
}
