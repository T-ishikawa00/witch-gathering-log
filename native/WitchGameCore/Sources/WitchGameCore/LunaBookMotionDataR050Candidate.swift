import Foundation

/// QA-only body/attachment midpoint. Body image contains no book pixels.
enum LunaBookMotionDataR050Candidate {
    static let bodyAssetID = "LUNA_BOOK_MOTION_EXEC_RECOVER_MID_R001_CANDIDATE"
    static let bodyAnchorY = 0.09140625 // alpha-bottom estimate on 256x256 canvas; not a semantic foot mask
    static let executeRecoverMidpoint = LunaBookMotionFrameRecord(
        poseState: "execute", frameIndex: 3, bodyAssetID: bodyAssetID, durationMilliseconds: 50,
        // Candidate moves the book onto the rendered near hand; all other fields and source artwork remain unchanged.
        bookCenterX: 0.7227, bookCenterY: 0.6172, bookRotationDegrees: 2.5, bookScale: 1.0,
        maskCenterX: 0.68165, maskCenterY: 0.63285, maskRadiusX: 0.0391, maskRadiusY: 0.0273)
}
