import XCTest

final class StoreKitLocalQAiOSProbeTests: XCTestCase {
    func testEmptyProductResultDoesNotCrashPurchaseFallback() {
        let app = XCUIApplication()
        app.launch()
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let resolved = status.waitForPredicate(format: "label CONTAINS 'products=' OR label CONTAINS 'productError='", timeout: 20)
        XCTAssertTrue(resolved, "\(status.label)")
        guard resolved else { return }
        guard status.label.contains("products=0") else {
            XCTFail("This regression expects the current StoreKit configuration failure to produce an empty list; got \(status.label)")
            return
        }
        app.buttons["buyFurniture"].tap()
        XCTAssertTrue(status.waitForPredicate(format: "label CONTAINS 'purchase=unavailable'", timeout: 12), "\(status.label)")
        XCTAssertTrue(app.exists)
    }
}

private extension XCUIElement {
    func waitForPredicate(format: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: format)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
