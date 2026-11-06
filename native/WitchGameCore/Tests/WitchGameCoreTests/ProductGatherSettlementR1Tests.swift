import Foundation
import XCTest
@testable import WitchGameCore

final class ProductGatherSettlementR1Tests: XCTestCase {
    func testExplicitGatherSettlesCurrentNaturalProfileOnlyOnceAndColdRetryIsIdempotent() async throws {
        let profile=try StandardPlayRuntimeProfileR1(base:GameRuntimeConfigurationR098.resolve(),options:.r020CurrentAppCandidate)
        let initial=try profile.makeNewSnapshot()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("product-gather-r1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url=directory.appendingPathComponent("save.json")
        let engine=try await profile.makeEngine(saves:SaveRepository(initial:initial,fileURL:url))
        let start=Date(timeIntervalSince1970:1_800_000_000)
        let region=try XCTUnwrap(profile.base.catalog.regions.first)
        let material=try XCTUnwrap(region.gatherMaterialIDs.first)
        _=try await engine.dispatch(.startExpeditionAt(regionID:region.id,now:start),operationID:UUID(),expectedRevision:initial.revision)
        let before=await engine.snapshot()
        let now=start.addingTimeInterval(Double(region.workSeconds)*2)
        let operation=UUID()
        let receipt=try await engine.dispatchConfirmingSavedReceipt(.gather(resourceID:material,now:now),
            operationID:operation,expectedRevision:before.revision)
        let after=await engine.snapshot()
        XCTAssertEqual(after.materials[material,default:0],before.materials[material,default:0]+2)
        XCTAssertEqual(after.revision,before.revision+1)
        XCTAssertTrue(receipt.result.contains("x2"))
        let cold=try await profile.makeEngine(saves:SaveRepository(fileURL:url))
        _=try await cold.dispatchConfirmingSavedReceipt(.gather(resourceID:material,now:now),operationID:operation,expectedRevision:before.revision)
        let retry=await cold.snapshot()
        XCTAssertEqual(retry,after)
        do {
            _=try await cold.dispatch(.gather(resourceID:material,now:now),operationID:UUID(),expectedRevision:after.revision)
            XCTFail("No elapsed unit must not grant anything")
        } catch {}
        let empty=await cold.snapshot()
        XCTAssertEqual(empty,after)
    }
}
