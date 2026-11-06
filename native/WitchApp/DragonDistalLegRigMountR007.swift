import Foundation
import SpriteKit
import CoreGraphics
import ImageIO

/// Mount adapter for an isolated ACT_B_R04_B body part. It replaces only the
/// fused body texture with an exact-source static mask and mounts four movable
/// source-pixel lower-leg textures as children. It is not used unless the strict
/// --qa-dragon-distal-leg-r007 flag is present.
@MainActor
final class DragonDistalLegRigMountR007 {
    static let sourceRelativePath = "GeneratedCandidates/ACT_B_R04_B/rig_candidate_r001/parts/body4legs_tail_part_r001.png"
    static let actionKey = "witch.enemy.part-rig.walk-distal-r007"

    let sourceSHA256 = DragonDistalLegRigCandidateR007.sourceSHA256
    let bodyPart: SKSpriteNode
    let bodyOriginalTexture: SKTexture?
    let bodyMaskedTexture: SKTexture
    let anchorCanvas: CGPoint
    let partition: DragonDistalLegRigCandidateR007.Partition
    private let partsByID: [String: (pivot: SKNode, sprite: SKSpriteNode)]
    private(set) var isMounted = false
    var bodyTexturePartitioned: Bool { bodyPart.texture === bodyMaskedTexture }
    var bodyTextureRestored: Bool {
        guard let bodyOriginalTexture else { return false }
        return bodyPart.texture === bodyOriginalTexture
    }

    init?(bodyPart: SKSpriteNode, artRoot: URL, anchorCanvas: CGPoint) {
        let sourceURL = artRoot.appendingPathComponent(Self.sourceRelativePath)
        guard let data = try? Data(contentsOf: sourceURL),
              let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              bodyPart.texture != nil,
              let partition = try? DragonDistalLegRigCandidateR007.partition(source: cgImage, sourceData: data),
              partition.recompositionByteMismatchCount == 0,
              abs(bodyPart.size.width - DragonDistalLegRigCandidateR007.nominalCanvas.width) < 0.5,
              abs(bodyPart.size.height - DragonDistalLegRigCandidateR007.nominalCanvas.height) < 0.5 else { return nil }
        self.bodyPart = bodyPart
        self.bodyOriginalTexture = bodyPart.texture
        self.bodyMaskedTexture = SKTexture(cgImage: partition.body)
        self.bodyMaskedTexture.filteringMode = .linear
        self.anchorCanvas = anchorCanvas
        self.partition = partition
        let sx = bodyPart.size.width / DragonDistalLegRigCandidateR007.nominalCanvas.width
        let sy = bodyPart.size.height / DragonDistalLegRigCandidateR007.nominalCanvas.height
        var built: [String: (pivot: SKNode, sprite: SKSpriteNode)] = [:]
        for segment in DragonDistalLegRigCandidateR007.segments {
            guard let image = partition.segments[segment.id] else { return nil }
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .linear
            let pivot = SKNode(); pivot.name = "r007_pivot_\(segment.id)"
            pivot.position = CGPoint(x: (segment.pivot.x-anchorCanvas.x)*sx,
                                     y: (anchorCanvas.y-segment.pivot.y)*sy)
            pivot.zPosition = CGFloat(segment.zOrderCandidate) * 0.001
            let sprite = SKSpriteNode(texture: texture, size: bodyPart.size)
            sprite.name = "r007_distal_\(segment.id)"
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            sprite.position = CGPoint(x: (DragonDistalLegRigCandidateR007.nominalCanvas.width/2-segment.pivot.x)*sx,
                                      y: (segment.pivot.y-DragonDistalLegRigCandidateR007.nominalCanvas.height/2)*sy)
            pivot.addChild(sprite)
            built[segment.id] = (pivot, sprite)
        }
        self.partsByID = built
    }

    func mount() {
        guard !isMounted else { return }
        bodyPart.texture = bodyMaskedTexture
        for segment in DragonDistalLegRigCandidateR007.segments {
            guard let pair = partsByID[segment.id], pair.pivot.parent == nil else { continue }
            bodyPart.addChild(pair.pivot)
        }
        isMounted = DragonDistalLegRigCandidateR007.segments.allSatisfy {
            partsByID[$0.id]?.pivot.parent === bodyPart
        }
    }

    func applyPose(elapsed: TimeInterval) {
        guard isMounted else { return }
        let cycle = max(0, elapsed).truncatingRemainder(dividingBy: DragonDistalLegRigCandidateR007.duration) /
            DragonDistalLegRigCandidateR007.duration
        for segment in DragonDistalLegRigCandidateR007.segments {
            guard let pivot = partsByID[segment.id]?.pivot else { continue }
            let phase = (cycle + segment.phase).truncatingRemainder(dividingBy: 1)
            guard phase > DragonDistalLegRigCandidateR007.stanceFraction else {
                pivot.zRotation = 0
                continue
            }
            let swing = (phase-DragonDistalLegRigCandidateR007.stanceFraction) /
                (1-DragonDistalLegRigCandidateR007.stanceFraction)
            let direction: CGFloat = segment.phase == 0 ? 1 : -1
            pivot.zRotation = direction * segment.rotationDegrees * sin(.pi*swing) * .pi / 180
        }
    }

    func unmount() {
        bodyPart.removeAction(forKey: Self.actionKey)
        for pair in partsByID.values {
            pair.pivot.removeAllActions()
            pair.pivot.removeFromParent()
            pair.pivot.zRotation = 0
        }
        bodyPart.texture = bodyOriginalTexture
        isMounted = false
    }

    var pivotReadback: [[String: Any]] {
        DragonDistalLegRigCandidateR007.segments.map { segment in
            let pivot = partsByID[segment.id]?.pivot
            return ["segmentID": segment.id, "rotationRadians": Double(pivot?.zRotation ?? 0),
                    "position": [Double(pivot?.position.x ?? .nan), Double(pivot?.position.y ?? .nan)],
                    "attached": pivot?.parent === bodyPart]
        }
    }
}
