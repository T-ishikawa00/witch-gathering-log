import Foundation
import SpriteKit

/// Off-glob QA serializer. It observes the rendered ERNA body/staff tree after SpriteKit actions;
/// it does not select poses, set transforms, or change action timing.
@MainActor enum ERNAStaffFrameSnapshotR040 {
    static func capture(
        scene: SKScene,
        body: SKSpriteNode?,
        costume: String?,
        selectedGearID: String?,
        selectedStaffAssetID: String?,
        handAnchorNormalizedTopLeft: CGPoint?,
        handAngleRadians: CGFloat?,
        poseState: String,
        activeWalkAction: Bool,
        activeCastAction: Bool,
        pendingRootActionID: String?,
        holdingAnticipate: Bool,
        sceneFrame: Int,
        sceneTime: TimeInterval,
        sceneClock: TimeInterval
    ) -> [String: Any] {
        guard let body else {
            return ["status": "missing_body", "sceneFrame": sceneFrame, "sceneTime": sceneTime, "sceneClock": sceneClock]
        }
        let actorFrame = ActorBodyFrame.current(on: body)
        let weapon = body.childNode(withName: "weapon_attachment") as? SKSpriteNode
        let handCrop = body.childNode(withName: "weapon_hand") as? SKCropNode
        let mask = handCrop?.maskNode
        let origin = CGPoint.zero
        let weaponCenter = weapon?.convert(origin, to: scene)
        // SKCropNode.maskNode is assigned as an independent node, not parented
        // beneath the crop. Its position is in crop-local coordinates.
        let maskCenter = handCrop.map { crop in crop.convert(mask?.position ?? .zero, to: scene) }
        let weaponCorners: [[Double]] = weapon.map { node in
            // SKSpriteNode's local origin is its anchorPoint, not the texture center.
            // Use the actual anchor so the world quad follows off-center STAFF_BRANCH
            // (0.547, 0.50) and STAFF_MOON (0.451, 0.50) attachments correctly.
            let minX = -node.anchorPoint.x * node.size.width
            let maxX = (1 - node.anchorPoint.x) * node.size.width
            let minY = -node.anchorPoint.y * node.size.height
            let maxY = (1 - node.anchorPoint.y) * node.size.height
            return [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                    CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)].map { p in
                let q = node.convert(p, to: scene)
                return [Double(q.x), Double(q.y)]
            }
        } ?? []
        let bodyWorld = body.convert(origin, to: scene)
        return [
            "status": actorFrame == nil ? "body_frame_unrecorded" : "sampled",
            "actorID": "ERNA",
            "costume": costume == "ERNA_TRAVEL" ? "travel" : "standard",
            "selectedGearID": selectedGearID ?? "",
            "selectedStaffAssetID": selectedStaffAssetID ?? "",
            "bodyAssetID": actorFrame?.assetID ?? "",
            "bodyFrameIndex": actorFrame?.frameIndex ?? -1,
            "bodyCanvasPx": [Double(actorFrame?.canvasSize.width ?? 0), Double(actorFrame?.canvasSize.height ?? 0)],
            "bodySizePoints": [Double(body.size.width), Double(body.size.height)],
            "bodyAnchorPoint": [Double(body.anchorPoint.x), Double(body.anchorPoint.y)],
            "poseState": poseState,
            "activeWalkAction": activeWalkAction,
            "activeCastAction": activeCastAction,
            "pendingRootActionID": pendingRootActionID as Any? ?? NSNull(),
            "holdingAnticipate": holdingAnticipate,
            "handAnchorNormalizedTopLeft": handAnchorNormalizedTopLeft.map { [Double($0.x), Double($0.y)] } ?? [],
            "handAngleRadians": handAngleRadians.map(Double.init) ?? NSNull(),
            "weaponNodeExists": weapon != nil,
            "weaponTextureExists": weapon?.texture != nil,
            // SKTexture.size() is the SpriteKit-reported logical size, not an
            // independent PNG pixel-dimension readback. Bundle PNG SHA/dimensions
            // are checked by the host against the frozen build receipt.
            "weaponTextureReportedSize": weapon.map { [Double($0.texture?.size().width ?? 0), Double($0.texture?.size().height ?? 0)] } ?? [],
            "weaponQAAssetID": weapon?.userData?["qaTextureAssetID"] as? String ?? "",
            "weaponParentIsBody": weapon?.parent === body,
            "weaponHidden": weapon?.isHidden ?? true,
            "weaponAlpha": weapon.map { Double($0.alpha) } ?? 0,
            "weaponPositionLocal": weapon.map { [Double($0.position.x), Double($0.position.y)] } ?? [],
            "weaponCenterScene": weaponCenter.map { [Double($0.x), Double($0.y)] } ?? [],
            "weaponSizePoints": weapon.map { [Double($0.size.width), Double($0.size.height)] } ?? [],
            "weaponAngleRadians": weapon.map { Double($0.zRotation) } ?? NSNull(),
            "weaponZ": weapon.map { Double($0.zPosition) } ?? NSNull(),
            "weaponWorldCorners": weaponCorners,
            "handMaskExists": mask != nil,
            "handMaskType": mask.map { String(describing: type(of: $0)) } ?? "",
            "handMaskAssignedToCrop": mask != nil && handCrop?.maskNode === mask,
            "handCropParentIsBody": handCrop?.parent === body,
            "handCropHidden": handCrop?.isHidden ?? true,
            "handCropAlpha": handCrop.map { Double($0.alpha) } ?? 0,
            "handMaskHidden": mask?.isHidden ?? true,
            "handMaskAlpha": mask.map { Double($0.alpha) } ?? 0,
            "handMaskPositionLocal": mask.map { [Double($0.position.x), Double($0.position.y)] } ?? [],
            "handMaskFrameLocal": mask.map { [Double($0.frame.minX), Double($0.frame.minY), Double($0.frame.width), Double($0.frame.height)] } ?? [],
            "handMaskCenterScene": maskCenter.map { [Double($0.x), Double($0.y)] } ?? [],
            "bodyPositionScene": [Double(bodyWorld.x), Double(bodyWorld.y)],
            "sceneFrame": sceneFrame,
            "sceneTime": sceneTime,
            "sceneClock": sceneClock
        ]
    }
}
