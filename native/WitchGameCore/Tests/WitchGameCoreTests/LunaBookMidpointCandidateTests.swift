import XCTest
@testable import WitchGameCore

final class LunaBookMidpointCandidateTests: XCTestCase {
    private let books = ["EQ_A_01": "BOOK_EQ_A_01", "EQ_A_02": "BOOK_EQ_A_02", "EQ_A_03": "BOOK_EQ_A_03"]

    func testDefaultClipsKeepOriginalFrameCountsAndAnchor() throws {
        for gear in books.keys {
            for state in ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"] {
                let frames = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: gear))
                XCTAssertEqual(frames.count, state == "walk" ? 9 : 3, "\(gear):\(state)")
                XCTAssertFalse(frames.contains { $0.bodyAssetID == LunaBookMotionDataR050Candidate.bodyAssetID })
                XCTAssertTrue(frames.allSatisfy { $0.bodyAnchorY == 12.0 / 256.0 })
                XCTAssertTrue(frames.allSatisfy { $0.attachment.layerAssetID == books[gear] })
            }
        }
    }

    func testOptInAddsMidpointBetweenExecuteAndRecoverWithoutExtendingAttack() throws {
        for gear in books.keys {
            let ordinary = try XCTUnwrap(LunaBookMotion.frames(state: "attack", gearID: gear))
            let candidate = try XCTUnwrap(LunaBookMotion.frames(state: "attack", gearID: gear, includeR050ExecuteRecoverMidpoint: true))
            XCTAssertEqual(ordinary.reduce(0) { $0 + $1.durationMilliseconds }, 900)
            XCTAssertEqual(candidate.reduce(0) { $0 + $1.durationMilliseconds }, 900)
            let index = try XCTUnwrap(candidate.firstIndex { $0.bodyAssetID == LunaBookMotionDataR050Candidate.bodyAssetID })
            XCTAssertEqual(index, 6)
            XCTAssertEqual(candidate[index - 1].bodyAssetID, "LUNA_BOOK_MOTION_EXECUTE_F03_CANDIDATE_R001")
            XCTAssertEqual(candidate[index + 1].bodyAssetID, "LUNA_BOOK_MOTION_RECOVER_F01_CANDIDATE_R001")
            XCTAssertEqual(candidate[index].attachment.layerAssetID, books[gear])
            XCTAssertEqual(candidate[index].bodyAnchorY, 0.09140625, accuracy: 1e-12)
            let execution = candidate.filter { $0.poseState == "execute" }
            XCTAssertEqual(execution.map(\.durationMilliseconds), [100, 100, 50, 50])
        }
    }

    func testOptInPreservesOtherClipsAndRejectsUnsupportedEquipment() throws {
        for gear in books.keys {
            for state in ["idle", "walk", "anticipate", "recover", "hit", "resolve"] {
                let before = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: gear))
                let after = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: gear, includeR050ExecuteRecoverMidpoint: true))
                XCTAssertEqual(before.map(\.bodyAssetID), after.map(\.bodyAssetID))
                XCTAssertEqual(before.map(\.durationMilliseconds), after.map(\.durationMilliseconds))
            }
        }
        XCTAssertNil(LunaBookMotion.frames(state: "execute", gearID: "EQ_S_03", includeR050ExecuteRecoverMidpoint: true))
        XCTAssertNil(LunaBookMotion.frames(state: "missing", gearID: "EQ_A_01", includeR050ExecuteRecoverMidpoint: true))
    }
}
