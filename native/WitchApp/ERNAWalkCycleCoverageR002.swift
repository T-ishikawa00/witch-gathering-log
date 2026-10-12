import Foundation

/// Pure QA-only walk-cycle gate. Inputs are sampled from the already-running
/// SpriteKit clip; this type never schedules an action or changes its cadence.
struct ERNAWalkCycleCoverageR002 {
    enum Outcome: Equatable {
        case waitingForFrameZero
        case observing(wrapCount: Int, uniqueFrameCount: Int)
        case complete
        case failed(String)
    }

    let expectedAssetIDs: [String]
    let requiredWraps: Int
    private(set) var outcome: Outcome = .waitingForFrameZero
    private(set) var uniqueIndices: Set<Int> = []
    private(set) var wraps = 0
    private var previousSceneFrame: Int?
    private var previousSceneTime: Double?
    private var previousIndex: Int?
    private var startedAtSceneTime: Double?

    init(expectedAssetIDs: [String], requiredWraps: Int = 3) {
        self.expectedAssetIDs = expectedAssetIDs
        self.requiredWraps = requiredWraps
    }

    mutating func observe(sceneFrame: Int, sceneTime: Double,
                          frameIndex: Int, bodyAssetID: String,
                          activeWalkAction: Bool, staffFrameIndex: Int,
                          staffBodyAssetID: String) -> Outcome {
        switch outcome {
        case .complete, .failed:
            return outcome
        default:
            return observeActive(sceneFrame: sceneFrame, sceneTime: sceneTime,
                                 frameIndex: frameIndex, bodyAssetID: bodyAssetID,
                                 activeWalkAction: activeWalkAction,
                                 staffFrameIndex: staffFrameIndex,
                                 staffBodyAssetID: staffBodyAssetID)
        }
    }

    private mutating func observeActive(sceneFrame: Int, sceneTime: Double,
                                        frameIndex: Int, bodyAssetID: String,
                                        activeWalkAction: Bool, staffFrameIndex: Int,
                                        staffBodyAssetID: String) -> Outcome {
        guard sceneFrame >= 0 else { return fail("scene_frame_invalid") }
        guard sceneTime.isFinite else { return fail("scene_time_not_finite") }
        if let prior = previousSceneFrame, sceneFrame <= prior { return fail("scene_frame_not_increasing") }
        if let prior = previousSceneTime, sceneTime <= prior { return fail("scene_time_not_increasing") }
        previousSceneFrame = sceneFrame
        previousSceneTime = sceneTime

        // The first texture assignment can race the observer arm by one rendered
        // frame. Preserve that raw sample in the caller, but begin coverage only
        // when the clip's exact frame-0 asset appears.
        if startedAtSceneTime == nil {
            guard frameIndex == 0 && expectedAssetIDs.first == bodyAssetID else {
                outcome = .waitingForFrameZero
                return outcome
            }
            guard activeWalkAction, staffFrameIndex == frameIndex, staffBodyAssetID == bodyAssetID else {
                return fail("frame_zero_staff_or_action_mismatch")
            }
            startedAtSceneTime = sceneTime
            previousIndex = 0
            uniqueIndices.insert(0)
            outcome = .observing(wrapCount: 0, uniqueFrameCount: 1)
            return outcome
        }

        guard activeWalkAction else { return fail("walk_action_not_active") }
        guard frameIndex >= 0 && frameIndex < expectedAssetIDs.count else { return fail("body_frame_index_out_of_range") }
        guard bodyAssetID == expectedAssetIDs[frameIndex] else { return fail("body_path_does_not_match_local_frame") }
        guard staffFrameIndex == frameIndex && staffBodyAssetID == bodyAssetID else { return fail("staff_did_not_follow_same_body_sample") }
        if let previousIndex {
            if frameIndex == previousIndex {
                // Repeated display samples are normal at render rates above 12 fps.
            } else if previousIndex == expectedAssetIDs.count - 1 && frameIndex == 0 {
                wraps += 1
            } else if frameIndex != previousIndex + 1 {
                return fail("walk_frame_sequence_discontinuity")
            }
        }
        previousIndex = frameIndex
        uniqueIndices.insert(frameIndex)
        if wraps >= requiredWraps && uniqueIndices == Set(expectedAssetIDs.indices) {
            outcome = .complete
        } else {
            outcome = .observing(wrapCount: wraps, uniqueFrameCount: uniqueIndices.count)
        }
        return outcome
    }

    private mutating func fail(_ reason: String) -> Outcome {
        outcome = .failed(reason)
        return outcome
    }
}
