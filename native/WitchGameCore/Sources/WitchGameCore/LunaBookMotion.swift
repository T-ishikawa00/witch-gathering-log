import Foundation

/// Normalized coordinates use a top-left origin: x grows right and y grows down.
public struct LunaBookNormalizedEllipse: Sendable, Equatable {
    public let centerX: Double
    public let centerY: Double
    public let radiusX: Double
    public let radiusY: Double
}

public struct LunaBookMotionTransform: Sendable, Equatable {
    public let centerX: Double
    public let centerY: Double
    public let rotationDegrees: Double
    public let scale: Double
}

public struct LunaBookMotionAttachment: Sendable, Equatable {
    public let sequenceIndex: Int
    public let durationMilliseconds: Int
    public let gearID: String
    public let layerAssetID: String
    public let transform: LunaBookMotionTransform
    /// Erase this ellipse from the book texture so the underlying base-pose palm is visible.
    public let palmOcclusionMask: LunaBookNormalizedEllipse
}

public struct LunaBookMotionFrame: Sendable, Equatable {
    public let requestedState: String
    public let poseState: String
    public let frameIndex: Int
    public let sequenceIndex: Int
    public let durationMilliseconds: Int
    public let bodyAssetID: String
    /// Normalized SpriteKit anchor Y for full-canvas registration; default is 12/256.
    public let bodyAnchorY: Double
    public let attachment: LunaBookMotionAttachment
}

struct LunaBookMotionFrameRecord: Sendable {
    let poseState: String
    let frameIndex: Int
    let bodyAssetID: String
    let durationMilliseconds: Int
    let bookCenterX: Double
    let bookCenterY: Double
    let bookRotationDegrees: Double
    let bookScale: Double
    let maskCenterX: Double
    let maskCenterY: Double
    let maskRadiusX: Double
    let maskRadiusY: Double

    func withDuration(_ milliseconds: Int) -> Self {
        Self(poseState: poseState, frameIndex: frameIndex, bodyAssetID: bodyAssetID,
             durationMilliseconds: milliseconds, bookCenterX: bookCenterX, bookCenterY: bookCenterY,
             bookRotationDegrees: bookRotationDegrees, bookScale: bookScale,
             maskCenterX: maskCenterX, maskCenterY: maskCenterY,
             maskRadiusX: maskRadiusX, maskRadiusY: maskRadiusY)
    }
}

/// Candidate-only key-pose sequencer. `play` emits paired body and attachment instructions
/// in sequence order; the renderer must schedule each pair on one shared frame clock.
public enum LunaBookMotion {
    public static let candidateStatus = "UNAPPROVED_TEST_OVERLAY_CANDIDATE"
    public static let canvasWidth = 256
    public static let canvasHeight = 256
    public static let footBaselineCanvasY = 244
    public static let supportedGearIDs: Set<String> = ["EQ_A_01", "EQ_A_02", "EQ_A_03"]
    public static let supportedStates: Set<String> = ["walk", "attack", "anticipate", "execute", "recover", "idle", "hit", "resolve"]

    private static let gearLayerAssetIDs: [String: String] = [
        "EQ_A_01": "BOOK_EQ_A_01",
        "EQ_A_02": "BOOK_EQ_A_02",
        "EQ_A_03": "BOOK_EQ_A_03"
    ]

    /// Returns key poses only when the equipped gear is one of the three existing apprentice books.
    /// `attack` combines anticipate, execute and recover; the isolated midpoint mode adds one frame.
    public static func frames(state: String, gearID: String, includeR050ExecuteRecoverMidpoint: Bool = false,
                              includeR088BridgeAfterMidpoint: Bool = false) -> [LunaBookMotionFrame]? {
        guard supportedGearIDs.contains(gearID),
              let layerID = gearLayerAssetIDs[gearID],
              supportedStates.contains(state) else { return nil }
        var records: [LunaBookMotionFrameRecord]
        if state == "attack" {
            records = LunaBookMotionDataR001.frames.filter { ["anticipate", "execute", "recover"].contains($0.poseState) }
        } else {
            records = LunaBookMotionDataR001.frames.filter { $0.poseState == state }
        }
        if includeR050ExecuteRecoverMidpoint && ["execute", "attack"].contains(state),
           let lastExecute = records.lastIndex(where: { $0.poseState == "execute" && $0.frameIndex == 2 }) {
            let endpoint = records[lastExecute]
            records[lastExecute] = LunaBookMotionFrameRecord(poseState: endpoint.poseState,
                                                              frameIndex: endpoint.frameIndex,
                                                              bodyAssetID: endpoint.bodyAssetID,
                                                              durationMilliseconds: includeR088BridgeAfterMidpoint ? 34 : 50,
                                                              bookCenterX: endpoint.bookCenterX,
                                                              bookCenterY: endpoint.bookCenterY,
                                                              bookRotationDegrees: endpoint.bookRotationDegrees,
                                                              bookScale: endpoint.bookScale,
                                                              maskCenterX: endpoint.maskCenterX,
                                                              maskCenterY: endpoint.maskCenterY,
                                                              maskRadiusX: endpoint.maskRadiusX,
                                                              maskRadiusY: endpoint.maskRadiusY)
            let midpoint = LunaBookMotionDataR050Candidate.executeRecoverMidpoint
            // Split the existing 100 ms endpoint budget. A QA pose must not
            // lengthen the attack or be cut off by the normal recover transition.
            records.insert(includeR088BridgeAfterMidpoint ? midpoint.withDuration(33) : midpoint, at: lastExecute + 1)
            if includeR088BridgeAfterMidpoint,
               let midpoint = records.firstIndex(where: { $0.bodyAssetID == LunaBookMotionDataR050Candidate.bodyAssetID }) {
                records.insert(LunaBookMotionDataR088Candidate.executeRecoverBridge, at: midpoint + 1)
            }
        }
        guard !records.isEmpty else { return nil }
        return records.enumerated().map { sequenceIndex, record in
            let transform = LunaBookMotionTransform(centerX: record.bookCenterX,
                                                    centerY: record.bookCenterY,
                                                    rotationDegrees: record.bookRotationDegrees,
                                                    scale: record.bookScale)
            let mask = LunaBookNormalizedEllipse(centerX: record.maskCenterX,
                                                 centerY: record.maskCenterY,
                                                 radiusX: record.maskRadiusX,
                                                 radiusY: record.maskRadiusY)
            let attachment = LunaBookMotionAttachment(sequenceIndex: sequenceIndex,
                                                      durationMilliseconds: record.durationMilliseconds,
                                                      gearID: gearID,
                                                      layerAssetID: layerID,
                                                      transform: transform,
                                                      palmOcclusionMask: mask)
            return LunaBookMotionFrame(requestedState: state,
                                       poseState: record.poseState,
                                       frameIndex: record.frameIndex,
                                       sequenceIndex: sequenceIndex,
                                       durationMilliseconds: record.durationMilliseconds,
                                       bodyAssetID: record.bodyAssetID,
                                       bodyAnchorY: record.bodyAssetID == LunaBookMotionDataR050Candidate.bodyAssetID ? LunaBookMotionDataR050Candidate.bodyAnchorY
                                           : (record.bodyAssetID == LunaBookMotionDataR088Candidate.bodyAssetID ? LunaBookMotionDataR088Candidate.bodyAnchorY : 12.0 / 256.0),
                                       attachment: attachment)
        }
    }

    /// Emits each body pose and its book/mask transform back-to-back in matching sequence order.
    /// The host should enqueue both callbacks using `sequenceIndex` and the shared duration.
    @discardableResult
    public static func play(state: String,
                            gearID: String,
                            on body: (LunaBookMotionFrame) -> Void,
                            attach book: (LunaBookMotionAttachment) -> Void,
                            includeR050ExecuteRecoverMidpoint: Bool = false,
                            includeR088BridgeAfterMidpoint: Bool = false) -> Bool {
        guard let sequence = frames(state: state, gearID: gearID,
                                    includeR050ExecuteRecoverMidpoint: includeR050ExecuteRecoverMidpoint,
                                    includeR088BridgeAfterMidpoint: includeR088BridgeAfterMidpoint) else { return false }
        for frame in sequence {
            body(frame)
            book(frame.attachment)
        }
        return true
    }
}
