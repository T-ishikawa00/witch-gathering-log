import XCTest
@testable import WitchGameCore

final class WardrobeCandidateIntegrationR128Tests: XCTestCase {
    private func candidateCatalog() throws -> GameCatalog {
        try WardrobeCandidateCatalogR128.extending(GameRuntimeConfigurationR098.resolve().catalog)
    }

    func testCatalogExtensionIsExplicitAndDoesNotChangeGameplayInputs() throws {
        let base = try GameRuntimeConfigurationR098.resolve().catalog
        XCTAssertFalse(base.appearances.contains { [WardrobeCandidateResolverR128.lunaID, WardrobeCandidateResolverR128.noirID].contains($0.id) })
        XCTAssertFalse(WardrobeCandidateCatalogR128.enabled(arguments: ["WitchGathering", "--qa-wardrobe-candidate-r128"]))
        XCTAssertFalse(WardrobeCandidateCatalogR128.enabled(arguments: ["WitchGathering", "--qa-isolated"]))
        let missingSaveKey = ["WitchGathering", "--qa-isolated", "--qa-wardrobe-candidate-r128",
                             "--qa-luna-mantle-r097", "--qa-luna-mantle-offsets-r127", "--qa-noir-neckwear-r124"]
        XCTAssertFalse(WardrobeCandidateCatalogR128.enabled(arguments: missingSaveKey))
        let malformedSaveKey = ["WitchGathering", "--qa-isolated", "--qa-save-key=not-a-uuid", "--qa-wardrobe-candidate-r128",
                                "--qa-luna-mantle-r097", "--qa-luna-mantle-offsets-r127", "--qa-noir-neckwear-r124"]
        XCTAssertFalse(WardrobeCandidateCatalogR128.enabled(arguments: malformedSaveKey))
        let oldR126Gate = ["WitchGathering", "--qa-isolated", "--qa-wardrobe-candidate-r128",
                           "--qa-luna-mantle-r097", "--qa-luna-mantle-bookless-r126", "--qa-noir-neckwear-r124"]
        XCTAssertFalse(WardrobeCandidateCatalogR128.enabled(arguments: oldR126Gate))
        let fullR127Gate = ["WitchGathering", "--qa-isolated", "--qa-save-key=4c7254c0-a11a-4bb6-8a4f-c56f7d848e94", "--qa-wardrobe-candidate-r128",
                            "--qa-luna-mantle-r097", "--qa-luna-mantle-offsets-r127", "--qa-noir-neckwear-r124"]
        XCTAssertTrue(WardrobeCandidateCatalogR128.enabled(arguments: fullR127Gate))

        let candidate = try WardrobeCandidateCatalogR128.extending(base)
        XCTAssertEqual(candidate.appearances.count, base.appearances.count + 2)
        XCTAssertEqual(candidate.gear.map(\.id), base.gear.map(\.id))
        XCTAssertEqual(candidate.authority, base.authority)
        XCTAssertEqual(candidate.gearAttackBonuses, base.gearAttackBonuses)
        XCTAssertEqual(candidate.gearHPBonuses, base.gearHPBonuses)
        XCTAssertEqual(candidate.gearDefenseBonuses, base.gearDefenseBonuses)
        XCTAssertEqual(candidate.gachaOddsBasisPoints, base.gachaOddsBasisPoints)
        XCTAssertEqual(candidate.dailyFreeTicketGrant, base.dailyFreeTicketGrant)
        let latent = try GameRuntimeConfigurationR098.resolve().latentPolicy
        XCTAssertEqual(try GameSnapshot.newCandidateGame(catalog: candidate, candidateLatentPolicy: latent), try GameSnapshot.newCandidateGame(catalog: base, candidateLatentPolicy: latent))
    }


    func testCatalogExtensionPreservesNonDefaultMetadata() throws {
        let resolved = try GameRuntimeConfigurationR098.resolve().catalog
        let synthetic = GameCatalog(version: resolved.version, regions: resolved.regions, enemies: resolved.enemies,
            gear: resolved.gear, research: resolved.research, materialIDs: resolved.materialIDs,
            materialAvailabilityGates: resolved.materialAvailabilityGates, recipes: resolved.recipes,
            actorIDs: resolved.actorIDs, challenges: resolved.challenges, researchEffects: resolved.researchEffects,
            appearances: resolved.appearances, furnitureIDs: resolved.furnitureIDs, dailyFreeTicketGrant: 3,
            authority: resolved.authority, gearAttackBonuses: [resolved.gear[0].id: 7],
            gearHPBonuses: [resolved.gear[0].id: 11], gearDefenseBonuses: [resolved.gear[0].id: 2],
            gachaOddsBasisPoints: ["Q0": 3_200, "Q1": 4_000, "Q2": 2_300, "Q3": 400, "Q4": 100])
        let extended = try WardrobeCandidateCatalogR128.extending(synthetic)
        XCTAssertEqual(extended.authority, synthetic.authority)
        XCTAssertEqual(extended.gearAttackBonuses, synthetic.gearAttackBonuses)
        XCTAssertEqual(extended.gearHPBonuses, synthetic.gearHPBonuses)
        XCTAssertEqual(extended.gearDefenseBonuses, synthetic.gearDefenseBonuses)
        XCTAssertEqual(extended.gachaOddsBasisPoints, synthetic.gachaOddsBasisPoints)
        XCTAssertEqual(extended.dailyFreeTicketGrant, synthetic.dailyFreeTicketGrant)
    }

    func testPersistPerActorReloadAndResetWithoutGameplayMutation() async throws {
        let catalog = try candidateCatalog()
        try catalog.validate()
        let initial = GameSnapshot.newGame(catalog: catalog)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wardrobe-r128-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Retain unique fault/roundtrip save evidence.
        let url = dir.appendingPathComponent("save.json")
        let repo = try SaveRepository(initial: initial, fileURL: url)
        let engine = try GameEngine(catalog: catalog, saves: repo)
        _ = try await engine.dispatch(.setCosmetic(WardrobeCandidateResolverR128.lunaID, owned: true), operationID: UUID(), expectedRevision: 0)
        let s1 = await engine.snapshot()
        _ = try await engine.dispatch(.selectCosmetic(actorID: "C_APPRENTICE", cosmeticID: WardrobeCandidateResolverR128.lunaID), operationID: UUID(), expectedRevision: s1.revision)
        let s2 = await engine.snapshot()
        _ = try await engine.dispatch(.setCosmetic(WardrobeCandidateResolverR128.noirID, owned: true), operationID: UUID(), expectedRevision: s2.revision)
        let s3 = await engine.snapshot()
        _ = try await engine.dispatch(.selectCosmetic(actorID: "C_FAMILIAR", cosmeticID: WardrobeCandidateResolverR128.noirID), operationID: UUID(), expectedRevision: s3.revision)
        let selected = await engine.snapshot()
        XCTAssertEqual(selected.selectedCosmeticIDs["C_APPRENTICE"], WardrobeCandidateResolverR128.lunaID)
        XCTAssertEqual(selected.selectedCosmeticIDs["C_FAMILIAR"], WardrobeCandidateResolverR128.noirID)
        XCTAssertEqual(selected.currency, initial.currency)
        XCTAssertEqual(selected.gear, initial.gear)

        let reopened = try SaveRepository(fileURL: url)
        let loaded = await reopened.snapshot()
        XCTAssertEqual(loaded.selectedCosmeticIDs, selected.selectedCosmeticIDs)
        XCTAssertEqual(loaded.ownedCosmeticIDs, selected.ownedCosmeticIDs)
        XCTAssertEqual(loaded.revision, selected.revision)
        let reopenedEngine = try GameEngine(catalog: catalog, saves: reopened)
        _ = try await reopenedEngine.dispatch(.selectCosmetic(actorID: "C_APPRENTICE", cosmeticID: nil), operationID: UUID(), expectedRevision: loaded.revision)
        let reset = await reopenedEngine.snapshot()
        XCTAssertNil(reset.selectedCosmeticIDs["C_APPRENTICE"])
        XCTAssertEqual(reset.selectedCosmeticIDs["C_FAMILIAR"], WardrobeCandidateResolverR128.noirID)
    }

    func testCandidateSelectionRejectsWrongActorAndUnownedID() async throws {
        let catalog = try candidateCatalog()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wardrobe-r128-negative-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Retain unique fault/roundtrip save evidence.
        let repo = try SaveRepository(initial: GameSnapshot.newGame(catalog: catalog), fileURL: dir.appendingPathComponent("save.json"))
        let engine = try GameEngine(catalog: catalog, saves: repo)
        do {
            _ = try await engine.dispatch(.selectCosmetic(actorID: "C_WITCH", cosmeticID: WardrobeCandidateResolverR128.lunaID), operationID: UUID(), expectedRevision: 0)
            XCTFail("wrong-actor selection must reject")
        } catch { }
        do {
            _ = try await engine.dispatch(.selectCosmetic(actorID: "C_APPRENTICE", cosmeticID: WardrobeCandidateResolverR128.lunaID), operationID: UUID(), expectedRevision: 0)
            XCTFail("unowned candidate selection must reject")
        } catch { }
        let after = await engine.snapshot()
        XCTAssertTrue(after.selectedCosmeticIDs.isEmpty)
        XCTAssertTrue(after.ownedCosmeticIDs.isEmpty)
    }

    func testSceneMetadataRequiresOwnedScopedSelectionAndCompleteGate() throws {
        let catalog = try candidateCatalog()
        let selection = ["C_APPRENTICE": WardrobeCandidateResolverR128.lunaID,
                         "C_FAMILIAR": WardrobeCandidateResolverR128.noirID]
        let owned: Set<String> = [WardrobeCandidateResolverR128.lunaID, WardrobeCandidateResolverR128.noirID]
        let incomplete = ["WitchGathering", "--qa-isolated", WardrobeCandidateResolverR128.flag]
        XCTAssertTrue(WardrobeCandidateResolverR128.sceneMetadata(base: [:], selectedByActor: selection, ownedIDs: owned, catalog: catalog, arguments: incomplete).isEmpty)
        let complete = ["WitchGathering", "--qa-isolated", "--qa-save-key=4c7254c0-a11a-4bb6-8a4f-c56f7d848e94", WardrobeCandidateResolverR128.flag,
                        "--qa-luna-mantle-r097", "--qa-luna-mantle-offsets-r127", "--qa-noir-neckwear-r124"]
        let metadata = WardrobeCandidateResolverR128.sceneMetadata(base: [:], selectedByActor: selection, ownedIDs: owned, catalog: catalog, arguments: complete)
        XCTAssertEqual(metadata[WardrobeCandidateResolverR128.lunaSceneKey], WardrobeCandidateResolverR128.lunaID)
        XCTAssertEqual(metadata[WardrobeCandidateResolverR128.lunaAppearanceKey], WardrobeCandidateResolverR128.lunaValue)
        XCTAssertEqual(metadata[WardrobeCandidateResolverR128.noirSceneKey], WardrobeCandidateResolverR128.noirID)
        XCTAssertEqual(metadata.count, 3)
        let staleBase = [WardrobeCandidateResolverR128.lunaSceneKey: WardrobeCandidateResolverR128.lunaID,
                         WardrobeCandidateResolverR128.noirSceneKey: WardrobeCandidateResolverR128.noirID,
                         WardrobeCandidateResolverR128.lunaAppearanceKey: WardrobeCandidateResolverR128.lunaValue]
        XCTAssertTrue(WardrobeCandidateResolverR128.sceneMetadata(base: staleBase, selectedByActor: [:], ownedIDs: [], catalog: catalog, arguments: complete).isEmpty)
        XCTAssertTrue(WardrobeCandidateResolverR128.sceneMetadata(base: staleBase, selectedByActor: selection, ownedIDs: owned, catalog: catalog, arguments: ["WitchGathering"]).isEmpty)
        XCTAssertTrue(WardrobeCandidateResolverR128.sceneMetadata(base: [:], selectedByActor: ["C_WITCH": WardrobeCandidateResolverR128.lunaID], ownedIDs: owned, catalog: catalog, arguments: complete).isEmpty)
        XCTAssertTrue(WardrobeCandidateResolverR128.sceneMetadata(base: [:], selectedByActor: selection, ownedIDs: [], catalog: catalog, arguments: complete).isEmpty)
        let unsupportedGear = WardrobeCandidateResolverR128.sceneMetadata(base: ["APPRENTICE_EQUIPPED_WEAPON_ID":"EQ_UNKNOWN"], selectedByActor: selection, ownedIDs: owned, catalog: catalog, arguments: complete)
        XCTAssertNil(unsupportedGear[WardrobeCandidateResolverR128.lunaSceneKey])
        XCTAssertNil(unsupportedGear[WardrobeCandidateResolverR128.lunaAppearanceKey])
        XCTAssertNil(WardrobeCandidateResolverR128.iconAssetID(for: "unknown"))
    }

    func testPreviewIsActorAwareAndReadOnly() {
        let base = ["C_WITCH":"ERNA_TRAVEL", "WITCH_WEAPON":"STAFF_BRANCH"]
        let luna = WardrobeCandidateResolverR128.preview(base: base, actorID: "C_APPRENTICE", appearanceID: WardrobeCandidateResolverR128.lunaID, kind: "costume", enabled: true)
        XCTAssertEqual(luna[WardrobeCandidateResolverR128.lunaSceneKey], WardrobeCandidateResolverR128.lunaID)
        XCTAssertEqual(luna[WardrobeCandidateResolverR128.lunaAppearanceKey], WardrobeCandidateResolverR128.lunaValue)
        XCTAssertEqual(luna["C_WITCH"], "ERNA_TRAVEL")
        let noir = WardrobeCandidateResolverR128.preview(base: base, actorID: "C_FAMILIAR", appearanceID: WardrobeCandidateResolverR128.noirID, kind: "accessory", enabled: true)
        XCTAssertEqual(noir[WardrobeCandidateResolverR128.noirSceneKey], WardrobeCandidateResolverR128.noirID)
        XCTAssertEqual(base, ["C_WITCH":"ERNA_TRAVEL", "WITCH_WEAPON":"STAFF_BRANCH"])
        var generic = WardrobePreviewSelectionR094()
        generic.show(appearanceID: "SAMPLE_COSTUME", kind: "costume")
        XCTAssertEqual(generic.applying(to: base, actorID: "C_APPRENTICE")["C_WITCH"], "ERNA_TRAVEL")
        XCTAssertEqual(generic.applying(to: base, actorID: "C_APPRENTICE")["C_APPRENTICE"], "SAMPLE_COSTUME")
        XCTAssertEqual(WardrobeCandidateResolverR128.preview(base: base, actorID: "C_WITCH", appearanceID: WardrobeCandidateResolverR128.lunaID, kind: "costume", enabled: false), base)
    }

    func testLunaBookSlotRoutingAndCorrectedExecuteFrame() {
        let enabledArgs = true
        let base = (actorID: "C_APPRENTICE", selectedID: WardrobeCandidateResolverR128.lunaID, owned: true, catalogAllowsActor: true)
        let empty = WardrobeCandidateResolverR128.lunaRoute(enabled: enabledArgs, selectedID: base.selectedID, owned: base.owned, actorID: base.actorID, catalogAllowsActor: base.catalogAllowsActor, equippedBookGearID: nil, bodyAssetID: "GeneratedArt/PartyWalk/LUNA__walk_4.png", localFrameIndex: 4, bookNodePresent: false, palmNodePresent: false)
        XCTAssertEqual(empty, .emptyBookSlot)
        let supportedBook = WardrobeCandidateResolverR128.lunaRoute(enabled: true, selectedID: base.selectedID, owned: true, actorID: base.actorID, catalogAllowsActor: true, equippedBookGearID: "EQ_A_01", bodyAssetID: "GeneratedArt/PartyAttack/LUNA__attack_04.png", localFrameIndex: 1, bookNodePresent: true, palmNodePresent: true)
        XCTAssertEqual(supportedBook, .supportedBookRoute)
        let unsupported = WardrobeCandidateResolverR128.lunaRoute(enabled: true, selectedID: base.selectedID, owned: true, actorID: base.actorID, catalogAllowsActor: true, equippedBookGearID: "UNKNOWN_WEAPON", bodyAssetID: "GeneratedArt/PartyWalk/LUNA__walk_4.png", localFrameIndex: 4, bookNodePresent: false, palmNodePresent: false)
        XCTAssertEqual(unsupported, .unsupportedWeapon)
        let correctedExecuteFrame = WardrobeCandidateResolverR128.lunaRoute(enabled: true, selectedID: base.selectedID, owned: true, actorID: base.actorID, catalogAllowsActor: true, equippedBookGearID: nil, bodyAssetID: "GeneratedArt/PartyAttack/LUNA__attack_04.png", localFrameIndex: 1, bookNodePresent: false, palmNodePresent: false)
        XCTAssertEqual(correctedExecuteFrame, .emptyBookSlot)
        XCTAssertNil(WardrobeCandidateResolverR128.lunaPoseIndex("GeneratedArt/PartyAttack/LUNA__attack_4.png"))
        XCTAssertNil(WardrobeCandidateResolverR128.lunaPoseIndex("GeneratedArt/PartyWalk/LUNA__walk_04.png"))
        let wrongExecuteIndex = WardrobeCandidateResolverR128.lunaRoute(enabled: true, selectedID: base.selectedID, owned: true, actorID: base.actorID, catalogAllowsActor: true, equippedBookGearID: nil, bodyAssetID: "GeneratedArt/PartyAttack/LUNA__attack_04.png", localFrameIndex: 0, bookNodePresent: false, palmNodePresent: false)
        XCTAssertEqual(wrongExecuteIndex, .unknownBodyFrame)
        let staleNode = WardrobeCandidateResolverR128.lunaRoute(enabled: true, selectedID: base.selectedID, owned: true, actorID: base.actorID, catalogAllowsActor: true, equippedBookGearID: nil, bodyAssetID: "GeneratedArt/PartyWalk/LUNA__walk_4.png", localFrameIndex: 4, bookNodePresent: true, palmNodePresent: false)
        XCTAssertEqual(staleNode, .inconsistentBookPresentation)
        XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(enabled: false, selectedID: base.selectedID, owned: true, actorID: base.actorID, catalogAllowsActor: true, equippedBookGearID: nil, bodyAssetID: "GeneratedArt/PartyWalk/LUNA__walk_4.png", localFrameIndex: 4, bookNodePresent: false, palmNodePresent: false), .disabled)
    }

    func testEmbeddedReadingMantleRouteIsExactAndPreservesBookPresentation() {
        let selected = WardrobeCandidateResolverR128.lunaID
        for index in 0...3 {
            let assetID = "LUNA_READING__\(index)"
            XCTAssertEqual(WardrobeCandidateResolverR128.lunaReadingIndex(assetID), index)
            XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(
                enabled: true, selectedID: selected, owned: true, actorID: "C_APPRENTICE",
                catalogAllowsActor: true, equippedBookGearID: "EQ_A_01", bodyAssetID: assetID,
                localFrameIndex: index, bookNodePresent: false, palmNodePresent: false), .embeddedReadingRoute)
        }
        XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(
            enabled: true, selectedID: selected, owned: true, actorID: "C_APPRENTICE",
            catalogAllowsActor: true, equippedBookGearID: "EQ_A_01", bodyAssetID: "LUNA_READING__0",
            localFrameIndex: 1, bookNodePresent: false, palmNodePresent: false), .unknownBodyFrame)
        XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(
            enabled: true, selectedID: selected, owned: true, actorID: "C_APPRENTICE",
            catalogAllowsActor: true, equippedBookGearID: "EQ_A_01", bodyAssetID: "LUNA_READING__4",
            localFrameIndex: 4, bookNodePresent: false, palmNodePresent: false), .unknownBodyFrame)
        XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(
            enabled: true, selectedID: selected, owned: true, actorID: "C_APPRENTICE",
            catalogAllowsActor: true, equippedBookGearID: "EQ_A_01", bodyAssetID: "LUNA_READING__0",
            localFrameIndex: 0, bookNodePresent: false, palmNodePresent: true), .inconsistentBookPresentation)
        XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(
            enabled: true, selectedID: selected, owned: true, actorID: "C_APPRENTICE",
            catalogAllowsActor: true, equippedBookGearID: "UNKNOWN", bodyAssetID: "LUNA_READING__0",
            localFrameIndex: 0, bookNodePresent: false, palmNodePresent: false), .unsupportedWeapon)
        for noncanonical in ["LUNA_READING__00", "LUNA_READING__+0", "LUNA_READING__ 0", "LUNA_READING__0 "] {
            XCTAssertNil(WardrobeCandidateResolverR128.lunaReadingIndex(noncanonical), noncanonical)
            XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(
                enabled: true, selectedID: selected, owned: true, actorID: "C_APPRENTICE",
                catalogAllowsActor: true, equippedBookGearID: "EQ_A_01", bodyAssetID: noncanonical,
                localFrameIndex: 0, bookNodePresent: false, palmNodePresent: false), .unknownBodyFrame)
        }
    }

    func testNoirExactFrameWhitelistIncludesRuntimeWalkMappingAndRejectsOthers() {
        XCTAssertTrue(WardrobeCandidateResolverR128.noirBodyPathSupported("GeneratedArt/PartyRest/NOIR__rest_04.png"))
        XCTAssertTrue(WardrobeCandidateResolverR128.noirBodyPathSupported("GeneratedArt/PartyAttack/NOIR__attack_04.png"))
        XCTAssertTrue(WardrobeCandidateResolverR128.noirBodyPathSupported("GeneratedArt/PartyWalk/NOIR__walk_2.png"))
        XCTAssertFalse(WardrobeCandidateResolverR128.noirBodyPathSupported("GeneratedArt/PartyWalk/NOIR__walk_1.png"))
        XCTAssertFalse(WardrobeCandidateResolverR128.noirBodyPathSupported("GeneratedArt/PartyAttack/NOIR__attack_09.png"))
    }
    func testSharedFactoryRejectsGameplayCatalogChangesAndPreservesBattle() async throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let extended = try WardrobeCandidateCatalogR128.extending(runtime.catalog)
        let initial = try runtime.makeNewSnapshot()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wardrobe-r128-shared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let baseRepo = try SaveRepository(initial: initial, fileURL: folder.appendingPathComponent("base.json"))
        let costumeRepo = try SaveRepository(initial: initial, fileURL: folder.appendingPathComponent("appearance.json"))
        let baseEngine = try runtime.makeEngine(saves: baseRepo)
        let costumeEngine = try runtime.makeEngine(saves: costumeRepo, appearanceCatalog: extended)
        for engine in [baseEngine, costumeEngine] {
            _ = try await engine.dispatch(.resolveEncounter(enemyID: "E_R01_02", seed: 128), operationID: UUID(), expectedRevision: 0)
        }
        let a = await baseEngine.snapshot(), b = await costumeEngine.snapshot()
        XCTAssertEqual(a.lastCombatResult, b.lastCombatResult)
        XCTAssertEqual(a.gear, b.gear); XCTAssertEqual(a.currency, b.currency); XCTAssertEqual(a.materials, b.materials)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(extended)) as? [String: Any])
        object["dailyFreeTicketGrant"] = 99
        let changed = try JSONDecoder().decode(GameCatalog.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try runtime.makeEngine(saves: baseRepo, appearanceCatalog: changed)) { error in
            guard case CoreError.invalidCatalog = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

}
