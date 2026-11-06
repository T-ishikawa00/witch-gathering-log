import Foundation
import CryptoKit
import XCTest
@testable import WitchGameCore

final class CommerceRuntimeR465Tests: XCTestCase {
    func testProductionGateDefaultsAndRequiresEveryApprovalFact() throws {
        let config = CommerceApprovalConfigurationR465(
            approvalID: "", bundleID: "", productIDs: [], authorityURL: URL(string: "http://localhost:8080")!,
            authorityContractVersion: 1, accountBindingConfigured: false, humanApproved: false)
        XCTAssertEqual(Set(config.validationReasons), Set([
            .humanApprovalMissing, .pricePresentationMissing, .approvalIdentityMissing,
            .bundleIdentityMissing, .productCatalogMissing, .authorityEndpointNotApproved,
            .authorityContractNotApproved, .accountBindingUnavailable
        ]))

        let seeminglyApproved = CommerceApprovalConfigurationR465(
            approvalID: "human-approved-r1", bundleID: "com.example.game", productIDs: ["candidate.sku"],
            authorityURL: URL(string: "https://authority.example/v2/purchase")!, authorityContractVersion: 2,
            accountBindingConfigured: true, humanApproved: true, pricePresentationApproved: true)
        XCTAssertTrue(seeminglyApproved.validationReasons.isEmpty)
        // This is a structural validator only. No product/service values exist in
        // the package and this test performs no StoreKit call or network request.
    }

    func testOperationIdentityIsStableAndTransactionFingerprintIsChecked() throws {
        let first = CommerceOperationRecordR465.stableOperationID(
            environment: "Sandbox", bundleID: "com.example.game", transactionID: "987654321")
        let retry = CommerceOperationRecordR465.stableOperationID(
            environment: "Sandbox", bundleID: "com.example.game", transactionID: "987654321")
        let distinct = CommerceOperationRecordR465.stableOperationID(
            environment: "Sandbox", bundleID: "com.example.game", transactionID: "987654322")
        XCTAssertEqual(first, retry)
        XCTAssertNotEqual(first, distinct)

        let record = try CommerceOperationRecordR465(
            id: first, environment: "Sandbox", bundleID: "com.example.game",
            transactionID: "987654321", originalTransactionID: "987654321",
            productID: "candidate.sku", quantity: 1, kind: .consumable, status: .verifiedAwaitingAuthority,
            signedTransactionJWS: "e30.e30.signature")
        try record.validate()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object["transactionFingerprint"] = String(repeating: "0", count: 64)
        let corrupt = try JSONDecoder().decode(CommerceOperationRecordR465.self,
                                               from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try corrupt.validate())
    }

    func testLifecycleRequiresVerifiedAuthorityBeforeDeliveryAndRestoreExcludesConsumables() {
        XCTAssertFalse(CommerceLifecycleR465.permits(from: .awaitingStoreKit, to: .finished))
        XCTAssertFalse(CommerceLifecycleR465.permits(from: .authorityRetryRequired, to: .finished))
        XCTAssertTrue(CommerceLifecycleR465.permits(from: .authorityRetryRequired, to: .deliveredAwaitingFinish))
        XCTAssertTrue(CommerceLifecycleR465.permits(from: .deliveredAwaitingFinish, to: .finished))
        XCTAssertTrue(CommerceLifecycleR465.permits(from: .finished, to: .revoked))
        XCTAssertFalse(CommerceLifecycleR465.canRestore(.consumable))
        XCTAssertTrue(CommerceLifecycleR465.canRestore(.nonConsumable))
        XCTAssertTrue(CommerceLifecycleR465.canRestore(.subscription))
    }

    func testCandidateSignedReceiptLedgerIsIdempotentAndRevocationTombstoneWins() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let account = String(repeating: "a", count: 64)
        let requestHash = String(repeating: "b", count: 64)
        let identity = CommerceAuthorityReceiptCandidateV1.Identity(
            environment: "Sandbox", bundleID: "com.example.game", transactionID: "7001",
            originalTransactionID: "7001", productID: "candidate.sku", quantity: 1)
        let operation = UUID(uuidString: "10aabbcc-ddee-4ff0-8111-223344556677")!
        let grant = try signedReceipt(event: .grant, operationID: operation, requestHash: requestHash,
                                      account: account, revision: 1, identity: identity,
                                      entitlement: .init(entitlementID: "candidate.wardrobe", units: 1,
                                                         expiresAtEpochSeconds: nil), key: privateKey)
        let encoded = try canonicalReceipt(grant)
        let decoded = try CommerceAuthorityReceiptCandidateV1.decodeStrict(encoded)
        var ledger = try CommerceEntitlementLedgerCandidateV1(accountBindingSHA256: account)
        XCTAssertTrue(try ledger.applying(decoded, expectedOperationID: operation,
                                          expectedRequestSHA256: requestHash, expectedTransaction: identity,
                                          expectedKeyID: "qa-key-1", publicKey: privateKey.publicKey,
                                          nowEpochSeconds: 1_800_000_000))
        XCTAssertEqual(ledger.entries.map(\.id), ["7001/candidate.wardrobe"])
        XCTAssertFalse(try ledger.applying(decoded, expectedOperationID: operation,
                                           expectedRequestSHA256: requestHash, expectedTransaction: identity,
                                           expectedKeyID: "qa-key-1", publicKey: privateKey.publicKey,
                                           nowEpochSeconds: 1_800_000_000))
        let ownedProjection = CommerceOwnershipReadModelCandidateV1(ledger: ledger, nowEpochSeconds: 1_800_000_000)
        XCTAssertTrue(ownedProjection.owns("candidate.wardrobe"))
        XCTAssertEqual(ownedProjection.units(for: "candidate.wardrobe"), 1)

        var storeKitRevoked = ledger
        let storeKitProof = String(repeating: "e", count: 64)
        try storeKitRevoked.applyingVerifiedStoreKitRevocation(transactionID: "7001", proofFingerprint: storeKitProof)
        XCTAssertTrue(storeKitRevoked.entries.isEmpty)
        XCTAssertEqual(storeKitRevoked.tombstones.first?.receiptFingerprint, storeKitProof)
        XCTAssertNoThrow(try storeKitRevoked.applyingVerifiedStoreKitRevocation(
            transactionID: "7001", proofFingerprint: String(repeating: "f", count: 64)))
        XCTAssertEqual(storeKitRevoked.revision, ledger.revision,
                       "a refreshed verified StoreKit proof must not consume a server revision")

        let revokeOperation = UUID(uuidString: "20aabbcc-ddee-4ff0-8111-223344556677")!
        let revokeHash = String(repeating: "c", count: 64)
        let revoke = try signedReceipt(event: .revoke, operationID: revokeOperation, requestHash: revokeHash,
                                       account: account, revision: 2, identity: identity,
                                       entitlement: nil, key: privateKey)
        XCTAssertTrue(try ledger.applying(revoke, expectedOperationID: revokeOperation,
                                          expectedRequestSHA256: revokeHash, expectedTransaction: identity,
                                          expectedKeyID: "qa-key-1", publicKey: privateKey.publicKey,
                                          nowEpochSeconds: 1_800_000_000))
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertEqual(ledger.tombstones.map(\.transactionID), ["7001"])

        let replayOperation = UUID(uuidString: "30aabbcc-ddee-4ff0-8111-223344556677")!
        let replayHash = String(repeating: "d", count: 64)
        let delayedGrant = try signedReceipt(event: .grant, operationID: replayOperation,
                                             requestHash: replayHash, account: account, revision: 3,
                                             identity: identity,
                                             entitlement: .init(entitlementID: "candidate.wardrobe", units: 1,
                                                                expiresAtEpochSeconds: nil), key: privateKey)
        XCTAssertThrowsError(try ledger.applying(delayedGrant, expectedOperationID: replayOperation,
                                                 expectedRequestSHA256: replayHash, expectedTransaction: identity,
                                                 expectedKeyID: "qa-key-1", publicKey: privateKey.publicKey,
                                                 nowEpochSeconds: 1_800_000_000))
        let projection = CommerceOwnershipReadModelCandidateV1(ledger: ledger, nowEpochSeconds: 1_800_000_000)
        XCTAssertFalse(projection.owns("candidate.wardrobe"))
        XCTAssertEqual(projection.units(for: "candidate.wardrobe"), 0)
        XCTAssertFalse(CommerceOwnershipReadModelCandidateV1.empty.owns("candidate.wardrobe"))
    }

    private func signedReceipt(event: CommerceAuthorityReceiptCandidateV1.Event, operationID: UUID,
                               requestHash: String, account: String, revision: Int64,
                               identity: CommerceAuthorityReceiptCandidateV1.Identity,
                               entitlement: CommerceAuthorityReceiptCandidateV1.Grant?,
                               key: Curve25519.Signing.PrivateKey) throws -> CommerceAuthorityReceiptCandidateV1 {
        let unsigned = CommerceAuthorityReceiptCandidateV1(event: event, operationID: operationID,
            requestSHA256: requestHash, accountBindingSHA256: account, revision: revision,
            transaction: identity, grant: entitlement, keyID: "qa-key-1", signatureBase64: "")
        let signature = try key.signature(for: unsigned.signingBytes()).base64EncodedString()
        return CommerceAuthorityReceiptCandidateV1(event: event, operationID: operationID,
            requestSHA256: requestHash, accountBindingSHA256: account, revision: revision,
            transaction: identity, grant: entitlement, keyID: "qa-key-1", signatureBase64: signature)
    }

    private func canonicalReceipt(_ receipt: CommerceAuthorityReceiptCandidateV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(receipt)
    }
}
