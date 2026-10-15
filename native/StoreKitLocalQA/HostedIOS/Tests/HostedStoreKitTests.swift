import XCTest
import StoreKitTest

final class HostedStoreKitTests: XCTestCase {
    func testHostedSessionCreatesLocalTransaction() async throws {
        let hostBundle = Bundle.main
        XCTAssertNotNil(hostBundle.bundleIdentifier)
        let config = try XCTUnwrap(hostBundle.url(forResource: "WitchLocalTest", withExtension: "storekit"))
        print("HOSTED_STOREKIT_TEST bundle=\(hostBundle.bundleIdentifier ?? "nil") config=\(config.path)")

        let session = try SKTestSession(configurationFileNamed: "WitchLocalTest")
        session.disableDialogs = true
        let transaction = try await session.buyProduct(identifier: "local.witch.test.furniture")
        XCTAssertEqual(transaction.productID, "local.witch.test.furniture")
        XCTAssertEqual(transaction.environment, .xcode)
        XCTAssertTrue(session.allTransactions().contains { $0.identifier == UInt(transaction.id) && $0.state == .purchased })
    }
}
