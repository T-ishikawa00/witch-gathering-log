import XCTest
@testable import WitchGameCore

final class LunaBookMotionTests: XCTestCase {
    func testBookGearProducesCompleteMotionSequences() throws {
        for gearID in ["EQ_A_01", "EQ_A_02", "EQ_A_03"] {
            let walk = try XCTUnwrap(LunaBookMotion.frames(state: "walk", gearID: gearID))
            let attack = try XCTUnwrap(LunaBookMotion.frames(state: "attack", gearID: gearID))
            XCTAssertEqual(walk.count, 9)
            XCTAssertEqual(attack.count, 9)
            XCTAssertEqual(attack.map(\.poseState), ["anticipate", "anticipate", "anticipate", "execute", "execute", "execute", "recover", "recover", "recover"])
            XCTAssertEqual(Set((walk + attack).map(\.bodyAssetID)).count, 18)
            XCTAssertTrue((walk + attack).allSatisfy { $0.attachment.gearID == gearID })
        }
    }

    func testRestAndIndividualAttackPhasesHaveThreePairedFrames() throws {
        for state in ["anticipate", "execute", "recover", "idle", "hit", "resolve"] {
            let frames = try XCTUnwrap(LunaBookMotion.frames(state: state, gearID: "EQ_A_02"))
            XCTAssertEqual(frames.count, 3, state)
            XCTAssertEqual(frames.map(\.sequenceIndex), [0, 1, 2], state)
            let expected = state == "idle" ? [450, 180, 450] : [100, 100, 100]
            XCTAssertEqual(frames.map(\.durationMilliseconds), expected)
            XCTAssertTrue(frames.allSatisfy { $0.durationMilliseconds == $0.attachment.durationMilliseconds })
        }
    }

    func testPlaybackEmitsBodyAndAttachmentInMatchedOrder() {
        var callbacks: [String] = []
        let started = LunaBookMotion.play(state: "attack", gearID: "EQ_A_03", on: { frame in
            callbacks.append("body:\(frame.sequenceIndex):\(frame.bodyAssetID)")
        }, attach: { attachment in
            callbacks.append("book:\(attachment.sequenceIndex):\(attachment.layerAssetID)")
        })
        XCTAssertTrue(started)
        XCTAssertEqual(callbacks.count, 18)
        for index in 0..<9 {
            XCTAssertTrue(callbacks[index * 2].hasPrefix("body:\(index):"))
            XCTAssertEqual(callbacks[index * 2 + 1], "book:\(index):BOOK_EQ_A_03")
        }
    }

    func testUnsupportedGearOrStateDoesNotFallbackToWrongAppearance() {
        XCTAssertNil(LunaBookMotion.frames(state: "idle", gearID: "EQ_A_99"))
        XCTAssertNil(LunaBookMotion.frames(state: "fly", gearID: "EQ_A_01"))
        XCTAssertFalse(LunaBookMotion.play(state: "idle", gearID: "EQ_A_99", on: { _ in XCTFail("unexpected body") }, attach: { _ in XCTFail("unexpected book") }))
    }

    func testTransformsAndHandMasksAreFiniteAndNormalized() throws {
        for gearID in LunaBookMotion.supportedGearIDs {
            let frames = try XCTUnwrap(LunaBookMotion.frames(state: "attack", gearID: gearID)) +
                XCTUnwrap(LunaBookMotion.frames(state: "walk", gearID: gearID))
            for frame in frames {
                let t = frame.attachment.transform
                let m = frame.attachment.palmOcclusionMask
                XCTAssertTrue([t.centerX, t.centerY, t.rotationDegrees, t.scale, m.centerX, m.centerY, m.radiusX, m.radiusY].allSatisfy(\.isFinite))
                XCTAssertTrue((0...1).contains(t.centerX) && (0...1).contains(t.centerY))
                XCTAssertGreaterThan(t.scale, 0)
                XCTAssertTrue((0...1).contains(m.centerX) && (0...1).contains(m.centerY))
                XCTAssertTrue((0...1).contains(m.radiusX) && (0...1).contains(m.radiusY))
            }
        }
    }
}
