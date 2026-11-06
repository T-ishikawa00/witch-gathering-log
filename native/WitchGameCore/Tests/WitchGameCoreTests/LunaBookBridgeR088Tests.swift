import XCTest
@testable import WitchGameCore

final class LunaBookBridgeR088Tests: XCTestCase {
    func testDualOptInPreservesAttackBudgetAndPairedAttachmentsForAllBooks() throws {
        for gear in LunaBookMotion.supportedGearIDs {
            for state in ["execute", "attack"] {
                let baseline = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: gear))
                let bridge = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: gear,
                    includeR050ExecuteRecoverMidpoint: true, includeR088BridgeAfterMidpoint: true))
                XCTAssertEqual(bridge.reduce(0) { $0 + $1.durationMilliseconds },
                               baseline.reduce(0) { $0 + $1.durationMilliseconds })
                let index = try XCTUnwrap(bridge.firstIndex { $0.bodyAssetID == LunaBookMotionDataR088Candidate.bodyAssetID })
                XCTAssertEqual(bridge[index - 1].bodyAssetID, LunaBookMotionDataR050Candidate.bodyAssetID)
                XCTAssertEqual(Array(bridge[(index - 2)...index].map(\.durationMilliseconds)), [34, 33, 33])
                XCTAssertEqual(bridge[index].bodyAnchorY, 106.0 / 1254.0, accuracy: 1e-12)
                for (sequence, frame) in bridge.enumerated() {
                    XCTAssertEqual(frame.attachment.gearID, gear)
                    XCTAssertEqual(frame.sequenceIndex, sequence)
                    XCTAssertEqual(frame.attachment.sequenceIndex, sequence)
                    XCTAssertEqual(frame.durationMilliseconds, frame.attachment.durationMilliseconds)
                }
            }
        }
    }

    func testBridgeFlagAloneCannotChangeDefaultOrUnrelatedClips() throws {
        for gear in LunaBookMotion.supportedGearIDs {
            for state in LunaBookMotion.supportedStates {
                let baseline = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: gear))
                let flagOnly = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: gear, includeR088BridgeAfterMidpoint: true))
                XCTAssertEqual(baseline.map(\.bodyAssetID), flagOnly.map(\.bodyAssetID))
                XCTAssertEqual(baseline.map(\.durationMilliseconds), flagOnly.map(\.durationMilliseconds))
            }
        }
    }
}
