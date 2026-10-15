import XCTest
import CryptoKit

/// The host supplies isolated, archived copies; these tests never edit save bytes.
final class SaveRecoveryR120UITests: XCTestCase {
    private let app = XCUIApplication()

    private func launch(_ variable: String) throws -> String {
        guard let key = ProcessInfo.processInfo.environment[variable] else {
            throw XCTSkip("The archived R120 host fixture is required")
        }
        let prefix = "save-r120-"
        guard key.hasPrefix(prefix), UUID(uuidString: String(key.dropFirst(prefix.count))) != nil else {
            XCTFail("Unexpected save fixture key")
            throw NSError(domain: "SaveRecoveryR120", code: 1)
        }
        continueAfterFailure = false
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key]
        app.launch()
        return key
    }

    private func capture(_ name: String, key: String) throws {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let executable = try XCTUnwrap(Bundle(for: type(of: self)).executableURL)
        let hash = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        let identity = ["testCase": self.name, "saveKey": key, "testExecutableSHA256": hash]
        let data = try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name + "_identity"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPreviousGenerationRecoveryNoticeCanBeDismissed() throws {
        let key = try launch("WITCH_R120_RECOVERY_SAVE_KEY")
        let notice = app.alerts["セーブを復元しました"]
        XCTAssertTrue(notice.waitForExistence(timeout: 20))
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "最後の操作が反映されていない")).firstMatch.exists)
        try capture("save_r120_recovery_notice", key: key)
        let close = app.buttons["dismiss_save_notice"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout: 10))
        XCTAssertFalse(notice.exists)
        try capture("save_r120_recovered_home", key: key)
        app.terminate()
    }

    func testFutureSaveRefusedWithoutOpeningGame() throws {
        let key = try launch("WITCH_R120_FUTURE_SAVE_KEY")
        let error = app.staticTexts["launch_error"]
        XCTAssertTrue(error.waitForExistence(timeout: 20))
        XCTAssertTrue(error.label.contains("元のデータは保持しています"))
        XCTAssertFalse(app.buttons["tab_家"].exists)
        try capture("save_r120_future_refused", key: key)
        app.buttons["launch_retry"].tap()
        XCTAssertTrue(error.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["tab_家"].exists)
        try capture("save_r120_future_retry_refused", key: key)
        app.terminate()
    }
}
