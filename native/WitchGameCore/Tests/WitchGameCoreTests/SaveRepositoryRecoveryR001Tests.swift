import Foundation
import CryptoKit
import XCTest
@testable import WitchGameCore

final class SaveRepositoryRecoveryR001Tests: XCTestCase {
    func testUnknownFieldsStayWithStableGearIDsAcrossReorderAndKnownMutation() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let catalog = try GameCatalog.bundledTestOverlay()
        var initial = GameSnapshot.newGame(catalog: catalog)
        let originalGearIDs = initial.gear.map { $0.id.uuidString }
        let repository = try SaveRepository(initial: initial, fileURL: url)
        _ = try await transact(repository, result: "seed")

        var root = try readJSON(url)
        root["futureEnvelopeField"] = ["opaque": "root"]
        var snapshot = try XCTUnwrap(root["snapshot"] as? [String: Any])
        snapshot["futureSnapshotField"] = ["opaque": 17]
        var currency = try XCTUnwrap(snapshot["currency"] as? [String: Any])
        currency["retired_currency_key"] = 77
        snapshot["currency"] = currency
        snapshot["selectedCosmeticIDs"] = ["C_WITCH": "ERNA_TRAVEL"]
        snapshot["selectedWeaponAppearanceIDs"] = ["C_WITCH": "STAFF_BRANCH"]
        snapshot["lastEncounterID"] = "OLD_ENCOUNTER"
        var gear = try XCTUnwrap(snapshot["gear"] as? [[String: Any]])
        XCTAssertEqual(gear.compactMap { $0["id"] as? String }, originalGearIDs)
        for index in gear.indices { gear[index]["futureGearField"] = "belongs-to-\(gear[index]["id"]!)" }
        gear.reverse()
        snapshot["gear"] = gear
        root["snapshot"] = snapshot
        try writeChecksummedJSON(root, to: url)

        let reopened = try SaveRepository(fileURL: url)
        _ = try await reopened.transact(expectedRevision: 1, operationID: UUID(), requestFingerprint: "mutate") {
            $0.currency["coin", default: 0] += 3
            $0.currency.removeValue(forKey: "retired_currency_key")
            $0.selectedCosmeticIDs.removeValue(forKey: "C_WITCH")
            $0.selectedWeaponAppearanceIDs.removeValue(forKey: "C_WITCH")
            $0.lastEncounterID = nil
            return "mutated"
        }

        let saved = try readJSON(url)
        XCTAssertEqual(saved["futureEnvelopeField"] as? [String: String], ["opaque": "root"])
        XCTAssertEqual(saved["integritySHA256"] as? String, try SaveDocumentCodec.checksum(for: saved))
        let savedSnapshot = try XCTUnwrap(saved["snapshot"] as? [String: Any])
        XCTAssertEqual(savedSnapshot["futureSnapshotField"] as? [String: Int], ["opaque": 17])
        XCTAssertNil((savedSnapshot["currency"] as? [String: Any])?["retired_currency_key"], "known dynamic-map removals must not be resurrected")
        XCTAssertNil((savedSnapshot["selectedCosmeticIDs"] as? [String: Any])?["C_WITCH"])
        XCTAssertNil((savedSnapshot["selectedWeaponAppearanceIDs"] as? [String: Any])?["C_WITCH"])
        XCTAssertNil(savedSnapshot["lastEncounterID"], "known optional-field clearing must remain a clearing")
        let savedGear = try XCTUnwrap(savedSnapshot["gear"] as? [[String: Any]])
        XCTAssertEqual(savedGear.compactMap { $0["id"] as? String }, Array(originalGearIDs.reversed()))
        for item in savedGear {
            let id = try XCTUnwrap(item["id"] as? String)
            XCTAssertEqual(item["futureGearField"] as? String, "belongs-to-\(id)")
        }
        initial = await reopened.snapshot()
        XCTAssertEqual(initial.gear.map { $0.id.uuidString }, Array(originalGearIDs.reversed()))
    }

    func testNestedFutureVersionMarkerRefusesWithoutUsingValidBackupOrChangingBytes() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let repository = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(repository, result: "generation-one")
        _ = try await transact(repository, result: "generation-two")
        let backupURL = url.appendingPathExtension("previous")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let backupBytes = try Data(contentsOf: backupURL)

        var root = try readJSON(url)
        var snapshot = try XCTUnwrap(root["snapshot"] as? [String: Any])
        snapshot["futureVersion"] = 999
        root["snapshot"] = snapshot
        let futureBytes = try jsonData(root)
        try futureBytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try SaveRepository(fileURL: url)) { error in
            guard let saveError = error as? SaveRepositoryError,
                  case .unsupportedFutureVersionMarker(let path, let value) = saveError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, "$.snapshot.futureVersion")
            XCTAssertEqual(value, 999)
        }
        XCTAssertEqual(try Data(contentsOf: url), futureBytes)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBytes, "valid backup remains untouched")
    }

    func testFutureEnvelopeSchemaNeverFallsBackToPreviousGeneration() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let repository = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(repository, result: "first")
        _ = try await transact(repository, result: "second")
        var root = try readJSON(url)
        root["schemaVersion"] = 999
        let bytes = try jsonData(root)
        try bytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try SaveRepository(fileURL: url)) { error in
            XCTAssertEqual(error as? SaveRepositoryError, .unsupportedFutureSchemaVersion(999))
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testMalformedDeclaredSchemaVersionFailsClosedWithoutChangingPrimary() throws {
        for rawVersion: Any in ["999", 1.5, NSNull(), NSNumber(value: true), NSNumber(value: Double.greatestFiniteMagnitude)] {
            let dir = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("save.json")
            var root: [String: Any] = ["snapshot": ["revision": 0], "receipts": [:]]
            root["schemaVersion"] = rawVersion
            let bytes = try jsonData(root)
            try bytes.write(to: url, options: .atomic)
            XCTAssertThrowsError(try SaveRepository(fileURL: url), "version=\(rawVersion)")
            XCTAssertEqual(try Data(contentsOf: url), bytes, "invalid schema metadata must not be rewritten")
        }
    }

    func testSchemaOneRequiresAllNonoptionalSnapshotFieldsAndDoesNotRewritePartialJSON() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let seed = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(seed, result: "schema-one-seed")
        let validBytes = try Data(contentsOf: url)
        var partial = try readJSON(url)
        var snapshot = try XCTUnwrap(partial["snapshot"] as? [String: Any])
        snapshot.removeValue(forKey: "gear")
        partial["snapshot"] = snapshot
        let bytes = try checksummedData(partial)
        try bytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try SaveRepository(fileURL: url))
        XCTAssertEqual(try Data(contentsOf: url), bytes)

        var nullRequired = try XCTUnwrap(JSONSerialization.jsonObject(with: validBytes) as? [String: Any])
        var nullSnapshot = try XCTUnwrap(nullRequired["snapshot"] as? [String: Any])
        nullSnapshot["gear"] = NSNull()
        nullRequired["snapshot"] = nullSnapshot
        let nullBytes = try checksummedData(nullRequired)
        try nullBytes.write(to: url, options: .atomic)
        XCTAssertThrowsError(try SaveRepository(fileURL: url), "a recomputed checksum must not make null required state valid")
        XCTAssertEqual(try Data(contentsOf: url), nullBytes)
    }

    func testValidJSONBitChangeFailsChecksumAndRecoversFromPreviousGeneration() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let seed = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(seed, result: "checksum-one")
        _ = try await transact(seed, result: "checksum-two")
        let backupURL = url.appendingPathExtension("previous")
        let backupBefore = try Data(contentsOf: backupURL)
        var changed = try readJSON(url)
        var snapshot = try XCTUnwrap(changed["snapshot"] as? [String: Any])
        var currency = try XCTUnwrap(snapshot["currency"] as? [String: Any])
        currency["coin"] = (currency["coin"] as? Int ?? 0) + 1
        snapshot["currency"] = currency
        changed["snapshot"] = snapshot
        let changedBytes = try jsonData(changed) // Valid JSON, stale checksum.
        try changedBytes.write(to: url, options: .atomic)

        let recovered = try SaveRepository(fileURL: url)
        let recoveryStatus = await recovered.recoveryStatus()
        XCTAssertEqual(recoveryStatus.source, .previousGeneration)
        XCTAssertEqual(try Data(contentsOf: url), changedBytes)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBefore)
        let recoveredSnapshot = await recovered.snapshot()
        XCTAssertEqual(recoveredSnapshot.currency["coin"], 0)
    }

    func testCorruptPrimaryAndPreviousRefuseWithoutOverwritingEitherGeneration() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let seed = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(seed, result: "both-corrupt-one")
        _ = try await transact(seed, result: "both-corrupt-two")
        let backupURL = url.appendingPathExtension("previous")
        var primary = try readJSON(url)
        var primarySnapshot = try XCTUnwrap(primary["snapshot"] as? [String: Any])
        primarySnapshot["gear"] = "invalid"
        primary["snapshot"] = primarySnapshot
        let primaryBytes = try jsonData(primary)
        var backup = try readJSON(backupURL)
        var backupSnapshot = try XCTUnwrap(backup["snapshot"] as? [String: Any])
        backupSnapshot["gear"] = "invalid"
        backup["snapshot"] = backupSnapshot
        let backupBytes = try jsonData(backup)
        try primaryBytes.write(to: url, options: .atomic)
        try backupBytes.write(to: backupURL, options: .atomic)

        XCTAssertThrowsError(try SaveRepository(fileURL: url)) { error in
            XCTAssertEqual(error as? SaveRepositoryError, .noValidRecoveryGeneration)
        }
        XCTAssertEqual(try Data(contentsOf: url), primaryBytes)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBytes)
    }

    func testLegacyPartialSnapshotStillUsesSchemaZeroDefaults() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let legacy = try jsonData(["snapshot": [:], "receipts": []])
        try legacy.write(to: url, options: .atomic)
        let repository = try SaveRepository(fileURL: url)
        let snapshot = await repository.snapshot()
        XCTAssertEqual(snapshot.revision, 0)
        XCTAssertEqual(snapshot.currency["coin"], 0)
        let status = await repository.recoveryStatus()
        XCTAssertEqual(status.source, .legacyMigrationPending)
        XCTAssertEqual(try Data(contentsOf: url), legacy)
    }

    func testFutureKnownPayloadVersionIsDetectedBeforeTypedDecodeOrBackupFallback() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let repository = try SaveRepository(initial: GameSnapshot.newGame(catalog: GameCatalog.bundledTestOverlay()), fileURL: url)
        _ = try await transact(repository, result: "known-payload-version")
        _ = try await transact(repository, result: "create-valid-backup")
        let backupURL = url.appendingPathExtension("previous")
        let backupBytes = try Data(contentsOf: backupURL)
        var root = try readJSON(url)
        var snapshot = try XCTUnwrap(root["snapshot"] as? [String: Any])
        var gear = try XCTUnwrap(snapshot["gear"] as? [[String: Any]])
        gear[0]["candidateLatentSlots"] = ["version": 2, "slots": []]
        snapshot["gear"] = gear
        root["snapshot"] = snapshot
        let futureBytes = try jsonData(root)
        try futureBytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try SaveRepository(fileURL: url)) { error in
            guard let saveError = error as? SaveRepositoryError,
                  case .unsupportedFutureVersionMarker(let path, let value) = saveError else {
                return XCTFail("typed decoder must not hide a future payload version: \(error)")
            }
            XCTAssertTrue(path.contains("candidateLatentSlots.version"))
            XCTAssertEqual(value, 2)
        }
        XCTAssertEqual(try Data(contentsOf: url), futureBytes)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBytes)
    }

    func testMalformedKnownNestedVersionMarkerRefusesBackupFallback() async throws {
        for marker: Any in ["two", 1.25, NSNumber(value: true)] {
            let dir = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("save.json")
            let seed = try SaveRepository(initial: GameSnapshot.newGame(catalog: GameCatalog.bundledTestOverlay()), fileURL: url)
            _ = try await transact(seed, result: "seed")
            _ = try await transact(seed, result: "backup")
            var root = try readJSON(url)
            var snapshot = try XCTUnwrap(root["snapshot"] as? [String: Any])
            var gear = try XCTUnwrap(snapshot["gear"] as? [[String: Any]])
            gear[0]["candidateLatentSlots"] = ["version": marker, "slots": []]
            snapshot["gear"] = gear
            root["snapshot"] = snapshot
            let bytes = try jsonData(root)
            try bytes.write(to: url, options: .atomic)
            let backupBytes = try Data(contentsOf: url.appendingPathExtension("previous"))

            XCTAssertThrowsError(try SaveRepository(fileURL: url), "marker=\(marker)")
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("previous")), backupBytes)
        }
    }

    func testInvalidReceiptIdentityOrFutureRevisionTriggersProtectedBackupRecovery() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let repository = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        let operationID = UUID(uuidString: "7a000000-0000-4000-8000-000000000021")!
        _ = try await repository.transact(expectedRevision: 0, operationID: operationID,
                                          requestFingerprint: "receipt-one") { _ in "receipt-one" }
        _ = try await transact(repository, result: "receipt-two")
        let backupURL = url.appendingPathExtension("previous")
        let backupBytes = try Data(contentsOf: backupURL)

        var root = try readJSON(url)
        var receipts = try XCTUnwrap(root["receipts"] as? [Any])
        XCTAssertGreaterThanOrEqual(receipts.count, 2)
        var receipt = try XCTUnwrap(receipts[1] as? [String: Any])
        receipt["revision"] = 99
        receipts[1] = receipt
        root["receipts"] = receipts
        let invalidBytes = try checksummedData(root)
        try invalidBytes.write(to: url, options: .atomic)

        let recovered = try SaveRepository(fileURL: url)
        let status = await recovered.recoveryStatus()
        XCTAssertEqual(status.source, .previousGeneration)
        XCTAssertEqual(status.loadedRevision, 1)
        XCTAssertEqual(status.rejectedPrimaryRevision, 2)
        XCTAssertEqual(try Data(contentsOf: url), invalidBytes)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBytes)
        let receiptFromBackup = await recovered.receipt(for: operationID)
        XCTAssertNotNil(receiptFromBackup)
    }

    func testReceiptDictionaryKeyMustMatchReceiptOperationID() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let repository = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(repository, result: "first")
        _ = try await transact(repository, result: "second")
        var root = try readJSON(url)
        var receipts = try XCTUnwrap(root["receipts"] as? [Any])
        XCTAssertGreaterThanOrEqual(receipts.count, 2)
        let receipt = try XCTUnwrap(receipts[1])
        let receiptObject = try XCTUnwrap(receipt as? [String: Any])
        let receiptOperationID = try XCTUnwrap(receiptObject["operationID"] as? String)
        var wrongKey = UUID().uuidString
        while wrongKey == receiptOperationID { wrongKey = UUID().uuidString }
        receipts[0] = wrongKey
        root["receipts"] = receipts
        let bytes = try checksummedData(root)
        try bytes.write(to: url, options: .atomic)

        let recovered = try SaveRepository(fileURL: url)
        let status = await recovered.recoveryStatus()
        XCTAssertEqual(status.source, .previousGeneration)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testLegacyMissingEnvelopeMetadataMigratesOnlyOnSuccessfulWrite() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let repository = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(repository, result: "legacy-source")
        var legacy = try readJSON(url)
        legacy.removeValue(forKey: "schemaVersion")
        legacy.removeValue(forKey: "generation")
        legacy.removeValue(forKey: "integritySHA256")
        legacy["legacyOpaque"] = ["keep": true]
        let legacyBytes = try jsonData(legacy)
        try legacyBytes.write(to: url, options: .atomic)

        let reopened = try SaveRepository(fileURL: url)
        let status = await reopened.recoveryStatus()
        XCTAssertEqual(status.source, .legacyMigrationPending)
        XCTAssertEqual(try Data(contentsOf: url), legacyBytes, "read-only load must preserve exact legacy bytes")
        _ = try await transact(reopened, result: "migration-write")
        let migrated = try readJSON(url)
        XCTAssertEqual(migrated["schemaVersion"] as? Int, 1)
        XCTAssertEqual(migrated["generation"] as? Int, 1)
        XCTAssertEqual(migrated["legacyOpaque"] as? [String: Bool], ["keep": true])
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("previous")), legacyBytes)
    }

    func testCorruptPrimaryReportsRollbackAndArchivesExactBytesOnSuccessfulRecoveryWrite() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let repository = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        let firstOperationID = UUID(uuidString: "7a000000-0000-4000-8000-000000000001")!
        _ = try await repository.transact(expectedRevision: 0, operationID: firstOperationID,
                                          requestFingerprint: "revision-one") { _ in "revision-one" }
        _ = try await transact(repository, result: "revision-two")
        let validLatest = try readJSON(url)
        let latestSnapshot = try XCTUnwrap(validLatest["snapshot"] as? [String: Any])
        let latestRevision = try XCTUnwrap(latestSnapshot["revision"] as? Int)
        var damagedRoot = validLatest
        var damagedSnapshot = latestSnapshot
        damagedSnapshot["gear"] = "not-an-array" // recognizable revision, invalid typed save
        damagedRoot["snapshot"] = damagedSnapshot
        let damaged = try jsonData(damagedRoot)
        try damaged.write(to: url, options: .atomic)

        let recovered = try SaveRepository(fileURL: url)
        let statusBefore = await recovered.recoveryStatus()
        XCTAssertEqual(statusBefore.source, .previousGeneration)
        XCTAssertEqual(statusBefore.rejectedPrimaryRevision, Int64(latestRevision))
        XCTAssertEqual(statusBefore.rejectedPrimaryByteCount, damaged.count)
        XCTAssertGreaterThan(statusBefore.possibleRevisionRollback ?? 0, 0)
        XCTAssertNil(statusBefore.preservedRejectedPrimaryFilename)
        XCTAssertEqual(try Data(contentsOf: url), damaged, "opening a recovered save must not rewrite either generation")
        let priorReceiptValue = await recovered.receipt(for: firstOperationID)
        let priorReceipt = try XCTUnwrap(priorReceiptValue)
        XCTAssertEqual(priorReceipt.result, "revision-one", "backup generation retains the prior dedupe receipt")

        let recoveredOperationID = UUID()
        let recoveredRevision = statusBefore.loadedRevision
        _ = try await recovered.transact(expectedRevision: recoveredRevision, operationID: recoveredOperationID,
                                         requestFingerprint: "after-recovery") { _ in "after-recovery" }
        let statusAfter = await recovered.recoveryStatus()
        XCTAssertEqual(statusAfter.source, .primary)
        XCTAssertNotNil(statusAfter.preservedRejectedPrimaryFilename)
        XCTAssertEqual(statusAfter.rejectedPrimaryByteCount, damaged.count)
        let preservedURL = dir.appendingPathComponent(try XCTUnwrap(statusAfter.preservedRejectedPrimaryFilename))
        XCTAssertEqual(try Data(contentsOf: preservedURL), damaged)
        let reopened = try SaveRepository(fileURL: url)
        let reopenedSnapshot = await reopened.snapshot()
        XCTAssertEqual(reopenedSnapshot.revision, statusBefore.loadedRevision + 1)
        let reopenedStatus = await reopened.recoveryStatus()
        XCTAssertEqual(reopenedStatus.source, .primary)
        XCTAssertEqual(reopenedStatus.preservedRejectedPrimaryFilename, statusAfter.preservedRejectedPrimaryFilename)
        XCTAssertEqual(reopenedStatus.possibleRevisionRollback, statusBefore.possibleRevisionRollback)
        let reopenedReceipt = await reopened.receipt(for: recoveredOperationID)
        let recoveredReceipt = try XCTUnwrap(reopenedReceipt)
        XCTAssertEqual(recoveredReceipt.result, "after-recovery")
    }

    func testWriteFailureBeforeReplacePreservesBytesAndAfterReplaceIsDeduplicated() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let seed = try SaveRepository(initial: GameSnapshot(), fileURL: url)
        _ = try await transact(seed, result: "seed")
        let before = try Data(contentsOf: url)

        let beforeReplace = try SaveRepository(initial: GameSnapshot(), fileURL: url, faultInjector: { phase in
            if phase == .beforePrimaryReplace { throw SaveRepositoryError.injectedWriteFailure("before replace") }
        })
        do {
            _ = try await transact(beforeReplace, result: "must-not-commit")
            XCTFail("expected injected failure")
        } catch let error as SaveRepositoryError {
            XCTAssertEqual(error, .injectedWriteFailure("before replace"))
        }
        XCTAssertEqual(try Data(contentsOf: url), before)

        let operationID = UUID()
        let afterReplace = try SaveRepository(initial: GameSnapshot(), fileURL: url, faultInjector: { phase in
            if phase == .afterPrimaryReplace { throw SaveRepositoryError.injectedWriteFailure("after replace") }
        })
        do {
            _ = try await afterReplace.transact(expectedRevision: 1, operationID: operationID,
                                                requestFingerprint: "commit-once") { snapshot in
                snapshot.currency["coin", default: 0] += 9
                return "committed"
            }
            XCTFail("post-replace interruption must be surfaced as ambiguous commit")
        } catch let error as SaveRepositoryError {
            guard case .commitMayHaveSucceeded(let id, let revision) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(id, operationID)
            XCTAssertEqual(revision, 2)
        }
        let reopened = try SaveRepository(fileURL: url)
        let replay = try await reopened.transact(expectedRevision: 1, operationID: operationID,
                                                 requestFingerprint: "commit-once") { snapshot in
            snapshot.currency["coin", default: 0] += 9
            return "duplicate"
        }
        XCTAssertEqual(replay.revision, 2)
        XCTAssertEqual(replay.result, "committed")
        let reopenedState = await reopened.snapshot()
        XCTAssertEqual(reopenedState.currency["coin"], 9)
    }

    func testUnkeyedArrayWithOpaqueElementsFailsClosedOnPossibleReassociation() throws {
        let old: Any = [["label": "first", "unknown": 1], ["label": "second", "unknown": 2]]
        let modeled: Any = [["label": "second"], ["label": "first"]]
        let oldModelled: Any = [["label": "first"], ["label": "second"]]
        XCTAssertThrowsError(try SaveDocumentCodec.mergeOpaque(prior: old, priorModelled: oldModelled,
                                                               modeled: modeled, path: "$.fixture")) { error in
            XCTAssertEqual(error as? SaveRepositoryError, .unsafeOpaqueArrayMutation(path: "$.fixture"))
        }

        XCTAssertThrowsError(try SaveDocumentCodec.mergeOpaque(
            prior: [["label": "first", "unknown": 1], ["label": "opaque-tail", "unknown": 2]],
            priorModelled: [["label": "first"]], modeled: [], path: "$.fixture")) { error in
            XCTAssertEqual(error as? SaveRepositoryError, .unsafeOpaqueArrayMutation(path: "$.fixture"))
        }
    }

    func testSchemaZeroNegativeRevisionIsRejectedAtLoadWithoutRewritingInput() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("save.json")
        let bytes = Data("{\"snapshot\":{\"revision\":-1,\"materials\":{\"moss\":4}}}".utf8)
        try bytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try SaveRepository(fileURL: url))
        XCTAssertEqual(try Data(contentsOf: url), bytes, "invalid legacy state must remain untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("lock").path),
                       "load-time rejection occurs before acquiring a transaction lock")
    }

    private func transact(_ repository: SaveRepository, result: String) async throws -> CommandReceipt {
        let current = await repository.snapshot()
        return try await repository.transact(expectedRevision: current.revision, operationID: UUID(),
                                             requestFingerprint: result) { _ in result }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("save-recovery-r001-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try jsonData(object).write(to: url, options: .atomic)
    }

    private func writeChecksummedJSON(_ object: [String: Any], to url: URL) throws {
        try checksummedData(object).write(to: url, options: .atomic)
    }

    private func checksummedData(_ object: [String: Any]) throws -> Data {
        var payload = object
        payload.removeValue(forKey: "integritySHA256")
        let canonical = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .fragmentsAllowed])
        payload["integritySHA256"] = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return try jsonData(payload)
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

}
