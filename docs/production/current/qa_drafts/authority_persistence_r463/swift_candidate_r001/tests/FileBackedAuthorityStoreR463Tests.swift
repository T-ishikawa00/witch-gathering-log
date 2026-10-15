import Foundation
import Darwin
import XCTest
@testable import WitchGameCore

final class FileBackedAuthorityStoreR463Tests: XCTestCase {
    private let binding = String(repeating: "a", count: 64)
    private var temporaryRoot: URL!
    private var rehearsalRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("R463-\(UUID().uuidString.lowercased())", isDirectory: true)
        rehearsalRoot = temporaryRoot.appendingPathComponent("r459-sandbox-rehearsal", isDirectory: true)
        try FileManager.default.createDirectory(at: rehearsalRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data("NOT_AUTHORIZED_FOR_PRODUCTION\n".utf8)
            .write(to: rehearsalRoot.appendingPathComponent("R459_LOCAL_REHEARSAL_ONLY"), options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
            ofItemAtPath: rehearsalRoot.appendingPathComponent("R459_LOCAL_REHEARSAL_ONLY").path)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
        try super.tearDownWithError()
    }

    func testPendingOperationSurvivesColdReopenAndRejectsUUIDCollision() async throws {
        let first = try makeStore()
        let pending = try makePending("e30.e30.AA")
        try await first.registerIfAbsent(pending)
        let firstLoaded = try await first.loadPending(operationID: try XCTUnwrap(UUID(uuidString: pending.request.operationID)))
        XCTAssertEqual(firstLoaded, pending)
        let before = try Data(contentsOf: pendingURL)

        let reopened = try makeStore()
        let recovered = try await reopened.loadPending(operationID: try XCTUnwrap(UUID(uuidString: pending.request.operationID)))
        XCTAssertEqual(recovered, pending)
        try await reopened.registerIfAbsent(pending)
        XCTAssertEqual(try Data(contentsOf: pendingURL), before)

        let collision = try makePending("e30.e30.BB")
        do {
            try await reopened.registerIfAbsent(collision)
            XCTFail("same operation UUID accepted different JWS")
        } catch {
            XCTAssertTrue(String(describing: error).contains("operation UUID"))
        }
        XCTAssertEqual(try Data(contentsOf: pendingURL), before)
    }

    func testPendingOperationsAreIsolatedByTheStoresPinnedAccountNamespace() async throws {
        let first = try makeStore()
        let pending = try makePending("e30.e30.AA")
        try await first.registerIfAbsent(pending)

        let otherBinding = String(repeating: "b", count: 64)
        let otherAccountStore = try makeStore(binding: otherBinding)
        let sameOperationID = try XCTUnwrap(UUID(uuidString: pending.request.operationID))
        let crossAccountLoad = try await otherAccountStore.loadPending(operationID: sameOperationID)
        XCTAssertNil(crossAccountLoad)

        let independentlyBoundRequest = try PendingPurchaseOperationR461(
            operationID: sameOperationID, signedTransactionJWS: "e30.e30.BB")
        try await otherAccountStore.registerIfAbsent(independentlyBoundRequest)
        let otherAccountReadback = try await otherAccountStore.loadPending(operationID: sameOperationID)
        XCTAssertEqual(otherAccountReadback, independentlyBoundRequest)

        let originalReadback = try await first.loadPending(operationID: sameOperationID)
        XCTAssertEqual(originalReadback, pending)
    }

    func testObservationCASIsMonotonicAcrossInstancesAndBindingNamespace() async throws {
        let first = try makeStore()
        let second = try makeStore()
        let five = observation(5, .active, balance: 2, debt: 0)
        let firstSave = try await first.compareAndSave(five, expectedPreviousRevision: nil)
        let identicalSave = try await second.compareAndSave(five, expectedPreviousRevision: 5)
        let conflictingEqualSave = try await second.compareAndSave(observation(5, .refunded, balance: 0, debt: 2), expectedPreviousRevision: 5)
        let olderSave = try await first.compareAndSave(observation(4, .active, balance: 3, debt: 0), expectedPreviousRevision: 5)
        XCTAssertTrue(firstSave)
        XCTAssertTrue(identicalSave)
        XCTAssertFalse(conflictingEqualSave)
        XCTAssertFalse(olderSave)

        let six = observation(6, .active, balance: 1, debt: 0)
        let seven = observation(7, .refunded, balance: 0, debt: 1)
        async let saveSix = first.compareAndSave(six, expectedPreviousRevision: 5)
        async let saveSeven = second.compareAndSave(seven, expectedPreviousRevision: 5)
        let outcomes = try await [saveSix, saveSeven]
        XCTAssertEqual(outcomes.filter { $0 }.count, 1)
        let final = try await first.load(accountBindingSHA256: binding)
        XCTAssertTrue(final == six || final == seven)
        let baseRevision = try XCTUnwrap(final?.revision)
        let sameInstanceA = observation(baseRevision + 1, .active, balance: 1, debt: 0)
        let sameInstanceB = observation(baseRevision + 2, .refunded, balance: 0, debt: 1)
        async let sameSaveA = first.compareAndSave(sameInstanceA, expectedPreviousRevision: baseRevision)
        async let sameSaveB = first.compareAndSave(sameInstanceB, expectedPreviousRevision: baseRevision)
        let sameInstanceOutcomes = try await [sameSaveA, sameSaveB]
        XCTAssertEqual(sameInstanceOutcomes.filter { $0 }.count, 1)

        do {
            _ = try await first.load(accountBindingSHA256: String(repeating: "b", count: 64))
            XCTFail("cross-account observation read accepted")
        } catch {
            XCTAssertTrue(String(describing: error).contains("binding"))
        }
    }

    func testCorruptFutureAndUnknownStoreSchemasFailClosedWithoutOverwrite() async throws {
        let store = try makeStore()
        let url = observationURL
        let future = Data("{\"accountBindingSHA256\":\"\(binding)\",\"observation\":{\"accountBindingSHA256\":\"\(binding)\",\"revision\":1,\"status\":\"active\",\"ticketBalance\":0,\"ticketDebt\":0},\"schemaVersion\":2}".utf8)
        try writePrivate(future, to: url)
        do { _ = try await store.load(accountBindingSHA256: binding); XCTFail("future schema accepted") }
        catch { XCTAssertTrue(String(describing: error).contains("store")) }
        XCTAssertEqual(try Data(contentsOf: url), future)

        let unknown = Data("{\"accountBindingSHA256\":\"\(binding)\",\"future\":true,\"observation\":{\"accountBindingSHA256\":\"\(binding)\",\"revision\":1,\"status\":\"active\",\"ticketBalance\":0,\"ticketDebt\":0},\"schemaVersion\":1}".utf8)
        try writePrivate(unknown, to: url)
        do { _ = try await store.load(accountBindingSHA256: binding); XCTFail("unknown field accepted") }
        catch { XCTAssertTrue(String(describing: error).contains("store")) }
        XCTAssertEqual(try Data(contentsOf: url), unknown)
    }

    func testInterruptedTemporaryWriteRecoversPreviousCommittedValue() async throws {
        let store = try makeStore()
        let pending = try makePending("e30.e30.AA")
        try await store.registerIfAbsent(pending)
        let committed = try Data(contentsOf: pendingURL)
        try writePrivate(Data("{partial".utf8), to: pendingTempURL)

        let reopened = try makeStore()
        let recovered = try await reopened.loadPending(operationID: UUID(uuidString: pending.request.operationID)!)
        XCTAssertEqual(recovered, pending)
        XCTAssertEqual(try Data(contentsOf: pendingURL), committed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingTempURL.path))
    }

    func testSymlinkedRootAndHardlinkedStoreFileAreRejected() async throws {
        let alias = temporaryRoot.appendingPathComponent("linked-root", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: rehearsalRoot)
        XCTAssertThrowsError(try FileBackedAuthorityStoreR463(rehearsalDirectory: alias,
                                                               accountBindingSHA256: binding))

        let store = try makeStore()
        try await store.registerIfAbsent(makePending("e30.e30.AA"))
        let externalAlias = temporaryRoot.appendingPathComponent("outside-hardlink")
        guard link(pendingURL.path, externalAlias.path) == 0 else {
            XCTFail("could not create test hard link (errno \(errno))"); return
        }
        let reopened = try makeStore()
        do {
            _ = try await reopened.loadPending(operationID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!)
            XCTFail("hard-linked storage file accepted")
        } catch { XCTAssertTrue(String(describing: error).contains("single-link")) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalAlias.path))
    }

    private func makeStore(binding value: String? = nil) throws -> FileBackedAuthorityStoreR463 {
        try FileBackedAuthorityStoreR463(rehearsalDirectory: rehearsalRoot,
                                         accountBindingSHA256: value ?? binding)
    }

    private func makePending(_ jws: String) throws -> PendingPurchaseOperationR461 {
        try PendingPurchaseOperationR461(
            operationID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            signedTransactionJWS: jws)
    }

    private func observation(_ revision: Int64, _ status: CurrentPurchaseAccountStateR461.Status,
                             balance: Int, debt: Int) -> AuthorityObservationR461 {
        AuthorityObservationR461(accountBindingSHA256: binding, revision: revision,
                                 status: status, ticketBalance: balance, ticketDebt: debt)
    }

    private var accountDirectory: URL {
        rehearsalRoot.appendingPathComponent(FileBackedAuthorityStoreR463.namespacePrefix + binding,
                                             isDirectory: true)
    }
    private var pendingURL: URL { accountDirectory.appendingPathComponent(FileBackedAuthorityStoreR463.pendingFileName) }
    private var pendingTempURL: URL { accountDirectory.appendingPathComponent(FileBackedAuthorityStoreR463.pendingTempName) }
    private var observationURL: URL { accountDirectory.appendingPathComponent(FileBackedAuthorityStoreR463.observationFileName) }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
