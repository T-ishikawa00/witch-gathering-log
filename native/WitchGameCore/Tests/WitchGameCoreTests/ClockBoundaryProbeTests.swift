import Foundation
import XCTest
@testable import WitchGameCore

/// Opt-in characterization, not an assertion that caller time is secure.
final class ClockBoundaryProbeTests: XCTestCase {
    func testCallerSuppliedDailyDatesAcrossRestart() async throws {
        guard let output = ProcessInfo.processInfo.environment["WITCH_CLOCK_PROBE_OUTPUT"] else {
            throw XCTSkip("Explicit local clock-boundary evidence run only")
        }
        let catalog = try GameCatalog.bundledTestOverlay()
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.gachaUnlocked = true
        let save = FileManager.default.temporaryDirectory.appendingPathComponent("witch-clock-probe-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: save)
            try? FileManager.default.removeItem(at: save.appendingPathExtension("lock"))
        }
        let repository = try SaveRepository(initial: initial, fileURL: save)
        let engine = try GameEngine(catalog: catalog, saves: repository)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let start = ProcessInfo.processInfo.systemUptime
        var rows: [[String: Any]] = []
        for offset in [0, 1, 30] {
            let before = await engine.snapshot()
            let receipt = try await engine.dispatch(.dailyClaim(now: day.addingTimeInterval(Double(offset) * 86_400)),
                operationID: UUID(), expectedRevision: before.revision)
            let after = await engine.snapshot()
            rows.append(["suppliedDayOffset": offset, "revision": receipt.revision,
                         "ticketDelta": after.currency["ticket_free", default: 0] - before.currency["ticket_free", default: 0]])
        }
        let reopened = try GameEngine(catalog: catalog, saves: SaveRepository(fileURL: save))
        let beforeBackdate = await reopened.snapshot()
        let bytes = try Data(contentsOf: save)
        var rejection = ""
        do {
            _ = try await reopened.dispatch(.dailyClaim(now: day), operationID: UUID(), expectedRevision: beforeBackdate.revision)
            XCTFail("The recorded future timestamp did not reject a return to day0")
        } catch { rejection = String(reflecting: error) }
        let afterBackdate = await reopened.snapshot()
        XCTAssertEqual(beforeBackdate, afterBackdate)
        XCTAssertEqual(bytes, try Data(contentsOf: save))
        let report: [String: Any] = ["status": "CALLER_TIME_TRUST_BOUNDARY_REPRODUCED",
            "scope": "Core supplied-Date injection only; host/device clock and security settings unchanged",
            "elapsedMonotonicSeconds": ProcessInfo.processInfo.systemUptime - start,
            "claims": rows, "restartRevision": beforeBackdate.revision,
            "returnToOriginalDayError": rejection, "rejectedReturnSaveUnchanged": true,
            "productionTimeAuthority": false, "humanApproval": false]
        let url = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}
