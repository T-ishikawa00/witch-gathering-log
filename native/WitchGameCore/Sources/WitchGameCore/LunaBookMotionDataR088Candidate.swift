import Foundation

/// Unapproved four-pose continuity candidate; only inserted behind both explicit isolated QA flags.
enum LunaBookMotionDataR088Candidate {
    static let bodyAssetID = "LUNA_EXEC_RECOVER_BRIDGE_R088_SOURCE"
    static let bodyAnchorY = 106.0 / 1254.0 // alpha8 bottom registration, not semantic foot detection
    static let executeRecoverBridge = LunaBookMotionFrameRecord(
        poseState: "execute", frameIndex: 4, bodyAssetID: bodyAssetID, durationMilliseconds: 33,
        bookCenterX: 0.6600, bookCenterY: 0.6000, bookRotationDegrees: 2.5, bookScale: 1.0,
        maskCenterX: 0.5664, maskCenterY: 0.6367, maskRadiusX: 0.0547, maskRadiusY: 0.0313)
}
