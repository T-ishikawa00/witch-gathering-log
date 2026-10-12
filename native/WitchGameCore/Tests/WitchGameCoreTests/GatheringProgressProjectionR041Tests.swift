import Foundation
import XCTest
@testable import WitchGameCore

final class GatheringProgressProjectionR041Tests: XCTestCase {
    func testPreviewMatchesActualSettlementAtBoundariesAndCap() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for (elapsed, remainder) in [(0.0, 0.0), (299, 0), (300, 0), (301, 0), (299, 1), (600, 20), (200_000, 30)] {
            var initial = GameSnapshot.newGame(catalog: catalog)
            initial.activeRegionID = "R01"
            initial.lastClaimAt = start
            initial.offlineRemainderSeconds = remainder
            initial.gatherTargetMaterialID = "M_R01_G3" // locked target must use the same fallback as the engine
            let now = start.addingTimeInterval(elapsed)
            guard case .collecting(let reading) = GatheringProgressProjectionR041.read(catalog: catalog, state: initial, now: now) else {
                return XCTFail("valid gathering state did not produce a preview")
            }
            let repo = try SaveRepository(initial: initial)
            let engine = try GameEngine(catalog: catalog, saves: repo)
            let unchanged = await engine.snapshot()
            XCTAssertEqual(unchanged, initial)
            _ = try await engine.claimOffline(now: now, operationID: UUID(), expectedRevision: initial.revision)
            let claimed = await engine.snapshot()
            XCTAssertEqual(claimed.materials[reading.materialID, default: 0] - initial.materials[reading.materialID, default: 0], reading.readyUnits)
            XCTAssertEqual(claimed.gear, initial.gear)
            XCTAssertEqual(claimed.currency, initial.currency)
            XCTAssertEqual(reading.reachedCap, elapsed >= 48 * 3600)
        }
    }

    func testNextUnitCountdownAndReadyCountAreSeparate() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var state = GameSnapshot.newGame(catalog: catalog)
        state.activeRegionID = "R01"
        state.lastClaimAt = start
        for (elapsed, units, next) in [(0.0, 0, 300), (299.1, 0, 1), (300, 1, 300), (605, 2, 295)] {
            guard case .collecting(let reading) = GatheringProgressProjectionR041.read(catalog: catalog, state: state, now: start.addingTimeInterval(elapsed)) else { return XCTFail("missing reading") }
            XCTAssertEqual(reading.readyUnits, units)
            XCTAssertEqual(reading.secondsUntilNextUnit, next)
        }
    }

    func testUnavailableAndBackwardClockDoNotInventRewards() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = GameSnapshot.newGame(catalog: catalog)
        state.activeRegionID = nil
        XCTAssertEqual(GatheringProgressProjectionR041.read(catalog: catalog, state: state, now: now), .inactive)
        state.activeRegionID = "R01"
        state.lastClaimAt = now.addingTimeInterval(1)
        XCTAssertEqual(GatheringProgressProjectionR041.read(catalog: catalog, state: state, now: now), .clockBehind)
        state.lastClaimAt = now
        state.offlineRemainderSeconds = .nan
        XCTAssertEqual(GatheringProgressProjectionR041.read(catalog: catalog, state: state, now: now), .unavailable)
        state.offlineRemainderSeconds = 0
        XCTAssertEqual(GatheringProgressProjectionR041.read(catalog: catalog, state: state, now: Date(timeIntervalSince1970: .infinity)), .unavailable)
    }
    func testUnrepresentableCatalogCountdownDoesNotTrap() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        var regions = try XCTUnwrap(json["regions"] as? [[String: Any]])
        let index = try XCTUnwrap(regions.firstIndex { $0["id"] as? String == "R01" })
        regions[index]["workSeconds"] = Int.max
        json["regions"] = regions
        let unusual = try JSONDecoder().decode(GameCatalog.self, from: JSONSerialization.data(withJSONObject: json))
        var state = GameSnapshot.newGame(catalog: unusual)
        state.activeRegionID = "R01"
        XCTAssertEqual(GatheringProgressProjectionR041.read(catalog: unusual, state: state,
            now: Date(timeIntervalSince1970: 1_800_000_000)), .unavailable)
    }

}
