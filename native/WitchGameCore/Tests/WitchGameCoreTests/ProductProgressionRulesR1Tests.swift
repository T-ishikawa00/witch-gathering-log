import XCTest
@testable import WitchGameCore

final class ProductProgressionRulesR1Tests: XCTestCase {
    func testCandidateManifestCapturesExistingRuntimeWithoutAdoptingIt() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let work = try PartyWorkPolicyR144(baseProfileID: runtime.profileID,
                                           baseConfigurationFingerprint: runtime.configurationFingerprint)
        let natural = NaturalGearDiscoveryPolicyR350()
        let refinement = NaturalGearRefinementPolicyR352()
        let dismantle = GearDismantleRefundPolicyR353()

        let manifest = try ProductProgressionRulesManifestR1.candidate(
            runtime: runtime, work: work, naturalGear: natural,
            refinement: refinement, dismantle: dismantle)

        XCTAssertEqual(manifest.schema, ProductProgressionRulesManifestR1.schema)
        XCTAssertEqual(manifest.runtimeProfileID, runtime.profileID)
        XCTAssertEqual(manifest.runtimeConfigurationFingerprint, runtime.configurationFingerprint)
        XCTAssertEqual(manifest.catalogSHA256, runtime.catalogSHA256)
        XCTAssertFalse(manifest.hasHumanApprovedRules)
        XCTAssertTrue(manifest.rules.allSatisfy { $0.disposition == .candidate && $0.approvalReference == nil })
        XCTAssertEqual(manifest.rules.first { $0.id == "runtime-growth" }?.values["strengthBasisPoints"],
                       String(runtime.growth.strengthBP))
        XCTAssertEqual(manifest.rules.first { $0.id == "natural-gear" }?.sourceFingerprint,
                       natural.policyFingerprint)
        XCTAssertEqual(manifest.rules.first { $0.id == "natural-gear" }?.values["workUnitsPerDrop"],
                       String(NaturalGearDiscoveryPolicyR350.workUnitsPerDrop))
        XCTAssertEqual(manifest.rules.first { $0.id == "dismantle-refund" }?.sourceFingerprint,
                       dismantle.policyFingerprint)
        XCTAssertEqual(try manifest.sha256(), try manifest.sha256(), "canonical manifest hash must be stable")
    }

    func testSharedProfileFactoryRecordsExactEnabledChainWithoutMigratingSaves() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let options = try StandardPlayRuntimeOptionsR1(standardPlayEnabled: true,
            sharedPartyWorkR144Enabled: true, firstCraftAidR179Enabled: true,
            enhancementR230Enabled: true, equipmentLoadoutsR342Enabled: true,
            naturalGearR350Enabled: true,
            refinementR352Enabled: true, dismantleRefundR353Enabled: true)
        let profile = try StandardPlayRuntimeProfileR1(base: runtime, options: options)
        XCTAssertEqual(profile.profileID,
            "app-candidate-r098-v1-growth-500bp-enhancement-r230-v1-natural-r350-v1-refinement-r352-v2-dismantle-r353-v2")
        XCTAssertNotNil(profile.partyWork)
        XCTAssertTrue(profile.firstCraftAid.isEnabled)
        XCTAssertTrue(try profile.makeNewSnapshot().firstCraftAidEligibleR179 == true)

        let manifest = try ProductProgressionRulesManifestR1.candidate(profile: profile)
        XCTAssertEqual(manifest.runtimeProfileID, profile.profileID)
        XCTAssertEqual(manifest.runtimeConfigurationFingerprint, profile.configurationFingerprint)
        XCTAssertEqual(manifest.runtimeOptions, options)
        XCTAssertFalse(manifest.hasHumanApprovedRules)
        XCTAssertEqual(manifest.rules.first { $0.id == "runtime-feature-gates" }?.values["naturalGearR350"], "true")
        XCTAssertEqual(manifest.rules.first { $0.id == "runtime-feature-gates" }?.values["equipmentLoadoutsR342"], "true")
        XCTAssertEqual(manifest.rules.first { $0.id == "first-craft-aid" }?.values["freshR169SaveEligibility"],
                       "stamped only by makeNewSnapshot; no save migration")

        let ordinary = try StandardPlayRuntimeProfileR1(base: runtime, options: .ordinary)
        XCTAssertFalse(try ordinary.makeNewSnapshot().firstCraftAidEligibleR179 == true)
        XCTAssertEqual(ordinary.profileID, runtime.profileID)
    }

    func testProfileOptionsRejectImpossibleCompileGateCombinations() {
        XCTAssertThrowsError(try StandardPlayRuntimeOptionsR1(naturalGearR350Enabled: true))
        XCTAssertThrowsError(try StandardPlayRuntimeOptionsR1(standardPlayEnabled: true,
            refinementR352Enabled: true))
        XCTAssertThrowsError(try StandardPlayRuntimeOptionsR1(standardPlayEnabled: true,
            naturalGearR350Enabled: true, dismantleRefundR353Enabled: true))
        XCTAssertNoThrow(try StandardPlayRuntimeOptionsR1(sharedPartyWorkR144Enabled: true),
                         "isolated R146/R144 QA is not the R169 standard-play build")
    }

    func testHumanApprovedDispositionRequiresExplicitReference() throws {
        XCTAssertThrowsError(try ProductRuleRecordR1(
            id: "gacha", disposition: .humanApproved, sourceProfileID: "profile",
            sourceFingerprint: "fingerprint", values: [:]))
        XCTAssertThrowsError(try ProductRuleRecordR1(
            id: "gacha", disposition: .candidate, sourceProfileID: "profile",
            sourceFingerprint: "fingerprint", values: [:], approvalReference: "unexpected"))

        let record = try ProductRuleRecordR1(
            id: "gacha", disposition: .humanApproved, sourceProfileID: "profile",
            sourceFingerprint: "fingerprint", values: [:], approvalReference: "human-record-01")
        XCTAssertEqual(record.approvalReference, "human-record-01")
    }

    func testNaturalAcquisitionProjectionDoesNotCountUnrelatedOrRemovedItems() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var state = GameSnapshot.newGame(catalog: catalog)
        let removedNaturalID = UUID(uuidString: "35000000-0000-4000-8000-000000000001")!
        let retainedNaturalID = UUID(uuidString: "35000000-0000-4000-8000-000000000002")!
        state.naturalGearDiscoveryR350 = NaturalGearDiscoveryLedgerR350(seedHex: String(repeating: "a", count: 64))
        state.naturalGearDiscoveryR350?.naturalRollIndex = 2
        state.naturalGearDiscoveryR350?.acquisitionRecords = [
            NaturalGearAcquisitionRecordR350(gearInstanceID: removedNaturalID, templateID: "EQ_W_01",
                sourceRegionID: "R01", attunementRank: 1, naturalRollIndex: 1,
                qualityID: "Q0", operationID: UUID(uuidString: "35000000-0000-4000-8000-000000000011")!),
            NaturalGearAcquisitionRecordR350(gearInstanceID: retainedNaturalID, templateID: "EQ_A_01",
                sourceRegionID: "R01", attunementRank: 1, naturalRollIndex: 2,
                qualityID: "Q2", operationID: UUID(uuidString: "35000000-0000-4000-8000-000000000012")!)
        ]
        state.gear.append(GearInstance(id: retainedNaturalID, definitionID: "EQ_A_01"))

        let projection = NaturalAcquisitionProjectionR1.project(state)

        XCTAssertEqual(projection.naturalRollIndex, 2)
        XCTAssertEqual(projection.retainedRecordCount, 2)
        XCTAssertEqual(projection.totalOwnedGear, 5)
        XCTAssertEqual(projection.naturalOwnedGearCount, 1)
        XCTAssertEqual(projection.qualityCounts, ["Q0": 1, "Q2": 1])
        XCTAssertEqual(projection.templateCounts, ["EQ_W_01": 1, "EQ_A_01": 1])
    }
}
