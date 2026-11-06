import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Isolated Core hypothesis only. Uses ordinary R098/R144 commands and a real fixed-seed first clear.
final class FirstCraftAidPersistenceR179Tests: XCTestCase {
    private let caseID = "R179-first-RC_EQ_F_01-cost-v1"

    @MainActor func testOnlyFirstSuccessfulCraftUsesOneOneAndNormalSixSixPersistsAfterReopen() async throws {
        guard ProcessInfo.processInfo.environment["WITCH_R179_CASE_ID"] == caseID,
              let path = ProcessInfo.processInfo.environment["WITCH_R179_EVIDENCE_ROOT"],
              path.hasPrefix("/"), !path.isEmpty else {
            throw CoreError.invalidCommand("R179 requires its explicitly prepared isolated evidence root")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue,
              !(try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false) else {
            throw CoreError.invalidCommand("R179 evidence root must be a pre-created non-linked directory")
        }
        let run = root.appendingPathComponent("first-craft", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: run.path) else {
            throw CoreError.invalidCommand("R179 first-craft evidence directory must be new")
        }
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: false)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func write<T: Encodable>(_ value: T, _ name: String) throws {
            try encoder.encode(value).write(to: run.appendingPathComponent(name), options: .withoutOverwriting)
        }
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

        let runtime = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let policy = try PartyWorkPolicyR144(baseProfileID: runtime.profileID,
            baseConfigurationFingerprint: runtime.configurationFingerprint)
        XCTAssertEqual(runtime.configurationFingerprint, "4b556e250948bd35ff31a7bdc9dbbc01a671e358565182f556ab1d8d3bf4efb0")
        let ordinaryInitial = try runtime.makeNewSnapshot()
        XCTAssertNil(ordinaryInitial.firstCraftAidEligibleR179)
        var initial = ordinaryInitial
        initial.firstCraftAidEligibleR179 = true
        var initialWithoutEligibility = initial
        initialWithoutEligibility.firstCraftAidEligibleR179 = nil
        XCTAssertEqual(initialWithoutEligibility, ordinaryInitial, "eligibility is the only fresh-snapshot difference")
        let saveURL = run.appendingPathComponent("primary.save.json")
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        func makeEngine(_ repo: SaveRepository) throws -> GameEngine {
            try runtime.makeSharedPartyWorkEngineR146(saves: repo, appearanceCatalog: nil,
                                                       firstCraftAidCapabilityR179: .enabled)
        }
        var engine = try makeEngine(store)
        let start: Int64 = 1_800_000_000
        var cursor = Date(timeIntervalSince1970: TimeInterval(start))
        var operation = 0
        func nextID() -> UUID {
            operation += 1
            return UUID(uuidString: String(format: "17900000-0000-4000-8000-%012d", operation))!
        }
        func dispatch(_ command: GameCommand, repo: SaveRepository, using engine: GameEngine) async throws -> CommandReceipt {
            let before = await repo.snapshot()
            return try await engine.dispatch(command, operationID: nextID(), expectedRevision: before.revision)
        }
        func choose(_ target: PartyWorkTargetR144, repo: SaveRepository) async throws -> CommandReceipt {
            let before = await repo.snapshot()
            return try await engine.setPartyWorkTargetR144(target, now: cursor,
                operationID: nextID(), expectedRevision: before.revision)
        }
        func claim(_ elapsedSeconds: Int, repo: SaveRepository, using engine: GameEngine) async throws -> CommandReceipt {
            cursor = cursor.addingTimeInterval(TimeInterval(elapsedSeconds))
            let before = await repo.snapshot()
            return try await engine.claimOffline(now: cursor, operationID: nextID(), expectedRevision: before.revision)
        }

        try write(initial, "initial-snapshot.json")
        let baselineURL = run.appendingPathComponent("baseline-primary.save.json")
        let baselineStore = try SaveRepository(initial: ordinaryInitial, fileURL: baselineURL)
        let baselineEngine = try runtime.makeSharedPartyWorkEngineR146(saves: baselineStore, appearanceCatalog: nil)
        XCTAssertEqual(baselineEngine.firstCraftAidCapabilityR179, .disabled)
        let baselineInitial = await baselineStore.snapshot()
        XCTAssertEqual(baselineInitial, ordinaryInitial)
        var baselineReceipts: [CommandReceipt] = []
        baselineReceipts.append(try await dispatch(.startExpeditionAt(regionID: "R01", now: cursor), repo: baselineStore, using: baselineEngine))
        baselineReceipts.append(try await dispatch(.resolveEncounter(enemyID: "E_R01_02", seed: 1002), repo: baselineStore, using: baselineEngine))
        let baselineBattle = await baselineStore.snapshot()
        XCTAssertTrue(baselineBattle.lastCombatResult?.won == true)
        baselineReceipts.append(try await baselineEngine.setPartyWorkTargetR144(.gather("M_R01_G1"), now: cursor,
            operationID: nextID(), expectedRevision: baselineBattle.revision))
        baselineReceipts.append(try await claim(301, repo: baselineStore, using: baselineEngine))
        let baselineAt301 = await baselineStore.snapshot()
        XCTAssertEqual(baselineAt301.materials["M_R01_G1", default: 0], 1)
        XCTAssertEqual(baselineAt301.materials["M_R01_E2", default: 0], 1)
        try assertProjectedCost(runtime.catalog, baselineAt301, capability: .disabled,
                                expected: FirstCraftCostProjectionR179.declaredBaseline, ready: false)
        let baselineBytes = try Data(contentsOf: baselineURL)
        do {
            _ = try await dispatch(.craftRecipe("RC_EQ_F_01"), repo: baselineStore, using: baselineEngine)
            XCTFail("default-off baseline still needs six of each material")
        } catch CoreError.insufficientResource(let message) {
            XCTAssertEqual(message, "insufficient M_R01_E2")
        }
        let baselineAfterRefusal = await baselineStore.snapshot()
        XCTAssertEqual(baselineAfterRefusal, baselineAt301)
        XCTAssertFalse(baselineAfterRefusal.craftedGearOnce)
        XCTAssertEqual(try Data(contentsOf: baselineURL), baselineBytes)
        try write(baselineAfterRefusal, "baseline-after-301s-refusal.json")
        try write(baselineReceipts, "baseline-accepted-command-receipts.json")
        cursor = Date(timeIntervalSince1970: TimeInterval(start))
        let startReceipt = try await dispatch(.startExpeditionAt(regionID: "R01", now: cursor), repo: store, using: engine)
        let battleReceipt = try await dispatch(.resolveEncounter(enemyID: "E_R01_02", seed: 1002), repo: store, using: engine)
        var acceptedReceipts = [startReceipt, battleReceipt]
        var current = await store.snapshot()
        XCTAssertTrue(battleReceipt.result.hasPrefix("VICTORY:"))
        XCTAssertTrue(current.completedEncounterIDs.contains("E_R01_02"))
        XCTAssertTrue(current.lastCombatResult?.won == true)
        XCTAssertEqual(current.materials["M_R01_E2", default: 0] - initial.materials["M_R01_E2", default: 0], 1,
                       "only the real fixed-seed first-clear reward supplies the first E2")
        XCTAssertFalse(current.craftedGearOnce)
        XCTAssertEqual(current.firstCraftAidEligibleR179, true)
        try assertProjectedCost(runtime.catalog, current, capability: .enabled,
                                expected: FirstCraftCostProjectionR179.eligibleFirstCraft, ready: false)
        try write(current, "after-first-clear.json")

        let bytesBeforeFirstFailure = try Data(contentsOf: saveURL)
        let stateBeforeFirstFailure = current
        do {
            _ = try await dispatch(.craftRecipe("RC_EQ_F_01"), repo: store, using: engine)
            XCTFail("one E2 but no G1 cannot craft")
        } catch CoreError.insufficientResource(let message) {
            XCTAssertEqual(message, "insufficient M_R01_G1")
        }
        let afterFirstFailure = await store.snapshot()
        XCTAssertEqual(afterFirstFailure, stateBeforeFirstFailure)
        XCTAssertEqual(try Data(contentsOf: saveURL), bytesBeforeFirstFailure)
        XCTAssertFalse(afterFirstFailure.craftedGearOnce, "failed craft must not consume the first-craft allowance")

        acceptedReceipts.append(try await choose(.gather("M_R01_G1"), repo: store))
        let firstClaim = try await claim(301, repo: store, using: engine)
        acceptedReceipts.append(firstClaim)
        XCTAssertTrue(firstClaim.result.contains("units=1"))
        current = await store.snapshot()
        XCTAssertEqual(current.materials["M_R01_G1", default: 0] - initial.materials["M_R01_G1", default: 0], 1)
        XCTAssertEqual(current.materials["M_R01_E2", default: 0] - initial.materials["M_R01_E2", default: 0], 1)
        try assertProjectedCost(runtime.catalog, current, capability: .enabled,
                                expected: FirstCraftCostProjectionR179.eligibleFirstCraft, ready: true)
        let revisionBeforeFirstCraft = current.revision
        let walletBeforeFirstCraft = current.currency
        let gearIDsBeforeFirstCraft = Set(current.gear.map(\.id))
        let firstCraft = try await dispatch(.craftRecipe("RC_EQ_F_01"), repo: store, using: engine)
        acceptedReceipts.append(firstCraft)
        XCTAssertTrue(firstCraft.result.hasPrefix("crafted: EQ_F_01"))
        current = await store.snapshot()
        XCTAssertTrue(current.craftedGearOnce)
        XCTAssertEqual(current.materials["M_R01_G1", default: 0], initial.materials["M_R01_G1", default: 0])
        XCTAssertEqual(current.materials["M_R01_E2", default: 0], initial.materials["M_R01_E2", default: 0])
        XCTAssertEqual(current.currency, walletBeforeFirstCraft)
        XCTAssertEqual(current.gear.filter { !gearIDsBeforeFirstCraft.contains($0.id) }.map(\.definitionID), ["EQ_F_01"])
        try write(current, "after-first-craft.json")
        let firstCraftBytes = try Data(contentsOf: saveURL)
        try firstCraftBytes.write(to: run.appendingPathComponent("first-craft-primary.bytes"), options: .withoutOverwriting)

        let duplicate = try await engine.dispatch(.craftRecipe("RC_EQ_F_01"),
            operationID: firstCraft.operationID, expectedRevision: revisionBeforeFirstCraft)
        XCTAssertEqual(duplicate, firstCraft)
        let afterDuplicate = await store.snapshot()
        XCTAssertEqual(afterDuplicate, current)
        XCTAssertEqual(try Data(contentsOf: saveURL), firstCraftBytes)
        XCTAssertEqual(current.firstCraftAidEligibleR179, true)
        try assertProjectedCost(runtime.catalog, current, capability: .enabled,
                                expected: FirstCraftCostProjectionR179.declaredBaseline, ready: false)
        let stateBeforeSecondFailure = current
        do {
            _ = try await dispatch(.craftRecipe("RC_EQ_F_01"), repo: store, using: engine)
            XCTFail("repeat craft must require normal 6/6 stock")
        } catch CoreError.insufficientResource(let message) {
            XCTAssertEqual(message, "insufficient M_R01_E2")
        }
        current = await store.snapshot()
        XCTAssertEqual(current, stateBeforeSecondFailure)
        XCTAssertEqual(try Data(contentsOf: saveURL), firstCraftBytes)

        let reopened = try SaveRepository(fileURL: saveURL)
        engine = try makeEngine(reopened)
        current = await reopened.snapshot()
        XCTAssertEqual(current, stateBeforeSecondFailure)
        XCTAssertTrue(current.craftedGearOnce, "successful first craft must remain spent after cold reopen")
        XCTAssertEqual(try Data(contentsOf: saveURL), firstCraftBytes)
        XCTAssertEqual(current.firstCraftAidEligibleR179, true)
        let coldDuplicate = try await engine.dispatch(.craftRecipe("RC_EQ_F_01"),
            operationID: firstCraft.operationID, expectedRevision: revisionBeforeFirstCraft)
        XCTAssertEqual(coldDuplicate, firstCraft)
        let afterColdDuplicate = await reopened.snapshot()
        XCTAssertEqual(afterColdDuplicate, current)
        XCTAssertEqual(try Data(contentsOf: saveURL), firstCraftBytes)
        let bytesBeforeReopenedFailure = try Data(contentsOf: saveURL)
        let stateBeforeReopenedFailure = current
        do {
            _ = try await dispatch(.craftRecipe("RC_EQ_F_01"), repo: reopened, using: engine)
            XCTFail("cold-reopened repeat cannot reuse the one-time cost")
        } catch CoreError.insufficientResource(let message) {
            XCTAssertEqual(message, "insufficient M_R01_E2")
        }
        current = await reopened.snapshot()
        XCTAssertEqual(current, stateBeforeReopenedFailure)
        XCTAssertEqual(try Data(contentsOf: saveURL), bytesBeforeReopenedFailure)
        try write(current, "cold-reopen-after-first-craft.json")

        // Earn repeat-craft stock through normal R144 work, never a material grant.
        acceptedReceipts.append(try await choose(.gather("M_R01_G1"), repo: reopened))
        let gatherReceipt = try await claim(1_801, repo: reopened, using: engine)
        acceptedReceipts.append(gatherReceipt)
        XCTAssertTrue(gatherReceipt.result.contains("units=6"))
        acceptedReceipts.append(try await choose(.investigate("E_R01_02"), repo: reopened))
        let investigateReceipt = try await claim(1_801, repo: reopened, using: engine)
        acceptedReceipts.append(investigateReceipt)
        XCTAssertTrue(investigateReceipt.result.contains("units=6"))
        current = await reopened.snapshot()
        XCTAssertEqual(current.materials["M_R01_G1", default: 0], 6)
        XCTAssertEqual(current.materials["M_R01_E2", default: 0], 6)
        XCTAssertTrue(current.craftedGearOnce)
        try assertProjectedCost(runtime.catalog, current, capability: .enabled,
                                expected: FirstCraftCostProjectionR179.declaredBaseline, ready: true)
        let gearIDsBeforeRepeat = Set(current.gear.map(\.id))
        let repeatCraft = try await dispatch(.craftRecipe("RC_EQ_F_01"), repo: reopened, using: engine)
        acceptedReceipts.append(repeatCraft)
        XCTAssertTrue(repeatCraft.result.hasPrefix("crafted: EQ_F_01"))
        current = await reopened.snapshot()
        XCTAssertEqual(current.materials["M_R01_G1", default: 0], 0)
        XCTAssertEqual(current.materials["M_R01_E2", default: 0], 0)
        XCTAssertEqual(current.currency, walletBeforeFirstCraft)
        XCTAssertEqual(current.gear.filter { !gearIDsBeforeRepeat.contains($0.id) }.map(\.definitionID), ["EQ_F_01"])
        XCTAssertTrue(current.completedEncounterIDs.contains("E_R01_02"))
        try write(current, "after-normal-cost-repeat-craft.json")
        let repeatBytes = try Data(contentsOf: saveURL)
        try repeatBytes.write(to: run.appendingPathComponent("repeat-craft-primary.bytes"), options: .withoutOverwriting)
        let finalRepository = try SaveRepository(fileURL: saveURL)
        let finalEngine = try makeEngine(finalRepository)
        let finalSnapshot = await finalEngine.snapshot()
        XCTAssertEqual(finalSnapshot, current)
        XCTAssertEqual(try Data(contentsOf: saveURL), repeatBytes)
        try write(finalSnapshot, "cold-reopen-after-repeat-craft.json")
        try write(acceptedReceipts, "accepted-command-receipts.json")
        XCTAssertEqual(Set(acceptedReceipts.map(\.operationID)).count, acceptedReceipts.count)
        let report: [String: Any] = [
            "schema": "r179-first-craft-once-core-hypothesis-v1", "caseID": caseID,
            "profileID": runtime.profileID, "runtimeConfigurationFingerprint": runtime.configurationFingerprint,
            "sharedPolicyFingerprint": policy.policyFingerprint, "battle": ["enemyID": "E_R01_02", "seed": 1002, "realFirstClear": true],
            "firstCraftCosts": FirstCraftCostProjectionR179.eligibleFirstCraft, "repeatCraftCosts": FirstCraftCostProjectionR179.declaredBaseline,
            "firstCraftElapsedVirtualSeconds": 301, "repeatStockEarnedByR144Claims": ["G1": 6, "E2": 6],
            "craftedGearOnceSurvivesColdReopen": true, "currencyUnchangedByCrafts": current.currency == walletBeforeFirstCraft,
            "firstCraftPrimarySHA256": hash(firstCraftBytes), "repeatCraftPrimarySHA256": hash(repeatBytes),
            "candidateOnly": true, "balanceApproved": false, "coreCostProjectionVerified": true, "nativeUIVerified": false,
            "eligibilityOnlyInitialDifference": true, "duplicateCraftReplays": 2, "baselineDefaultOffRefusedAt301": true, "baselinePrimarySHA256": hash(baselineBytes),
            "candidateAcceptedCommands": acceptedReceipts.count, "candidateRefusals": 3,
            "baselineAcceptedCommands": baselineReceipts.count, "baselineRefusals": 1,
            "finalRevision": finalSnapshot.revision
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
            .write(to: root.appendingPathComponent("R179_RESULT.json"), options: .withoutOverwriting)
    }

    private func assertProjectedCost(_ catalog: GameCatalog, _ state: GameSnapshot,
                                     capability: FirstCraftAidCapabilityR179,
                                     expected: [String: Int], ready: Bool) throws {
        let goal = try XCTUnwrap(RecipeGoalProjectionR035.goals(catalog: catalog, state: state,
            firstCraftAidCapabilityR179: capability).first { $0.recipeID == "RC_EQ_F_01" })
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: goal.requirements.map { ($0.materialID, $0.required) }), expected)
        XCTAssertEqual(goal.ready, ready)
        // Projection-only tracked metadata; inventory, currency, progression and saved state are untouched.
        var tracked = state
        tracked.trackedRecipeID = "RC_EQ_F_01"
        let trackedGoal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: tracked,
            firstCraftAidCapabilityR179: capability))
        XCTAssertEqual(trackedGoal.requirements, goal.requirements)
        XCTAssertEqual(trackedGoal.ready, goal.ready)
    }

    private func newEvidenceDirectory(_ name: String) throws -> URL {
        guard ProcessInfo.processInfo.environment["WITCH_R179_CASE_ID"] == caseID,
              let path = ProcessInfo.processInfo.environment["WITCH_R179_EVIDENCE_ROOT"],
              path.hasPrefix("/"), !path.isEmpty else {
            throw CoreError.invalidCommand("R179 requires its explicitly prepared isolated evidence root")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CoreError.invalidCommand("R179 root must be a pre-created non-linked directory")
        }
        let directory = root.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw CoreError.invalidCommand("R179 evidence case must not overwrite an existing run")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func legacyFixture() throws -> Data {
        guard let path = ProcessInfo.processInfo.environment["WITCH_R179_LEGACY_FIXTURE"], path.hasPrefix("/") else {
            throw CoreError.invalidCommand("R179 requires its exact pre-R179 file-backed fixture")
        }
        let url = URL(fileURLWithPath: path)
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CoreError.invalidCommand("R179 fixture must not be linked")
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == "412568c60ce01030e4ab4fc348269c6014f692f1711326b30639229c3da93363" else {
            throw CoreError.invalidCommand("R179 existing-save fixture hash mismatch")
        }
        return data
    }

    @MainActor func testExistingPrimaryAndPreviousGenerationNeverAcquireFreshEligibility() async throws {
        let run = try newEvidenceDirectory("existing-save-recovery")
        let fixture = try legacyFixture()
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        XCTAssertEqual(raw["schemaVersion"] as? Int, 1)
        let oldSnapshot = try JSONDecoder().decode(GameSnapshot.self,
            from: JSONSerialization.data(withJSONObject: XCTUnwrap(raw["snapshot"])))
        XCTAssertNil(oldSnapshot.firstCraftAidEligibleR179)
        XCTAssertFalse(oldSnapshot.craftedGearOnce)
        XCTAssertEqual(oldSnapshot.materials["M_R01_G1"], 1)
        XCTAssertEqual(oldSnapshot.materials["M_R01_E2"], 1)
        let runtime = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        var eligibleInitial = try runtime.makeNewSnapshot()
        eligibleInitial.firstCraftAidEligibleR179 = true
        var rows: [[String: Any]] = []
        for mode in ["existing-primary", "missing-primary-valid-previous", "corrupt-primary-valid-previous"] {
            let directory = run.appendingPathComponent(mode, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let primary = directory.appendingPathComponent("primary.save.json")
            let previous = primary.appendingPathExtension("previous")
            let corrupt = Data("{R179 deliberate invalid JSON".utf8)
            if mode == "existing-primary" {
                try fixture.write(to: primary, options: .withoutOverwriting)
            } else {
                try fixture.write(to: previous, options: .withoutOverwriting)
                if mode == "corrupt-primary-valid-previous" {
                    try corrupt.write(to: primary, options: .withoutOverwriting)
                }
            }
            // Same initializer the absent-primary App route provides. A valid saved generation must win.
            let store = try SaveRepository(initial: eligibleInitial, fileURL: primary)
            let loaded = await store.snapshot()
            let recovery = await store.recoveryStatus()
            XCTAssertEqual(loaded, oldSnapshot)
            XCTAssertNil(loaded.firstCraftAidEligibleR179)
            XCTAssertEqual(recovery.source, mode == "existing-primary" ? .primary : .previousGeneration)
            try assertProjectedCost(runtime.catalog, loaded, capability: .enabled,
                                    expected: FirstCraftCostProjectionR179.declaredBaseline, ready: false)
            let engine = try runtime.makeSharedPartyWorkEngineR146(saves: store, appearanceCatalog: nil,
                                                                  firstCraftAidCapabilityR179: .enabled)
            do {
                _ = try await engine.dispatch(.craftRecipe("RC_EQ_F_01"), operationID: UUID(), expectedRevision: loaded.revision)
                XCTFail("old saves must not receive the new-save first-craft aid")
            } catch CoreError.insufficientResource(let message) {
                XCTAssertEqual(message, "insufficient M_R01_E2")
            }
            let afterRefusal = await store.snapshot()
            XCTAssertEqual(afterRefusal, loaded)
            if mode == "missing-primary-valid-previous" {
                XCTAssertFalse(FileManager.default.fileExists(atPath: primary.path))
            } else {
                XCTAssertEqual(try Data(contentsOf: primary), mode == "existing-primary" ? fixture : corrupt)
            }
            if mode != "existing-primary" { XCTAssertEqual(try Data(contentsOf: previous), fixture) }
            let receipt = try await engine.dispatch(.setTrackedRecipe("RC_EQ_F_01"),
                operationID: UUID(), expectedRevision: loaded.revision)
            let afterCommit = await store.snapshot()
            XCTAssertEqual(receipt.revision, loaded.revision + 1)
            XCTAssertNil(afterCommit.firstCraftAidEligibleR179)
            XCTAssertEqual(afterCommit.materials, loaded.materials)
            XCTAssertEqual(afterCommit.currency, loaded.currency)
            XCTAssertEqual(afterCommit.gear, loaded.gear)
            XCTAssertFalse(afterCommit.craftedGearOnce)
            XCTAssertEqual(afterCommit.trackedRecipeID, "RC_EQ_F_01")
            let recoveryAfterCommit = await store.recoveryStatus()
            var rejectedArchiveName: String? = nil
            if mode == "corrupt-primary-valid-previous" {
                let name = try XCTUnwrap(recoveryAfterCommit.preservedRejectedPrimaryFilename)
                XCTAssertTrue(name.hasPrefix("primary.save.json.corrupt-"))
                XCTAssertFalse(name.contains("/"), "archive must stay in the isolated save directory")
                let archive = directory.appendingPathComponent(name)
                XCTAssertEqual(try Data(contentsOf: archive), corrupt,
                               "recovery commit must preserve the exact rejected primary bytes")
                XCTAssertEqual(recoveryAfterCommit.rejectedPrimaryByteCount, corrupt.count)
                rejectedArchiveName = name
            } else {
                XCTAssertNil(recoveryAfterCommit.preservedRejectedPrimaryFilename)
            }
            let committedBytes = try Data(contentsOf: primary)
            let committedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: committedBytes) as? [String: Any])
            let committedSnapshot = try XCTUnwrap(committedObject["snapshot"] as? [String: Any])
            XCTAssertNil(committedSnapshot["firstCraftAidEligibleR179"], "old saves must keep the absent eligibility key")
            let cold = try SaveRepository(initial: eligibleInitial, fileURL: primary)
            let coldSnapshot = await cold.snapshot()
            XCTAssertEqual(coldSnapshot, afterCommit)
            XCTAssertEqual(try Data(contentsOf: primary), committedBytes)
            XCTAssertEqual(try Data(contentsOf: previous), fixture)
            let coldRecovery = await cold.recoveryStatus()
            XCTAssertEqual(coldRecovery.preservedRejectedPrimaryFilename, rejectedArchiveName)
            let archiveNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix("primary.save.json.corrupt-") }
            if let rejectedArchiveName {
                XCTAssertEqual(archiveNames, [rejectedArchiveName],
                               "cold read must not duplicate or discard the recovery archive")
                XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(rejectedArchiveName)), corrupt)
            } else {
                XCTAssertTrue(archiveNames.isEmpty)
            }
            try assertProjectedCost(runtime.catalog, coldSnapshot, capability: .enabled,
                                    expected: FirstCraftCostProjectionR179.declaredBaseline, ready: false)
            rows.append(["mode": mode, "initialRevision": loaded.revision, "committedRevision": afterCommit.revision,
                         "eligibilityGranted": false, "coldReopenExact": true, "refusalBytesPreserved": true,
                         "rejectedArchiveBytesVerified": mode == "corrupt-primary-valid-previous",
                         "rejectedArchiveCount": archiveNames.count])
        }
        XCTAssertEqual(try legacyFixture(), fixture)
        try JSONSerialization.data(withJSONObject: ["schema": "r179-existing-save-regression-v1", "cases": rows],
            options: [.sortedKeys, .prettyPrinted]).write(to: run.appendingPathComponent("RESULT.json"), options: .withoutOverwriting)
    }

    @MainActor func testUnrecoverableAndFuturePrimaryFailClosedWithoutFreshEligibilityFallback() async throws {
        let run = try newEvidenceDirectory("fail-closed")
        let fixture = try legacyFixture()
        let runtime = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        var eligibleInitial = try runtime.makeNewSnapshot()
        eligibleInitial.firstCraftAidEligibleR179 = true
        var rows: [[String: Any]] = []
        for mode in ["corrupt-no-previous", "future-primary-valid-previous"] {
            let directory = run.appendingPathComponent(mode, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let primary = directory.appendingPathComponent("primary.save.json")
            let previous = primary.appendingPathExtension("previous")
            let input: Data
            if mode == "future-primary-valid-previous" {
                var future = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
                future["schemaVersion"] = 2
                // Future-version refusal must precede checksum/fallback handling.
                input = try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
                try fixture.write(to: previous, options: .withoutOverwriting)
            } else {
                input = Data("{R179 deliberate unrecoverable JSON".utf8)
            }
            try input.write(to: primary, options: .withoutOverwriting)
            do {
                _ = try SaveRepository(initial: eligibleInitial, fileURL: primary)
                XCTFail("invalid/future saves must never become a fresh eligible save")
            } catch let error as SaveRepositoryError {
                XCTAssertEqual(error, mode == "future-primary-valid-previous" ? .unsupportedFutureSchemaVersion(2) : .invalidDocument)
            }
            XCTAssertEqual(try Data(contentsOf: primary), input)
            if mode == "future-primary-valid-previous" { XCTAssertEqual(try Data(contentsOf: previous), fixture) }
            let expectedNames = mode == "future-primary-valid-previous" ? ["primary.save.json", "primary.save.json.previous"] : ["primary.save.json"]
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), expectedNames)
            rows.append(["mode": mode, "refused": true, "inputBytesUnchanged": true])
        }
        XCTAssertEqual(try legacyFixture(), fixture)
        try JSONSerialization.data(withJSONObject: ["schema": "r179-fail-closed-regression-v1", "cases": rows],
            options: [.sortedKeys, .prettyPrinted]).write(to: run.appendingPathComponent("RESULT.json"), options: .withoutOverwriting)
    }
}
