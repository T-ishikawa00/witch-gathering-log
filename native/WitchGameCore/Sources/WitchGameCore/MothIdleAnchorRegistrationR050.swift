import Foundation

public struct MothIdleAnchorPointR050: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct MothIdleAnchorFrameR050: Equatable, Sendable {
    public let path: String
    public let sha256: String
    public let canvasWidth: Double
    public let canvasHeight: Double
    public init(path: String, sha256: String, canvasWidth: Double, canvasHeight: Double) {
        self.path = path; self.sha256 = sha256
        self.canvasWidth = canvasWidth; self.canvasHeight = canvasHeight
    }
}

public struct MothIdleAnchorClipFactsR050: Equatable, Sendable {
    public let actorID: String
    public let state: String
    public let frames: [MothIdleAnchorFrameR050]
    public let canvasWidth: Double
    public let canvasHeight: Double
    /// Authored clip anchor in top-left image pixel coordinates.
    public let anchorTopLeftX: Double
    public let anchorTopLeftY: Double
    public let declaredFrameCount: Int
    public let fps: Double
    public let durationSeconds: Double
    public let displayScale: Double
    public let loops: Bool
    public init(actorID: String, state: String, frames: [MothIdleAnchorFrameR050],
                canvasWidth: Double, canvasHeight: Double, anchorTopLeftX: Double,
                anchorTopLeftY: Double, declaredFrameCount: Int, fps: Double,
                durationSeconds: Double, displayScale: Double, loops: Bool) {
        self.actorID = actorID; self.state = state; self.frames = frames
        self.canvasWidth = canvasWidth; self.canvasHeight = canvasHeight
        self.anchorTopLeftX = anchorTopLeftX; self.anchorTopLeftY = anchorTopLeftY
        self.declaredFrameCount = declaredFrameCount
        self.fps = fps; self.durationSeconds = durationSeconds
        self.displayScale = displayScale; self.loops = loops
    }
}

public struct MothIdleAnchorFramePlanR050: Equatable, Sendable {
    public let frameIndex: Int
    public let path: String
    public let sourceOffsetX: Double
    public let sourceOffsetYTopDown: Double
    public let normalizedAnchorX: Double
    public let normalizedAnchorYBottomUp: Double
}

public struct MothIdleAnchorPlanR050: Equatable, Sendable {
    public let frames: [MothIdleAnchorFramePlanR050]
    public let baseAnchorNormalizedX: Double
    public let baseAnchorNormalizedYBottomUp: Double
    public let fps: Double
    public let frameDurationSeconds: Double
}

public enum MothIdleAnchorDecisionR050: Equatable, Sendable {
    case notRequested
    case rejected(String)
    case allowed(MothIdleAnchorPlanR050)
}

/// Pure source-space registration calculation. It does not mutate art or SpriteKit state.
public enum MothIdleAnchorRegistrationR050 {
    public static let requiredFlags: Set<String> = [
        "--qa-isolated", "--qa-moth-idle-registration-r050"
    ]
    public static let actorID = "ACT_E_R02_04"
    public static let state = "idle"
    public static let canvas = (width: 512.0, height: 512.0)
    public static let topLeftAnchor = (x: 256.0, y: 300.0)
    public static let fps = 8.0
    public static let durationSeconds = 0.75
    public static let displayScale = 1.0
    public static let commonWingRoot = MothIdleAnchorPointR050(x: 256, y: 286)

    private struct Pin {
        let path: String
        let sha256: String
        let dxRight: Double
        let dyTopDown: Double
    }

    // Frame paths and pixel hashes are the exact existing R003 six-frame sequence.
    // Duplicate visual poses remain distinct runtime frame resources and indices.
    private static let pins: [Pin] = [
        Pin(path: "GeneratedCandidates/ACT_E_R02_04/idle_cycle_candidate_r003/frames/idle_000.png",
            sha256: "9467cd656323992886ad2a79dbd2012032e3c28fb182691800d502b0bd0191ea", dxRight: 0, dyTopDown: -18),
        Pin(path: "GeneratedCandidates/ACT_E_R02_04/idle_cycle_candidate_r003/frames/idle_001.png",
            sha256: "87b358d05029cfedc8039d5c96ea9ac1341c0f7646f4003079fbdc9bd254e3cb", dxRight: 0, dyTopDown: -19),
        Pin(path: "GeneratedCandidates/ACT_E_R02_04/idle_cycle_candidate_r003/frames/idle_002.png",
            sha256: "e9fd0ed646b13b7b3aad9b9d68bc6da51b7189e4467af303f1254bc6bb5dc095", dxRight: 0, dyTopDown: 6),
        Pin(path: "GeneratedCandidates/ACT_E_R02_04/idle_cycle_candidate_r003/frames/idle_003.png",
            sha256: "68e14e18c0e323fe6c4f91a81febad9abc55d334f5411d84b9aeb9d30b3c73bb", dxRight: 0, dyTopDown: 34),
        Pin(path: "GeneratedCandidates/ACT_E_R02_04/idle_cycle_candidate_r003/frames/idle_004.png",
            sha256: "e9fd0ed646b13b7b3aad9b9d68bc6da51b7189e4467af303f1254bc6bb5dc095", dxRight: 0, dyTopDown: 6),
        Pin(path: "GeneratedCandidates/ACT_E_R02_04/idle_cycle_candidate_r003/frames/idle_005.png",
            sha256: "87b358d05029cfedc8039d5c96ea9ac1341c0f7646f4003079fbdc9bd254e3cb", dxRight: 0, dyTopDown: -19)
    ]

    public static func isEnabled(arguments: [String]) -> Bool {
        let values = Set(arguments)
        return requiredFlags.isSubset(of: values)
    }

    public static func isPartiallyRequested(arguments: [String]) -> Bool {
        let values = Set(arguments)
        return !requiredFlags.isSubset(of: values) && !requiredFlags.isDisjoint(with: values)
    }

    public static var expectedPaths: [String] { pins.map(\.path) }
    public static var expectedSHA256ByPath: [String: String] {
        Dictionary(uniqueKeysWithValues: pins.map { ($0.path, $0.sha256) })
    }
    public static var expectedTopDownOffsets: [MothIdleAnchorPointR050] {
        pins.map { MothIdleAnchorPointR050(x: $0.dxRight, y: $0.dyTopDown) }
    }

    public static func normalizedAnchor(baseTopLeftX: Double, baseTopLeftY: Double,
                                        canvasWidth: Double, canvasHeight: Double,
                                        offsetXRight: Double, offsetYDown: Double) -> MothIdleAnchorPointR050? {
        guard [baseTopLeftX, baseTopLeftY, canvasWidth, canvasHeight, offsetXRight, offsetYDown].allSatisfy(\.isFinite),
              canvasWidth > 0, canvasHeight > 0 else { return nil }
        let x = baseTopLeftX / canvasWidth - offsetXRight / canvasWidth
        let y = 1 - baseTopLeftY / canvasHeight + offsetYDown / canvasHeight
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return MothIdleAnchorPointR050(x: x, y: y)
    }

    public static func plan(arguments: [String], facts: MothIdleAnchorClipFactsR050) -> MothIdleAnchorDecisionR050 {
        guard isEnabled(arguments: arguments) else {
            return isPartiallyRequested(arguments: arguments) ? .rejected("both_isolated_and_candidate_flags_required") : .notRequested
        }
        return validatedPlan(facts: facts)
    }

    /// Local development default selected after the R050 native comparison.
    /// This is provisional integration, not formal art approval. Baseline replay
    /// can opt out only in an isolated simulator QA session.
    public static func usesLocalCandidate(arguments: [String], isSimulator: Bool) -> Bool {
        !(isSimulator && arguments.contains("--qa-isolated") &&
          arguments.contains("--qa-moth-idle-baseline-r050"))
    }

    public static func validatedPlan(facts: MothIdleAnchorClipFactsR050) -> MothIdleAnchorDecisionR050 {
        guard facts.actorID == actorID else { return .rejected("actor_mismatch") }
        guard facts.state == state else { return .rejected("state_mismatch") }
        guard facts.canvasWidth.isFinite, facts.canvasHeight.isFinite,
              facts.canvasWidth == canvas.width, facts.canvasHeight == canvas.height else { return .rejected("clip_canvas_mismatch") }
        guard facts.anchorTopLeftX.isFinite, facts.anchorTopLeftY.isFinite,
              facts.anchorTopLeftX == topLeftAnchor.x, facts.anchorTopLeftY == topLeftAnchor.y else { return .rejected("clip_anchor_mismatch") }
        guard facts.declaredFrameCount == pins.count else { return .rejected("declared_frame_count_mismatch") }
        guard facts.frames.count == pins.count else { return .rejected("frame_count_mismatch") }
        guard facts.fps.isFinite, facts.fps == fps else { return .rejected("clip_fps_mismatch") }
        guard facts.durationSeconds.isFinite, facts.durationSeconds == durationSeconds,
              Double(facts.frames.count) / facts.fps == facts.durationSeconds else { return .rejected("clip_duration_mismatch") }
        guard facts.displayScale.isFinite, facts.displayScale == displayScale else { return .rejected("display_scale_mismatch") }
        guard facts.loops else { return .rejected("clip_must_loop") }
        for (index, pair) in zip(pins, facts.frames).enumerated() {
            let (pin, frame) = pair
            guard frame.path == pin.path else { return .rejected("frame_\(index)_path_mismatch") }
            guard frame.sha256.lowercased() == pin.sha256 else { return .rejected("frame_\(index)_sha256_mismatch") }
            guard frame.canvasWidth.isFinite, frame.canvasHeight.isFinite,
                  frame.canvasWidth == canvas.width, frame.canvasHeight == canvas.height else { return .rejected("frame_\(index)_canvas_mismatch") }
        }

        let plans = pins.enumerated().map { index, pin in
            // Convert a top-left source-pixel visual translation into SpriteKit's
            // bottom-left normalized anchor coordinates.
            let anchor = normalizedAnchor(baseTopLeftX: facts.anchorTopLeftX,
                baseTopLeftY: facts.anchorTopLeftY, canvasWidth: facts.canvasWidth,
                canvasHeight: facts.canvasHeight, offsetXRight: pin.dxRight,
                offsetYDown: pin.dyTopDown) ?? MothIdleAnchorPointR050(x: .nan, y: .nan)
            return MothIdleAnchorFramePlanR050(frameIndex: index, path: pin.path,
                sourceOffsetX: pin.dxRight, sourceOffsetYTopDown: pin.dyTopDown,
                normalizedAnchorX: anchor.x, normalizedAnchorYBottomUp: anchor.y)
        }
        guard plans.allSatisfy({ $0.normalizedAnchorX.isFinite && $0.normalizedAnchorYBottomUp.isFinite
                                 && (0...1).contains($0.normalizedAnchorX) && (0...1).contains($0.normalizedAnchorYBottomUp) }) else {
            return .rejected("computed_anchor_out_of_unit_bounds")
        }
        guard let baseAnchor = normalizedAnchor(baseTopLeftX: facts.anchorTopLeftX,
            baseTopLeftY: facts.anchorTopLeftY, canvasWidth: facts.canvasWidth,
            canvasHeight: facts.canvasHeight, offsetXRight: 0, offsetYDown: 0) else {
            return .rejected("base_anchor_out_of_unit_bounds")
        }
        return .allowed(MothIdleAnchorPlanR050(frames: plans,
                                                baseAnchorNormalizedX: baseAnchor.x,
                                                baseAnchorNormalizedYBottomUp: baseAnchor.y,
                                                fps: facts.fps,
                                                frameDurationSeconds: 1 / facts.fps))
    }
}
