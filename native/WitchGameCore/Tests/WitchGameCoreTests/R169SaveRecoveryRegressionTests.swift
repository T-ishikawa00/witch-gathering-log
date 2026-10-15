import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Regresses save-target detection when a valid `.previous` exists without a primary.
/// All file inputs/outputs are confined to the caller-provided fresh evidence root.
final class R169SaveRecoveryRegressionTests: XCTestCase {
    private struct Evidence: Encodable {
        let schema: String
        let profileID: String
        let configurationFingerprint: String
        let initialSnapshotSHA256: String
        let memorySource: String
        let memoryRequiresExistingTarget: Bool
        let ordinarySaveSHA256: String
        let ordinaryReopenSource: String
        let ordinaryReopenSnapshotEqual: Bool
        let recoveryPrimaryAbsentBefore: Bool
        let recoverySource: String
        let recoveryRequiresExistingTarget: Bool
        let recoveredSnapshotEqual: Bool
        let sourcePrimarySHA256AfterRead: String
        let copiedPreviousSHA256AfterRead: String
        let revision: Int64
        let activeRegionID: String?
        let partyWorkTargetKind: String?
        let partyWorkTargetID: String?
        let lastClaimAt: Date?
        let offlineRemainderSeconds: TimeInterval
    }

    func testR169PreviousGenerationIsAnExistingSaveTarget() async throws {
        guard ProcessInfo.processInfo.environment["WITCH_R169_CASE_ID"] == "R169-previous-generation-existing-target-v1" else {
            throw XCTSkip("R169 requires its preregistered isolated Core case")
        }
        guard let rawRoot = ProcessInfo.processInfo.environment["WITCH_R169_EVIDENCE_ROOT"],
              rawRoot.hasPrefix("/"), !rawRoot.isEmpty else {
            throw CoreError.invalidCommand("WITCH_R169_EVIDENCE_ROOT must be an absolute existing directory")
        }
        let root = URL(fileURLWithPath: rawRoot, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard root.isFileURL, root.hasDirectoryPath, root.path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CoreError.invalidCommand("R169 evidence root must be an existing absolute directory")
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path), entries.isEmpty else {
            throw CoreError.invalidCommand("R169 evidence root must be empty before test output")
        }

        let runtime = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let policy = try PartyWorkPolicyR144(baseProfileID: runtime.profileID,
            baseConfigurationFingerprint: runtime.configurationFingerprint)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let initial = try runtime.makeNewSnapshot()
        let initialBytes = try encoder.encode(initial)
        let initialHash = Self.sha(initialBytes)

        func makeBranch(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }
        func persistWithoutOverwrite(_ data: Data, at url: URL) throws {
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw CoreError.invalidCommand("R169 evidence output already exists: \(url.lastPathComponent)")
            }
            try data.write(to: url, options: .withoutOverwriting)
        }
        try persistWithoutOverwrite(initialBytes, at: root.appendingPathComponent("initial_snapshot.json"))

        // A genuinely memory-backed fresh repository must not be mistaken for a save.
        let memoryRepository = try SaveRepository(initial: initial)
        let memoryStatus = await memoryRepository.recoveryStatus()
        XCTAssertEqual(memoryStatus.source, .memory)
        XCTAssertFalse(StandardPlayStartupSelectionR169.requiresExistingTarget(recoverySource: memoryStatus.source))

        // Create an ordinary R144 save only by issuing the real engine commands.
        let ordinaryDir = try makeBranch("ordinary_r144_save")
        let ordinaryURL = ordinaryDir.appendingPathComponent("save.json")
        let store = try SaveRepository(initial: initial, fileURL: ordinaryURL)
        let engine = try GameEngine(catalog: runtime.catalog, saves: store,
            candidateCombatOverlay: runtime.combatOverlay,
            candidateCharacterGrowth: runtime.growth,
            candidateLatentPolicy: runtime.latentPolicy,
            candidatePartyWorkPolicyR144: policy)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await engine.dispatch(.startExpeditionAt(regionID: "R01", now: start),
            operationID: UUID(uuidString: "16900000-0000-4000-8000-000000000001")!, expectedRevision: 0)
        var state = await store.snapshot()
        _ = try await engine.setPartyWorkTargetR144(.gather("M_R01_G1"),
            now: start, operationID: UUID(uuidString: "16900000-0000-4000-8000-000000000002")!,
            expectedRevision: state.revision)
        state = await store.snapshot()
        XCTAssertEqual(state.activeRegionID, "R01")
        XCTAssertEqual(state.partyWorkTargetR144?.kind, .gather)
        XCTAssertEqual(state.partyWorkTargetR144?.targetID, "M_R01_G1")
        let ordinaryBytes = try Data(contentsOf: ordinaryURL)
        let ordinaryHash = Self.sha(ordinaryBytes)
        try persistWithoutOverwrite(ordinaryBytes, at: ordinaryDir.appendingPathComponent("primary_before_reopen.bytes"))
        let reopenedOrdinary = try SaveRepository(fileURL: ordinaryURL)
        let ordinaryReopenedState = await reopenedOrdinary.snapshot()
        let ordinaryReopenStatus = await reopenedOrdinary.recoveryStatus()
        XCTAssertEqual(ordinaryReopenStatus.source, .primary)
        XCTAssertTrue(StandardPlayStartupSelectionR169.requiresExistingTarget(recoverySource: ordinaryReopenStatus.source))
        XCTAssertEqual(ordinaryReopenedState, state)
        XCTAssertEqual(try Data(contentsOf: ordinaryURL), ordinaryBytes, "ordinary cold reopen must not rewrite primary bytes")

        // Simulate only the actual filesystem shape: exact valid save bytes at `.previous`, no primary.
        let recoveryDir = try makeBranch("previous_only_recovery")
        let recoveryURL = recoveryDir.appendingPathComponent("save.json")
        let previousURL = recoveryURL.appendingPathExtension("previous")
        try persistWithoutOverwrite(ordinaryBytes, at: previousURL)
        let primaryAbsentBefore = !FileManager.default.fileExists(atPath: recoveryURL.path)
        XCTAssertTrue(primaryAbsentBefore)
        let copiedPreviousBefore = try Data(contentsOf: previousURL)
        let recovered = try SaveRepository(fileURL: recoveryURL)
        let recoveredStatus = await recovered.recoveryStatus()
        let recoveredState = await recovered.snapshot()
        XCTAssertEqual(recoveredStatus.source, .previousGeneration)
        XCTAssertTrue(StandardPlayStartupSelectionR169.requiresExistingTarget(recoverySource: recoveredStatus.source))
        XCTAssertEqual(recoveredState, state, "previous-generation recovery must preserve every snapshot field")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path), "read-only recovery must not silently create a primary")
        XCTAssertEqual(try Data(contentsOf: ordinaryURL), ordinaryBytes, "source primary must remain untouched")
        XCTAssertEqual(try Data(contentsOf: previousURL), copiedPreviousBefore, "copied previous generation must remain untouched")

        let recoverySnapshotBytes = try encoder.encode(recoveredState)
        try persistWithoutOverwrite(recoverySnapshotBytes, at: recoveryDir.appendingPathComponent("recovered_snapshot.json"))
        let evidence = Evidence(schema: "r169_previous_generation_existing_target_v1",
            profileID: runtime.profileID, configurationFingerprint: runtime.configurationFingerprint,
            initialSnapshotSHA256: initialHash, memorySource: memoryStatus.source.rawValue,
            memoryRequiresExistingTarget: StandardPlayStartupSelectionR169.requiresExistingTarget(recoverySource: memoryStatus.source),
            ordinarySaveSHA256: ordinaryHash, ordinaryReopenSource: ordinaryReopenStatus.source.rawValue,
            ordinaryReopenSnapshotEqual: ordinaryReopenedState == state,
            recoveryPrimaryAbsentBefore: primaryAbsentBefore, recoverySource: recoveredStatus.source.rawValue,
            recoveryRequiresExistingTarget: StandardPlayStartupSelectionR169.requiresExistingTarget(recoverySource: recoveredStatus.source),
            recoveredSnapshotEqual: recoveredState == state,
            sourcePrimarySHA256AfterRead: Self.sha(try Data(contentsOf: ordinaryURL)),
            copiedPreviousSHA256AfterRead: Self.sha(try Data(contentsOf: previousURL)),
            revision: recoveredState.revision, activeRegionID: recoveredState.activeRegionID,
            partyWorkTargetKind: recoveredState.partyWorkTargetR144?.kind.rawValue,
            partyWorkTargetID: recoveredState.partyWorkTargetR144?.targetID,
            lastClaimAt: recoveredState.lastClaimAt,
            offlineRemainderSeconds: recoveredState.offlineRemainderSeconds)
        try persistWithoutOverwrite(try encoder.encode(evidence), at: root.appendingPathComponent("R169_RECOVERY_RESULT.json"))
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
