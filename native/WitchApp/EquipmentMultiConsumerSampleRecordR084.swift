import Foundation

/// Foundation-only sample-record builder. The observer and executable host
/// smoke test share this exact dictionary construction, so duplicate keys
/// cannot be hidden by a source-only grep or parser check.
enum EquipmentMultiConsumerSampleRecordR084 {
    static let requiredKeys: Set<String> = [
        "ownerID", "spriteActorID", "gearID", "slot", "phase", "sceneFrame", "sceneTime",
        "bodyAssetID", "bodyFrameIndex", "bodyCanvas", "actorBodyExists", "actorBodyNodeName",
        "actorBasePoseState", "registrationStatus", "registrationState", "registrationBodyAssetID",
        "registrationBodyFrameIndex", "registrationMatchesRenderedBodyFrame", "registrationSource",
        "normalizedPoint", "normalizedSize", "normalizedHeight", "angleRadians", "registrationVisible",
        "holderExists", "partExists", "holderParentMatchesActor", "partParentMatchesHolder", "holderHidden", "holderAlpha",
        "partHidden", "partAlpha", "partPosition", "partSize", "partRotation", "partWorldCenter",
        "bodySize", "bodyAnchor", "bodyToSceneBasis", "expectedPartWorldCorners", "partWorldCorners",
        "ancestorVisibility", "visibilityChainReachesScene", "effectiveVisible", "effectiveAlpha",
        "textureDecoded", "decodedTexturePixelSize", "texturePixelSHA256", "resolvedResourcePixelSHA256",
        "renderedPixelsMatchResolvedResource",
        "resourcePath", "resourceSHA256",
        "resourceHashPresent", "sampleStatus"
    ]

    static func make(ownerID: String, spriteActorID: String, gearID: String, slot: String,
                     phase: String, sceneFrame: Int, sceneTime: TimeInterval,
                     bodyAssetID: String, bodyFrameIndex: Int, bodyCanvas: [Double],
                     actorBodyExists: Bool, actorBodyNodeName: String,
                     registration: [String: Any], registrationMatchesRenderedBodyFrame: Bool,
                     holderExists: Bool, partExists: Bool, holderParentMatchesActor: Bool, partParentMatchesHolder: Bool,
                     holderHidden: Any, holderAlpha: Any, partHidden: Any, partAlpha: Any,
                     partPosition: [Double], partSize: [Double], partRotation: Double,
                     partWorldCenter: [Double], bodySize: [Double], bodyAnchor: [Double],
                     bodyToSceneBasis: [Double], expectedPartWorldCorners: [[Double]], partWorldCorners: [[Double]],
                     ancestorVisibility: [[String: Any]], visibilityChainReachesScene: Bool, effectiveVisible: Bool, effectiveAlpha: Double,
                     textureDecoded: Bool, decodedTexturePixelSize: [Int],
                     texturePixelSHA256: String, resolvedResourcePixelSHA256: String,
                     renderedPixelsMatchResolvedResource: Bool,
                     resourcePath: String, resourceSHA256: String) -> [String: Any] {
        [
            "ownerID": ownerID, "spriteActorID": spriteActorID,
            "gearID": gearID, "slot": slot, "phase": phase,
            "sceneFrame": sceneFrame, "sceneTime": sceneTime,
            "bodyAssetID": bodyAssetID, "bodyFrameIndex": bodyFrameIndex,
            "bodyCanvas": bodyCanvas, "actorBodyExists": actorBodyExists,
            "actorBodyNodeName": actorBodyNodeName, "actorBasePoseState": phase,
            "registrationStatus": registration["status"] as? String ?? "missing_registration",
            "registrationState": registration["state"] as? String ?? "",
            "registrationBodyAssetID": registration["bodyAssetID"] as? String ?? "",
            "registrationBodyFrameIndex": registration["bodyFrameIndex"] as? Int ?? -1,
            "registrationMatchesRenderedBodyFrame": registrationMatchesRenderedBodyFrame,
            "registrationSource": registration["registrationSource"] as? String ?? "missing",
            "normalizedPoint": registration["normalizedPoint"] ?? NSNull(),
            "normalizedSize": registration["normalizedSize"] ?? NSNull(),
            "normalizedHeight": registration["normalizedHeight"] ?? NSNull(),
            "angleRadians": registration["angleRadians"] ?? NSNull(),
            "registrationVisible": registration["visible"] as? Bool ?? false,
            "holderExists": holderExists, "partExists": partExists,
            "holderParentMatchesActor": holderParentMatchesActor, "partParentMatchesHolder": partParentMatchesHolder,
            "holderHidden": holderHidden, "holderAlpha": holderAlpha,
            "partHidden": partHidden, "partAlpha": partAlpha,
            "partPosition": partPosition, "partSize": partSize, "partRotation": partRotation,
            "partWorldCenter": partWorldCenter, "bodySize": bodySize, "bodyAnchor": bodyAnchor,
            "bodyToSceneBasis": bodyToSceneBasis, "expectedPartWorldCorners": expectedPartWorldCorners,
            "partWorldCorners": partWorldCorners, "ancestorVisibility": ancestorVisibility,
            "visibilityChainReachesScene": visibilityChainReachesScene, "effectiveVisible": effectiveVisible, "effectiveAlpha": effectiveAlpha,
            "textureDecoded": textureDecoded,
            "decodedTexturePixelSize": decodedTexturePixelSize,
            "texturePixelSHA256": texturePixelSHA256,
            "resolvedResourcePixelSHA256": resolvedResourcePixelSHA256,
            "renderedPixelsMatchResolvedResource": renderedPixelsMatchResolvedResource,
            "resourcePath": resourcePath, "resourceSHA256": resourceSHA256,
            "resourceHashPresent": resourceSHA256.count == 64,
            "sampleStatus": Self.allowedPhases.contains(phase) ? "sampled" : "unknown_phase"
        ]
    }

    private static let allowedPhases: Set<String> = ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"]
}
