import Foundation
import CryptoKit
import XCTest
@testable import WitchGameCore

final class StandardPlayWardrobeR170Tests: XCTestCase {
    private let qaArgs = [
        "--qa-isolated", "--qa-save-key=11111111-1111-4111-8111-111111111111",
        "--qa-wardrobe-candidate-r128", "--qa-luna-mantle-r097",
        "--qa-luna-mantle-offsets-r127", "--qa-noir-neckwear-r124"
    ]

    func testDevelopmentEnablementIsExplicitAndPreservesLegacyQAAndDefaultCatalogs() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let base = runtime.catalog
        XCTAssertFalse(WardrobeCandidateCatalogR128.enabled(arguments: [], developmentEnabled: false))
        XCTAssertFalse(WardrobeCandidateCatalogR130.enabled(arguments: [], developmentEnabled: false))
        XCTAssertTrue(WardrobeCandidateCatalogR128.enabled(arguments: qaArgs, developmentEnabled: false))
        XCTAssertTrue(WardrobeCandidateCatalogR130.enabled(arguments: qaArgs + [WardrobeCandidateCatalogR130.flag], developmentEnabled: false))
        XCTAssertTrue(WardrobeCandidateCatalogR128.enabled(arguments: [], developmentEnabled: true))
        XCTAssertTrue(WardrobeCandidateCatalogR130.enabled(arguments: [], developmentEnabled: true))
        XCTAssertFalse(base.appearances.contains { [WardrobeCandidateResolverR128.lunaID,
            WardrobeCandidateResolverR128.noirID, WardrobeCandidateCatalogR130.appearanceID].contains($0.id) })

        let r128 = try WardrobeCandidateCatalogR128.extending(base)
        let effective = try WardrobeCandidateCatalogR130.extending(r128)
        XCTAssertEqual(effective.appearances.suffix(3).map(\.id), [
            WardrobeCandidateResolverR128.lunaID,
            WardrobeCandidateResolverR128.noirID,
            WardrobeCandidateCatalogR130.appearanceID
        ])
        XCTAssertTrue(effective.appearances.suffix(3).allSatisfy { $0.status == "UNAPPROVED_LOCAL_QA_CANDIDATE_NOT_FOR_SALE" })
        XCTAssertEqual(effective.gear.map(\.id), base.gear.map(\.id))
        XCTAssertEqual(effective.furnitureIDs, base.furnitureIDs)
        XCTAssertEqual(effective.gachaOddsBasisPoints, base.gachaOddsBasisPoints)
        XCTAssertThrowsError(try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: true, isolatedR146GateEnabled: false, arguments: qaArgs))
    }

    func testSceneProjectionRequiresOwnedActorScopedCandidateAndKeepsLunaGearBranches() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let catalog = try WardrobeCandidateCatalogR130.extending(WardrobeCandidateCatalogR128.extending(runtime.catalog))
        let lunaID = WardrobeCandidateResolverR128.lunaID
        let noirID = WardrobeCandidateResolverR128.noirID
        let apronID = WardrobeCandidateCatalogR130.appearanceID
        let chosen: [String: String] = ["C_APPRENTICE": lunaID, "C_FAMILIAR": noirID, "C_SMITH": apronID]
        let owned = Set([lunaID, noirID, apronID])

        let ordinary = WardrobeCandidateResolverR128.sceneMetadata(
            base: [:], selectedByActor: chosen, ownedIDs: owned, catalog: catalog,
            arguments: [], developmentEnabled: false)
        XCTAssertNil(ordinary[WardrobeCandidateResolverR128.lunaSceneKey])
        XCTAssertNil(ordinary[WardrobeCandidateResolverR128.noirSceneKey])
        let dev = WardrobeCandidateResolverR128.sceneMetadata(
            base: [:], selectedByActor: chosen, ownedIDs: owned, catalog: catalog,
            arguments: [], developmentEnabled: true)
        XCTAssertEqual(dev[WardrobeCandidateResolverR128.lunaSceneKey], lunaID)
        XCTAssertEqual(dev[WardrobeCandidateResolverR128.lunaAppearanceKey], WardrobeCandidateResolverR128.lunaBooklessRenderValue)
        XCTAssertEqual(dev[WardrobeCandidateResolverR128.noirSceneKey], noirID)

        let wrongActor = WardrobeCandidateResolverR128.sceneMetadata(
            base: [:], selectedByActor: ["C_WITCH": lunaID], ownedIDs: owned, catalog: catalog,
            arguments: [], developmentEnabled: true)
        XCTAssertNil(wrongActor[WardrobeCandidateResolverR128.lunaSceneKey])
        let notOwned = WardrobeCandidateResolverR128.sceneMetadata(
            base: [:], selectedByActor: chosen, ownedIDs: [], catalog: catalog,
            arguments: [], developmentEnabled: true)
        XCTAssertNil(notOwned[WardrobeCandidateResolverR128.lunaSceneKey])

        let knownBook = WardrobeCandidateResolverR128.sceneMetadata(
            base: ["APPRENTICE_EQUIPPED_WEAPON_ID": "EQ_A_02"],
            selectedByActor: ["C_APPRENTICE": lunaID], ownedIDs: [lunaID], catalog: catalog,
            arguments: [], developmentEnabled: true)
        XCTAssertEqual(knownBook[WardrobeCandidateResolverR128.lunaAppearanceKey], WardrobeCandidateResolverR128.lunaValue)
        let unknownBook = WardrobeCandidateResolverR128.sceneMetadata(
            base: ["APPRENTICE_EQUIPPED_WEAPON_ID": "EQ_A_UNKNOWN"],
            selectedByActor: ["C_APPRENTICE": lunaID], ownedIDs: [lunaID], catalog: catalog,
            arguments: [], developmentEnabled: true)
        XCTAssertNil(unknownBook[WardrobeCandidateResolverR128.lunaSceneKey])
        XCTAssertEqual(WardrobeCandidateResolverR128.lunaRoute(
            enabled: true, selectedID: lunaID, owned: true, actorID: "C_APPRENTICE",
            catalogAllowsActor: true, equippedBookGearID: "EQ_A_UNKNOWN",
            bodyAssetID: "GeneratedArt/PartyRest/LUNA__rest_00.png", localFrameIndex: 0,
            bookNodePresent: true, palmNodePresent: true), .unsupportedWeapon)

        let wrongApron = WardrobeCandidateCatalogR130.sceneMetadata(
            base: [:], selectedByActor: ["C_APPRENTICE": apronID], ownedIDs: [apronID], catalog: catalog,
            arguments: [], developmentEnabled: true)
        XCTAssertNil(wrongApron[WardrobeCandidateCatalogR130.sceneKey])
        let validApron = WardrobeCandidateCatalogR130.sceneMetadata(
            base: [:], selectedByActor: ["C_SMITH": apronID], ownedIDs: [apronID], catalog: catalog,
            arguments: [], developmentEnabled: true)
        XCTAssertEqual(validApron[WardrobeCandidateCatalogR130.sceneKey], apronID)
    }

    @MainActor
    func testAllThreeCandidatesAndDeskPersistThroughSharedRuntimeWithoutGameplayChanges() async throws {
        guard ProcessInfo.processInfo.environment["WITCH_R170_CASE_ID"] == "R170-development-wardrobe-v1",
              let rawRoot = ProcessInfo.processInfo.environment["WITCH_R170_EVIDENCE_ROOT"],
              rawRoot.hasPrefix("/") else {
            throw CoreError.invalidCommand("R170 requires its exclusive bounded evidence root")
        }
        let root = URL(fileURLWithPath: rawRoot, isDirectory: true)
        guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else {
            throw CoreError.invalidCommand("R170 evidence root is not empty")
        }
        let runURL = root.appendingPathComponent("wardrobe", isDirectory: true)
        try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: false)
        func write(_ value: some Encodable, _ name: String) throws {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(value).write(to: runURL.appendingPathComponent(name), options: .withoutOverwriting)
        }
        func keep(_ data: Data, _ name: String) throws {
            try data.write(to: runURL.appendingPathComponent(name), options: .withoutOverwriting)
        }
        func sha(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let runtime = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let catalog = try WardrobeCandidateCatalogR130.extending(WardrobeCandidateCatalogR128.extending(runtime.catalog))
        let initial = try runtime.makeNewSnapshot()
        let url = runURL.appendingPathComponent("save.json")
        let repo = try SaveRepository(initial: initial, fileURL: url)
        let engine = try runtime.makeSharedPartyWorkEngineR146(saves: repo, appearanceCatalog: catalog)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var receipts: [CommandReceipt] = []
        receipts.append(try await engine.setPartyWorkTargetR144(.gather("M_R01_G1"), now: start,
            operationID: UUID(), expectedRevision: 0))
        let baseline = await engine.snapshot()
        XCTAssertEqual(baseline.partyWorkTargetR144, .gather("M_R01_G1"))
        XCTAssertEqual(baseline.lastClaimAt, start)
        try write(baseline, "baseline-snapshot.json")
        let baselineBytes = try Data(contentsOf: url)
        try keep(baselineBytes, "save-baseline.json")
        do {
            _ = try await engine.dispatch(.selectCosmetic(actorID: "C_APPRENTICE", cosmeticID: WardrobeCandidateResolverR128.lunaID), operationID: UUID(), expectedRevision: baseline.revision)
            XCTFail("Unowned candidate must reject")
        } catch { guard case CoreError.invalidCommand = error else { throw error } }
        let afterDenied = await engine.snapshot()
        XCTAssertEqual(afterDenied, baseline)
        XCTAssertEqual(try Data(contentsOf: url), baselineBytes)

        let entries = [("C_APPRENTICE", WardrobeCandidateResolverR128.lunaID),
                       ("C_FAMILIAR", WardrobeCandidateResolverR128.noirID),
                       ("C_SMITH", WardrobeCandidateCatalogR130.appearanceID)]
        var state = baseline
        for (actor, id) in entries {
            receipts.append(try await engine.dispatch(.setCosmetic(id, owned: true), operationID: UUID(), expectedRevision: state.revision))
            state = await engine.snapshot()
            receipts.append(try await engine.dispatch(.selectCosmetic(actorID: actor, cosmeticID: id), operationID: UUID(), expectedRevision: state.revision))
            state = await engine.snapshot()
        }
        var expected = baseline
        expected.revision += 6
        expected.ownedCosmeticIDs.formUnion(entries.map(\.1))
        var expectedCommerceOwnership = CommerceOwnershipProvenanceR1()
        for (_, id) in entries { expectedCommerceOwnership.adoptLegacyOwnership(cosmetics: [id], furniture: []) }
        expected.commerceOwnershipR1 = expectedCommerceOwnership
        for (actor, id) in entries { expected.selectedCosmeticIDs[actor] = id }
        XCTAssertEqual(state, expected, "Only appearance ownership/selection/revision may change")
        try write(state, "selected-snapshot.json")
        let selectedBytes = try Data(contentsOf: url)
        try keep(selectedBytes, "save-selected.json")
        do {
            _ = try await engine.dispatch(.selectCosmetic(actorID: "C_WITCH", cosmeticID: WardrobeCandidateResolverR128.lunaID), operationID: UUID(), expectedRevision: state.revision)
            XCTFail("Wrong-actor selection must reject")
        } catch { guard case CoreError.invalidCommand = error else { throw error } }
        let afterWrongActor = await engine.snapshot()
        XCTAssertEqual(afterWrongActor, expected)
        XCTAssertEqual(try Data(contentsOf: url), selectedBytes)

        let reopened = try SaveRepository(fileURL: url)
        let reopenedEngine = try runtime.makeSharedPartyWorkEngineR146(saves: reopened, appearanceCatalog: catalog)
        let coldSelected = await reopenedEngine.snapshot()
        XCTAssertEqual(coldSelected, expected)
        XCTAssertEqual(try Data(contentsOf: url), selectedBytes, "Read-only cold reopen cannot rewrite primary")
        try write(coldSelected, "cold-selected-snapshot.json")
        state = coldSelected
        for (index, entry) in entries.enumerated() {
            receipts.append(try await reopenedEngine.dispatch(.selectCosmetic(actorID: entry.0, cosmeticID: nil), operationID: UUID(), expectedRevision: state.revision))
            expected.revision += 1
            expected.selectedCosmeticIDs.removeValue(forKey: entry.0)
            state = await reopenedEngine.snapshot()
            XCTAssertEqual(state, expected, "Reset must preserve all other actors and every non-appearance field")
            try write(state, "reset-\(index)-snapshot.json")
        }
        let resetBytes = try Data(contentsOf: url)
        try keep(resetBytes, "save-reset.json")
        let resetRepository = try SaveRepository(fileURL: url)
        let resetEngine = try runtime.makeSharedPartyWorkEngineR146(saves: resetRepository, appearanceCatalog: catalog)
        let coldReset = await resetEngine.snapshot()
        XCTAssertEqual(coldReset, expected)
        XCTAssertEqual(try Data(contentsOf: url), resetBytes)
        try write(coldReset, "cold-reset-snapshot.json")

        let desk = "FURN_DESK_BOTANICAL"
        receipts.append(try await resetEngine.dispatch(.setFurniture(desk, owned: true), operationID: UUID(), expectedRevision: expected.revision))
        expected.revision += 1; expected.ownedFurnitureIDs.insert(desk)
        expectedCommerceOwnership.adoptLegacyOwnership(cosmetics: [], furniture: [desk])
        expected.commerceOwnershipR1 = expectedCommerceOwnership
        receipts.append(try await resetEngine.dispatch(.placeFurniture(desk, placed: true), operationID: UUID(), expectedRevision: expected.revision))
        expected.revision += 1; expected.placedFurnitureIDs.insert(desk)
        let deskState = await resetEngine.snapshot()
        XCTAssertEqual(deskState, expected)
        try write(deskState, "desk-placed-snapshot.json")
        let deskBytes = try Data(contentsOf: url)
        try keep(deskBytes, "save-desk-placed.json")
        let deskRepository = try SaveRepository(fileURL: url)
        let deskEngine = try runtime.makeSharedPartyWorkEngineR146(saves: deskRepository, appearanceCatalog: catalog)
        let coldDesk = await deskEngine.snapshot()
        XCTAssertEqual(coldDesk, expected)
        XCTAssertEqual(try Data(contentsOf: url), deskBytes)
        try write(coldDesk, "cold-desk-placed-snapshot.json")
        receipts.append(try await deskEngine.dispatch(.placeFurniture(desk, placed: false), operationID: UUID(), expectedRevision: expected.revision))
        expected.revision += 1; expected.placedFurnitureIDs.remove(desk)
        let packedDesk = await deskEngine.snapshot()
        XCTAssertEqual(packedDesk, expected)
        let packedBytes = try Data(contentsOf: url)
        try keep(packedBytes, "save-desk-packed.json")
        let finalRepository = try SaveRepository(fileURL: url)
        let final = await finalRepository.snapshot()
        XCTAssertEqual(final, expected)
        XCTAssertEqual(try Data(contentsOf: url), packedBytes)
        try write(final, "final-snapshot.json")
        try write(receipts, "command-receipts.json")
        let report: [String: Any] = [
            "schema": "r170-shared-wardrobe-lifecycle-v2", "caseID": "R170-development-wardrobe-v1",
            "factory": "makeSharedPartyWorkEngineR146", "candidateIDs": entries.map(\.1),
            "selectedActors": entries.map(\.0), "acceptedCommands": receipts.count,
            "rejectedCommands": 2, "baselineRevision": baseline.revision, "finalRevision": final.revision,
            "policyFingerprint": try PartyWorkPolicyR144(baseProfileID: runtime.profileID, baseConfigurationFingerprint: runtime.configurationFingerprint).policyFingerprint,
            "runtimeConfigurationFingerprint": runtime.configurationFingerprint,
            "baselineSaveSHA256": sha(baselineBytes), "selectedSaveSHA256": sha(selectedBytes),
            "resetSaveSHA256": sha(resetBytes), "deskPlacedSaveSHA256": sha(deskBytes),
            "finalSaveSHA256": sha(packedBytes), "coldReopenBytesUnchanged": true,
            "fullSnapshotAssertions": true, "nativeUIRun": false, "formalApproval": false
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        try reportData.write(to: root.appendingPathComponent("R170_RESULT.json"), options: .withoutOverwriting)
    }

    @MainActor
    func testSharedFactoryRejectsGameplayChangeInAppearanceCatalog() async throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let catalog = try WardrobeCandidateCatalogR130.extending(WardrobeCandidateCatalogR128.extending(runtime.catalog))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        object["dailyFreeTicketGrant"] = 99
        let changed = try JSONDecoder().decode(GameCatalog.self, from: JSONSerialization.data(withJSONObject: object))
        let repository = try SaveRepository(initial: runtime.makeNewSnapshot())
        XCTAssertThrowsError(try runtime.makeSharedPartyWorkEngineR146(saves: repository, appearanceCatalog: changed)) { error in
            guard case CoreError.invalidCatalog = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}

