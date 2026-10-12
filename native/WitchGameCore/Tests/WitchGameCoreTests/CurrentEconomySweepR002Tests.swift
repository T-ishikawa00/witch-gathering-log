import XCTest
@testable import WitchGameCore

final class CurrentEconomySweepR002Tests: XCTestCase {
        func testCurrentContractTenPersonaNinetyDaySweepR003() async throws {
        guard ProcessInfo.processInfo.environment["WITCH_CURRENT_ECONOMY_SWEEP_R002"] == "1" else {
            throw XCTSkip("Set WITCH_CURRENT_ECONOMY_SWEEP_R002=1 to run the bounded 120-scenario 90-day current-contract matrix")
        }
        let catalog = try GameCatalog.bundledTestOverlay()
        struct Persona {
            let name: String; let targetGear: String?; let invest: String; let gatherSuffix: String?
            var grantDay: Int? = nil; var grantTickets: Int = 0; var repeatEveryDays: Int = 0; var repeatTickets: Int = 0
            var rewardedAdCompletionPolicy: Bool = false; var qaProductID: String? = nil; var cosmeticID: String? = nil; var furnitureID: String? = nil; var adaptiveBuild: [String]? = nil
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
            Persona(name: "rewarded_ad_engaged", targetGear: nil, invest: "research", gatherSuffix: "G1", rewardedAdCompletionPolicy: true),
            Persona(name: "adaptive_free_ward_build", targetGear: nil, invest: "evolve", gatherSuffix: "G3", adaptiveBuild: ["EQ_W_G1", "EQ_A_03", "EQ_S_03", "EQ_F_03"])
        ]
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(catalog.furnitureIDs.contains("FURN_DESK_BOTANICAL"), "furniture-only persona needs a valid catalog item")
        XCTAssertEqual(catalog.dailyFreeTicketGrant, 5, "current-contract run uses the bundled catalog grant without changing product values")
        var jsonRows: [[String: Any]] = []
        for growthBP in [0, 500] {
         for dailyFreeTickets in [catalog.dailyFreeTicketGrant] {
          for loginsPerDay in [1, 3] {
           for seedBase in [17, 91, 404] {
          for (personaIndex, persona) in personas.enumerated() {
            let personaCatalog = catalog
            let growthProfile = CandidateCharacterGrowth(strengthBP: growthBP)
            let game = try GameEngine(catalog: personaCatalog, saves: SaveRepository(initial: GameSnapshot.newGame(catalog: personaCatalog)), candidateCharacterGrowth: growthProfile)
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
            var adCompletedCount = 0
            var adRewardXP = 0
            var adRewardDust = 0
            var campaignAttempts = 0, campaignWins = 0, campaignDefeats = 0
            var campaignAttemptsAtDay30 = 0, campaignWinsAtDay30 = 0, campaignDefeatsAtDay30 = 0
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
                var state = await game.snapshot()
                if state.activeRegionID != nil { _ = try await game.claimOffline(now: now, operationID: UUID(), expectedRevision: state.revision) }
                state = await game.snapshot()
                if persona.rewardedAdCompletionPolicy, let opportunityID = state.localAdRewardOpportunities.keys.sorted().first {
                    let session = "current-economy-\(seedBase)-\(growthBP)-\(persona.name)-\(day)-\(sessionIndex)-\(opportunityID)"
                    _ = try await send(.recordMockRewardedAdAttempt(opportunityID: opportunityID,
                        result: .simulate(sessionID: session, outcome: .completed)))
                    adCompletedCount += 1
                    let attempt = (await game.snapshot()).localAdAttemptRecords[session]
                    adRewardXP += attempt?.rewardXPByActor.values.reduce(0, +) ?? 0
                    adRewardDust += attempt?.rewardDust ?? 0
                }
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
                    let battle = try await send(.resolveEncounter(enemyID: enemyID, seed: UInt64(seedBase * 1_000_000 + (personaIndex + 1) * 100_000 + day * 100)))
                    campaignAttempts += 1
                    if battle.result.hasPrefix("VICTORY:") { campaignWins += 1 }
                    else if battle.result.hasPrefix("DEFEAT:") { campaignDefeats += 1 }
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
              if day == 30 {
                  day30 = await game.snapshot()
                  campaignAttemptsAtDay30 = campaignAttempts
                  campaignWinsAtDay30 = campaignWins
                  campaignDefeatsAtDay30 = campaignDefeats
              }
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
            d30["campaignAttempts"] = campaignAttemptsAtDay30
            d30["campaignWins"] = campaignWinsAtDay30
            d30["campaignDefeats"] = campaignDefeatsAtDay30
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
                "clearedEnemies": clears90, "campaignAttempts": campaignAttempts, "campaignWins": campaignWins,
                "campaignDefeats": campaignDefeats, "challengeAttempts": 0, "unlockedRegions": final.unlockedRegionIDs.count,
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
            let totalXP = final.characterXP.values.reduce(0, +)
            let growthLevels = Dictionary(uniqueKeysWithValues: final.characterXP.map { ($0.key, CandidateCharacterGrowth.progress(totalXP: $0.value).level) })
            let row: [String: Any] = [
                "authority": "UNAPPROVED_TEST_OVERLAY", "growthBP": growthBP, "growthProfileID": growthProfile.id,
                "seed": seedBase, "dailyFreeTickets": dailyFreeTickets, "adCompletions": adCompletedCount,
                "adRewardXP": adRewardXP, "adRewardDust": adRewardDust, "totalCharacterXP": totalXP, "finalLevels": growthLevels,
                "loginsPerDay": loginsPerDay, "totalLogins": 90 * loginsPerDay, "persona": persona.name,
                "targetTemplate": targetTemplate, "desiredBuildSet": buildSet, "desiredBuildSetEffects": buildSetEffects,
                "milestones": milestones, "d30": d30, "d90": d90
            ]
            jsonRows.append(row)
            print("CURRENT_ECONOMY_SWEEP,profile=\(growthBP),seed=\(seedBase),activity=\(loginsPerDay),daily=\(dailyFreeTickets),\(persona.name),adCompleted=\(adCompletedCount),adXP=\(adRewardXP),adDust=\(adRewardDust),d30=\(clears30)/30,r\(mid.unlockedRegionIDs.count),gear\(mid.gear.count),d90=\(clears90)/30,r\(final.unlockedRegionIDs.count),gear\(final.gear.count),templates=\(distinctTemplates),surplusCandidates=\(duplicateCandidates),firstTarget=\(firstTargetTemplateDay.map(String.init) ?? "NOT_REACHED"),targetQ4=\(firstTargetQ4Day.map(String.init) ?? "NOT_REACHED"),anyQ4=\(firstAnyQ4Day.map(String.init) ?? "NOT_REACHED"),2affix=\(firstTargetTwoAffixesDay.map(String.init) ?? "NOT_REACHED"),build=\(firstBuildReadyDay.map(String.init) ?? "NOT_REACHED")")
          }
           }
          }
         }
        }
        let report: [String: Any] = ["schemaVersion": 3, "status": "UNAPPROVED_TEST_OVERLAY", "method": "120 actual GameEngine command scenarios: 10 personas x 2 login cadences x 3 seeds x paired 0/500BP injection; bundled dailyFreeTicketGrant=5; completed local-ad rewards only after actual gathered work creates opportunities; one completed opportunity per ad-engaged login when available; actual committed campaign wins/losses counted from GameEngine receipts; explicitly synthetic mock purchase input assumptions; no real payment, prices, or revenue forecast", "targetQ4Definition": "desired template + Q4 on same instance", "twoAffixDefinition": "desired template has at least two distinct candidate affixes from POWER/VITALITY/GUARD on one instance", "buildReadyDefinition": "all four desired templates are owned, assigned to their catalog actor, and equipped in catalog slots; candidate build sets are unapproved", "personaCount": personas.count, "growthBPSet": [0, 500], "seedSet": [17, 91, 404], "dailyTicketSet": [catalog.dailyFreeTicketGrant], "loginSessionSet": [1, 3], "rewardedAdModel": "actual claimOffline work accrual plus .recordMockRewardedAdAttempt(.simulate(...completed)); reward grants only configured XP/dust, never tickets", "mockPurchaseInputModel": "test-only direct SaveRepository setup records explicitly marked UNAPPROVED_TEST_OVERLAY; not StoreKit or real purchase", "challengeCoverage": "none; this matrix tracks campaign attempts and outcomes only", "rows": jsonRows]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../docs/production/current/qa_drafts/r017_character_growth/ECONOMY_CURRENT_R003.json").standardizedFileURL
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
    }

}
