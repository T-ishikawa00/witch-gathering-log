import XCTest
import CryptoKit

/// Same saved furniture placement, comparing only the isolated visual candidate.
final class FurnitureVisualR124Tests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate() }

    func testDeskCandidateRetainsSavedPlacementAndHomeActivity() {
        let key = "furniture-r124-" + UUID().uuidString
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
                               "--qa-home-desk-r124", "--qa-candidate-scene-r124", "--screen=模様替え"]
        app.launch()
        let receive = app.buttons["無料の研究机を受け取る"]
        XCTAssertTrue(receive.waitForExistence(timeout: 20))
        receive.tap()
        let place = app.buttons["place_desk"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: place)
        waitForExpectations(timeout: 8)
        place.tap()
        expectation(for: NSPredicate(format: "label == %@", "机をしまう"), evaluatedWith: place)
        waitForExpectations(timeout: 8)
        app.buttons.matching(NSPredicate(format: "label == %@", "閉じる")).firstMatch.tap()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        attach("candidate_placed", key: key)
        app.terminate()

        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
                               "--qa-candidate-scene-r124", "--screen=家"]
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        attach("baseline_same_save", key: key)
        app.terminate()

        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
                               "--qa-home-desk-r124", "--qa-candidate-scene-r124", "--screen=模様替え"]
        app.launch()
        XCTAssertTrue(app.buttons["place_desk"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["place_desk"].label, "机をしまう")
        attach("candidate_reopened_placement", key: key)
    }

    private func attach(_ label: String, key: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "furniture_r124_" + label
        screenshot.lifetime = .keepAlways
        add(screenshot)
        var fields = ["stage": label, "saveKey": key, "test": name,
                      "arguments": app.launchArguments.joined(separator: " ")]
        if let path = Bundle(for: type(of: self)).executableURL, let bytes = try? Data(contentsOf: path) {
            fields["testSHA256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        if let bytes = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
           let text = String(data: bytes, encoding: .utf8) {
            let receipt = XCTAttachment(string: text)
            receipt.name = "furniture_r124_" + label + "_identity"
            receipt.lifetime = .keepAlways
            add(receipt)
        }
    }
}
