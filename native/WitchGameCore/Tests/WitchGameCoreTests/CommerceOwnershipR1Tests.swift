import Foundation
import CryptoKit
import XCTest
@testable import WitchGameCore

final class CommerceOwnershipR1Tests: XCTestCase {
    private let account = String(repeating: "a", count: 64)
    private let requestHash = String(repeating: "b", count: 64)
    private let now: Int64 = 1_800_000_000
    private let identity = CommerceAuthorityReceiptCandidateV1.Identity(
        environment: "Sandbox", bundleID: "com.example.game", transactionID: "txn-100",
        originalTransactionID: "txn-100", productID: "candidate.wardrobe", quantity: 1)

    func testLegacyFreeOwnershipSurvivesVerifiedGrantRevokeAndColdRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let catalog = GameCatalog(version: "commerce-test", regions: [], enemies: [], gear: [], research: [],
                                  appearances: [AppearanceDefinition(id: "paid-cosmetic", kind: "costume",
                                                                    actorIDs: ["C_WITCH"], status: "candidate")],
                                  furnitureIDs: ["paid-chair"])
        let legacy = GameSnapshot(ownedCosmeticIDs: ["free-cosmetic"],
                                  selectedCosmeticIDs: ["C_APPRENTICE": "free-cosmetic"],
                                  ownedFurnitureIDs: ["free-desk"], placedFurnitureIDs: ["free-desk"])
        let legacyReload = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(legacyReload.commerceOwnershipR1)
        XCTAssertEqual(legacyReload.ownedCosmeticIDs, ["free-cosmetic"])
        XCTAssertEqual(legacyReload.ownedFurnitureIDs, ["free-desk"])

        let grant = try signed(event: .grant, operation: UUID(), revision: 1,
                               grant: .init(entitlementID: "candidate.wardrobe", units: 1,
                                            expiresAtEpochSeconds: nil), key: key)
        let grantMutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: grant, expectedOperationID: UUID(uuidString: grant.operationID)!,
            expectedRequestSHA256: requestHash, expectedAccountBindingSHA256: account,
            expectedTransaction: identity, expectedKeyID: "test-key", publicKey: key.publicKey,
            nowEpochSeconds: now,
            contentByEntitlementID: ["candidate.wardrobe": (cosmeticIDs: ["paid-cosmetic"], furnitureIDs: ["paid-chair"])])
        var state = legacyReload
        try state.applyCommerceOwnershipR1(grantMutation, catalog: catalog, nowEpochSeconds: now)
        XCTAssertEqual(state.ownedCosmeticIDs, ["free-cosmetic", "paid-cosmetic"])
        XCTAssertEqual(state.ownedFurnitureIDs, ["free-desk", "paid-chair"])

        let cold = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(cold, state)
        XCTAssertEqual(cold.commerceOwnershipR1?.grants.count, 1)

        let revoke = try signed(event: .revoke, operation: UUID(), revision: 2, grant: nil, key: key)
        let revokeMutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: revoke, expectedOperationID: UUID(uuidString: revoke.operationID)!,
            expectedRequestSHA256: requestHash, expectedAccountBindingSHA256: account,
            expectedTransaction: identity, expectedKeyID: "test-key", publicKey: key.publicKey,
            nowEpochSeconds: now, contentByEntitlementID: [:])
        try state.applyCommerceOwnershipR1(revokeMutation, catalog: catalog, nowEpochSeconds: now)
        XCTAssertEqual(state.ownedCosmeticIDs, ["free-cosmetic"])
        XCTAssertEqual(state.ownedFurnitureIDs, ["free-desk"])
        XCTAssertEqual(state.selectedCosmeticIDs["C_APPRENTICE"], "free-cosmetic")
        XCTAssertEqual(state.placedFurnitureIDs, ["free-desk"])
        XCTAssertEqual(state.commerceOwnershipR1?.tombstones.map(\.transactionID), ["txn-100"])
        let revokedCold = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(revokedCold, state)

        XCTAssertNoThrow(try state.applyCommerceOwnershipR1(revokeMutation, catalog: catalog, nowEpochSeconds: now))
        XCTAssertEqual(state.ownedCosmeticIDs, ["free-cosmetic"])
        XCTAssertNoThrow(try state.applyCommerceOwnershipR1(grantMutation, catalog: catalog, nowEpochSeconds: now))
        XCTAssertEqual(state.ownedCosmeticIDs, ["free-cosmetic"])
    }

    func testExpiryReconciliationAndInvalidSignatureDoNotGrant() throws {
        let key = Curve25519.Signing.PrivateKey()
        let catalog = GameCatalog(version: "commerce-test", regions: [], enemies: [], gear: [], research: [],
                                  appearances: [AppearanceDefinition(id: "timed", kind: "accessory",
                                                                    actorIDs: ["C_WITCH"], status: "candidate")])
        let expiring = try signed(event: .grant, operation: UUID(), revision: 1,
                                  grant: .init(entitlementID: "candidate.temporary", units: 1,
                                               expiresAtEpochSeconds: now + 10), key: key)
        let mutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: expiring, expectedOperationID: UUID(uuidString: expiring.operationID)!,
            expectedRequestSHA256: requestHash, expectedAccountBindingSHA256: account,
            expectedTransaction: identity, expectedKeyID: "test-key", publicKey: key.publicKey,
            nowEpochSeconds: now,
            contentByEntitlementID: ["candidate.temporary": (cosmeticIDs: ["timed"], furnitureIDs: [])])
        var state = GameSnapshot()
        try state.applyCommerceOwnershipR1(mutation, catalog: catalog, nowEpochSeconds: now)
        XCTAssertEqual(state.ownedCosmeticIDs, ["timed"])
        state.reconcileCommerceOwnershipR1(nowEpochSeconds: now + 10)
        XCTAssertTrue(state.ownedCosmeticIDs.isEmpty)

        let bad = CommerceAuthorityReceiptCandidateV1(event: .grant,
            operationID: UUID(uuidString: expiring.operationID)!, requestSHA256: requestHash,
            accountBindingSHA256: account, revision: 1, transaction: identity,
            grant: .init(entitlementID: "candidate.temporary", units: 1, expiresAtEpochSeconds: nil),
            keyID: "test-key", signatureBase64: String(repeating: "A", count: 88))
        XCTAssertThrowsError(try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: bad, expectedOperationID: UUID(uuidString: bad.operationID)!,
            expectedRequestSHA256: requestHash, expectedAccountBindingSHA256: account,
            expectedTransaction: identity, expectedKeyID: "test-key", publicKey: key.publicKey,
            nowEpochSeconds: now,
            contentByEntitlementID: ["candidate.temporary": (cosmeticIDs: ["timed"], furnitureIDs: [])]))
        XCTAssertTrue(state.ownedCosmeticIDs.isEmpty)
    }

    func testOutOfOrderReceiptsAndLocalRevocationKeepServerWatermarkIndependent() throws {
        let key = Curve25519.Signing.PrivateKey()
        let catalog = GameCatalog(version: "commerce-order-test", regions: [], enemies: [], gear: [], research: [],
                                  appearances: [
                                    AppearanceDefinition(id: "older", kind: "costume", actorIDs: ["C_WITCH"], status: "candidate"),
                                    AppearanceDefinition(id: "newer", kind: "costume", actorIDs: ["C_WITCH"], status: "candidate"),
                                    AppearanceDefinition(id: "next", kind: "costume", actorIDs: ["C_WITCH"], status: "candidate")
                                  ])
        let newerIdentity = identityWithTransaction("txn-newer")
        let olderIdentity = identityWithTransaction("txn-older")
        let nextIdentity = identityWithTransaction("txn-next")
        let newer = try signed(event: .grant, operation: UUID(), revision: 10,
                               grant: .init(entitlementID: "candidate.newer", units: 1, expiresAtEpochSeconds: nil),
                               key: key, identity: newerIdentity)
        let older = try signed(event: .grant, operation: UUID(), revision: 9,
                               grant: .init(entitlementID: "candidate.older", units: 1, expiresAtEpochSeconds: nil),
                               key: key, identity: olderIdentity)
        let next = try signed(event: .grant, operation: UUID(), revision: 11,
                              grant: .init(entitlementID: "candidate.next", units: 1, expiresAtEpochSeconds: nil),
                              key: key, identity: nextIdentity)

        var ledger = try CommerceEntitlementLedgerCandidateV1(accountBindingSHA256: account)
        XCTAssertTrue(try apply(newer, to: &ledger, key: key, expected: newerIdentity))
        XCTAssertTrue(try apply(older, to: &ledger, key: key, expected: olderIdentity))
        XCTAssertEqual(ledger.revision, 10, "watermark must retain the greatest server revision")
        XCTAssertEqual(Set(ledger.entries.map(\.transactionID)), ["txn-newer", "txn-older"],
                       "an unseen, valid older receipt must not be lost")

        try ledger.applyingVerifiedStoreKitRevocation(
            transactionID: "txn-newer", proofFingerprint: String(repeating: "c", count: 64))
        XCTAssertEqual(ledger.revision, 10, "Apple revocation proof must not consume a server revision")
        XCTAssertEqual(ledger.tombstones.first(where: { $0.transactionID == "txn-newer" })?.revision, 0)
        XCTAssertEqual(Set(ledger.entries.map(\.transactionID)), ["txn-older"])
        XCTAssertTrue(try apply(next, to: &ledger, key: key, expected: nextIdentity),
                      "the next server revision remains applicable after a local revocation")
        XCTAssertEqual(ledger.revision, 11)

        let delayedGrant = try signed(event: .grant, operation: UUID(), revision: 12,
                                      grant: .init(entitlementID: "candidate.newer", units: 1, expiresAtEpochSeconds: nil),
                                      key: key, identity: newerIdentity)
        XCTAssertThrowsError(try apply(delayedGrant, to: &ledger, key: key, expected: newerIdentity),
                             "a delayed grant must not resurrect a locally revoked transaction")

        let content = [
            "candidate.newer": (cosmeticIDs: Set(["newer"]), furnitureIDs: Set<String>()),
            "candidate.older": (cosmeticIDs: Set(["older"]), furnitureIDs: Set<String>()),
            "candidate.next": (cosmeticIDs: Set(["next"]), furnitureIDs: Set<String>())
        ]
        var snapshot = GameSnapshot()
        for (receipt, transaction) in [(newer, newerIdentity), (older, olderIdentity)] {
            let mutation = try VerifiedCommerceOwnershipMutationR1.validate(
                receipt: receipt, expectedOperationID: UUID(uuidString: receipt.operationID)!,
                expectedRequestSHA256: requestHash, expectedAccountBindingSHA256: account,
                expectedTransaction: transaction, expectedKeyID: "test-key", publicKey: key.publicKey,
                nowEpochSeconds: now, contentByEntitlementID: content)
            try snapshot.applyCommerceOwnershipR1(mutation, catalog: catalog, nowEpochSeconds: now)
        }
        XCTAssertEqual(snapshot.commerceOwnershipR1?.authorityRevision, 10)
        XCTAssertEqual(snapshot.ownedCosmeticIDs, ["newer", "older"])
        let localRevoke = try VerifiedCommerceOwnershipMutationR1.verifiedStoreKitRevocation(
            transactionID: "txn-newer", proofFingerprint: String(repeating: "d", count: 64),
            authorityRevision: 0, operationID: UUID())
        try snapshot.applyCommerceOwnershipR1(localRevoke, catalog: catalog, nowEpochSeconds: now)
        XCTAssertEqual(snapshot.commerceOwnershipR1?.authorityRevision, 10)
        XCTAssertEqual(snapshot.ownedCosmeticIDs, ["older"])
        let nextMutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: next, expectedOperationID: UUID(uuidString: next.operationID)!,
            expectedRequestSHA256: requestHash, expectedAccountBindingSHA256: account,
            expectedTransaction: nextIdentity, expectedKeyID: "test-key", publicKey: key.publicKey,
            nowEpochSeconds: now, contentByEntitlementID: content)
        try snapshot.applyCommerceOwnershipR1(nextMutation, catalog: catalog, nowEpochSeconds: now)
        XCTAssertEqual(snapshot.commerceOwnershipR1?.authorityRevision, 11)
        XCTAssertEqual(snapshot.ownedCosmeticIDs, ["older", "next"])
    }

    func testSignedServerRevokeFollowsGrantForSameRequestOperation() throws {
        let key = Curve25519.Signing.PrivateKey()
        let transaction = identityWithTransaction("txn-grant-then-server-revoke")
        let operation = UUID()
        let grant = try signed(event: .grant, operation: operation, revision: 7,
                               grant: .init(entitlementID: "candidate.wardrobe", units: 1,
                                            expiresAtEpochSeconds: nil), key: key, identity: transaction)
        let revoke = try signed(event: .revoke, operation: operation, revision: 8,
                                grant: nil, key: key, identity: transaction)
        let content = ["candidate.wardrobe": (cosmeticIDs: Set(["paid-cosmetic"]), furnitureIDs: Set<String>())]
        let grantMutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: grant, expectedOperationID: operation, expectedRequestSHA256: requestHash,
            expectedAccountBindingSHA256: account, expectedTransaction: transaction,
            expectedKeyID: "test-key", publicKey: key.publicKey, nowEpochSeconds: now,
            contentByEntitlementID: content)
        let revokeMutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: revoke, expectedOperationID: operation, expectedRequestSHA256: requestHash,
            expectedAccountBindingSHA256: account, expectedTransaction: transaction,
            expectedKeyID: "test-key", publicKey: key.publicKey, nowEpochSeconds: now,
            contentByEntitlementID: content)
        XCTAssertNotEqual(grantMutation.durableOperationID, revokeMutation.durableOperationID)

        var ledger = try CommerceEntitlementLedgerCandidateV1(accountBindingSHA256: account)
        XCTAssertTrue(try apply(grant, to: &ledger, key: key, expected: transaction))
        XCTAssertTrue(try apply(revoke, to: &ledger, key: key, expected: transaction))
        XCTAssertEqual(ledger.revision, 8)
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertEqual(ledger.tombstones.first?.receiptFingerprint, revoke.receiptFingerprint)
        XCTAssertFalse(try apply(revoke, to: &ledger, key: key, expected: transaction),
                       "exact signed revoke replay is idempotent")

        var snapshot = GameSnapshot()
        try snapshot.applyCommerceOwnershipR1(grantMutation, catalog: GameCatalog(
            version: "commerce-revoke-test", regions: [], enemies: [], gear: [], research: [],
            appearances: [AppearanceDefinition(id: "paid-cosmetic", kind: "costume",
                                               actorIDs: ["C_WITCH"], status: "candidate")]),
            nowEpochSeconds: now)
        XCTAssertTrue(snapshot.ownedCosmeticIDs.contains("paid-cosmetic"))
        try snapshot.applyCommerceOwnershipR1(revokeMutation, catalog: GameCatalog(
            version: "commerce-revoke-test", regions: [], enemies: [], gear: [], research: [],
            appearances: [AppearanceDefinition(id: "paid-cosmetic", kind: "costume",
                                               actorIDs: ["C_WITCH"], status: "candidate")]),
            nowEpochSeconds: now)
        XCTAssertFalse(snapshot.ownedCosmeticIDs.contains("paid-cosmetic"))
        XCTAssertEqual(snapshot.commerceOwnershipR1?.authorityRevision, 8)
        XCTAssertNoThrow(try snapshot.applyCommerceOwnershipR1(revokeMutation,
            catalog: GameCatalog(version: "commerce-revoke-test", regions: [], enemies: [], gear: [], research: [],
                                 appearances: [AppearanceDefinition(id: "paid-cosmetic", kind: "costume",
                                                                    actorIDs: ["C_WITCH"], status: "candidate")]),
            nowEpochSeconds: now))
    }

    func testVerifiedOwnershipDispatchPersistsBeforeColdReload() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let appearance = try XCTUnwrap(catalog.appearances.first)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("commerce-ownership-r1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saveURL = directory.appendingPathComponent("save.json")
        let saves = try SaveRepository(initial: GameSnapshot(ownedCosmeticIDs: [appearance.id]), fileURL: saveURL)
        let engine = try GameEngine(catalog: catalog, saves: saves)

        let key = Curve25519.Signing.PrivateKey()
        let op = UUID()
        let tx = CommerceAuthorityReceiptCandidateV1.Identity(
            environment: "Sandbox", bundleID: "com.example.game", transactionID: "txn-durable",
            originalTransactionID: "txn-durable", productID: "candidate.wardrobe", quantity: 1)
        let unsigned = CommerceAuthorityReceiptCandidateV1(event: .grant, operationID: op,
            requestSHA256: requestHash, accountBindingSHA256: account, revision: 1,
            transaction: tx, grant: .init(entitlementID: "candidate.wardrobe", units: 1,
                                           expiresAtEpochSeconds: nil), keyID: "test-key", signatureBase64: "")
        let signed = CommerceAuthorityReceiptCandidateV1(event: .grant, operationID: op,
            requestSHA256: requestHash, accountBindingSHA256: account, revision: 1,
            transaction: tx, grant: .init(entitlementID: "candidate.wardrobe", units: 1,
                                           expiresAtEpochSeconds: nil), keyID: "test-key",
            signatureBase64: try key.signature(for: unsigned.signingBytes()).base64EncodedString())
        let token = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: signed, expectedOperationID: op, expectedRequestSHA256: requestHash,
            expectedAccountBindingSHA256: account, expectedTransaction: tx, expectedKeyID: "test-key",
            publicKey: key.publicKey, nowEpochSeconds: now,
            contentByEntitlementID: ["candidate.wardrobe": (cosmeticIDs: [appearance.id], furnitureIDs: [])])

        _ = try await engine.dispatch(.applyVerifiedCommerceOwnershipR1(token, nowEpochSeconds: now),
                                      operationID: op, expectedRevision: 0)
        let firstSaved = await saves.snapshot()
        XCTAssertTrue(firstSaved.ownedCosmeticIDs.contains(appearance.id))
        do {
            _ = try await engine.dispatch(.setCosmetic(appearance.id, owned: false),
                                          operationID: UUID(), expectedRevision: 1)
            XCTFail("free-owned appearance must not be removable through the legacy setter")
        } catch { }
        let reopened = try SaveRepository(initial: GameSnapshot(), fileURL: saveURL)
        let cold = await reopened.snapshot()
        XCTAssertTrue(cold.ownedCosmeticIDs.contains(appearance.id))
        XCTAssertEqual(cold.commerceOwnershipR1?.grants.first?.transactionID, "txn-durable")

        // Retrying the exact authority operation is idempotent and does not
        // advance revision or duplicate its durable source record.
        _ = try await engine.dispatch(.applyVerifiedCommerceOwnershipR1(token, nowEpochSeconds: now),
                                      operationID: op, expectedRevision: 0)
        let retried = await saves.snapshot()
        XCTAssertEqual(retried.revision, 1)
        XCTAssertEqual(retried.commerceOwnershipR1?.grants.count, 1)
    }

    private func signed(event: CommerceAuthorityReceiptCandidateV1.Event, operation: UUID,
                        revision: Int64, grant: CommerceAuthorityReceiptCandidateV1.Grant?,
                        key: Curve25519.Signing.PrivateKey,
                        identity suppliedIdentity: CommerceAuthorityReceiptCandidateV1.Identity? = nil) throws -> CommerceAuthorityReceiptCandidateV1 {
        let transaction = suppliedIdentity ?? identity
        let unsigned = CommerceAuthorityReceiptCandidateV1(event: event, operationID: operation,
            requestSHA256: requestHash, accountBindingSHA256: account, revision: revision,
            transaction: transaction, grant: grant, keyID: "test-key", signatureBase64: "")
        return CommerceAuthorityReceiptCandidateV1(event: event, operationID: operation,
            requestSHA256: requestHash, accountBindingSHA256: account, revision: revision,
            transaction: transaction, grant: grant, keyID: "test-key",
            signatureBase64: try key.signature(for: unsigned.signingBytes()).base64EncodedString())
    }

    private func identityWithTransaction(_ transactionID: String) -> CommerceAuthorityReceiptCandidateV1.Identity {
        CommerceAuthorityReceiptCandidateV1.Identity(environment: "Sandbox", bundleID: "com.example.game",
            transactionID: transactionID, originalTransactionID: transactionID,
            productID: "candidate.wardrobe", quantity: 1)
    }

    private func apply(_ receipt: CommerceAuthorityReceiptCandidateV1,
                       to ledger: inout CommerceEntitlementLedgerCandidateV1,
                       key: Curve25519.Signing.PrivateKey,
                       expected identity: CommerceAuthorityReceiptCandidateV1.Identity) throws -> Bool {
        try ledger.applying(receipt, expectedOperationID: UUID(uuidString: receipt.operationID)!,
                            expectedRequestSHA256: requestHash, expectedTransaction: identity,
                            expectedKeyID: "test-key", publicKey: key.publicKey,
                            nowEpochSeconds: now)
    }
}
