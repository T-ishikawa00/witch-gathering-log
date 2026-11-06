import XCTest
@testable import WitchGameCore

final class GearEnhancementGrowthR230Tests: XCTestCase {
    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func loadEarnedSnapshot() throws -> (GameSnapshot, Data) {
        let bytes = try Data(contentsOf: packageRoot().appendingPathComponent("fixtures/r227_earned_save.json"))
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let obj = try XCTUnwrap(envelope["snapshot"])
        let snapshotBytes = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
        return (try JSONDecoder().decode(GameSnapshot.self, from: snapshotBytes), bytes)
    }

    private func copiedCatalog(_ c: GameCatalog, appearances: [AppearanceDefinition]? = nil,
                               attack: [String: Int]? = nil) -> GameCatalog {
        GameCatalog(version: c.version, regions: c.regions, enemies: c.enemies, gear: c.gear,
            research: c.research, materialIDs: c.materialIDs, materialAvailabilityGates: c.materialAvailabilityGates,
            recipes: c.recipes, actorIDs: c.actorIDs, challenges: c.challenges,
            researchEffects: c.researchEffects, appearances: appearances ?? c.appearances,
            furnitureIDs: c.furnitureIDs, dailyFreeTicketGrant: c.dailyFreeTicketGrant, authority: c.authority,
            gearAttackBonuses: attack ?? c.gearAttackBonuses, gearHPBonuses: c.gearHPBonuses,
            gearDefenseBonuses: c.gearDefenseBonuses, gachaOddsBasisPoints: c.gachaOddsBasisPoints)
    }

    private func exactEquippedItems(actorID: String, snapshot: GameSnapshot) throws -> [GearInstance] {
        let prefix = actorID + "|"
        let ids = snapshot.equippedGearIDs.filter { $0.key.hasPrefix(prefix) }.map { $0.value }
        XCTAssertFalse(ids.isEmpty, "fixture must contain exact equipped IDs for \(actorID)")
        let byID = Dictionary(uniqueKeysWithValues: snapshot.gear.map { ($0.id, $0) })
        let items = try ids.map { id -> GearInstance in
            guard let item = byID[id] else { throw NSError(domain: "R230Fixture", code: 1) }
            return item
        }
        XCTAssertTrue(items.allSatisfy { $0.ownerID == nil || $0.ownerID == actorID })
        return items
    }

    private func r005(_ catalog: GameCatalog, actorID: String, items: [GearInstance],
                      snapshot: GameSnapshot, runtime: GameRuntimeConfigurationR098,
                      policy: EnhancementProjectionPolicyR230) throws -> Combatant {
        try catalog.projectCandidateCombatantR005(for: actorID, with: items,
            completedResearchIDs: snapshot.completedResearchIDs,
            totalXP: snapshot.characterXP[actorID, default: 0], candidateGrowth: runtime.growth,
            candidateLatentPolicy: runtime.latentPolicy,
            enhancementProjectionPolicyR230: policy).combatant
    }

    func testBudgetsZeroNeutralIntermediateAndCapDeltas() {
        let expected: [(String, GearEnhancementGrowthR230.Deltas)] = [
            ("weapon", .init(attack: 4, hp: 0, defense: 0)), ("body", .init(attack: 0, hp: 24, defense: 3)),
            ("hands", .init(attack: 1, hp: 0, defense: 1)), ("feet", .init(attack: 0, hp: 12, defense: 2)),
            ("amulet", .init(attack: 1, hp: 7, defense: 0)), ("ring", .init(attack: 1, hp: 0, defense: 0)),
            ("hand", .init(attack: 1, hp: 0, defense: 1))
        ]
        for (slot, cap) in expected {
            XCTAssertEqual(GearEnhancementGrowthR230.delta(slot: slot, enhancement: 0, refinement: 0), .init(attack: 0, hp: 0, defense: 0), slot)
            XCTAssertEqual(GearEnhancementGrowthR230.delta(slot: slot, enhancement: 10, refinement: 0), cap, slot)
        }
        XCTAssertEqual(GearEnhancementGrowthR230.delta(slot: "weapon", enhancement: 3, refinement: 0)?.attack, 1)
        XCTAssertEqual((0...10).compactMap { GearEnhancementGrowthR230.delta(slot: "weapon", enhancement: $0, refinement: 0)?.attack }, [0,0,0,1,1,2,2,2,3,3,4])
        XCTAssertNil(GearEnhancementGrowthR230.delta(slot: "unknown", enhancement: 1, refinement: 0))
        XCTAssertNil(GearEnhancementGrowthR230.delta(slot: "weapon", enhancement: 11, refinement: 0))
    }

    func testR098DefaultsAndR230ExplicitFactoryAreDistinctAndSharedWorkValidates() throws {
        let base = try GameRuntimeConfigurationR098.resolve()
        let candidate = try GameRuntimeEnhancementProfileR230(base: base)
        XCTAssertEqual(candidate.base.configurationFingerprint, base.configurationFingerprint)
        XCTAssertEqual(candidate.base.profileID, base.profileID)
        XCTAssertNotEqual(candidate.configurationFingerprint, base.configurationFingerprint)
        XCTAssertEqual(base.profileID, "app-candidate-r098-v1-growth-500bp")
        let starter = try base.makeNewSnapshot()
        let legacyEngine = try base.makeEngine(saves: SaveRepository(initial: starter))
        XCTAssertNil(legacyEngine.candidatePartyWorkPolicyR144)
        let policy = try PartyWorkPolicyR144()
        let candidateEngine = try candidate.makeEngine(saves: SaveRepository(initial: starter), candidatePartyWorkPolicyR144: policy)
        XCTAssertEqual(candidateEngine.candidatePartyWorkPolicyR144, policy)
        XCTAssertEqual(candidateEngine.enhancementProjectionPolicyR230, .r2SlotBudgetCandidate)
    }

    func testR230FactoryAcceptsValidAppearanceExtensionAndSharedWorkTogether() throws {
        let base = try GameRuntimeConfigurationR098.resolve()
        let candidate = try GameRuntimeEnhancementProfileR230(base: base)
        let extra = AppearanceDefinition(id: "R230_TEST_ONLY_COSTUME", kind: "costume", actorIDs: ["C_WITCH"], status: "UNAPPROVED_TEST_OVERLAY_CANDIDATE")
        let extended = copiedCatalog(base.catalog, appearances: base.catalog.appearances + [extra])
        let engine = try candidate.makeEngine(saves: SaveRepository(initial: base.makeNewSnapshot()),
            appearanceCatalog: extended, candidatePartyWorkPolicyR144: PartyWorkPolicyR144())
        XCTAssertEqual(engine.catalog.appearances.last, extra)
        let policy = try PartyWorkPolicyR144()
        XCTAssertEqual(engine.candidatePartyWorkPolicyR144, policy)
    }

    func testR230FactoryRejectsGameplayCatalogChangeEvenWithAppearanceExtension() throws {
        let base = try GameRuntimeConfigurationR098.resolve()
        let candidate = try GameRuntimeEnhancementProfileR230(base: base)
        var attack = base.catalog.gearAttackBonuses
        attack["EQ_W_G1", default: 0] += 1
        let extra = AppearanceDefinition(id: "R230_TEST_ONLY_COSTUME", kind: "costume", actorIDs: ["C_WITCH"], status: "UNAPPROVED_TEST_OVERLAY_CANDIDATE")
        let changed = copiedCatalog(base.catalog, appearances: base.catalog.appearances + [extra], attack: attack)
        XCTAssertThrowsError(try candidate.makeEngine(saves: SaveRepository(initial: base.makeNewSnapshot()),
            appearanceCatalog: changed, candidatePartyWorkPolicyR144: PartyWorkPolicyR144())) { error in
            guard let coreError = error as? CoreError, case .invalidCatalog = coreError else { return XCTFail("expected fail-closed gameplay catalog guard; got \(error)") }
        }
    }

    func testEarnedR227ExactEquippedIDsUseSameR005InputsAndZeroGrowthMatches() throws {
        let (snapshot, originalEnvelope) = try loadEarnedSnapshot()
        let runtime = try GameRuntimeConfigurationR098.resolve()
        _ = try GameRuntimeEnhancementProfileR230(base: runtime)
        XCTAssertEqual(snapshot.partyActorIDs, ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"])
        XCTAssertEqual(snapshot.characterXP.values.sorted(), [1716, 1716, 1716, 1716])
        XCTAssertEqual(snapshot.completedResearchIDs, ["RS_THEORY_1"])
        let expectedIDs: [String: Set<String>] = [
            "C_WITCH": ["806603B0-0324-43C6-833F-A592EE2E5E13"],
            "C_APPRENTICE": ["80B5B8D8-241B-4A7A-96F3-FE1FF7FBB17D", "C3700CAB-94E2-4C34-A433-AA4301A803DA", "10000000-0000-4000-8000-000000000002"],
            "C_SMITH": ["26F7BBCA-CAF6-4897-BECD-2B76282A29EB", "5AD221AD-DCA5-421E-9E1B-F7C014CEC746", "5B5362E1-8BB8-4B1C-9CC8-F6D7C0AA1678"],
            "C_FAMILIAR": ["5D458C5E-1BD3-4E0D-9548-A452494E2565", "2A6509AE-03EA-4718-9DD1-2C64ABDC8065"]
        ]
        for actor in snapshot.partyActorIDs {
            let items = try exactEquippedItems(actorID: actor, snapshot: snapshot)
            let expectedActorGear = try XCTUnwrap(expectedIDs[actor])
            XCTAssertEqual(Set(items.map { $0.id.uuidString }), expectedActorGear)
            // Compare both policies on the real R005 payload route, with identical
            // actual gear, XP, research and R098 growth. At enhancement zero the
            // candidate adds no stat delta; the earned +1 Familiar weapon also floors to zero.
            let oldPath = try r005(runtime.catalog, actorID: actor, items: items, snapshot: snapshot, runtime: runtime, policy: .legacy)
            let candidatePath = try r005(runtime.catalog, actorID: actor, items: items, snapshot: snapshot, runtime: runtime, policy: .r2SlotBudgetCandidate)
            XCTAssertEqual(candidatePath, oldPath, actor)
            var zeroItems = items
            for i in zeroItems.indices { zeroItems[i].enhancement = 0 }
            XCTAssertEqual(try r005(runtime.catalog, actorID: actor, items: zeroItems, snapshot: snapshot, runtime: runtime, policy: .r2SlotBudgetCandidate),
                           try r005(runtime.catalog, actorID: actor, items: zeroItems, snapshot: snapshot, runtime: runtime, policy: .legacy), actor + " at +0")
        }
        XCTAssertEqual(try Data(contentsOf: packageRoot().appendingPathComponent("fixtures/r227_earned_save.json")), originalEnvelope)
    }

    func testPayloadWeaponPlusThreeAddsOneAttackAndLeavesOtherProjectionInputsFixed() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let def = try XCTUnwrap(runtime.catalog.gear.first(where: { $0.id == "EQ_W_G1" && $0.slot == "weapon" }))
        let slots = try runtime.latentPolicy.generateNewInstanceSlots(templateID: def.id, joinedActorIDs: ["C_WITCH"],
            operationID: UUID(uuidString: "23000000-0000-4000-8000-000000000201")!, domainSalt: "r230-plus3", minimumRawQ: 0)
        let base = GearInstance(id: UUID(uuidString: "23000000-0000-4000-8000-000000000202")!, definitionID: def.id,
            ownerID: "C_WITCH", enhancement: 0, candidateLatentSlots: slots, qualityID: "Q0")
        var plus3 = base; plus3.enhancement = 3
        let state = try runtime.makeNewSnapshot()
        let atZero = try r005(runtime.catalog, actorID: "C_WITCH", items: [base], snapshot: state, runtime: runtime, policy: .r2SlotBudgetCandidate)
        let atThree = try r005(runtime.catalog, actorID: "C_WITCH", items: [plus3], snapshot: state, runtime: runtime, policy: .r2SlotBudgetCandidate)
        XCTAssertEqual(atThree.attack - atZero.attack, 1)
        XCTAssertEqual(atThree.maxHP, atZero.maxHP)
        XCTAssertEqual(atThree.defense, atZero.defense)
        XCTAssertEqual(atThree.effectIDs, atZero.effectIDs)
    }

    func testThreeRealEnhancementCommandsKeepCostsAndNonGearSaveStateEquivalent() async throws {
        let (initial, _) = try loadEarnedSnapshot()
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let candidate = try GameRuntimeEnhancementProfileR230(base: runtime)
        let policy = try PartyWorkPolicyR144()
        let legacyStore = try SaveRepository(initial: initial)
        let candidateStore = try SaveRepository(initial: initial)
        let legacyEngine = try GameEngine(catalog: runtime.catalog, saves: legacyStore,
            candidateCombatOverlay: runtime.combatOverlay, candidateCharacterGrowth: runtime.growth,
            candidateLatentPolicy: runtime.latentPolicy, candidatePartyWorkPolicyR144: policy)
        let candidateEngine = try candidate.makeEngine(saves: candidateStore, candidatePartyWorkPolicyR144: policy)
        let weaponID = UUID(uuidString: "806603B0-0324-43C6-833F-A592EE2E5E13")!
        let weapon = try XCTUnwrap(initial.gear.first(where: { $0.id == weaponID }))
        XCTAssertEqual(weapon.ownerID, "C_WITCH"); XCTAssertEqual(weapon.enhancement, 0)
        let recipe = try XCTUnwrap(runtime.catalog.recipes.first(where: { $0.id == "ENHANCE_1" && $0.kind == "enhance" }))
        XCTAssertEqual(recipe.dustCost, 5); XCTAssertEqual(recipe.gateID, "G_START")
        let expectedCost = try (1...3).map { level in try XCTUnwrap(runtime.catalog.recipes.first(where: { $0.id == "ENHANCE_\(level)" })).dustCost }.reduce(0, +)
        XCTAssertEqual(expectedCost, 30)
        XCTAssertGreaterThanOrEqual(initial.materials["refine_dust", default: 0], expectedCost)
        for index in 0..<3 {
            let legacyID = UUID(uuidString: String(format: "23000000-0000-4000-8000-%012d", 301 + index))!
            let candidateID = legacyID // Same operation in two separate repositories enables exact receipt equality.
            let legacyNow = await legacyEngine.snapshot(); let candidateNow = await candidateEngine.snapshot()
            _ = try await legacyEngine.dispatch(.enhance(gearID: weaponID), operationID: legacyID, expectedRevision: legacyNow.revision)
            _ = try await candidateEngine.dispatch(.enhance(gearID: weaponID), operationID: candidateID, expectedRevision: candidateNow.revision)
        }
        var legacyAfter = await legacyEngine.snapshot(); var candidateAfter = await candidateEngine.snapshot()
        XCTAssertEqual(legacyAfter.gear.first(where: { $0.id == weaponID })?.enhancement, 3)
        XCTAssertEqual(candidateAfter.gear.first(where: { $0.id == weaponID })?.enhancement, 3)
        let witchItemsBefore = try exactEquippedItems(actorID: "C_WITCH", snapshot: initial)
        let witchItemsAfter = try exactEquippedItems(actorID: "C_WITCH", snapshot: candidateAfter)
        let witchBefore = try r005(runtime.catalog, actorID: "C_WITCH", items: witchItemsBefore, snapshot: initial, runtime: runtime, policy: .r2SlotBudgetCandidate)
        let witchAfter = try r005(runtime.catalog, actorID: "C_WITCH", items: witchItemsAfter, snapshot: candidateAfter, runtime: runtime, policy: .r2SlotBudgetCandidate)
        XCTAssertEqual(witchAfter.attack - witchBefore.attack, 1, "the earned equipped weapon's +3 increase is observable on the R005 combat path")
        XCTAssertEqual(witchAfter.maxHP, witchBefore.maxHP)
        XCTAssertEqual(witchAfter.defense, witchBefore.defense)
        XCTAssertEqual(legacyAfter.materials["refine_dust", default: 0], initial.materials["refine_dust", default: 0] - expectedCost)
        XCTAssertEqual(candidateAfter.materials, legacyAfter.materials)
        XCTAssertEqual(candidateAfter.currency, legacyAfter.currency)
        XCTAssertEqual(candidateAfter.revision, legacyAfter.revision)
        // Both repositories receive the same operation IDs. Compare exact earned
        // state first, then verify the entire post-command snapshot matches.
        XCTAssertEqual(candidateAfter.gear, legacyAfter.gear)
        legacyAfter.gear = initial.gear; candidateAfter.gear = initial.gear
        legacyAfter.materials = initial.materials; candidateAfter.materials = initial.materials
        legacyAfter.revision = initial.revision; candidateAfter.revision = initial.revision
        XCTAssertEqual(candidateAfter, legacyAfter)
    }

    func testOptInFactoryRejectsMalformedPersistedEquippedLevelsWithoutRepairOrWrite() async throws {
        let base = try GameRuntimeConfigurationR098.resolve()
        let candidate = try GameRuntimeEnhancementProfileR230(base: base)
        let (pristine, _) = try loadEarnedSnapshot()
        let policy = try PartyWorkPolicyR144()
        let validRepository = try SaveRepository(initial: pristine)
        let validEngine = try candidate.makeEngine(saves: validRepository, candidatePartyWorkPolicyR144: policy)
        let validEnemy = try XCTUnwrap(base.catalog.enemies.first(where: { $0.regionID == pristine.activeRegionID && $0.prerequisiteEncounterID == nil }))
        let validReceipt = try await validEngine.dispatch(.resolveEncounter(enemyID: validEnemy.id, seed: 230_998),
            operationID: UUID(uuidString: "23000000-0000-4000-8000-000000000998")!, expectedRevision: pristine.revision)
        XCTAssertEqual(validReceipt.revision, pristine.revision + 1)
        for (enhancement, refinement) in [(11, 0), (0, Int.max)] {
            var malformed = pristine
            let weaponID = UUID(uuidString: "806603B0-0324-43C6-833F-A592EE2E5E13")!
            let index = try XCTUnwrap(malformed.gear.firstIndex(where: { $0.id == weaponID }))
            malformed.gear[index].enhancement = enhancement
            malformed.gear[index].refinement = refinement
            let repository = try SaveRepository(initial: malformed)
            let engine = try candidate.makeEngine(saves: repository, candidatePartyWorkPolicyR144: policy)
            let enemy = try XCTUnwrap(base.catalog.enemies.first(where: { $0.regionID == malformed.activeRegionID && $0.prerequisiteEncounterID == nil }))
            do {
                _ = try await engine.dispatch(.resolveEncounter(enemyID: enemy.id, seed: 230_999),
                    operationID: UUID(), expectedRevision: malformed.revision)
                XCTFail("invalid persisted enhancement data must fail before combat and remain unmodified")
            } catch {
                guard let coreError = error as? CoreError, case .invalidCommand(let message) = coreError else { return XCTFail("expected invalidCommand, got \(error)") }
                XCTAssertEqual(message, "R230 candidate cannot project invalid gear definition/slot/enhancement/refinement")
            }
            let after = await engine.snapshot()
            XCTAssertEqual(after, malformed)
        }
    }
    func testAll33CatalogItemsAtZeroMatchDefaultLegacyProjection() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let catalog = runtime.catalog
        XCTAssertEqual(catalog.gear.count, 33)
        let candidate = try GameRuntimeEnhancementProfileR230(base: runtime)
        XCTAssertNotEqual(candidate.configurationFingerprint, runtime.configurationFingerprint)
        for definition in catalog.gear {
            let item = GearInstance(definitionID: definition.id, enhancement: 0)
            let legacy = catalog.projectCombatant(for: "C_WITCH", with: [item])
            let optIn = catalog.projectCombatant(for: "C_WITCH", with: [item],
                enhancementProjectionPolicyR230: .r2SlotBudgetCandidate)
            XCTAssertEqual(optIn.maxHP, legacy.maxHP, definition.id)
            XCTAssertEqual(optIn.attack, legacy.attack, definition.id)
            XCTAssertEqual(optIn.defense, legacy.defense, definition.id)
        }
        let weapon = try XCTUnwrap(catalog.gear.first(where: { $0.id == "EQ_W_G1" && $0.slot == "weapon" }))
        let legacyZero = catalog.projectCombatant(for: "C_WITCH", with: [GearInstance(definitionID: weapon.id)])
        let legacyCap = catalog.projectCombatant(for: "C_WITCH", with: [GearInstance(definitionID: weapon.id, enhancement: 10)])
        let candidateZero = catalog.projectCombatant(for: "C_WITCH", with: [GearInstance(definitionID: weapon.id)],
            enhancementProjectionPolicyR230: .r2SlotBudgetCandidate)
        let candidateCap = catalog.projectCombatant(for: "C_WITCH", with: [GearInstance(definitionID: weapon.id, enhancement: 10)],
            enhancementProjectionPolicyR230: .r2SlotBudgetCandidate)
        XCTAssertEqual(legacyCap.attack, legacyZero.attack, "default legacy callers remain unchanged")
        XCTAssertEqual(candidateZero.attack, legacyZero.attack, "opt-in level zero remains baseline-neutral")
        XCTAssertEqual(candidateCap.attack - candidateZero.attack, 4, "weapon receives only the R2 enhancement delta")
    }

    func testRealCatalogHandAliasPayloadProjectionUsesTheCandidateGrowthPath() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let catalog = runtime.catalog
        let familiarHand = try XCTUnwrap(catalog.gear.first(where: { $0.id == "EQ_F_HAND_01" && $0.slot == "hand" }))
        let policy = runtime.latentPolicy
        let slots = try policy.generateNewInstanceSlots(templateID: familiarHand.id, joinedActorIDs: ["C_FAMILIAR"],
            operationID: UUID(uuidString: "23000000-0000-4000-8000-000000000001")!, domainSalt: "r230-test", minimumRawQ: 0)
        let zero = GearInstance(definitionID: familiarHand.id, ownerID: "C_FAMILIAR", enhancement: 0,
                                candidateLatentSlots: slots, qualityID: "Q0")
        var cap = zero; cap.enhancement = 10
        let base = try catalog.projectCandidateCombatantR005(for: "C_FAMILIAR", with: [zero],
            candidateLatentPolicy: policy, enhancementProjectionPolicyR230: .legacy).combatant
        let optedZero = try catalog.projectCandidateCombatantR005(for: "C_FAMILIAR", with: [zero],
            candidateLatentPolicy: policy, enhancementProjectionPolicyR230: .r2SlotBudgetCandidate).combatant
        let optedCap = try catalog.projectCandidateCombatantR005(for: "C_FAMILIAR", with: [cap],
            candidateLatentPolicy: policy, enhancementProjectionPolicyR230: .r2SlotBudgetCandidate).combatant
        XCTAssertEqual(optedZero, base)
        XCTAssertGreaterThan(optedCap.attack, optedZero.attack)
        XCTAssertGreaterThan(optedCap.defense, optedZero.defense)
    }


}
