import XCTest
@testable import WitchGameCore

final class MothIdleAnchorRegistrationR050Tests: XCTestCase {
    private let flags = ["--qa-isolated", "--qa-moth-idle-registration-r050"]

    private func facts() -> MothIdleAnchorClipFactsR050 {
        let hashes = MothIdleAnchorRegistrationR050.expectedSHA256ByPath
        return MothIdleAnchorRegistrationR050.expectedPaths.map { path in
            MothIdleAnchorAnchorFrameFixture(path: path, sha: hashes[path] ?? "missing-pin")
        }.withClipFacts()
    }

    func testPinnedSixFramePlanUsesCorrectTopLeftToSpriteKitSignAndPreservesCadence() throws {
        guard case .allowed(let plan) = MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts()) else {
            return XCTFail("expected exact pinned clip to be permitted")
        }
        XCTAssertEqual(plan.frames.map(\.frameIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(plan.frames.map(\.sourceOffsetYTopDown), [-18, -19, 6, 34, 6, -19])
        XCTAssertEqual(plan.frameDurationSeconds, 0.125, accuracy: 0.000001)
        XCTAssertEqual(plan.frames[0].normalizedAnchorYBottomUp, 1 - 300.0 / 512 - 18.0 / 512, accuracy: 0.000001)
        XCTAssertEqual(plan.frames[3].normalizedAnchorYBottomUp, 1 - 300.0 / 512 + 34.0 / 512, accuracy: 0.000001)
        XCTAssertTrue(plan.frames.allSatisfy { $0.normalizedAnchorX == 0.5 })
        XCTAssertEqual(plan.baseAnchorNormalizedX, 0.5, accuracy: 0.000001)
        XCTAssertEqual(plan.baseAnchorNormalizedYBottomUp, 1 - 300.0 / 512, accuracy: 0.000001)
    }

    func testHorizontalAndVerticalVisualTranslationSignsAndInvalidDimensions() throws {
        let anchor = try XCTUnwrap(MothIdleAnchorRegistrationR050.normalizedAnchor(
            baseTopLeftX: 256, baseTopLeftY: 300, canvasWidth: 512, canvasHeight: 512,
            offsetXRight: 12, offsetYDown: -20))
        XCTAssertEqual(anchor.x, 0.5 - 12.0 / 512, accuracy: 0.000001)
        XCTAssertEqual(anchor.y, 1 - 300.0 / 512 - 20.0 / 512, accuracy: 0.000001)
        XCTAssertNil(MothIdleAnchorRegistrationR050.normalizedAnchor(
            baseTopLeftX: 256, baseTopLeftY: 300, canvasWidth: 0, canvasHeight: 512,
            offsetXRight: 0, offsetYDown: 0))
    }

    func testLegacyQAPlanAPIStillRequiresBothFlags() {
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: [], facts: facts()), .notRequested)
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: ["--qa-isolated"], facts: facts()),
                       .rejected("both_isolated_and_candidate_flags_required"))
        XCTAssertTrue(MothIdleAnchorRegistrationR050.isEnabled(arguments: flags))
    }

    func testLocalDevelopmentDefaultAndIsolatedSimulatorBaselineOverride() {
        XCTAssertTrue(MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: [], isSimulator: true))
        XCTAssertTrue(MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: [], isSimulator: false))
        let baseline = ["--qa-isolated", "--qa-moth-idle-baseline-r050"]
        XCTAssertFalse(MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: baseline, isSimulator: true))
        XCTAssertTrue(MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: baseline, isSimulator: false))
        XCTAssertTrue(MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: [baseline[1]], isSimulator: true))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.validatedPlan(facts: facts()),
                       MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts()))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.validatedPlan(facts: facts().changingFrame(0, sha: "changed")),
                       .rejected("frame_0_sha256_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.validatedPlan(facts: facts().changing(state: "walk")),
                       .rejected("state_mismatch"))
    }

    func testRejectsWrongActorAndNonIdleState() {
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(actorID: "ACT_E_R02_03")),
                       .rejected("actor_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(state: "walk")),
                       .rejected("state_mismatch"))
    }

    func testRejectsChangedFrameOrderPathHashAndCanvas() {
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changingFrame(0, path: "wrong.png")),
                       .rejected("frame_0_path_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changingFrame(2, sha: String(repeating: "0", count: 64))),
                       .rejected("frame_2_sha256_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changingFrame(4, width: 256)),
                       .rejected("frame_4_canvas_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().droppingLastFrame()),
                       .rejected("frame_count_mismatch"))
    }

    func testRejectsClipMetadataDrift() {
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(canvasWidth: 256)),
                       .rejected("clip_canvas_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(anchorTopLeftY: 301)),
                       .rejected("clip_anchor_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(fps: 12)),
                       .rejected("clip_fps_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(displayScale: 0.9)),
                       .rejected("display_scale_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(loops: false)),
                       .rejected("clip_must_loop"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(declaredFrameCount: 5)),
                       .rejected("declared_frame_count_mismatch"))
        XCTAssertEqual(MothIdleAnchorRegistrationR050.plan(arguments: flags, facts: facts().changing(durationSeconds: 1)),
                       .rejected("clip_duration_mismatch"))
    }
}

private struct MothIdleAnchorAnchorFrameFixture {
    let path: String
    let sha: String
    var width = 512.0
    var height = 512.0
    var core: MothIdleAnchorFrameR050 { .init(path: path, sha256: sha, canvasWidth: width, canvasHeight: height) }
}

private extension Array where Element == MothIdleAnchorFrameR050 {
    func withClipFacts() -> MothIdleAnchorClipFactsR050 {
        .init(actorID: MothIdleAnchorRegistrationR050.actorID, state: MothIdleAnchorRegistrationR050.state,
              frames: self, canvasWidth: 512, canvasHeight: 512, anchorTopLeftX: 256,
              anchorTopLeftY: 300, declaredFrameCount: 6, fps: 8,
              durationSeconds: 0.75, displayScale: 1, loops: true)
    }
}

private extension MothIdleAnchorClipFactsR050 {
    func changing(actorID: String? = nil, state: String? = nil, canvasWidth: Double? = nil,
                  anchorTopLeftY: Double? = nil, fps: Double? = nil,
                  displayScale: Double? = nil, loops: Bool? = nil,
                  declaredFrameCount: Int? = nil, durationSeconds: Double? = nil) -> Self {
        .init(actorID: actorID ?? self.actorID, state: state ?? self.state, frames: frames,
              canvasWidth: canvasWidth ?? self.canvasWidth, canvasHeight: canvasHeight,
              anchorTopLeftX: anchorTopLeftX, anchorTopLeftY: anchorTopLeftY ?? self.anchorTopLeftY,
              declaredFrameCount: declaredFrameCount ?? self.declaredFrameCount, fps: fps ?? self.fps,
              durationSeconds: durationSeconds ?? self.durationSeconds,
              displayScale: displayScale ?? self.displayScale, loops: loops ?? self.loops)
    }
    func changingFrame(_ index: Int, path: String? = nil, sha: String? = nil, width: Double? = nil) -> Self {
        var values = frames
        let old = values[index]
        values[index] = .init(path: path ?? old.path, sha256: sha ?? old.sha256,
                              canvasWidth: width ?? old.canvasWidth, canvasHeight: old.canvasHeight)
        return .init(actorID: actorID, state: state, frames: values, canvasWidth: canvasWidth,
                     canvasHeight: canvasHeight, anchorTopLeftX: anchorTopLeftX, anchorTopLeftY: anchorTopLeftY,
                     declaredFrameCount: declaredFrameCount, fps: fps, durationSeconds: durationSeconds,
                     displayScale: displayScale, loops: loops)
    }
    func droppingLastFrame() -> Self {
        .init(actorID: actorID, state: state, frames: Array(frames.dropLast()), canvasWidth: canvasWidth,
              canvasHeight: canvasHeight, anchorTopLeftX: anchorTopLeftX, anchorTopLeftY: anchorTopLeftY,
              declaredFrameCount: declaredFrameCount, fps: fps, durationSeconds: durationSeconds,
              displayScale: displayScale, loops: loops)
    }
}

private extension Array where Element == MothIdleAnchorAnchorFrameFixture {
    func withClipFacts() -> MothIdleAnchorClipFactsR050 {
        map(\.core).withClipFacts()
    }
}
