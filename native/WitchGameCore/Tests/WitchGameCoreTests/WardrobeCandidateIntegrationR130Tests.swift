import XCTest
@testable import WitchGameCore

final class WardrobeCandidateIntegrationR130Tests: XCTestCase {
    private let uuid = "4c7254c0-a11a-4bb6-8a4f-c56f7d848e94"
    private var r128Args: [String] { ["WitchGathering", "--qa-isolated", "--qa-save-key=" + uuid,
        "--qa-wardrobe-candidate-r128", "--qa-luna-mantle-r097", "--qa-luna-mantle-offsets-r127", "--qa-noir-neckwear-r124"] }
    private var r130Args: [String] { r128Args + [WardrobeCandidateCatalogR130.flag] }

    func testExtraFlagIsAdditiveAndCatalogExtensionIsAppearanceOnly() throws {
        XCTAssertTrue(WardrobeCandidateCatalogR128.enabled(arguments: r128Args))
        XCTAssertFalse(WardrobeCandidateCatalogR130.enabled(arguments: r128Args))
        XCTAssertTrue(WardrobeCandidateCatalogR130.enabled(arguments: r130Args))
        XCTAssertFalse(WardrobeCandidateCatalogR130.enabled(arguments: ["WitchGathering", "--qa-isolated", "--qa-save-key=" + uuid, WardrobeCandidateCatalogR130.flag]))
        XCTAssertFalse(WardrobeCandidateCatalogR130.enabled(arguments: r128Args.filter { $0 != "--qa-noir-neckwear-r124" } + [WardrobeCandidateCatalogR130.flag]))
        let base = try GameRuntimeConfigurationR098.resolve().catalog
        let old = try WardrobeCandidateCatalogR128.extending(base)
        let newer = try WardrobeCandidateCatalogR130.extending(old)
        XCTAssertEqual(old.appearances.count, base.appearances.count + 2)
        XCTAssertEqual(newer.appearances.count, old.appearances.count + 1)
        XCTAssertTrue(newer.appearances.contains { $0.id == WardrobeCandidateResolverR128.lunaID })
        XCTAssertTrue(newer.appearances.contains { $0.id == WardrobeCandidateResolverR128.noirID })
        let apron = try XCTUnwrap(newer.appearances.first { $0.id == WardrobeCandidateCatalogR130.appearanceID })
        XCTAssertEqual(apron.kind, "costume"); XCTAssertEqual(apron.actorIDs, ["C_SMITH"])
        XCTAssertEqual(apron.status, "UNAPPROVED_LOCAL_QA_CANDIDATE_NOT_FOR_SALE")
        XCTAssertEqual(newer.gear.map(\.id), old.gear.map(\.id))
        XCTAssertEqual(newer.authority, old.authority)
        XCTAssertEqual(newer.gearAttackBonuses, old.gearAttackBonuses)
        XCTAssertEqual(newer.gearHPBonuses, old.gearHPBonuses)
        XCTAssertEqual(newer.gearDefenseBonuses, old.gearDefenseBonuses)
        XCTAssertEqual(newer.gachaOddsBasisPoints, old.gachaOddsBasisPoints)
    }

    func testSceneMetadataRequiresSelectionOwnershipActorCatalogAndR130Gate() throws {
        let base = try GameRuntimeConfigurationR098.resolve().catalog
        let candidate = try WardrobeCandidateCatalogR130.extending(WardrobeCandidateCatalogR128.extending(base))
        let selection = ["C_SMITH": WardrobeCandidateCatalogR130.appearanceID]
        let owned: Set<String> = [WardrobeCandidateCatalogR130.appearanceID]
        let stale = [WardrobeCandidateCatalogR130.sceneKey: WardrobeCandidateCatalogR130.appearanceID]
        XCTAssertNil(WardrobeCandidateCatalogR130.sceneMetadata(base: stale, selectedByActor: selection, ownedIDs: owned, catalog: candidate, arguments: r128Args)[WardrobeCandidateCatalogR130.sceneKey])
        XCTAssertNil(WardrobeCandidateCatalogR130.sceneMetadata(base: stale, selectedByActor: selection, ownedIDs: [], catalog: candidate, arguments: r130Args)[WardrobeCandidateCatalogR130.sceneKey])
        XCTAssertNil(WardrobeCandidateCatalogR130.sceneMetadata(base: stale, selectedByActor: ["C_WITCH": WardrobeCandidateCatalogR130.appearanceID], ownedIDs: owned, catalog: candidate, arguments: r130Args)[WardrobeCandidateCatalogR130.sceneKey])
        XCTAssertEqual(WardrobeCandidateCatalogR130.sceneMetadata(base: [:], selectedByActor: selection, ownedIDs: owned, catalog: candidate, arguments: r130Args)[WardrobeCandidateCatalogR130.sceneKey], WardrobeCandidateCatalogR130.appearanceID)
        XCTAssertEqual(WardrobeCandidateCatalogR130.sceneMetadata(base: stale, selectedByActor: [:], ownedIDs: [], catalog: candidate, arguments: r130Args), [:])
    }

    // Persistence is covered by WardrobeCandidatePersistenceR130SharedRuntimeTests
    // through the exact app runtime factory; the legacy default-engine candidate
    // remains preserved off-live for review.

    func testPreviewIsActorAwareAndReadOnly() {
        let base = ["C_WITCH":"ERNA_TRAVEL"]
        let result = WardrobeCandidateCatalogR130.preview(base: base, actorID: "C_SMITH", appearanceID: WardrobeCandidateCatalogR130.appearanceID, kind: "costume", enabled: true)
        XCTAssertEqual(result[WardrobeCandidateCatalogR130.sceneKey], WardrobeCandidateCatalogR130.appearanceID)
        XCTAssertEqual(base, ["C_WITCH":"ERNA_TRAVEL"])
        XCTAssertEqual(WardrobeCandidateCatalogR130.preview(base: result, actorID: "C_FAMILIAR", appearanceID: WardrobeCandidateCatalogR130.appearanceID, kind: "costume", enabled: true), base)
        XCTAssertEqual(WardrobeCandidateCatalogR130.preview(base: result, actorID: "C_SMITH", appearanceID: WardrobeCandidateCatalogR130.appearanceID, kind: "costume", enabled: false), base)
    }
}
