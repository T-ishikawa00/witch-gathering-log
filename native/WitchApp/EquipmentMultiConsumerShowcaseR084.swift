import Foundation

/// Frame-counted choreography for a QA-only render showcase. It requests
/// existing authored poses on all four party actors but dispatches no game
/// command. A caller must record the returned phase as requested state and
/// separately supply the actual action/pose state observed after rendering.
struct EquipmentMultiConsumerShowcaseR084 {
    enum Step: Equatable {
        case applyPose(String)
        case finished
        case incomplete(String)
    }

    static let phases = ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"]
    static let partyActors = ["ERNA", "LUNA", "AIRA", "NOIR"]
    let minimumRenderedFramesPerPhase: Int
    let maximumRenderedFramesPerPhase: Int
    private(set) var phaseIndex = 0
    private(set) var matchingRenderedFrames = 0
    private(set) var phaseFrameCount = 0
    private(set) var lastSceneFrame = -1
    private(set) var status = "READY"

    init(minimumRenderedFramesPerPhase: Int = 90, maximumRenderedFramesPerPhase: Int = 360) {
        self.minimumRenderedFramesPerPhase = max(2, minimumRenderedFramesPerPhase)
        self.maximumRenderedFramesPerPhase = max(self.minimumRenderedFramesPerPhase, maximumRenderedFramesPerPhase)
    }

    var currentPhase: String? {
        guard status == "RUNNING", phaseIndex < Self.phases.count else { return nil }
        return Self.phases[phaseIndex]
    }

    mutating func start() -> Step {
        guard status == "READY" else { return .incomplete("showcase_started_more_than_once") }
        status = "RUNNING"
        return .applyPose(Self.phases[0])
    }

    /// Call exactly once after each observer sample in didFinishUpdate.
    /// A phase advances only after every expected actor's *actual* rendered
    /// state matches the requested state for the configured frame count.
    mutating func didRender(sceneFrame: Int, actualStateBySprite: [String: String]) -> Step? {
        guard status == "RUNNING", let phase = currentPhase else { return nil }
        guard sceneFrame > lastSceneFrame else {
            status = "INCOMPLETE"
            return .incomplete("non_monotonic_scene_frame")
        }
        lastSceneFrame = sceneFrame
        phaseFrameCount += 1
        let matches = Self.partyActors.allSatisfy { actualStateBySprite[$0] == phase }
        if matches { matchingRenderedFrames += 1 } else { matchingRenderedFrames = 0 }
        if matchingRenderedFrames >= minimumRenderedFramesPerPhase {
            phaseIndex += 1
            phaseFrameCount = 0
            matchingRenderedFrames = 0
            guard phaseIndex < Self.phases.count else {
                status = "CAPTURED_FORCED_RENDER_SHOWCASE"
                return .finished
            }
            return .applyPose(Self.phases[phaseIndex])
        }
        if phaseFrameCount >= maximumRenderedFramesPerPhase {
            status = "INCOMPLETE"
            return .incomplete("actual_pose_not_rendered_for_" + phase)
        }
        return nil
    }
}
