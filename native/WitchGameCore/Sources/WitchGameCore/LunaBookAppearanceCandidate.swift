import Foundation

/// Non-canonical visual mapping for the currently authored LUNA book-holding idle candidate.
/// The original LUNA pose art and gameplay gear identity remain unchanged.
public struct LunaBookAppearanceCandidate: Sendable, Equatable {
    public let actorID: String
    public let gearID: String
    public let basePoseAssetID: String
    public let bookLayerAssetID: String
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let bookTopLeftX: Int
    public let bookTopLeftY: Int
    public let requiresHandForegroundOcclusion: Bool

    public static let supportedPoseStates: Set<String> = ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"]
    public static let unsupportedPoseStates: Set<String> = []

    private static let bookAssets: [String: String] = [
        "EQ_A_01": "BOOK_EQ_A_01",
        "EQ_A_02": "BOOK_EQ_A_02",
        "EQ_A_03": "BOOK_EQ_A_03"
    ]
    private static let poseAssetNames: [String: String] = [
        "idle": "IDLE", "walk": "WALK", "anticipate": "ANTICIPATE",
        "execute": "EXECUTE", "recover": "RECOVER", "hit": "HIT", "resolve": "RESOLVE"
    ]

    /// Candidate-only projection for an equipped book. Each state is a single key pose,
    /// not proof of continuous animation. The host renderer must place the hand foreground
    /// over the book layer to avoid covering the grip.
    public static func resolve(actorID: String, gearID: String, isEquipped: Bool, poseState: String) -> Self? {
        guard actorID == "C_APPRENTICE",
              isEquipped,
              let poseName = poseAssetNames[poseState],
              let layer = bookAssets[gearID] else { return nil }
        let base = "LUNA_BOOKLESS_\(poseName)_CANDIDATE_R001"
        let layerID = poseState == "idle" ? layer : "\(layer)__\(poseState)"
        return Self(actorID: actorID,
                    gearID: gearID,
                    basePoseAssetID: base,
                    bookLayerAssetID: layerID,
                    canvasWidth: 256,
                    canvasHeight: 256,
                    bookTopLeftX: 104,
                    bookTopLeftY: 136,
                    requiresHandForegroundOcclusion: true)
    }

    private init(actorID: String, gearID: String, basePoseAssetID: String, bookLayerAssetID: String, canvasWidth: Int, canvasHeight: Int, bookTopLeftX: Int, bookTopLeftY: Int, requiresHandForegroundOcclusion: Bool) {
        self.actorID = actorID
        self.gearID = gearID
        self.basePoseAssetID = basePoseAssetID
        self.bookLayerAssetID = bookLayerAssetID
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.bookTopLeftX = bookTopLeftX
        self.bookTopLeftY = bookTopLeftY
        self.requiresHandForegroundOcclusion = requiresHandForegroundOcclusion
    }
}
