import Foundation

/// Pure, observer-side contracts for bounded samples from the existing SpriteKit
/// renderer. These values never drive or alter a SpriteKit action.
struct MotionCoverageR018 {
    struct ResolveSample: Equatable {
        let sceneGeneration: Int
        let sceneFrame: Int
        let actorID: String
        let state: String
        let bodyAssetID: String
        let localFrameIndex: Int
        let actionActive: Bool
    }

    struct WalkSample: Equatable {
        let sceneGeneration: Int
        let sceneFrame: Int
        let actorID: String
        let actionActive: Bool
        let bodyAssetID: String
        let frameIndex: Int
    }

    enum Outcome: Equatable {
        case observing
        case complete
        case incomplete(String)
    }

    private(set) var resolveSamples: [ResolveSample] = []
    private(set) var walkFrameTransitions: [Int] = []
    private var lastResolve: ResolveSample?
    private var lastWalkSceneFrame: Int?
    private var lastWalkIndex: Int?
    private var walkGeneration: Int?
    private let expectedWalkFrameCount: Int
    private let expectedResolveAssets = [
        "AIRA__rest_06.png", "AIRA__rest_07.png", "AIRA__rest_08.png"
    ]
    private var resolveSequenceIndex = 0
    private var resolveActionEnded = false

    init(expectedWalkFrameCount: Int = 9) {
        self.expectedWalkFrameCount = expectedWalkFrameCount
    }

    mutating func observeResolve(_ sample: ResolveSample) -> Outcome {
        guard sample.sceneFrame >= 0, !sample.actorID.isEmpty,
              !sample.bodyAssetID.isEmpty,
              (0...2).contains(sample.localFrameIndex) else { return .incomplete("invalid_resolve_sample") }
        guard sample.state == "resolve" else {
            return resolveActionEnded ? .complete : .incomplete("resolve_state_ended_before_terminal_hold")
        }
        if let previous = lastResolve {
            guard sample.sceneGeneration == previous.sceneGeneration else {
                return .incomplete("scene_generation_changed_during_resolve")
            }
            guard sample.actorID == previous.actorID else { return .incomplete("actor_changed_during_resolve") }
            guard sample.sceneFrame > previous.sceneFrame else { return .incomplete("nonmonotonic_resolve_scene_frame") }
            guard sample.sceneFrame == previous.sceneFrame + 1 else { return .incomplete("resolve_sample_gap") }
        }
        if resolveSequenceIndex < expectedResolveAssets.count {
            let expectedAsset = expectedResolveAssets[resolveSequenceIndex]
            if sample.localFrameIndex == resolveSequenceIndex,
               sample.bodyAssetID.hasSuffix(expectedAsset) {
                guard sample.actionActive else { return .incomplete("resolve_action_ended_before_all_frames") }
                resolveSequenceIndex += 1
            } else if resolveSequenceIndex > 0,
                      sample.localFrameIndex == resolveSequenceIndex - 1,
                      sample.bodyAssetID.hasSuffix(expectedResolveAssets[resolveSequenceIndex - 1]),
                      sample.actionActive {
                // Repeated render callbacks during this authored frame's dwell.
            } else {
                return .incomplete("resolve_asset_sequence_mismatch")
            }
        } else {
            // SpriteKit keeps rendering the final texture while its authored
            // duration runs (rest_08 is 240 ms). Accept each contiguous frame-2
            // sample while active; completion requires a later inactive frame-2
            // sample, proving that the same terminal pose remains after action end.
            guard sample.localFrameIndex == 2,
                  sample.bodyAssetID.hasSuffix(expectedResolveAssets[2]) else {
                return .incomplete("resolve_terminal_pose_not_held")
            }
            if sample.actionActive { 
                resolveSamples.append(sample)
                lastResolve = sample
                return .observing
            }
            resolveActionEnded = true
        }
        resolveSamples.append(sample)
        lastResolve = sample
        return resolveActionEnded ? .complete : .observing
    }

    /// Call only for a dedicated isolated walk observation. Repeated render
    /// callbacks of one texture collapse; every transition must follow the
    /// actual expected path 0...N-1, including both observed wraps.
    mutating func observeWalk(_ sample: WalkSample) -> Outcome {
        guard expectedWalkFrameCount > 1, sample.sceneFrame >= 0,
              !sample.actorID.isEmpty, !sample.bodyAssetID.isEmpty,
              (0..<expectedWalkFrameCount).contains(sample.frameIndex) else {
            return .incomplete("invalid_walk_sample")
        }
        guard sample.actionActive else { return .incomplete("walk_action_not_active") }
        if let generation = walkGeneration, generation != sample.sceneGeneration {
            return .incomplete("scene_generation_changed_during_walk")
        }
        if let previousFrame = lastWalkSceneFrame, sample.sceneFrame <= previousFrame {
            return .incomplete("nonmonotonic_walk_scene_frame")
        }
        if let previousIndex = lastWalkIndex, previousIndex != sample.frameIndex {
            let expected = (previousIndex + 1) % expectedWalkFrameCount
            guard sample.frameIndex == expected,
                  sample.bodyAssetID.hasSuffix("AIRA__walk_\(sample.frameIndex).png") else {
                return .incomplete("walk_frame_transition_gap_or_reversal")
            }
            walkFrameTransitions.append(sample.frameIndex)
        } else if lastWalkIndex == nil {
            guard sample.frameIndex == 0,
                  sample.bodyAssetID.hasSuffix("AIRA__walk_0.png") else { return .incomplete("walk_did_not_start_at_frame_zero") }
            walkFrameTransitions.append(0)
        }
        walkGeneration = sample.sceneGeneration
        lastWalkSceneFrame = sample.sceneFrame
        lastWalkIndex = sample.frameIndex
        // Count the initial frame 0 and every transition through the second
        // wrap. For N frames, 0...N-1,0...N-1 contains only one wrap; the final
        // 0 is the observable boundary proving the second full cycle completed.
        let required = expectedWalkFrameCount * 2 + 1
        return walkFrameTransitions.count >= required ? .complete : .observing
    }
}
