import Foundation
import CryptoKit
import XCTest
@testable import WitchGameCore

/// Runs only when the host supplies a SHA-pinned R453 Python fixture. No StoreKit,
/// external account, or production authority is contacted by this test suite.
final class LocalPurchaseDeliveryQAImporterR453Tests: XCTestCase {
    private struct Fixture {
        let data: Data
        let sha256: String
        let root: [String: Any]
        let importer: LocalPurchaseDeliveryQAImporterR453
        let items: [GearInstance]
        let pityBefore: GachaPityState
        let pityAfter: GachaPityState
    }

    private actor CurrentFixtureProvider {
        private var data: Data?
        private var reads = 0
        init(_ data: Data) { self.data = data }
        func current() throws -> Data {
            reads += 1
            guard let data else { throw CoreError.invalidCommand("mock provider reports current refund/tombstone") }
            return data
        }
        func replace(_ value: Data?) { data = value }
        func readCount() -> Int { reads }
    }

    private var fixture: Fixture!
    private var catalog: GameCatalog!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["WITCH_R453_DELIVERY_FIXTURE"],
              let pinnedSHA = ProcessInfo.processInfo.environment["WITCH_R453_DELIVERY_FIXTURE_SHA256"] else {
            throw XCTSkip("Set WITCH_R453_DELIVERY_FIXTURE and its independently pinned WITCH_R453_DELIVERY_FIXTURE_SHA256")
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Self.sha256(data), pinnedSHA, "fixture bytes must match the host-pinned SHA")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let transaction = try XCTUnwrap(root["transaction"] as? [String: Any])
        let draw = try XCTUnwrap(root["drawReceipt"] as? [String: Any])
        let bundleID = try XCTUnwrap(transaction["bundleID"] as? String)
        let profileFingerprint = try XCTUnwrap(root["profileFingerprint"] as? String)
        let accountHash = try XCTUnwrap(draw["accountIDSHA256"] as? String)
        let tokenHash = try XCTUnwrap(transaction["appAccountTokenSHA256"] as? String)

        catalog = try GameCatalog.bundledTestOverlay()
        let importer = try LocalPurchaseDeliveryQAImporterR453(
            explicitIsolatedTestMode: true, catalog: catalog, bundleID: bundleID,
            profileFingerprint: profileFingerprint, accountHash: accountHash, tokenHash: tokenHash)
        let rawItems = try XCTUnwrap(root["gearInstances"] as? [[String: Any]])
        let items = try rawItems.map { row -> GearInstance in
            let rawID = try XCTUnwrap(row["id"] as? String)
            return GearInstance(id: try XCTUnwrap(UUID(uuidString: rawID)),
                definitionID: try XCTUnwrap(row["definitionID"] as? String),
                latentEffectID: row["latentEffectID"] as? String,
                qualityID: try XCTUnwrap(row["qualityID"] as? String),
                affixIDs: try XCTUnwrap(row["affixIDs"] as? [String]))
        }
        let rows = try XCTUnwrap(draw["draws"] as? [[String: Any]])
        let beforeRaw = try XCTUnwrap(rows.first?["pityBefore"])
        let before = try Self.decodePity(beforeRaw)
        let after = try Self.decodePity(try XCTUnwrap(root["postPityState"]))
        fixture = Fixture(data: data, sha256: pinnedSHA, root: root, importer: importer,
                          items: items, pityBefore: before, pityAfter: after)
    }

    func testPinnedFixtureImportsExactGearAndPityOnceAcrossColdReplay() async throws {
        let (folder, saveURL) = try makeTempSave("success")
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = baseline(pity: fixture.pityBefore)
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let provider = CurrentFixtureProvider(fixture.data)
        let operationID = try fixtureOperationID()

        let receipt = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: store) {
            try await provider.current()
        }
        XCTAssertEqual(receipt.operationID, operationID)
        XCTAssertEqual(receipt.revision, initial.revision + 1)
        let storedReceipt = await store.receipt(for: operationID)
        XCTAssertEqual(storedReceipt, receipt)
        let saved = await store.snapshot()
        var expected = initial
        expected.gear.append(contentsOf: fixture.items)
        expected.gachaPity = fixture.pityAfter
        expected.revision += 1
        XCTAssertEqual(saved, expected, "only gear, pity, and revision may change; currency/natural/work/other state must remain exact")
        XCTAssertEqual(saved.currency, initial.currency, "ticket currency stays outside Core")
        XCTAssertEqual(Array(saved.gear.suffix(fixture.items.count)), fixture.items)

        let savedBytes = try Data(contentsOf: saveURL)
        let reopened = try SaveRepository(fileURL: saveURL)
        let replayProvider = CurrentFixtureProvider(fixture.data)
        let replay = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: reopened) {
            try await replayProvider.current()
        }
        XCTAssertEqual(replay, receipt)
        let replayedSnapshot = await reopened.snapshot()
        XCTAssertEqual(replayedSnapshot, expected)
        XCTAssertEqual(try Data(contentsOf: saveURL), savedBytes, "same operation replay must not rewrite or duplicate the primary save")
        let providerReads = await replayProvider.readCount()
        XCTAssertEqual(providerReads, 1, "replay must consult the current authority provider")
    }

    func testBeforePrimaryReplaceFailureLeavesNoReceiptAndRetryCommitsOnce() async throws {
        let (folder, saveURL) = try makeTempSave("before-replace")
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = baseline(pity: fixture.pityBefore)
        let failing = try SaveRepository(initial: initial, fileURL: saveURL, faultInjector: { phase in
            if phase == .beforePrimaryReplace { throw SaveRepositoryError.injectedWriteFailure("R453 before primary replace") }
        })
        let operationID = try fixtureOperationID()
        let provider = CurrentFixtureProvider(fixture.data)
        do {
            _ = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: failing) { try await provider.current() }
            XCTFail("injected pre-replace failure must propagate")
        } catch let error as SaveRepositoryError {
            XCTAssertEqual(error, .injectedWriteFailure("R453 before primary replace"))
        }
        let failedSnapshot = await failing.snapshot()
        let failedReceipt = await failing.receipt(for: operationID)
        XCTAssertEqual(failedSnapshot, initial)
        XCTAssertNil(failedReceipt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path), "failed first write must not create a primary save")

        let retryStore = try SaveRepository(initial: initial, fileURL: saveURL)
        let retry = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: retryStore) { try await provider.current() }
        XCTAssertEqual(retry.revision, initial.revision + 1)
        let retrySnapshot = await retryStore.snapshot()
        let retryReceipt = await retryStore.receipt(for: operationID)
        XCTAssertEqual(retrySnapshot.gear.count, initial.gear.count + fixture.items.count)
        XCTAssertEqual(retryReceipt, retry)
    }

    func testAfterPrimaryReplaceAmbiguityColdReopenAndRetryDoNotDoubleApply() async throws {
        let (folder, saveURL) = try makeTempSave("after-replace")
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = baseline(pity: fixture.pityBefore)
        let operationID = try fixtureOperationID()
        let failing = try SaveRepository(initial: initial, fileURL: saveURL, faultInjector: { phase in
            if phase == .afterPrimaryReplace { throw SaveRepositoryError.injectedWriteFailure("R453 after primary replace") }
        })
        let provider = CurrentFixtureProvider(fixture.data)
        do {
            _ = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: failing) { try await provider.current() }
            XCTFail("post-replace fault must report ambiguous completion")
        } catch let error as SaveRepositoryError {
            guard case .commitMayHaveSucceeded(let id, let revision) = error else {
                return XCTFail("expected commitMayHaveSucceeded, got \(error)")
            }
            XCTAssertEqual(id, operationID)
            XCTAssertEqual(revision, initial.revision + 1)
        }

        let committedBytes = try Data(contentsOf: saveURL)
        let reopened = try SaveRepository(fileURL: saveURL)
        let committed = await reopened.snapshot()
        XCTAssertEqual(committed.revision, initial.revision + 1)
        XCTAssertEqual(committed.gear.count, initial.gear.count + fixture.items.count)
        let coldReceipt = await reopened.receipt(for: operationID)
        XCTAssertEqual(coldReceipt?.revision, committed.revision)

        let replay = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: reopened) { try await provider.current() }
        XCTAssertEqual(replay.operationID, operationID)
        XCTAssertEqual(replay.revision, committed.revision)
        let replaySnapshot = await reopened.snapshot()
        XCTAssertEqual(replaySnapshot, committed)
        XCTAssertEqual(try Data(contentsOf: saveURL), committedBytes)
    }

    func testCurrentRefundProviderIsRecheckedEvenForSavedOperationReplay() async throws {
        let (folder, saveURL) = try makeTempSave("refund-provider")
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = baseline(pity: fixture.pityBefore)
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let provider = CurrentFixtureProvider(fixture.data)
        _ = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: store) { try await provider.current() }
        let committed = await store.snapshot()
        let bytes = try Data(contentsOf: saveURL)

        await provider.replace(nil) // Represents the current provider's refund/tombstone response.
        do {
            _ = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: store) { try await provider.current() }
            XCTFail("a saved receipt must not bypass current refund/tombstone validation")
        } catch let error as CoreError {
            XCTAssertEqual(error, .invalidCommand("mock provider reports current refund/tombstone"))
        } catch {
            XCTFail("unexpected provider error: \(error)")
        }
        let providerReads = await provider.readCount()
        let afterRefundReplay = await store.snapshot()
        XCTAssertEqual(providerReads, 2)
        XCTAssertEqual(afterRefundReplay, committed)
        XCTAssertEqual(try Data(contentsOf: saveURL), bytes)
    }

    func testTamperedPayloadsAndSameUUIDChangedPayloadRejectWithoutSaveMutation() async throws {
        let (folder, saveURL) = try makeTempSave("tamper")
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = baseline(pity: fixture.pityBefore)
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))

        let fixtureData = fixture.data
        var badHash = fixture.sha256
        badHash.replaceSubrange(badHash.startIndex...badHash.startIndex, with: "0")
        if badHash == fixture.sha256 { badHash.replaceSubrange(badHash.startIndex...badHash.startIndex, with: "1") }
        do {
            _ = try await fixture.importer.apply(expectedFileSHA256: badHash, saves: store) { fixtureData }
            XCTFail("incorrect byte pin must reject")
        } catch { }
        var snapshotAfterBadHash = await store.snapshot()
        XCTAssertEqual(snapshotAfterBadHash, initial)

        let variants: [Data] = try [
            Self.mutate(fixture.root) { root in
                var tx = root["transaction"] as! [String: Any]; tx["bundleID"] = "other.bundle"; root["transaction"] = tx
            },
            Self.mutate(fixture.root) { root in
                var rows = root["gearInstances"] as! [[String: Any]]; rows[0]["definitionID"] = "UNKNOWN_GEAR"
                var draw = root["drawReceipt"] as! [String: Any]
                var draws = draw["draws"] as! [[String: Any]]
                draws[0]["gearTemplateID"] = "UNKNOWN_GEAR"
                draw["draws"] = draws; root["drawReceipt"] = draw
                Self.refreshDrawProvenanceFingerprints(root: &root)
                root["gearInstances"] = rows
            },
            Self.mutate(fixture.root) { root in
                var rows = root["gearInstances"] as! [[String: Any]]; rows[0].removeValue(forKey: "id"); root["gearInstances"] = rows
            },
            Self.mutate(fixture.root) { root in
                var rows = root["gearInstances"] as! [[String: Any]]
                guard rows.count > 1 else { return }
                let firstID = rows[0]["id"] as! String; rows[1]["id"] = firstID
                var provenance = root["gearProvenance"] as! [[String: Any]]; provenance[1]["gearID"] = firstID
                root["gearInstances"] = rows; root["gearProvenance"] = provenance
            }
        ]
        for data in variants {
            let expectedSHA = Self.sha256(data)
            do {
                _ = try await fixture.importer.apply(expectedFileSHA256: expectedSHA, saves: store) { data }
                XCTFail("tampered identity/gear payload must reject")
            } catch { }
            snapshotAfterBadHash = await store.snapshot()
            XCTAssertEqual(snapshotAfterBadHash, initial)
            let noReceipt = await store.receipt(for: try fixtureOperationID())
            XCTAssertNil(noReceipt)
        }

        let firstProvider = CurrentFixtureProvider(fixture.data)
        let first = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: store) { try await firstProvider.current() }
        let committed = await store.snapshot()
        let committedBytes = try Data(contentsOf: saveURL)
        let altered = try Self.mutate(fixture.root) { root in
            var items = root["gearInstances"] as! [[String: Any]]
            var affixes = items[0]["affixIDs"] as! [String]
            if affixes.contains("AFFIX_GUARD_TEST") { affixes.removeAll { $0 == "AFFIX_GUARD_TEST" } }
            else { affixes.append("AFFIX_GUARD_TEST") }
            items[0]["affixIDs"] = affixes; root["gearInstances"] = items
        }
        do {
            _ = try await fixture.importer.apply(expectedFileSHA256: Self.sha256(altered), saves: store) { altered }
            XCTFail("same operation UUID with different valid payload must collide")
        } catch let error as CoreError {
            XCTAssertEqual(error, .duplicateOperation)
        } catch {
            XCTFail("unexpected changed-payload replay error: \(error)")
        }
        let expectedOperationID = try fixtureOperationID()
        XCTAssertEqual(first.operationID, expectedOperationID)
        let snapshotAfterCollision = await store.snapshot()
        XCTAssertEqual(snapshotAfterCollision, committed)
        XCTAssertEqual(try Data(contentsOf: saveURL), committedBytes)
    }

    func testOutOfOrderPityRejectsWithoutSaveOrReceiptMutation() async throws {
        let (folder, saveURL) = try makeTempSave("pity-order")
        defer { try? FileManager.default.removeItem(at: folder) }
        var initial = baseline(pity: fixture.pityBefore)
        initial.gachaPity.drawsSinceMid = (fixture.pityBefore.drawsSinceMid + 1) % 20
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let operationID = try fixtureOperationID()
        let provider = CurrentFixtureProvider(fixture.data)
        do {
            _ = try await fixture.importer.apply(expectedFileSHA256: fixture.sha256, saves: store) { try await provider.current() }
            XCTFail("fixture with stale pity-before must reject")
        } catch { }
        let afterRejected = await store.snapshot()
        let noReceipt = await store.receipt(for: operationID)
        XCTAssertEqual(afterRejected, initial)
        XCTAssertNil(noReceipt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))
    }

    func testUnknownPityTargetsRejectAcrossDrawSequenceWithoutMutation() async throws {
        let (folder, saveURL) = try makeTempSave("unknown-pity-target")
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = baseline(pity: fixture.pityBefore)
        let store = try SaveRepository(initial: initial, fileURL: saveURL)
        let operationID = try fixtureOperationID()
        let invalidTarget = try Self.mutate(fixture.root) { root in
            var draw = root["drawReceipt"] as! [String: Any]
            var rows = draw["draws"] as! [[String: Any]]
            for index in rows.indices {
                for key in ["pityBefore", "pityAfter"] {
                    var pity = rows[index][key] as! [String: Any]
                    pity["targetTemplateID"] = "UNKNOWN_TEMPLATE"
                    rows[index][key] = pity
                }
            }
            var drawPity = draw["pityAfter"] as! [String: Any]
            drawPity["targetTemplateID"] = "UNKNOWN_TEMPLATE"
            draw["pityAfter"] = drawPity
            draw["draws"] = rows
            root["drawReceipt"] = draw
            var post = root["postPityState"] as! [String: Any]
            post["targetTemplateID"] = "UNKNOWN_TEMPLATE"
            root["postPityState"] = post
            Self.refreshDrawProvenanceFingerprints(root: &root)
        }

        do {
            _ = try await fixture.importer.apply(expectedFileSHA256: Self.sha256(invalidTarget), saves: store) { invalidTarget }
            XCTFail("unknown targets in any pity transition must reject")
        } catch { }
        let afterRejected = await store.snapshot()
        let receipt = await store.receipt(for: operationID)
        XCTAssertEqual(afterRejected, initial)
        XCTAssertNil(receipt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))
    }

    private func baseline(pity: GachaPityState) -> GameSnapshot {
        let equippedID = UUID(uuidString: "45000000-0000-4000-8000-000000000001")!
        var snapshot = GameSnapshot(revision: 0, currency: ["coin": 77, "ticket_free": 3, "ticket_paid_mock": 0],
            materials: ["M_R01_G1": 9], characterXP: ["C_WITCH": 41],
            gear: [GearInstance(id: equippedID, definitionID: "EQ_W_01", ownerID: "C_WITCH", protected: true)],
            unlockedRegionIDs: ["R01", "R02"], completedResearchIDs: ["RS_THEORY_1"],
            equippedGearIDs: ["C_WITCH:weapon": equippedID],
            ownedCosmeticIDs: ["ERNA_TRAVEL"], selectedCosmeticIDs: ["C_WITCH": "ERNA_TRAVEL"],
            ownedFurnitureIDs: ["FURN_DESK_BOTANICAL"], placedFurnitureIDs: ["FURN_DESK_BOTANICAL"],
            lastClaimAt: Date(timeIntervalSince1970: 1_800_000_000), offlineRemainderSeconds: 13.25,
            partyActorIDs: ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"],
            activeRegionID: "R02", gatherTargetMaterialID: "M_R02_G1", gachaPity: pity)
        snapshot.naturalGearDiscoveryR350 = NaturalGearDiscoveryLedgerR350(seedHex: String(repeating: "a", count: 64))
        return snapshot
    }

    private func fixtureOperationID() throws -> UUID {
        let raw = try XCTUnwrap(fixture.root["operationID"] as? String)
        return try XCTUnwrap(UUID(uuidString: raw))
    }

    private func makeTempSave(_ label: String) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("R453-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, folder.appendingPathComponent("save.json"))
    }

    private static func decodePity(_ raw: Any) throws -> GachaPityState {
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        return try JSONDecoder().decode(GachaPityState.self, from: data)
    }

    private static func mutate(_ original: [String: Any], _ body: (inout [String: Any]) -> Void) throws -> Data {
        var root = original
        body(&root)
        root.removeValue(forKey: "receiptFingerprint")
        let canonical = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        root["receiptFingerprint"] = sha256(canonical)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func refreshDrawProvenanceFingerprints(root: inout [String: Any]) {
        var draw = root["drawReceipt"] as! [String: Any]
        var rows = draw["draws"] as! [[String: Any]]
        var source = root["gearProvenance"] as! [[String: Any]]
        guard rows.count == source.count else { return }
        for index in rows.indices {
            let data = try! JSONSerialization.data(withJSONObject: rows[index], options: [.sortedKeys, .withoutEscapingSlashes])
            source[index]["drawRowFingerprint"] = sha256(data)
        }
        draw["draws"] = rows; root["drawReceipt"] = draw; root["gearProvenance"] = source
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
