import Foundation
import SpriteKit
import UIKit

/// Runtime adapter for R130 isolated previews. Bundle resources are copied byte-for-byte;
/// source/worktree paths are only provenance, never used as runtime file paths.
enum AIRAHarvestApronOverlayR130 {
    static let appearanceID = WardrobeCandidateCatalogR130.appearanceID
    static let overlayName = "QA_AIRA_APRON_R130_OVERLAY"
    static let foregroundName = "QA_AIRA_APRON_R130_FOREGROUND"
    static let expectedRegistrationSourcePin = "fa463c9b8fa8f2eab261ed8686900810d30335e27dba6a8350037e0a63a1d5b6"
    private static let exactAssetIDs: Set<String> = [
        "GeneratedArt/PartyAttack/AIRA__attack_00.png",
        "GeneratedArt/PartyAttack/AIRA__attack_01.png",
        "GeneratedArt/PartyAttack/AIRA__attack_02.png",
        "GeneratedArt/PartyAttack/AIRA__attack_03.png",
        "GeneratedArt/PartyAttack/AIRA__attack_04.png",
        "GeneratedArt/PartyAttack/AIRA__attack_05.png",
        "GeneratedArt/PartyAttack/AIRA__attack_06.png",
        "GeneratedArt/PartyAttack/AIRA__attack_07.png",
        "GeneratedArt/PartyAttack/AIRA__attack_08.png",
        "GeneratedArt/PartyRest/AIRA__rest_00.png",
        "GeneratedArt/PartyRest/AIRA__rest_01.png",
        "GeneratedArt/PartyRest/AIRA__rest_02.png",
        "GeneratedArt/PartyRest/AIRA__rest_03.png",
        "GeneratedArt/PartyRest/AIRA__rest_04.png",
        "GeneratedArt/PartyRest/AIRA__rest_05.png",
        "GeneratedArt/PartyRest/AIRA__rest_06.png",
        "GeneratedArt/PartyRest/AIRA__rest_07.png",
        "GeneratedArt/PartyRest/AIRA__rest_08.png",
        "GeneratedArt/PartyWalk/AIRA__walk_0.png",
        "GeneratedArt/PartyWalk/AIRA__walk_1.png",
        "GeneratedArt/PartyWalk/AIRA__walk_2.png",
        "GeneratedArt/PartyWalk/AIRA__walk_3.png",
        "GeneratedArt/PartyWalk/AIRA__walk_4.png",
        "GeneratedArt/PartyWalk/AIRA__walk_5.png",
        "GeneratedArt/PartyWalk/AIRA__walk_6.png",
        "GeneratedArt/PartyWalk/AIRA__walk_7.png",
        "GeneratedArt/PartyWalk/AIRA__walk_8.png",
    ]

    private struct ImagePin: Decodable { let sha256: String; let alphaContentBoundsPx: [CGFloat] }
    private struct Frame: Decodable {
        let state: String; let index: Int; let path: String; let canvasPx: [CGFloat]
        let anchorPxTopLeft: [CGFloat]; let contentCenterTopLeftPx: [CGFloat]
        let contentWidthPx: CGFloat; let foregroundPolygonsTopLeftPx: [[[CGFloat]]]
        let frameID: String
        var runtimeAssetID: String? {
            guard let range = path.range(of: "GeneratedArt/") else { return nil }
            return String(path[range.lowerBound...])
        }
    }
    private struct Registration: Decodable {
        let sourcePinSha256: String; let apronRaw: ImagePin; let frames: [Frame]
    }
    private struct Resources { let registration: Registration; let apron: SKTexture }
    private static let resources: Resources? = loadResources()

    private static func loadResources() -> Resources? {
        guard let jsonURL = Bundle.main.url(forResource: "AIRA_APRON_REGISTRATION_R001", withExtension: "json", subdirectory: "CandidateAppearance/R130"),
              let imageURL = Bundle.main.url(forResource: "AIRA_HARVEST_APRON_R130", withExtension: "png", subdirectory: "CandidateAppearance/R130"),
              let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode(Registration.self, from: data),
              decoded.sourcePinSha256 == expectedRegistrationSourcePin,
              decoded.frames.count == exactAssetIDs.count,
              Set(decoded.frames.compactMap(\.runtimeAssetID)) == exactAssetIDs,
              Set(decoded.frames.map(\.path)).count == 27,
              decoded.apronRaw.alphaContentBoundsPx.count == 4,
              let image = UIImage(contentsOfFile: imageURL.path),
              let cg = image.cgImage, cg.width == 1254, cg.height == 1254 else { return nil }
        return Resources(registration: decoded, apron: SKTexture(cgImage: cg))
    }

    static func snapshot(on body: SKSpriteNode) -> [String: Any] {
        let overlay = body.childNode(withName: overlayName) as? SKSpriteNode
        let foreground = body.childNode(withName: foregroundName)
        return [
            "present": overlay != nil,
            "visible": overlay.map { !$0.isHidden && $0.alpha > 0 } ?? false,
            "frameAssetID": overlay?.userData?["frameAssetID"] as? String ?? "",
            "frameID": overlay?.userData?["frameID"] as? String ?? "",
            "ownedOverlayCount": body.children.filter { $0.name == overlayName }.count,
            "ownedForegroundCount": body.children.filter { $0.name == foregroundName }.count,
            "foregroundPresent": foreground != nil,
            "bodyLocalZ": body.zPosition,
            "overlayLocalZ": overlay?.zPosition ?? 0,
            "foregroundLocalZ": foreground?.zPosition ?? 0,
            "parentIsBody": overlay.map { $0.parent === body } ?? false,
            "candidateStatus": "UNAPPROVED_LOCAL_QA_CANDIDATE_NOT_FOR_SALE"
        ]
    }

    static func clearOwnedNodes(on body: SKSpriteNode) {
        body.children.filter { $0.name == overlayName || $0.name == foregroundName }.forEach { $0.removeFromParent() }
    }

    @discardableResult static func apply(frameAssetID: String, on body: SKSpriteNode) -> Bool {
        guard exactAssetIDs.contains(frameAssetID), let resources,
              let frame = resources.registration.frames.first(where: { $0.runtimeAssetID == frameAssetID }),
              frame.canvasPx.count == 2, frame.anchorPxTopLeft.count == 2,
              frame.contentCenterTopLeftPx.count == 2, frame.contentWidthPx > 0,
              resources.registration.apronRaw.alphaContentBoundsPx.count == 4,
              body.size.width > 0, body.size.height > 0 else {
            clearOwnedNodes(on: body); return false
        }
        let canvasWidth = frame.canvasPx[0], canvasHeight = frame.canvasPx[1]
        let bounds = resources.registration.apronRaw.alphaContentBoundsPx
        let canvas = CGSize(width: canvasWidth, height: canvasHeight)
        let imageBounds = CGRect(x: bounds[0], y: bounds[1], width: bounds[2] - bounds[0], height: bounds[3] - bounds[1])
        guard let placement = AIRAApronPlacementR130.project(canvas: canvas,
            center: CGPoint(x: frame.contentCenterTopLeftPx[0], y: frame.contentCenterTopLeftPx[1]),
            contentWidth: frame.contentWidthPx, bodySize: body.size, bodyAnchor: body.anchorPoint,
            imageBounds: imageBounds),
            AIRAApronPlacementR130.validForeground(frame.foregroundPolygonsTopLeftPx, canvas: canvas) else {
            clearOwnedNodes(on: body); return false
        }
        let placementKey = "\(body.size.width)|\(body.size.height)|\(body.anchorPoint.x)|\(body.anchorPoint.y)"
        if let current = body.childNode(withName: overlayName),
           current.userData?["frameAssetID"] as? String == frameAssetID,
           current.userData?["placementKey"] as? String == placementKey,
           (body.childNode(withName: foregroundName) != nil || frame.foregroundPolygonsTopLeftPx.isEmpty) { return true }
        clearOwnedNodes(on: body)
        let sx = placement.bodyUnitsPerPixel.width, sy = placement.bodyUnitsPerPixel.height
        let anchor = placement.anchorTopLeft, center = placement.center
        let imageSize = resources.apron.size()
        let overlay = SKSpriteNode(texture: resources.apron,
            size: CGSize(width: imageSize.width * placement.imageScale.width, height: imageSize.height * placement.imageScale.height))
        overlay.name = overlayName; overlay.anchorPoint = CGPoint(x: 0.5, y: 0.5); overlay.zPosition = AIRAApronPlacementR130.overlayLocalZ
        overlay.position = CGPoint(x: center.x - ((bounds[0] + bounds[2]) / 2 - imageSize.width / 2) * placement.imageScale.width,
                                   y: center.y + ((bounds[1] + bounds[3]) / 2 - imageSize.height / 2) * placement.imageScale.height)
        overlay.userData = ["frameAssetID": frameAssetID, "frameID": frame.frameID, "placementKey": placementKey]
        body.addChild(overlay)
        guard !frame.foregroundPolygonsTopLeftPx.isEmpty else { return true }
        let path = CGMutablePath()
        for polygon in frame.foregroundPolygonsTopLeftPx {
            guard let first = polygon.first, first.count == 2 else { continue }
            path.move(to: CGPoint(x: first[0] - anchor.x, y: anchor.y - first[1]))
            for point in polygon.dropFirst() where point.count == 2 {
                path.addLine(to: CGPoint(x: point[0] - anchor.x, y: anchor.y - point[1]))
            }
            path.closeSubpath()
        }
        let crop = SKCropNode(); crop.name = foregroundName; crop.position = .zero
        crop.xScale = sx; crop.yScale = sy; crop.zPosition = AIRAApronPlacementR130.foregroundLocalZ
        let original = SKSpriteNode(texture: body.texture, size: CGSize(width: canvasWidth, height: canvasHeight))
        original.anchorPoint = body.anchorPoint; original.position = .zero; crop.addChild(original)
        let mask = SKShapeNode(path: path); mask.fillColor = .white; mask.strokeColor = .clear; crop.maskNode = mask
        body.addChild(crop)
        return true
    }
}
