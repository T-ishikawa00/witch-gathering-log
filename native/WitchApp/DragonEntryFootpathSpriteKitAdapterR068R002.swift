import Foundation
import SpriteKit

/// Off-live adapter. It only adjusts existing R064 pivots for the normal 0.6s
/// arrival. The canonical body texture and partition sprites remain unchanged.
@MainActor
final class DragonEntryFootpathSpriteKitAdapterR068R002 {
    struct LegNodes {
        let upperPivot: SKSpriteNode
        let lowerPivot: SKNode
        let wristPivot: SKNode
        let hip: CGPoint
        let knee: CGPoint
        let ankle: CGPoint
        let toe: CGPoint
    }
    private struct SavedTransform {
        let upperPosition: CGPoint
        let upperRotation: CGFloat
        let lowerPosition: CGPoint
        let lowerRotation: CGFloat
        let wristPosition: CGPoint
        let wristRotation: CGFloat
    }
    private struct AppliedRootOffset {
        let actionBasePosition: CGPoint
        let appliedPosition: CGPoint
        let parentDelta: CGPoint
    }

    static let bodyPartID = "body4legs_tail"
    static let sourcePath = "GeneratedCandidates/ACT_B_R04_B/rig_candidate_r001/parts/body4legs_tail_part_r001.png"
    static let sourceSHA256 = DragonEntryFootpathIKR068R002.sourceSHA256
    static let referenceTraceSHA256 = DragonEntryFootpathIKR068R002.referenceTraceSHA256
    static let candidateID = "dragon_entry_footpath_ik_r068_r002"

    let actorRoot: SKNode
    let bodyPart: SKSpriteNode
    let sourceTextureAtInit: SKTexture?
    private let solver: DragonEntryFootpathIKR068R002
    private let legs: [String: LegNodes]
    private let saved: [String: SavedTransform]
    private let sx: CGFloat
    private let sy: CGFloat
    private let sourceAnchor = CGPoint(x: 178, y: 56)
    private var appliedRootOffset: AppliedRootOffset?
    private(set) var lastSnapshot: [String: Any] = [:]
    private(set) var lastElapsed = 0.0

    init?(solver: DragonEntryFootpathIKR068R002, actorRoot: SKNode, bodyPart: SKSpriteNode,
          legs: [String: LegNodes]) {
        let required: Set<String> = ["fore_far", "fore_near", "hind_far", "hind_near"]
        guard Set(legs.keys) == required,
              bodyPart.size.width.isFinite, bodyPart.size.height.isFinite,
              bodyPart.size.width > 0, bodyPart.size.height > 0,
              abs(bodyPart.size.width / bodyPart.size.height - 455.0 / 157.0) < 0.01,
              bodyPart.parent != nil, actorRoot.parent != nil,
              let solverCheck = try? DragonEntryFootpathIKR068R002() else { return nil }
        _ = solverCheck
        self.solver = solver
        self.actorRoot = actorRoot
        self.bodyPart = bodyPart
        self.legs = legs
        self.sourceTextureAtInit = bodyPart.texture
        self.sx = bodyPart.size.width / 455.0
        self.sy = bodyPart.size.height / 157.0
        var transforms: [String: SavedTransform] = [:]
        for (id, nodes) in legs {
            guard nodes.upperPivot.parent === bodyPart,
                  nodes.lowerPivot.parent === bodyPart,
                  nodes.wristPivot.parent === nodes.lowerPivot,
                  nodes.hip.x.isFinite, nodes.hip.y.isFinite,
                  nodes.knee.x.isFinite, nodes.knee.y.isFinite,
                  nodes.ankle.x.isFinite, nodes.ankle.y.isFinite,
                  nodes.toe.x.isFinite, nodes.toe.y.isFinite else { return nil }
            transforms[id] = SavedTransform(upperPosition: nodes.upperPivot.position,
                upperRotation: nodes.upperPivot.zRotation,
                lowerPosition: nodes.lowerPivot.position, lowerRotation: nodes.lowerPivot.zRotation,
                wristPosition: nodes.wristPivot.position, wristRotation: nodes.wristPivot.zRotation)
        }
        self.saved = transforms
    }

    private func bodyLocal(_ p: DragonEntryFootpathIKR068R002.Point, bodyDrop: Double) -> CGPoint {
        CGPoint(x: CGFloat(p.x - Double(sourceAnchor.x)) * sx,
                y: CGFloat(Double(sourceAnchor.y) - (p.y - bodyDrop)) * sy)
    }
    private func rotate(_ p: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(x: p.x*cos(angle)-p.y*sin(angle), y: p.x*sin(angle)+p.y*cos(angle))
    }
    private func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x*b.x + a.y*b.y }
    private func subtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x:a.x-b.x,y:a.y-b.y) }

    private func sourceOffset(sceneDelta: CGPoint, scene: SKScene) -> Double? {
        let origin = bodyPart.convert(CGPoint.zero, to: scene)
        let oneSourcePixel = bodyPart.convert(CGPoint(x: sx, y: 0), to: scene)
        let axis = subtract(oneSourcePixel, origin)
        let axis2 = dot(axis, axis)
        guard axis2.isFinite, axis2 > 1e-12,
              sceneDelta.x.isFinite, sceneDelta.y.isFinite else { return nil }
        return Double(dot(sceneDelta, axis) / axis2)
    }

    static func rootDropParentDelta(bodyPart: SKSpriteNode, actorRoot: SKNode,
                                    sourcePixels: Double, scene: SKScene) -> CGPoint? {
        guard sourcePixels.isFinite, let rootParent = actorRoot.parent else { return nil }
        // Convert the body-local source-pixel vector through SpriteKit's actual
        // hierarchy, then into actorRoot's immediate parent coordinate system.
        let sy = bodyPart.size.height / 157.0
        let bodyOriginInScene = bodyPart.convert(CGPoint.zero, to: scene)
        let bodyDownInScene = bodyPart.convert(CGPoint(x: 0, y: -CGFloat(sourcePixels) * sy), to: scene)
        let originInRootParent = rootParent.convert(bodyOriginInScene, from: scene)
        let downInRootParent = rootParent.convert(bodyDownInScene, from: scene)
        let delta = CGPoint(x: downInRootParent.x-originInRootParent.x,
                            y: downInRootParent.y-originInRootParent.y)
        guard delta.x.isFinite, delta.y.isFinite else { return nil }
        return delta
    }

    /// Run after SpriteKit has evaluated the ordinary arrival SKAction. Start,
    /// current, and home are same-scene root-origin points captured/read that frame.
    func apply(elapsed: Double, entryStartRootScene: CGPoint, currentRootScene: CGPoint,
              homeRootScene: CGPoint, scene: SKScene) throws -> [String: Any] {
        guard elapsed.isFinite, entryStartRootScene.x.isFinite, entryStartRootScene.y.isFinite,
              currentRootScene.x.isFinite, currentRootScene.y.isFinite,
              homeRootScene.x.isFinite, homeRootScene.y.isFinite else {
            throw DragonEntryFootpathIKR068R002.CandidateError.invalidTravel
        }
        // The customAction elapsed value is the arrival group's action clock.
        // If it has not advanced, the move action did not author a new position;
        // remove the prior adapter correction and preserve any external movement
        // made since the last sample. When elapsed advances, SpriteKit has written
        // the next authored move position and it is the new base.
        let basePosition: CGPoint
        let effectiveCurrentRootScene: CGPoint
        let recoveredPreviousOffset: Bool
        let externalRootDelta: CGPoint
        if let previous = appliedRootOffset, abs(elapsed-lastElapsed) < 1e-9,
           let parent = actorRoot.parent {
            externalRootDelta = CGPoint(x: actorRoot.position.x-previous.appliedPosition.x,
                                        y: actorRoot.position.y-previous.appliedPosition.y)
            basePosition = CGPoint(x: previous.actionBasePosition.x+externalRootDelta.x,
                                   y: previous.actionBasePosition.y+externalRootDelta.y)
            effectiveCurrentRootScene = parent.convert(basePosition, to: scene)
            recoveredPreviousOffset = true
        } else {
            basePosition = actorRoot.position
            effectiveCurrentRootScene = currentRootScene
            recoveredPreviousOffset = false
            externalRootDelta = .zero
        }
        guard let currentOffset = sourceOffset(sceneDelta: subtract(effectiveCurrentRootScene, entryStartRootScene), scene: scene),
              let totalTravel = sourceOffset(sceneDelta: subtract(homeRootScene, entryStartRootScene), scene: scene) else {
            throw DragonEntryFootpathIKR068R002.CandidateError.invalidTravel
        }
        let measuredPose = try solver.poseFollowingMeasuredTravel(
            actionElapsed: elapsed,
            currentRootOffsetSourceX: currentOffset,
            actualEntryTravelSourceX: totalTravel)
        let pose = measuredPose.pose
        guard let rootDelta = Self.rootDropParentDelta(bodyPart: bodyPart, actorRoot: actorRoot,
                                                       sourcePixels: pose.bodyDropSourceY, scene: scene) else {
            throw DragonEntryFootpathIKR068R002.CandidateError.coordinateConversionFailed
        }

        for (id, legPose) in pose.legs {
            guard let nodes = legs[id], let source = DragonEntryFootpathIKR068R002.legGeometry[id] else { continue }
            nodes.upperPivot.position = bodyLocal(legPose.hip, bodyDrop: pose.bodyDropSourceY)
            nodes.upperPivot.zRotation = CGFloat(-legPose.upperDeltaRadians)
            nodes.lowerPivot.position = bodyLocal(legPose.knee, bodyDrop: pose.bodyDropSourceY)
            let lowerRotation = CGFloat(-legPose.lowerDeltaRadians)
            nodes.lowerPivot.zRotation = lowerRotation
            let ankleBody = CGPoint(x: CGFloat(legPose.ankle.x-legPose.knee.x)*sx,
                                    y: -CGFloat(legPose.ankle.y-legPose.knee.y)*sy)
            nodes.wristPivot.position = rotate(ankleBody, by: -lowerRotation)
            let baselineToe = CGPoint(x: CGFloat(source.toe.x-source.ankle.x)*sx,
                                      y: -CGFloat(source.toe.y-source.ankle.y)*sy)
            let targetToe = CGPoint(x: CGFloat(legPose.toe.x-legPose.ankle.x)*sx,
                                    y: -CGFloat(legPose.toe.y-legPose.ankle.y)*sy)
            nodes.wristPivot.zRotation = atan2(targetToe.y,targetToe.x)-atan2(baselineToe.y,baselineToe.x)-lowerRotation
        }

        // Each SKAction move tick provides the authored base position. The
        // converted offset is added to that fresh value, never accumulated.
        actorRoot.position = CGPoint(x: basePosition.x + rootDelta.x, y: basePosition.y + rootDelta.y)
        appliedRootOffset = AppliedRootOffset(actionBasePosition: basePosition,
                                              appliedPosition: actorRoot.position,
                                              parentDelta: rootDelta)
        lastElapsed = elapsed
        lastSnapshot = [
            "candidateID": Self.candidateID,
            "elapsedSeconds": measuredPose.actionElapsed,
            "elapsedSource": "battle_arrival_group_custom_action",
            "contactPhaseElapsedSeconds": measuredPose.phaseElapsed,
            "normalizedMeasuredTravel": measuredPose.normalizedTravel,
            "rootBaseRecoveredFromPreviousOffset": recoveredPreviousOffset,
            "externalRootDeltaParent": [Double(externalRootDelta.x), Double(externalRootDelta.y)],
            "effectiveCurrentRootScene": [Double(effectiveCurrentRootScene.x), Double(effectiveCurrentRootScene.y)],
            "sourceSHA256": Self.sourceSHA256,
            "referenceTraceSHA256": Self.referenceTraceSHA256,
            "entryTravelSourceX": totalTravel,
            "measuredRootOffsetSourceX": currentOffset,
            "scaledReferenceOffsetSourceX": pose.scaledReferenceOffsetSourceX,
            "bodyDropSourcePx": pose.bodyDropSourceY,
            "rootDropParentDelta": [Double(rootDelta.x), Double(rootDelta.y)],
            "rootDropSceneDelta": {
                let origin = bodyPart.convert(CGPoint.zero, to: scene)
                let down = bodyPart.convert(CGPoint(x:0,y:-CGFloat(pose.bodyDropSourceY)*sy), to: scene)
                return [Double(down.x-origin.x), Double(down.y-origin.y)]
            }(),
            "textureUnchanged": bodyPart.texture === sourceTextureAtInit,
            "legCount": pose.legs.count,
            "legs": pose.legs.mapValues { [
                "stance": $0.stance, "liftSourcePx": $0.liftSourcePixels,
                "upperDeltaRadians": $0.upperDeltaRadians, "lowerDeltaRadians": $0.lowerDeltaRadians,
                "reachResidual": $0.reachResidual
            ] }
        ]
        return lastSnapshot
    }

    /// Restores saved R064 pivots and only removes the root delta if the root is
    /// still at the position this adapter wrote. External movement is preserved.
    func restore() {
        for (id, nodes) in legs {
            guard let saved = saved[id] else { continue }
            nodes.upperPivot.position = saved.upperPosition
            nodes.upperPivot.zRotation = saved.upperRotation
            nodes.lowerPivot.position = saved.lowerPosition
            nodes.lowerPivot.zRotation = saved.lowerRotation
            nodes.wristPivot.position = saved.wristPosition
            nodes.wristPivot.zRotation = saved.wristRotation
        }
        if let applied = appliedRootOffset,
           hypot(actorRoot.position.x - applied.appliedPosition.x,
                 actorRoot.position.y - applied.appliedPosition.y) < 0.001 {
            actorRoot.position = applied.actionBasePosition
        }
        appliedRootOffset = nil
        lastElapsed = 0
    }
}
