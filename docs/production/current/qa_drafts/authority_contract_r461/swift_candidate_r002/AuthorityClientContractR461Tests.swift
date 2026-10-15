import Foundation
import CryptoKit
import CoreFoundation
import XCTest
@testable import WitchGameCore

final class AuthorityClientContractR461Tests: XCTestCase {
    private let bindingSHA = String(repeating: "a", count: 64)
    private let accountIDSHA = String(repeating: "d", count: 64)
    private let operation = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!

    func testRequestIsClosedAndPendingRoundTripsForRetry() async throws {
        let pending = try makePending()
        let bytes = try pending.request.canonicalData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "operationID", "action", "signedTransactionJWS"])
        XCTAssertEqual(object["operationID"] as? String, operation.uuidString.lowercased())
        XCTAssertEqual(object["action"] as? String, "purchaseAndDraw")
        XCTAssertNil(object["account"]); XCTAssertNil(object["productID"]); XCTAssertNil(object["seed"])

        let persisted = try JSONEncoder().encode(pending)
        let reopened = try JSONDecoder().decode(PendingPurchaseOperationR461.self, from: persisted)
        try reopened.validate()
        XCTAssertEqual(reopened, pending)
        XCTAssertEqual(try reopened.request.canonicalData(), bytes)

        let collision = try PendingPurchaseOperationR461(operationID: operation, signedTransactionJWS: "e30.e30.BB")
        let registry = Store()
        try await registry.registerIfAbsent(pending)
        do { try await registry.registerIfAbsent(collision); XCTFail("operation collision accepted") }
        catch { XCTAssertTrue(String(describing: error).contains("collision")) }
    }

    func testDeliveredRetryRefundAndOldSuccessAfterRefund() async throws {
        let pending = try makePending()
        let expected = try expectation()
        let delivered = try response(pending: pending, revision: 8)
        let replay = try response(pending: pending, revision: 8)
        let refunded = try response(pending: pending, status: "REJECTED", revision: 9,
                                    currentStatus: "refunded", operationStatus: "unknown", error: "TRANSACTION_REFUNDED",
                                    delivery: nil)
        let store = Store()
        let transport = SequenceTransport([delivered, replay, refunded, delivered])
        let client = PurchaseAuthorityClientR461(transport: transport, observations: store, pendingOperations: store)
        _ = try await client.submit(pending, expectedStoreKit: expected)
        _ = try await client.submit(pending, expectedStoreKit: expected) // same operation and identical revision/state
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("refund was accepted") }
        catch {
            let observed = try await store.load(accountBindingSHA256: bindingSHA)
            XCTAssertEqual(observed?.revision, 9)
            XCTAssertEqual(observed?.status, .refunded)
        }
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("old success after refund accepted") }
        catch {
            let observed = try await store.load(accountBindingSHA256: bindingSHA)
            XCTAssertEqual(observed?.revision, 9)
            XCTAssertEqual(observed?.status, .refunded)
        }
    }

    func testTimeoutAfterPossibleServerCommitRetriesSamePersistedOperation() async throws {
        let pending = try makePending()
        let pendingBytes = try JSONEncoder().encode(pending)
        let reopenedPending = try JSONDecoder().decode(PendingPurchaseOperationR461.self, from: pendingBytes)
        try reopenedPending.validate()
        let expected = try expectation()
        let delivered = try response(pending: pending, revision: 4)
        let transport = TimeoutThenResponseTransport(delivered)
        let firstStore = Store()
        let firstClient = PurchaseAuthorityClientR461(transport: transport, observations: firstStore, pendingOperations: firstStore)
        do { _ = try await firstClient.submit(pending, expectedStoreKit: expected); XCTFail("simulated timeout was ignored") }
        catch { XCTAssertTrue(String(describing: error).contains("timeout")) }

        // Reconstructed store represents a cold process restart. The exact same
        // persisted operation ID and request bytes are sent to the authority.
        let restartedStore = Store()
        let restartedClient = PurchaseAuthorityClientR461(transport: transport, observations: restartedStore, pendingOperations: restartedStore)
        _ = try await restartedClient.submit(reopenedPending, expectedStoreKit: expected)
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0], sent[1])
        XCTAssertEqual(sent[0], try pending.request.canonicalData())
    }

    func testPersistedObservationReloadBlocksOlderAuthoritySnapshot() async throws {
        let saved = observation(revision: 12, status: .active, balance: 1, debt: 0)
        let bytes = try JSONEncoder().encode(saved)
        let reopened = try JSONDecoder().decode(AuthorityObservationR461.self, from: bytes)
        let pending = try makePending(), expected = try expectation()
        let store = Store(observation: reopened)
        let oldResponse = try response(pending: pending, revision: 11)
        let client = PurchaseAuthorityClientR461(transport: StaticTransport(oldResponse), observations: store, pendingOperations: store)
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("stale response accepted after persisted-state reload") }
        catch {
            let current = try await store.load(accountBindingSHA256: bindingSHA)
            XCTAssertEqual(current?.revision, 12)
        }
    }

    func testEqualRevisionConflictingStateIsRejectedWithoutOverwrite() async throws {
        let pending = try makePending(), expected = try expectation()
        let store = Store(observation: observation(revision: 8, status: .active, balance: 0, debt: 0))
        let conflicting = try response(pending: pending, revision: 8, balance: 5)
        let client = PurchaseAuthorityClientR461(transport: StaticTransport(conflicting), observations: store, pendingOperations: store)
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("equal revision conflict accepted") }
        catch {
            let observed = try await store.load(accountBindingSHA256: bindingSHA)
            XCTAssertEqual(observed, observation(revision: 8, status: .active, balance: 0, debt: 0))
        }
    }

    func testEqualRevisionSuccessCannotRacePastNewerConcurrentRefund() async throws {
        let pending = try makePending(), expected = try expectation()
        let prior = observation(revision: 7, status: .active, balance: 1, debt: 0)
        let store = Store(observation: prior)
        let staleSuccess = try response(pending: pending, revision: 7, balance: 1)
        let transport = InterleavingTransport(staleSuccess, store: store,
            concurrent: observation(revision: 8, status: .refunded, balance: 0, debt: 1))
        let client = PurchaseAuthorityClientR461(transport: transport, observations: store, pendingOperations: store)
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("stale success passed concurrent refund") }
        catch {
            let observed = try await store.load(accountBindingSHA256: bindingSHA)
            XCTAssertEqual(observed, observation(revision: 8, status: .refunded, balance: 0, debt: 1))
        }
    }

    func testTamperedHistoricalDeliveryFingerprintCannotAdvanceObservation() async throws {
        let pending = try makePending(), expected = try expectation()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: response(pending: pending, revision: 7)) as? [String: Any])
        var delivery = try XCTUnwrap(root["historicalDelivery"] as? [String: Any])
        delivery["deliveryFingerprint"] = String(repeating: "0", count: 64)
        root["historicalDelivery"] = delivery
        let store = Store()
        let client = PurchaseAuthorityClientR461(transport: StaticTransport(canonical(root)), observations: store, pendingOperations: store)
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("tampered delivery accepted") }
        catch {
            let observed = try await store.load(accountBindingSHA256: bindingSHA)
            XCTAssertNil(observed)
        }
    }

    func testUnauthenticatedRejectionCannotPoisonObservation() async throws {
        let pending = try makePending(), expected = try expectation()
        let denial: [String: Any] = ["schemaVersion": 1, "status": "REJECTED", "operationID": NSNull(),
            "requestSHA256": pending.requestSHA256, "accountBindingSHA256": NSNull(),
            "authorizationStatus": "NOT_AUTHORIZED_FOR_PRODUCTION", "historicalDelivery": NSNull(),
            "currentState": NSNull(), "errorCode": "AUTHENTICATION_REQUIRED"]
        let store = Store()
        let client = PurchaseAuthorityClientR461(transport: StaticTransport(canonical(denial)), observations: store, pendingOperations: store)
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("unauthenticated response accepted") }
        catch {
            let observed = try await store.load(accountBindingSHA256: bindingSHA)
            XCTAssertNil(observed)
        }
    }

    func testWrongOperationOrAccountCannotPoisonObservation() async throws {
        let pending = try makePending(), expected = try expectation()
        for mismatch in ["operation", "account"] {
            let bytes = try response(pending: pending, revision: 90, mismatch: mismatch)
            let store = Store()
            let client = PurchaseAuthorityClientR461(transport: StaticTransport(bytes), observations: store, pendingOperations: store)
            do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("mismatched response accepted") }
            catch { let observed = try await store.load(accountBindingSHA256: bindingSHA); XCTAssertNil(observed) }
        }
    }

    func testMalformedUnknownAndNoncanonicalResponsesFailClosed() throws {
        XCTAssertThrowsError(try PurchaseAuthorityResponseR461.decodeStrict(Data()))
        XCTAssertThrowsError(try PurchaseAuthorityResponseR461.decodeStrict(Data("{\"schemaVersion\":1".utf8)))
        let pending = try makePending()
        let valid = try response(pending: pending, revision: 2)
        XCTAssertThrowsError(try PurchaseAuthorityResponseR461.decodeStrict(Data(valid.dropLast())))
        XCTAssertThrowsError(try PurchaseAuthorityResponseR461.decodeStrict(Data("{\"a\":1,\"a\":2}\n".utf8)))
        var unknown = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        unknown["futureAuthority"] = true
        XCTAssertThrowsError(try PurchaseAuthorityResponseR461.decodeStrict(canonical(unknown)))
    }

    func testObservationCASRejectsOlderConcurrentWriter() async throws {
        let store = Store()
        async let first = store.compareAndSave(observation(revision: 10, status: .active, balance: 2, debt: 0), expectedPreviousRevision: nil)
        async let second = store.compareAndSave(observation(revision: 11, status: .active, balance: 1, debt: 0), expectedPreviousRevision: nil)
        let outcomes = try await [first, second]
        XCTAssertEqual(outcomes.filter { $0 }.count, 1)
        let winnerValue = try await store.load(accountBindingSHA256: bindingSHA)
        let winner = try XCTUnwrap(winnerValue)
        let staleExpected = winner.revision
        let newerSaved = try await store.compareAndSave(observation(revision: staleExpected + 1, status: .refunded, balance: 0, debt: 0), expectedPreviousRevision: staleExpected)
        let staleSaved = try await store.compareAndSave(observation(revision: staleExpected + 2, status: .active, balance: 10, debt: 0), expectedPreviousRevision: staleExpected)
        let finalObservation = try await store.load(accountBindingSHA256: bindingSHA)
        XCTAssertTrue(newerSaved)
        XCTAssertFalse(staleSaved)
        XCTAssertEqual(finalObservation?.revision, staleExpected + 1)
    }

    func testPythonExchangeFixtureThroughSubmitWhenRequired() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["WITCH_R461_CROSS_LANGUAGE_FIXTURE_REQUIRED"] == "1" else {
            throw XCTSkip("Python exchange fixture is enabled only by the Root-pinned runner")
        }
        guard let path = env["WITCH_R461_EXCHANGE_FIXTURE_PATH"],
              let pin = env["WITCH_R461_EXCHANGE_FIXTURE_SHA256"], isSHA(pin) else {
            XCTFail("required fixture path/SHA missing"); return
        }
        let wrapperBytes = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(sha256(wrapperBytes), pin)
        let wrapper = try XCTUnwrap(JSONSerialization.jsonObject(with: wrapperBytes) as? [String: Any])
        XCTAssertEqual(Set(wrapper.keys), ["schemaVersion", "requestBase64", "requestSHA256", "operationID", "expectedStoreKit", "responses", "status", "productionEntitlementAuthorized", "privateKeyExported"])
        XCTAssertEqual(wrapper["schemaVersion"] as? Int, 1)
        XCTAssertEqual(wrapper["status"] as? String, "SYNTHETIC_TEST_ONLY_NOT_APPLE_AUTHORIZATION")
        XCTAssertEqual(wrapper["productionEntitlementAuthorized"] as? Bool, false)
        XCTAssertEqual(wrapper["privateKeyExported"] as? Bool, false)
        let requestBytes = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(wrapper["requestBase64"] as? String)))
        XCTAssertEqual(sha256(requestBytes), wrapper["requestSHA256"] as? String)
        let requestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBytes) as? [String: Any])
        XCTAssertEqual(Set(requestObject.keys), ["schemaVersion", "operationID", "action", "signedTransactionJWS"])
        let operationID = try XCTUnwrap(UUID(uuidString: XCTUnwrap(requestObject["operationID"] as? String)))
        XCTAssertEqual(operationID.uuidString.lowercased(), wrapper["operationID"] as? String)
        let pending = try PendingPurchaseOperationR461(operationID: operationID,
                                                        signedTransactionJWS: XCTUnwrap(requestObject["signedTransactionJWS"] as? String))
        XCTAssertEqual(try pending.request.canonicalData(), requestBytes)

        let expectedObject = try XCTUnwrap(wrapper["expectedStoreKit"] as? [String: Any])
        XCTAssertEqual(Set(expectedObject.keys), ["environment", "bundleID", "transactionID", "originalTransactionID", "productID", "quantity", "accountBindingSHA256", "accountIDSHA256"])
        let expected = try LocalStoreKitPurchaseExpectationR461(
            environment: XCTUnwrap(expectedObject["environment"] as? String),
            bundleID: XCTUnwrap(expectedObject["bundleID"] as? String),
            transactionID: XCTUnwrap(expectedObject["transactionID"] as? String),
            originalTransactionID: XCTUnwrap(expectedObject["originalTransactionID"] as? String),
            productID: XCTUnwrap(expectedObject["productID"] as? String),
            quantity: try exactInt(expectedObject["quantity"]),
            accountBindingSHA256: XCTUnwrap(expectedObject["accountBindingSHA256"] as? String),
            accountIDSHA256: XCTUnwrap(expectedObject["accountIDSHA256"] as? String))
        let rows = try XCTUnwrap(wrapper["responses"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["kind"] as? String }, ["delivered", "replay", "postRefund"])
        let responses = try rows.map { row -> Data in
            XCTAssertEqual(Set(row.keys), ["kind", "base64", "sha256"])
            let bytes = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(row["base64"] as? String)))
            XCTAssertEqual(sha256(bytes), row["sha256"] as? String)
            return bytes
        }
        let firstDecoded = try PurchaseAuthorityResponseR461.decodeStrict(responses[0])
        let store = Store()
        let client = PurchaseAuthorityClientR461(transport: SequenceTransport(responses), observations: store, pendingOperations: store)
        _ = try await client.submit(pending, expectedStoreKit: expected)
        _ = try await client.submit(pending, expectedStoreKit: expected)
        do { _ = try await client.submit(pending, expectedStoreKit: expected); XCTFail("post-refund response delivered") }
        catch {
            let afterRefund = try await store.load(accountBindingSHA256: expected.accountBindingSHA256)
            XCTAssertEqual(afterRefund?.status, .refunded)
            XCTAssertGreaterThan(afterRefund?.revision ?? -1, firstDecoded.currentState?.revision ?? Int64.max)
        }
    }

    private func makePending() throws -> PendingPurchaseOperationR461 {
        try PendingPurchaseOperationR461(operationID: operation, signedTransactionJWS: "e30.e30.AA")
    }
    private func expectation() throws -> LocalStoreKitPurchaseExpectationR461 {
        try LocalStoreKitPurchaseExpectationR461(environment: "Sandbox", bundleID: "local.witch.autonomous.r1.r461",
            transactionID: "tx-001", originalTransactionID: "original-001", productID: "local.witch.test.ticket",
            quantity: 1, accountBindingSHA256: bindingSHA, accountIDSHA256: accountIDSHA)
    }
    private func observation(revision: Int64, status: CurrentPurchaseAccountStateR461.Status, balance: Int, debt: Int) -> AuthorityObservationR461 {
        AuthorityObservationR461(accountBindingSHA256: bindingSHA, revision: revision, status: status, ticketBalance: balance, ticketDebt: debt)
    }

    private func response(pending: PendingPurchaseOperationR461, status: String = "DELIVERED", revision: Int,
                          currentStatus: String = "active", operationStatus: String = "delivered", balance: Int = 0,
                          debt: Int = 0, error: String? = nil, delivery: [String: Any]? = nil,
                          mismatch: String? = nil) throws -> Data {
        let op = mismatch == "operation" ? UUID().uuidString.lowercased() : pending.request.operationID
        let identity = ["environment": "Sandbox", "bundleID": "local.witch.autonomous.r1.r461", "transactionID": "tx-001",
                        "originalTransactionID": "original-001", "productID": "local.witch.test.ticket", "quantity": 1] as [String: Any]
        let historical: Any
        if let delivery { historical = delivery }
        else if status == "DELIVERED" { historical = makeDelivery(op: op, identity: identity) }
        else { historical = NSNull() }
        let root: [String: Any] = ["schemaVersion": 1, "status": status, "operationID": op,
            "requestSHA256": pending.requestSHA256,
            "accountBindingSHA256": mismatch == "account" ? String(repeating: "b", count: 64) : bindingSHA,
            "authorizationStatus": "NOT_AUTHORIZED_FOR_PRODUCTION", "historicalDelivery": historical,
            "currentState": ["revision": revision, "status": currentStatus, "ticketBalance": balance,
                "ticketDebt": debt, "operationStatus": operationStatus], "errorCode": error.map { $0 as Any } ?? NSNull()]
        return canonical(root)
    }

    private func makeDelivery(op: String, identity: [String: Any]) -> [String: Any] {
        let pity: [String: Any] = ["drawsSinceTop": 0, "drawsSinceMid": 0, "targetTemplateID": NSNull(), "guaranteeTargetOnNextTop": false]
        let receipt: [String: Any] = ["accountIDSHA256": accountIDSHA, "idempotencyKey": op,
            "transactionIdentity": "Sandbox/local.witch.autonomous.r1.r461/tx-001", "ticketsGranted": 1,
            "ticketsDebtOffset": 0, "ticketsDrawn": 1, "ticketsRemainingFromPurchase": 0,
            "draws": [["drawIndex": 0, "qualityID": "Q0", "gearTemplateID": "EQ_W_01", "pityBefore": pity, "pityAfter": pity]],
            "pityAfter": pity, "status": "COMMITTED_TEST_ONLY"]
        let drawRow: [String: Any] = ["drawIndex": 0, "qualityID": "Q0", "gearTemplateID": "EQ_W_01",
            "pityBefore": pity, "pityAfter": pity]
        let drawRowSHA = sha256(canonicalNoLF(drawRow))
        let items: [[String: Any]] = [["gearID": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "definitionID": "EQ_W_01",
            "qualityID": "Q0", "affixIDs": [], "latentEffectID": NSNull(), "drawIndex": 0,
            "drawRowFingerprint": drawRowSHA]]
        var receiptWithRow = receipt
        receiptWithRow["draws"] = [drawRow]
        let partial: [String: Any] = ["profileID": "r459-sandbox", "profileFingerprint": String(repeating: "e", count: 64),
            "transactionIdentity": identity, "operationID": op, "drawReceipt": receiptWithRow, "deliveredItems": items]
        let fingerprint = sha256(canonicalNoLF(partial))
        return partial.merging(["deliveryFingerprint": fingerprint]) { _, new in new }
    }

    private func exactInt(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = Int(number.stringValue) else { throw CoreError.invalidCommand("expected exact integer") }
        return integer
    }
    private func canonicalNoLF(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
    private func canonical(_ object: [String: Any]) -> Data {
        var data = canonicalNoLF(object); data.append(0x0A); return data
    }
    private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func isSHA(_ s: String) -> Bool { s.utf8.count == 64 && s.allSatisfy { "0123456789abcdef".contains($0) } }
}


private actor StaticTransport: PurchaseAuthorityTransportR461 {
    let response: Data
    init(_ response: Data) { self.response = response }
    func exchange(_ requestBytes: Data) async throws -> Data { response }
}

private actor InterleavingTransport: PurchaseAuthorityTransportR461 {
    private let response: Data
    private let store: Store
    private let concurrent: AuthorityObservationR461
    init(_ response: Data, store: Store, concurrent: AuthorityObservationR461) {
        self.response = response; self.store = store; self.concurrent = concurrent
    }
    func exchange(_ requestBytes: Data) async throws -> Data {
        let advanced = try await store.compareAndSave(concurrent, expectedPreviousRevision: 7)
        guard advanced else { throw CoreError.invalidCommand("test interleaving could not advance observation") }
        return response
    }
}

private actor TimeoutThenResponseTransport: PurchaseAuthorityTransportR461 {
    private let response: Data
    private var callCount = 0
    private var requestsSent: [Data] = []
    init(_ response: Data) { self.response = response }
    func exchange(_ requestBytes: Data) async throws -> Data {
        requestsSent.append(requestBytes)
        callCount += 1
        if callCount == 1 { throw CoreError.invalidCommand("synthetic transport timeout after possible commit") }
        return response
    }
    func requests() -> [Data] { requestsSent }
}

private actor SequenceTransport: PurchaseAuthorityTransportR461 {
    private var responses: [Data]
    init(_ responses: [Data]) { self.responses = responses }
    func exchange(_ requestBytes: Data) async throws -> Data {
        guard !responses.isEmpty else { throw CoreError.invalidCommand("fixture exhausted") }
        return responses.removeFirst()
    }
}

private actor Store: AuthorityObservationStoreR461, PendingPurchaseOperationStoreR461 {
    private var observations: [String: AuthorityObservationR461] = [:]
    private var pending: [String: PendingPurchaseOperationR461] = [:]
    init(observation: AuthorityObservationR461? = nil) {
        if let observation { observations[observation.accountBindingSHA256] = observation }
    }
    func load(accountBindingSHA256: String) async throws -> AuthorityObservationR461? { observations[accountBindingSHA256] }
    func compareAndSave(_ value: AuthorityObservationR461, expectedPreviousRevision: Int64?) async throws -> Bool {
        let old = observations[value.accountBindingSHA256]
        guard old?.revision == expectedPreviousRevision else { return false }
        if let expectedPreviousRevision {
            guard value.revision >= expectedPreviousRevision else { return false }
            if value.revision == expectedPreviousRevision, value != old { return false }
        }
        observations[value.accountBindingSHA256] = value
        return true
    }
    func registerIfAbsent(_ value: PendingPurchaseOperationR461) async throws {
        try value.validate()
        let key = value.request.operationID
        if let old = pending[key], old != value { throw CoreError.invalidCommand("R461 operation UUID collision") }
        pending[key] = value
    }
}
