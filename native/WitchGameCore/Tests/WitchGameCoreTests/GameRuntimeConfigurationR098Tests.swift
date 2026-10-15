import XCTest
@testable import WitchGameCore

final class GameRuntimeConfigurationR098Tests: XCTestCase {
    func testResolvedProfilePinsAppCandidateInputsAndStarterState() throws {
        let first = try GameRuntimeConfigurationR098.resolve()
        let second = try GameRuntimeConfigurationR098.resolve()

        XCTAssertEqual(first.profileID, "app-candidate-r098-v1-growth-500bp")
        XCTAssertEqual(first.profileVersion, 1)
        XCTAssertEqual(first.configurationFingerprint, second.configurationFingerprint)
        XCTAssertEqual(first.canonicalManifest, second.canonicalManifest)
        XCTAssertEqual(first.combatOverlay, .r014LocalCandidate)
        XCTAssertEqual(first.growth.strengthBP, 500)
        XCTAssertEqual(first.latentPolicySHA256.count, 64)
        XCTAssertEqual(first.catalogSHA256.count, 64)
        XCTAssertEqual(first.catalogSHA256, "bb218f0fe6b4b1a6037faa75ddb301ded27d7b9de070747bebf99a3e72209337")
        XCTAssertEqual(first.latentPolicySHA256, "59ae258fce8d2451b8dd3d3cdd78e494c069d040aa56146abb249398dbfb4109")
        XCTAssertEqual(first.summonPoolIDs, first.catalog.gear.map(\.id))
        XCTAssertEqual(first.sortedCatalogGearIDs, first.catalog.gear.map(\.id).sorted())
        XCTAssertEqual(first.summonPoolIDs.count, 33)
        XCTAssertEqual(first.catalog.gachaOddsBasisPoints, ["Q0": 3_500, "Q1": 4_000, "Q2": 2_000, "Q3": 400, "Q4": 100])
        XCTAssertEqual(first.catalog.dailyFreeTicketGrant, 5)

        let snapshot = try first.makeNewSnapshot()
        XCTAssertEqual(snapshot.partyActorIDs, ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"])
        XCTAssertEqual(snapshot.gear.count, 4)
        XCTAssertEqual(snapshot.gear.map(\.definitionID), ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"])
        XCTAssertTrue(snapshot.gear.allSatisfy { $0.protected && $0.candidateLatentSlots != nil })
        XCTAssertEqual(first.initialSnapshotSHA256.count, 64)
    }

    func testGrowthVariantsHaveDistinctProfilesAndInvalidValueFailsClosed() throws {
        let standard = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let zero = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 0)
        XCTAssertNotEqual(standard.profileID, zero.profileID)
        XCTAssertNotEqual(standard.configurationFingerprint, zero.configurationFingerprint)
        XCTAssertNotEqual(standard.canonicalManifest, zero.canonicalManifest)
        XCTAssertThrowsError(try GameRuntimeConfigurationR098.resolve(growthStrengthBP: -1))
        XCTAssertThrowsError(try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 501)) { error in
            XCTAssertEqual(error as? GameRuntimeConfigurationR098.ConfigurationError, .invalidGrowthStrengthBP(501))
        }
    }

    func testRunIdentityIsSeparateFromConfigurationFingerprint() throws {
        let configuration = try GameRuntimeConfigurationR098.resolve()
        let first = GameRuntimeConfigurationR098.runIdentity(seed: 10, virtualStartEpochSeconds: 1_792_000_000,
                                                              virtualDayCount: 30, operationIDPolicy: "sequence-v1",
                                                              gearUUIDPolicy: "snapshot-defined")
        let second = GameRuntimeConfigurationR098.runIdentity(seed: 11, virtualStartEpochSeconds: 1_792_000_000,
                                                               virtualDayCount: 30, operationIDPolicy: "sequence-v1",
                                                               gearUUIDPolicy: "snapshot-defined")
        XCTAssertNotEqual(first.seed, second.seed)
        XCTAssertEqual(configuration.configurationFingerprint, try GameRuntimeConfigurationR098.resolve().configurationFingerprint)
    }
}
