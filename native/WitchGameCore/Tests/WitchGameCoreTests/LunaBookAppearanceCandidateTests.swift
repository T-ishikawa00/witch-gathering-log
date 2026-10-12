import XCTest
@testable import WitchGameCore

final class LunaBookAppearanceCandidateTests: XCTestCase {
    func testAllThreeBooksMapAcrossSevenStateKeyposes() throws {
        let states = ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"]
        for gearID in ["EQ_A_01", "EQ_A_02", "EQ_A_03"] {
            let baseLayer = "BOOK_\(gearID)"
            for state in states {
                let projection = try XCTUnwrap(LunaBookAppearanceCandidate.resolve(actorID: "C_APPRENTICE", gearID: gearID, isEquipped: true, poseState: state))
                XCTAssertEqual(projection.gearID, gearID)
                XCTAssertEqual(projection.bookLayerAssetID, state == "idle" ? baseLayer : "\(baseLayer)__\(state)")
                XCTAssertEqual(projection.basePoseAssetID, "LUNA_BOOKLESS_\(state.uppercased())_CANDIDATE_R001")
                XCTAssertEqual(projection.canvasWidth, 256)
                XCTAssertEqual(projection.canvasHeight, 256)
                XCTAssertEqual(projection.bookTopLeftX, 104)
                XCTAssertEqual(projection.bookTopLeftY, 136)
                XCTAssertTrue(projection.requiresHandForegroundOcclusion)
            }
        }
    }

    func testBookCandidateDoesNotResolveForOtherActorsUnequippedOrUnsupportedStates() {
        XCTAssertNil(LunaBookAppearanceCandidate.resolve(actorID: "C_WITCH", gearID: "EQ_A_01", isEquipped: true, poseState: "idle"))
        XCTAssertNil(LunaBookAppearanceCandidate.resolve(actorID: "C_APPRENTICE", gearID: "EQ_A_01", isEquipped: false, poseState: "idle"))
        XCTAssertNil(LunaBookAppearanceCandidate.resolve(actorID: "C_APPRENTICE", gearID: "EQ_A_01", isEquipped: true, poseState: "teleport"))
        XCTAssertNil(LunaBookAppearanceCandidate.resolve(actorID: "C_APPRENTICE", gearID: "EQ_A_04", isEquipped: true, poseState: "idle"))
    }
}
