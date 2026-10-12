import SpriteKit
import UIKit

/// Data contract for a SpriteKit articulated actor. All authored coordinates are
/// source-canvas pixels with a top-left origin; no inferred pivot is supplied.
struct EnemyPartRigDefinition: Decodable {
    // Keep the acronym in lower camel case so JSONDecoder's
    // convertFromSnakeCase maps `actor_id` to this property (`actorId`).
    let actorId: String
    let canvasPx: [Double]
    let anchorPx: [Double]
    let fps: Double
    let parts: [EnemyRigPartDefinition]
    let clips: [String: EnemyRigClipDefinition]
}

struct EnemyRigPartDefinition: Decodable {
    let id: String
    let path: String
    let pivotInPartPx: [Double]
    let restPositionPx: [Double]
    let zPosition: Double
}

struct EnemyRigClipDefinition: Decodable {
    let fps: Double?
    let loop: Bool
    let frameCount: Int
    let keyframes: [EnemyRigKeyframe]
}

struct EnemyRigKeyframe: Decodable {
    let frame: Double
    let poseByPart: [String: EnemyRigPartPose]
}

struct EnemyRigPartPose: Decodable {
    /// Translation from the part's rest position, in canvas pixels.
    let translationPx: [Double]?
    /// Clockwise rotation in degrees in the source top-left coordinate system.
    let rotationDeg: Double?
    // `convertFromSnakeCase` maps `scale_xy` to `scaleXy`, not `scaleXY`.
    let scaleXy: [Double]?
}

/// Candidate leg-only replacement supplied through an actor runtime overlay.
/// The source body texture remains canonical; the replacement is cropped to the
/// authored leg polygons and is enabled only while the exact walk state plays.
private struct EnemyRigWalkLegOverlay {
    let framePaths: [String]
    let fps: Double
    let bodyPartID: String
    let polygons: [[[Double]]]

    init?(raw: [String: Any]) {
        guard raw["mode"] as? String == "part_rig_leg_overlay_candidate_v1",
              let paths = raw["frame_paths"] as? [String], paths.count >= 2,
              let fpsNumber = raw["fps"] as? NSNumber,
              fpsNumber.doubleValue.isFinite, (1...12).contains(fpsNumber.doubleValue),
              let bodyPart = raw["body_part_id"] as? String, !bodyPart.isEmpty,
              let polygons = raw["mask_polygons_px"] as? [[[Double]]],
              !polygons.isEmpty else { return nil }
        for path in paths {
            let components = path.split(separator: "/")
            guard !path.hasPrefix("/"), !components.isEmpty,
                  !components.contains(".."), path.hasSuffix(".png") else { return nil }
        }
        for polygon in polygons {
            guard polygon.count >= 3,
                  polygon.allSatisfy({ $0.count == 2 && $0[0].isFinite && $0[1].isFinite &&
                      $0[0] >= 0 && $0[0] <= 455 && $0[1] >= 0 && $0[1] <= 157 }) else { return nil }
        }
        self.framePaths = paths
        self.fps = fpsNumber.doubleValue
        self.bodyPartID = bodyPart
        self.polygons = polygons
    }
}

enum EnemyPartRigError: Error, LocalizedError {
    case invalidDefinition(String)
    case missingTexture(String)

    var errorDescription: String? {
        switch self {
        case .invalidDefinition(let reason): return "Invalid enemy part-rig definition: \(reason)"
        case .missingTexture(let path): return "Enemy part texture is missing or unreadable: \(path)"
        }
    }
}

/// Plays transforms on explicitly authored cutout parts. This does not synthesize
/// unseen anatomy: the manifest must provide the source artwork, pivots, placement,
/// and per-state keyframes. Missing states remain missing.
@MainActor
final class EnemyPartRig {
    let actorID: String
    let canvasSize: CGSize
    let normalizedAnchor: CGPoint
    let node: SKNode
    private(set) var availableStates: Set<String>
    var onUnsupportedState: ((String) -> Void)?
    var onClipCompleted: ((String) -> Void)?

    private let definition: EnemyPartRigDefinition
    private let actionKey = "witch.enemy.part-rig.clip"
    private var partNodes: [String: SKSpriteNode] = [:]
    private var baseScaleByPart: [String: CGPoint] = [:]
    private var activeState: String?
    private var presentationStatus = "not_started"
    private var presentationDuration = 0.0
    private var presentationElapsed = 0.0
    private var presentationFPS = 0.0
    private var presentationFramePosition = 0.0
    private var presentationFrameCount = 0
    private var presentationKeyframeIndex = -1
    private var presentationNextKeyframeIndex = -1
    private var presentationKeyframeBlend = 0.0
    private let canvasScaleX: CGFloat
    private let canvasScaleY: CGFloat
    private var walkLegOverlay: EnemyRigWalkLegOverlay?
    private var walkCoreCrop: SKCropNode?
    private var walkCandidateCrop: SKCropNode?
    private var walkCandidateSprite: SKSpriteNode?
    private var walkCandidateTextures: [SKTexture] = []
    private var walkCandidateFrameIndex = 0
    private let walkOverlayActionKey = "witch.enemy.part-rig.walk-legs"
    private(set) var walkOverlayStatus = "unavailable"
    private let walkMeshActionKey = "witch.enemy.part-rig.walk-mesh-r004"
    private var walkMeshCandidate: DragonWalkMeshCandidate?
    private var walkGaitR038Frames: [DragonLocalizedLegWarpCandidateR003.Frame]?
    private var walkGaitR038OriginalSubdivision = 0
    private var walkGaitR038Active = false
    private var walkGaitR038Requested = false
    private let walkGaitR038ActionKey = "witch.enemy.part-rig.walk-gait-r038"
    private(set) var walkGaitR038Status = "not_enabled"
    private var walkDistalR007Requested = false
    private var walkFourLegR064Requested = false
    private var walkFourLegR064Mount: DragonFourLegStanceMountR064?
    private var walkFourLegR064Active = false
    private var normalEntryFootpathR068R002Adapter: DragonEntryFootpathSpriteKitAdapterR068R002?
    private var normalEntryFootpathR068R002Status = "not_started"
    private var normalEntryFootpathR068R002LastSnapshot: [String: Any] = [:]
    private let normalEntryBackendR068: String
    private(set) var walkFourLegR064Status = "not_enabled"
    private var walkDistalR007Mount: DragonDistalLegRigMountR007?
    private var walkDistalR007Active = false
    private let walkDistalR007ActionKey = DragonDistalLegRigMountR007.actionKey
    private(set) var walkDistalR007Status = "not_enabled"
    private var walkMeshOriginalSubdivision = 0
    private var walkMeshActive = false
    private(set) var groundedEntryActive = false
    private(set) var walkMeshStatus = "not_enabled"
    var hasWalkMeshCandidate: Bool { walkMeshCandidate != nil }

    /// `artRoot` is the Art bundle directory. `displaySize` sets the whole-rig size;
    /// nil uses one SpriteKit point per source pixel.
    init(definitionURL: URL, artRoot: URL, displaySize: CGSize? = nil,
         walkOverlay: [String: Any]? = nil, qaWalkMeshCandidateEnabled: Bool = false,
         qaDragonGaitR038Enabled: Bool = false, qaDragonDistalLegR007Enabled: Bool = false,
         qaDragonFourLegR064Enabled: Bool = false,
         normalEntryBackendR068: String = "legacy_existing_override") throws {
        let data = try Data(contentsOf: definitionURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parsed = try decoder.decode(EnemyPartRigDefinition.self, from: data)
        guard parsed.canvasPx.count == 2,
              parsed.anchorPx.count == 2,
              parsed.canvasPx[0] > 0,
              parsed.canvasPx[1] > 0,
              parsed.fps > 0,
              !parsed.parts.isEmpty else {
            throw EnemyPartRigError.invalidDefinition("canvas, anchor, fps, or parts are invalid")
        }

        let sx = displaySize.map { Double($0.width) / parsed.canvasPx[0] } ?? 1.0
        let sy = displaySize.map { Double($0.height) / parsed.canvasPx[1] } ?? 1.0
        self.canvasSize = CGSize(width: parsed.canvasPx[0], height: parsed.canvasPx[1])
        self.normalizedAnchor = CGPoint(x: parsed.anchorPx[0]/parsed.canvasPx[0], y: 1-parsed.anchorPx[1]/parsed.canvasPx[1])
        self.actorID = parsed.actorId
        self.definition = parsed
        self.node = SKNode()
        self.availableStates = Set(parsed.clips.keys)
        self.canvasScaleX = CGFloat(sx)
        self.canvasScaleY = CGFloat(sy)
        self.walkGaitR038Requested = qaDragonGaitR038Enabled && parsed.actorId == "ACT_B_R04_B"
        self.walkDistalR007Requested = qaDragonDistalLegR007Enabled && parsed.actorId == "ACT_B_R04_B"
        self.walkFourLegR064Requested = qaDragonFourLegR064Enabled && parsed.actorId == "ACT_B_R04_B"
        self.normalEntryBackendR068 = normalEntryBackendR068

        for part in parsed.parts {
            guard part.pivotInPartPx.count == 2,
                  part.restPositionPx.count == 2,
                  let image = UIImage(contentsOfFile: artRoot.appendingPathComponent(part.path).path) else {
                throw EnemyPartRigError.missingTexture(part.path)
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            let sprite = SKSpriteNode(texture: texture)
            let width = Double(image.size.width) * Double(image.scale)
            let height = Double(image.size.height) * Double(image.scale)
            guard width > 0, height > 0 else {
                throw EnemyPartRigError.invalidDefinition("part \(part.id) has an empty texture")
            }
            sprite.name = "\(parsed.actorId).\(part.id)"
            sprite.anchorPoint = CGPoint(
                x: CGFloat(part.pivotInPartPx[0] / width),
                y: CGFloat(1.0 - part.pivotInPartPx[1] / height)
            )
            sprite.size = CGSize(width: width * sx, height: height * sy)
            sprite.position = Self.scenePoint(
                sourcePx: part.restPositionPx,
                rootAnchorPx: parsed.anchorPx,
                scaleX: sx,
                scaleY: sy
            )
            sprite.zPosition = part.zPosition
            self.node.addChild(sprite)
            self.partNodes[part.id] = sprite
            self.baseScaleByPart[part.id] = CGPoint(x: 1, y: 1)
        }

        if let walkOverlay,
           let spec = EnemyRigWalkLegOverlay(raw: walkOverlay),
           installWalkLegOverlay(spec, artRoot: artRoot) {
            self.walkLegOverlay = spec
            self.availableStates.insert("walk")
            self.walkOverlayStatus = "candidate_ready_unapproved"
        } else if walkOverlay != nil {
            self.walkOverlayStatus = "candidate_rejected_invalid_or_missing_resource"
        }
        if qaWalkMeshCandidateEnabled, actorID == "ACT_B_R04_B" {
            if let body = partNodes[DragonWalkMeshCandidate.bodyPartID],
               body.warpGeometry == nil,
               abs(Double(body.size.width) / sx - 455) < 0.5,
               abs(Double(body.size.height) / sy - 157) < 0.5 {
                do {
                    walkMeshCandidate = try DragonWalkMeshCandidate()
                    walkMeshOriginalSubdivision = body.subdivisionLevels
                    walkMeshStatus = "candidate_ready_unapproved"
                    availableStates.insert("walk")
                } catch {
                    walkMeshStatus = "candidate_rejected_invalid_geometry"
                }
            } else {
                walkMeshStatus = "candidate_rejected_body_mismatch"
            }
        }
        if qaDragonGaitR038Enabled, actorID == "ACT_B_R04_B" {
            if let body = partNodes[DragonLocalizedLegWarpCandidateR003.bodyPartID],
               body.warpGeometry == nil,
               abs(Double(body.size.width) / sx - Double(DragonLocalizedLegWarpCandidateR003.bodyWidth)) < 0.5,
               abs(Double(body.size.height) / sy - Double(DragonLocalizedLegWarpCandidateR003.bodyHeight)) < 0.5 {
                do {
                    let frames = try DragonLocalizedLegWarpCandidateR003.makeFrames()
                    guard frames.count == DragonLocalizedLegWarpCandidateR003.sampleCount,
                          frames.first?.time == 0,
                          frames.last?.time == DragonLocalizedLegWarpCandidateR003.duration else {
                        throw DragonLocalizedLegWarpCandidateR003.BuildError.invalidSourceGrid
                    }
                    walkGaitR038Frames = frames
                    walkGaitR038OriginalSubdivision = body.subdivisionLevels
                    walkGaitR038Status = "candidate_ready_unapproved"
                    availableStates.insert("walk")
                } catch {
                    walkGaitR038Status = "candidate_rejected_invalid_geometry"
                }
            } else {
                walkGaitR038Status = "candidate_rejected_body_mismatch"
            }
        }
        if walkDistalR007Requested, actorID == "ACT_B_R04_B" {
            if let body = partNodes["body4legs_tail"],
               let partDefinition = parsed.parts.first(where: { $0.id == "body4legs_tail" }),
               partDefinition.pivotInPartPx.count == 2 {
                let anchor = CGPoint(x: partDefinition.pivotInPartPx[0], y: partDefinition.pivotInPartPx[1])
                if let mount = DragonDistalLegRigMountR007(bodyPart: body, artRoot: artRoot, anchorCanvas: anchor) {
                    walkDistalR007Mount = mount
                    walkDistalR007Status = "candidate_ready_unapproved"
                    availableStates.insert("walk")
                } else {
                    walkDistalR007Status = "candidate_rejected_source_or_body_mismatch"
                }
            } else {
                walkDistalR007Status = "candidate_rejected_missing_body_part"
            }
        }
        if walkFourLegR064Requested, actorID == "ACT_B_R04_B",
           !walkDistalR007Requested, !walkGaitR038Requested, walkMeshCandidate == nil {
            if let body = partNodes["body4legs_tail"],
               let partDefinition = parsed.parts.first(where: { $0.id == "body4legs_tail" }),
               partDefinition.path == DragonFourLegStanceMountR064.sourceRelativePath,
               partDefinition.pivotInPartPx.count == 2 {
                let anchor = CGPoint(x: partDefinition.pivotInPartPx[0], y: partDefinition.pivotInPartPx[1])
                if let mount = DragonFourLegStanceMountR064(bodyPart: body, artRoot: artRoot, anchorCanvas: anchor) {
                    walkFourLegR064Mount = mount
                    walkFourLegR064Status = "candidate_ready_unapproved"
                    availableStates.insert("walk")
                } else {
                    walkFourLegR064Status = "candidate_rejected_source_or_partition"
                }
            } else {
                walkFourLegR064Status = "candidate_rejected_body_path_or_part"
            }
        }
    }

    /// Plays one authored transform clip at its declared frame rate. Returns false
    /// for an absent or malformed state without changing the current pose.
    func duration(of state:String)->Double? {
        if state == "walk", walkFourLegR064Requested {
            return walkFourLegR064Mount == nil ? nil : GaitContactScheduleR064.periodSeconds
        }
        if state == "walk", walkDistalR007Requested {
            return walkDistalR007Mount == nil ? nil : TimeInterval(DragonDistalLegRigCandidateR007.duration)
        }
        if state == "walk", walkGaitR038Requested {
            return walkGaitR038Frames == nil ? nil : TimeInterval(DragonLocalizedLegWarpCandidateR003.duration)
        }
        if state == "walk", walkMeshCandidate != nil { return DragonWalkMeshCandidate.duration }
        if state == "walk", let walkLegOverlay { return Double(walkLegOverlay.framePaths.count) / walkLegOverlay.fps }
        guard let clip=definition.clips[state] else{return nil}
        let fps=clip.fps ?? definition.fps
        guard fps.isFinite,fps>0,clip.frameCount>0 else{return nil}
        return Double(clip.frameCount)/fps
    }
    @discardableResult
    func play(_ state: String, restart: Bool = false) -> Bool {
        if state == "walk", walkFourLegR064Requested {
            guard playWalkFourLegR064(restart: restart) else { onUnsupportedState?(state); return false }
            return true
        }
        if state == "walk", walkDistalR007Requested {
            guard playWalkDistalR007(restart: restart) else {
                onUnsupportedState?(state)
                return false
            }
            return true
        }
        if state == "walk", walkGaitR038Requested {
            guard playWalkGaitR038(restart: restart) else {
                onUnsupportedState?(state)
                return false
            }
            return true
        }
        if state == "walk", walkMeshCandidate != nil {
            guard playWalkMeshCandidate(restart: restart) else {
                onUnsupportedState?(state)
                return false
            }
            return true
        }
        if state == "walk", walkLegOverlay != nil {
            guard playWalkLegOverlay(restart: restart) else {
                onUnsupportedState?(state)
                return false
            }
            return true
        }
        guard let clip = definition.clips[state] else {
            onUnsupportedState?(state)
            return false
        }
        guard clip.frameCount > 0,
              !clip.keyframes.isEmpty,
              (clip.fps ?? definition.fps) > 0 else {
            onUnsupportedState?(state)
            return false
        }
        if activeState == state && !restart { return true }

        let ordered = clip.keyframes.sorted { $0.frame < $1.frame }
        guard ordered.first?.frame ?? 0 >= 0,
              ordered.last?.frame ?? -1 < Double(clip.frameCount) else {
            onUnsupportedState?(state)
            return false
        }
        stopWalkFourLegR064()
        stopWalkDistalR007()
        stopWalkGaitR038()
        stopWalkMeshCandidate()
        setWalkLegOverlayActive(false)
        walkCandidateSprite?.removeAction(forKey: walkOverlayActionKey)
        node.removeAction(forKey: actionKey)
        activeState = state

        let fps = clip.fps ?? definition.fps
        let duration = Double(clip.frameCount) / fps
        presentationStatus = "playing"
        presentationDuration = duration
        presentationElapsed = 0
        presentationFPS = fps
        presentationFramePosition = 0
        presentationFrameCount = clip.frameCount
        presentationKeyframeIndex = -1
        presentationNextKeyframeIndex = -1
        presentationKeyframeBlend = 0
        let update = SKAction.customAction(withDuration: duration) { [weak self] _, elapsed in
            guard let self else { return }
            let position = min(Double(clip.frameCount - 1), max(0, Double(elapsed) * fps))
            self.apply(ordered, atFrame: position)
        }
        let completion = SKAction.run { [weak self] in
            guard let self, self.activeState == state else { return }
            if !clip.loop {
                self.presentationStatus = "completed"
                self.presentationElapsed = duration
                self.presentationFramePosition = Double(clip.frameCount - 1)
                self.onClipCompleted?(state)
            }
        }
        let action = SKAction.sequence([update, completion])
        node.run(clip.loop ? .repeatForever(action) : action, withKey: actionKey)
        return true
    }

    func stop(resetToRestPose: Bool = true) {
        node.removeAction(forKey: actionKey)
        stopWalkFourLegR064()
        stopWalkDistalR007()
        stopWalkGaitR038()
        stopWalkMeshCandidate()
        setWalkLegOverlayActive(false)
        walkCandidateSprite?.removeAction(forKey: walkOverlayActionKey)
        activeState = nil
        presentationStatus = "stopped"
        presentationDuration = 0
        presentationElapsed = 0
        presentationFPS = 0
        presentationFramePosition = 0
        presentationFrameCount = 0
        presentationKeyframeIndex = -1
        presentationNextKeyframeIndex = -1
        presentationKeyframeBlend = 0
        if resetToRestPose {
            for part in definition.parts {
                guard let sprite = partNodes[part.id],
                      let baseScale = baseScaleByPart[part.id] else { continue }
                sprite.position = Self.scenePoint(
                    sourcePx: part.restPositionPx,
                    rootAnchorPx: definition.anchorPx,
                    scaleX: Double(canvasScaleX),
                    scaleY: Double(canvasScaleY)
                )
                sprite.zRotation = 0
                sprite.xScale = baseScale.x
                sprite.yScale = baseScale.y
            }
        }
    }

    /// Read-only evidence for the active rig timeline. The frame position is
    /// sampled alongside the transforms applied to the rendered parts.
    var presentationSnapshot: [String: Any] {
        var snapshot: [String: Any] = ["status": presentationStatus,
         "state": activeState ?? "none",
         "durationSeconds": presentationDuration,
         "elapsedSeconds": presentationElapsed,
         "normalizedProgress": presentationDuration > 0 ? presentationElapsed / presentationDuration : 0,
         "fps": presentationFPS,
         "frameCount": presentationFrameCount,
         "framePosition": presentationFramePosition,
         "frameIndex": presentationFrameCount > 0 ? Int(presentationFramePosition.rounded(.down)) : -1,
         "keyframeIndex": presentationKeyframeIndex,
         "nextKeyframeIndex": presentationNextKeyframeIndex,
         "keyframeBlend": presentationKeyframeBlend,
         "completed": presentationStatus == "completed",
         "actionRunning": node.action(forKey: actionKey) != nil,
         "walkLegOverlayStatus": walkOverlayStatus,
         "walkLegOverlayActive": walkCandidateCrop?.isHidden == false,
         "walkLegOverlayFrameIndex": walkCandidateFrameIndex,
         "walkLegOverlayFramePath": walkLegOverlay.flatMap { spec in
             spec.framePaths.indices.contains(walkCandidateFrameIndex) ? spec.framePaths[walkCandidateFrameIndex] : nil
         } ?? "none",
         "walkGaitR038Status": walkGaitR038Status,
         "walkGaitR038Requested": walkGaitR038Requested,
         "walkGaitR038Active": walkGaitR038Active,
         "walkGaitR038GeometryPresent": walkGaitR038Active && partNodes[DragonLocalizedLegWarpCandidateR003.bodyPartID]?.warpGeometry != nil,
         "walkGaitR038WarpGeometryActuallyPresent": partNodes[DragonLocalizedLegWarpCandidateR003.bodyPartID]?.warpGeometry != nil,
         "walkGaitR038ActionRunning": partNodes[DragonLocalizedLegWarpCandidateR003.bodyPartID]?.action(forKey: walkGaitR038ActionKey) != nil,
         "walkGaitR038BodyVisible": partNodes[DragonLocalizedLegWarpCandidateR003.bodyPartID]?.isHidden == false,
         "walkGaitR038OriginalSubdivisionLevels": walkGaitR038OriginalSubdivision,
         "walkFourLegR064Requested": walkFourLegR064Requested,
         "walkFourLegR064Status": walkFourLegR064Status,
         "walkFourLegR064Active": walkFourLegR064Active,
         "walkFourLegR064MountPresent": walkFourLegR064Mount?.isMounted == true,
         "walkFourLegR064Animating": walkFourLegR064Mount?.isAnimating == true,
         "walkFourLegR064BodyTextureRestored": walkFourLegR064Mount?.originalTextureRestored == true,
         "walkFourLegR064BodyCoreInstalled": walkFourLegR064Mount?.staticCoreInstalled == true,
         "walkFourLegR064BodyVisible": partNodes["body4legs_tail"]?.isHidden == false,
         "walkFourLegR064ActionRunning": partNodes["body4legs_tail"]?.action(forKey: DragonFourLegStanceMountR064.actionKey) != nil,
         "walkFourLegR064SourceSHA256": walkFourLegR064Mount?.sourceSHA256Readback ?? "none",
         "walkFourLegR064RecompositionByteMismatchCount": walkFourLegR064Mount?.recompositionByteMismatchCount ?? -1,
         "walkFourLegR064Pivots": walkFourLegR064Mount?.pivotReadback ?? [],
         "normalEntryBackendR068": normalEntryBackendR068,
         "normalEntryFootpathR068R002Active": normalEntryFootpathR068R002Adapter != nil,
         "normalEntryFootpathR068R002Status": normalEntryFootpathR068R002Status,
         "normalEntryFootpathR068R002": normalEntryFootpathR068R002Adapter?.lastSnapshot ?? normalEntryFootpathR068R002LastSnapshot,
         "walkDistalR007Requested": walkDistalR007Requested,
         "walkDistalR007Status": walkDistalR007Status,
         "walkDistalR007Active": walkDistalR007Active,
         "walkDistalR007MountPresent": walkDistalR007Mount?.isMounted == true,
         "walkDistalR007BodyTexturePartitioned": walkDistalR007Mount?.bodyTexturePartitioned == true,
         "walkDistalR007BodyTextureRestored": walkDistalR007Mount?.bodyTextureRestored == true,
         "walkDistalR007BodyVisible": partNodes["body4legs_tail"]?.isHidden == false,
         "walkDistalR007ActionRunning": partNodes["body4legs_tail"]?.action(forKey: walkDistalR007ActionKey) != nil,
         "walkDistalR007SourceSHA256": walkDistalR007Mount?.sourceSHA256 ?? "none",
         "walkDistalR007MaskedPixelCount": walkDistalR007Mount?.partition.totalMaskedPixelCount ?? 0,
         "walkDistalR007JointOverlapPixelCounts": walkDistalR007Mount?.partition.jointOverlapPixelCounts ?? [:],
         "walkDistalR007Pivots": walkDistalR007Mount?.pivotReadback ?? [],
         "walkMeshStatus": walkMeshStatus,
         "walkMeshActive": walkMeshActive,
         "timelineBasis": walkGaitR038Active ? "full_texture_localized_warp_candidate_unapproved" :
             (walkMeshActive ? "authored_idle_skeleton_not_gait_phase" : "active_transform_clip"),
         "walkMeshPeriodSeconds": groundedEntryActive ? DragonGroundedEntryCandidate.duration : DragonWalkMeshCandidate.duration,
         "walkMeshCandidateID": walkGaitR038Active ? DragonLocalizedLegWarpCandidateR003.candidateID :
            (groundedEntryActive ? DragonGroundedEntryCandidate.candidateID : DragonWalkMeshCandidate.candidateID),
         "groundedEntryActive": groundedEntryActive]
        if let body = partNodes["body4legs_tail"] {
            snapshot["walkFourLegR064BodyTransform"] = [
                "position": [Double(body.position.x), Double(body.position.y)],
                "zRotation": Double(body.zRotation), "xScale": Double(body.xScale), "yScale": Double(body.yScale),
                "size": [Double(body.size.width), Double(body.size.height)],
                "anchorPoint": [Double(body.anchorPoint.x), Double(body.anchorPoint.y)],
                "zPosition": Double(body.zPosition), "hidden": body.isHidden,
                "parented": body.parent != nil
            ]
        }
        if let body = partNodes[DragonWalkMeshCandidate.bodyPartID] {
            snapshot["walkMeshGeometryPresent"] = body.warpGeometry != nil
            snapshot["walkMeshActionRunning"] = body.action(forKey: walkMeshActionKey) != nil
            snapshot["bodySubdivisionLevels"] = body.subdivisionLevels
            if walkMeshActive,
               let readback = DragonWalkMeshCandidate.readbackSnapshot(from: body),
               let data = try? JSONEncoder().encode(readback),
               let object = try? JSONSerialization.jsonObject(with: data) {
                snapshot["walkMeshReadback"] = object
            }
        }
        return snapshot
    }

    func loopBoundaryMode(for state: String) -> EnemyLoopBoundaryMode? {
        if state == "walk", walkDistalR007Requested {
            let ready = walkDistalR007Mount != nil
            let period = TimeInterval(DragonDistalLegRigCandidateR007.duration)
            return EnemyLoopBoundaryMode(state: state, presentationKind: "part_rig_exact_source_distal_masks_candidate_r007",
                supported: ready, loops: ready, frameCount: 13, expectedFPS: 10,
                expectedPeriodSeconds: period, framePaths: [],
                phaseMetric: "partRig.walkDistalR007Pivots+walkDistalR007ActionRunning+mountPresent",
                timelineBasis: "exact_runtime_body_source_distal_leg_masks_unapproved")
        }
        if state == "walk", walkGaitR038Requested {
            guard walkGaitR038Frames != nil else {
                return EnemyLoopBoundaryMode(state: state, presentationKind: "part_rig_localized_full_texture_warp_candidate",
                    supported: false, loops: false, frameCount: 0, expectedFPS: 0,
                    expectedPeriodSeconds: 0, framePaths: [], phaseMetric: "candidate_rejected_no_clip",
                    timelineBasis: "qa_requested_but_candidate_unavailable")
            }
            let period = TimeInterval(DragonLocalizedLegWarpCandidateR003.duration)
            return EnemyLoopBoundaryMode(state: state, presentationKind: "part_rig_localized_full_texture_warp_candidate",
                supported: false, loops: true, frameCount: DragonLocalizedLegWarpCandidateR003.sampleCount,
                expectedFPS: Double(DragonLocalizedLegWarpCandidateR003.sampleCount - 1) / period,
                expectedPeriodSeconds: period, framePaths: [],
                phaseMetric: "partRig.presentationFramePosition+walkGaitR038GeometryPresent+walkGaitR038ActionRunning",
                timelineBasis: "original_full_body_texture_localized_warp_visual_estimates_unapproved")
        }
        if state == "walk", walkMeshCandidate != nil {
            let period = DragonWalkMeshCandidate.duration
            return EnemyLoopBoundaryMode(state: state, presentationKind: "part_rig_mesh_candidate",
                supported: false, loops: true, frameCount: 13,
                expectedFPS: 13 / period, expectedPeriodSeconds: period, framePaths: [],
                phaseMetric: "partRig.normalizedProgress+walkMeshReadback.sampledLowerVertices+walkMeshActionRunning",
                timelineBasis: "authored_idle_skeleton_not_gait_phase")
        }
        if state == "walk", let walkLegOverlay {
            return EnemyLoopBoundaryMode(state: state, presentationKind: "part_rig_leg_overlay",
                supported: true, loops: true, frameCount: walkLegOverlay.framePaths.count,
                expectedFPS: walkLegOverlay.fps,
                expectedPeriodSeconds: Double(walkLegOverlay.framePaths.count) / walkLegOverlay.fps,
                framePaths: walkLegOverlay.framePaths,
                phaseMetric: "partRig.walkLegOverlayFrameIndex+walkLegOverlayFramePath",
                timelineBasis: "candidate_leg_overlay_not_skeleton_gait_phase")
        }
        guard let clip = definition.clips[state] else { return nil }
        let fps = clip.fps ?? definition.fps
        let count = max(1, clip.frameCount)
        let validFPS = fps.isFinite && fps > 0
        return EnemyLoopBoundaryMode(state: state, presentationKind: "part_rig_transform_clip",
            supported: true, loops: clip.loop, frameCount: count, expectedFPS: fps,
            expectedPeriodSeconds: validFPS ? Double(count) / fps : 0, framePaths: [],
            phaseMetric: "partRig.normalizedProgress+framePosition+actionRunning",
            timelineBasis: "authored_rig_transform_timeline_not_sprite_identity")
    }

    /// Installs the entry-only adapter after the ordinary R064 walk has mounted.
    /// This is a presentation candidate; it does not start/replace any SKAction.
    func beginNormalEntryFootpathR068R002(actorRoot: SKNode) -> Bool {
        guard actorID == "ACT_B_R04_B",
              normalEntryBackendR068 == "r064LocalDefaultCandidate",
              walkFourLegR064Requested, walkFourLegR064Active,
              normalEntryFootpathR068R002Adapter == nil,
              let mount = walkFourLegR064Mount,
              let body = partNodes[DragonEntryFootpathSpriteKitAdapterR068R002.bodyPartID],
              let bindings = mount.entryLegBindingsR068R002(),
              let solver = try? DragonEntryFootpathIKR068R002(),
              let adapter = DragonEntryFootpathSpriteKitAdapterR068R002(
                solver: solver, actorRoot: actorRoot, bodyPart: body, legs: bindings) else { return false }
        normalEntryFootpathR068R002Adapter = adapter
        normalEntryFootpathR068R002Status = "active"
        normalEntryFootpathR068R002LastSnapshot = [:]
        return true
    }

    func applyNormalEntryFootpathR068R002(elapsed: Double,
                                          entryStartRootScene: CGPoint,
                                          currentRootScene: CGPoint,
                                          homeRootScene: CGPoint,
                                          scene: SKScene) -> [String: Any]? {
        guard let adapter = normalEntryFootpathR068R002Adapter else { return nil }
        guard let snapshot = try? adapter.apply(elapsed: elapsed, entryStartRootScene: entryStartRootScene,
                                               currentRootScene: currentRootScene, homeRootScene: homeRootScene, scene: scene) else {
            return nil
        }
        normalEntryFootpathR068R002LastSnapshot = snapshot
        return snapshot
    }

    func restoreNormalEntryFootpathR068R002() {
        guard let adapter = normalEntryFootpathR068R002Adapter else { return }
        normalEntryFootpathR068R002LastSnapshot = adapter.lastSnapshot
        normalEntryFootpathR068R002Adapter?.restore()
        normalEntryFootpathR068R002Adapter = nil
        normalEntryFootpathR068R002Status = "restored"
    }

    /// QA getter only: four opaque source-mesh vertices near visible paws.
    /// These are reproducible artwork samples, not anatomical or ground-contact claims.
    func entryTraceSnapshot(in scene: SKScene) -> [String: Any] {
        guard actorID == "ACT_B_R04_B", let body = partNodes[DragonWalkMeshCandidate.bodyPartID] else { return [:] }
        let partDefinition = definition.parts.first(where: { $0.id == DragonWalkMeshCandidate.bodyPartID })
        let anchor = partDefinition.flatMap { part -> CGPoint? in
            guard part.pivotInPartPx.count == 2,
                  part.pivotInPartPx.allSatisfy({ $0.isFinite }) else { return nil }
            return CGPoint(x: part.pivotInPartPx[0], y: part.pivotInPartPx[1])
        }
        var toeTrace = walkFourLegR064Mount?.entryToeSnapshot(in: scene) ??
            anchor.map { DragonFourLegStanceMountR064.sourceToeSnapshot(bodyPart: body, anchorCanvas: $0, scene: scene) } ?? [:]
        if let entry = normalEntryFootpathR068R002Adapter?.lastSnapshot,
           let entryLegs = entry["legs"] as? [String: [String: Any]],
           let rows = toeTrace["legs"] as? [[String: Any]] {
            var trace = toeTrace
            trace["legs"] = rows.map { row in
                guard let id = row["legID"] as? String, let pose = entryLegs[id],
                      let stance = pose["stance"] as? Bool else { return row }
                var updated = row
                updated["stance"] = stance
                updated["stanceKnown"] = true
                updated["stanceSource"] = "r068_entry_footpath_ik_r002"
                return updated
            }
            trace["scheduleSource"] = "r068_entry_footpath_ik_r002"
            trace["elapsedSeconds"] = entry["elapsedSeconds"] ?? NSNull()
            toeTrace = trace
        }
        let observedGrid = body.warpGeometry as? SKWarpGeometryGrid
        let grid = observedGrid?.vertexCount == DragonWalkMeshCandidate.vertexCount ? observedGrid : nil
        let samples: [(String, Int, Double, Double)] = [
            ("fore_far", 34, 16, 140), ("fore_near", 43, 102, 140),
            ("hind_far", 85, 158, 128), ("hind_near", 61, 230, 140)]
        let points: [[String: Any]] = samples.map { name, index, x, y in
            let source = SIMD2<Float>(Float(x / 455), Float(1 - y / 157))
            let destination = grid.map { $0.destPosition(at: index) } ?? source
            let local = CGPoint(x: (CGFloat(destination.x) - body.anchorPoint.x) * body.size.width,
                                y: (CGFloat(destination.y) - body.anchorPoint.y) * body.size.height)
            let restLocal = CGPoint(x: (CGFloat(source.x) - body.anchorPoint.x) * body.size.width,
                                    y: (CGFloat(source.y) - body.anchorPoint.y) * body.size.height)
            let world = body.convert(local, to: scene)
            let restWorld = body.convert(restLocal, to: scene)
            let viewPoint = scene.convertPoint(toView: world)
            return ["sample": name, "index": index, "sourceArtworkPixels": [x, y],
                    "destinationNormalized": [Double(destination.x), Double(destination.y)],
                    "scenePoint": [Double(world.x), Double(world.y)],
                    "unwarpedScenePoint": [Double(restWorld.x), Double(restWorld.y)],
                    "viewPoint": [Double(viewPoint.x), Double(viewPoint.y)]]
        }
        return ["state": activeState ?? "none", "meshActive": walkMeshActive,
                "normalEntryFootpathR068R002Active": normalEntryFootpathR068R002Adapter != nil,
                "normalEntryFootpathR068R002Status": normalEntryFootpathR068R002Status,
                "normalEntryFootpathR068R002": normalEntryFootpathR068R002Adapter?.lastSnapshot ?? normalEntryFootpathR068R002LastSnapshot,
                "normalEntryWorldToeObserverR068": toeTrace,
                "normalEntrySelectedBackendR068": walkFourLegR064Requested && walkFourLegR064Mount == nil
                    ? "legacy_fallback_after_candidate_rejection" : normalEntryBackendR068,
                "walkFourLegR064Selected": walkFourLegR064Mount != nil,
                "walkFourLegR064Active": walkFourLegR064Active,
                "meshPresent": grid != nil, "meshVertexCount": grid?.vertexCount ?? 0,
                "groundedEntryActive": groundedEntryActive,
                "meshActionRunning": body.action(forKey: walkMeshActionKey) != nil,
                "overlayActive": walkCandidateCrop?.isHidden == false,
                "subdivisionLevels": body.subdivisionLevels,
                "bodyHidden": body.isHidden, "rigHidden": node.isHidden,
                "bodySize": [body.size.width, body.size.height], "points": points]
    }

    private func apply(_ keyframes: [EnemyRigKeyframe], atFrame frame: Double) {
        guard !keyframes.isEmpty else { return }
        presentationElapsed = presentationFPS > 0 ? min(presentationDuration, max(0, frame / presentationFPS)) : 0
        presentationFramePosition = frame
        presentationKeyframeIndex = keyframes.lastIndex(where: { $0.frame <= frame }) ?? 0
        presentationNextKeyframeIndex = min(presentationKeyframeIndex + 1, keyframes.count - 1)
        let leftFrame = keyframes[presentationKeyframeIndex].frame
        let rightFrame = keyframes[presentationNextKeyframeIndex].frame
        presentationKeyframeBlend = rightFrame > leftFrame
            ? min(1, max(0, (frame - leftFrame) / (rightFrame - leftFrame))) : 0
        for part in definition.parts {
            guard let sprite = partNodes[part.id],
                  let baseScale = baseScaleByPart[part.id] else { continue }
            // The gait mesh owns the lower-body motion. Holding this body's
            // authored rest transform avoids adding the idle clip's vertical
            // bob to every paw. Head and wing parts keep their authored poses.
            if walkMeshActive && part.id == DragonWalkMeshCandidate.bodyPartID { continue }
            let pose = Self.interpolatePose(partID: part.id, frame: frame,
                                            keyframes: keyframes)
            let translation = pose.translationPx ?? [0, 0]
            let translatedPosition = [
                part.restPositionPx[0] + (translation.count > 0 ? translation[0] : 0),
                part.restPositionPx[1] + (translation.count > 1 ? translation[1] : 0)
            ]
            sprite.position = Self.scenePoint(
                sourcePx: translatedPosition,
                rootAnchorPx: definition.anchorPx,
                scaleX: Double(canvasScaleX),
                scaleY: Double(canvasScaleY)
            )
            sprite.zRotation = -CGFloat((pose.rotationDeg ?? 0) * .pi / 180.0)
            let scale = pose.scaleXy ?? [1, 1]
            sprite.xScale = baseScale.x * CGFloat(scale.count > 0 ? scale[0] : 1)
            sprite.yScale = baseScale.y * CGFloat(scale.count > 1 ? scale[1] : 1)
            if part.id == walkLegOverlay?.bodyPartID { syncWalkLegOverlayTransform(from: sprite) }
        }
    }

    private func installWalkLegOverlay(_ spec: EnemyRigWalkLegOverlay, artRoot: URL) -> Bool {
        guard definition.parts.contains(where: { $0.id == spec.bodyPartID }),
              let body = partNodes[spec.bodyPartID],
              abs(Double(body.size.width) / Double(canvasScaleX) - 455) < 0.5,
              abs(Double(body.size.height) / Double(canvasScaleY) - 157) < 0.5 else { return false }

        let frames: [SKTexture] = spec.framePaths.compactMap { path in
            guard let image = UIImage(contentsOfFile: artRoot.appendingPathComponent(path).path),
                  let cgImage = image.cgImage, cgImage.width == 455, cgImage.height == 157 else { return nil }
            let texture = SKTexture(cgImage: cgImage)
            texture.filteringMode = .linear
            return texture
        }
        guard frames.count == spec.framePaths.count,
              let coreMaskCG = makeWalkMask(polygons: spec.polygons, keepInside: false),
              let candidateMaskCG = makeWalkMask(polygons: spec.polygons, keepInside: true) else { return false }

        let core = SKCropNode()
        core.name = "\(actorID).walkLegCore"
        core.position = body.position
        core.zPosition = body.zPosition
        core.zRotation = body.zRotation
        core.xScale = body.xScale
        core.yScale = body.yScale
        core.isHidden = true
        let originalTexture = body.texture
        let original = SKSpriteNode(texture: originalTexture, color: .clear, size: body.size)
        original.anchorPoint = body.anchorPoint
        original.position = .zero
        core.addChild(original)
        let coreMask = SKSpriteNode(texture: SKTexture(cgImage: coreMaskCG), size: body.size)
        coreMask.anchorPoint = body.anchorPoint
        coreMask.position = .zero
        core.maskNode = coreMask

        let candidateCrop = SKCropNode()
        candidateCrop.name = "\(actorID).walkLegCandidate"
        candidateCrop.position = body.position
        candidateCrop.zPosition = body.zPosition + 0.05
        candidateCrop.zRotation = body.zRotation
        candidateCrop.xScale = body.xScale
        candidateCrop.yScale = body.yScale
        candidateCrop.isHidden = true
        let candidate = SKSpriteNode(texture: frames[0], color: .clear, size: body.size)
        candidate.name = "\(actorID).walkLegCandidateFrames"
        candidate.anchorPoint = body.anchorPoint
        candidate.position = .zero
        candidateCrop.addChild(candidate)
        let candidateMask = SKSpriteNode(texture: SKTexture(cgImage: candidateMaskCG), size: body.size)
        candidateMask.anchorPoint = body.anchorPoint
        candidateMask.position = .zero
        candidateCrop.maskNode = candidateMask

        node.addChild(core)
        node.addChild(candidateCrop)
        walkCoreCrop = core
        walkCandidateCrop = candidateCrop
        walkCandidateSprite = candidate
        walkCandidateTextures = frames
        walkLegOverlay = spec
        return true
    }

    private func playWalkLegOverlay(restart: Bool) -> Bool {
        guard let spec = walkLegOverlay,
              let idleClip = definition.clips["idle"], idleClip.loop,
              idleClip.frameCount > 0, !idleClip.keyframes.isEmpty,
              let candidate = walkCandidateSprite, walkCandidateCrop != nil,
              walkCoreCrop != nil, walkCandidateTextures.count == spec.framePaths.count else { return false }
        let skeletonFPS = idleClip.fps ?? definition.fps
        guard skeletonFPS.isFinite, skeletonFPS > 0 else { return false }
        if activeState == "walk" && !restart { return true }
        stopWalkMeshCandidate()
        node.removeAction(forKey: actionKey)
        walkCandidateSprite?.removeAction(forKey: walkOverlayActionKey)
        activeState = "walk"
        setWalkLegOverlayActive(true)

        presentationStatus = "playing"
        presentationDuration = Double(idleClip.frameCount) / skeletonFPS
        presentationElapsed = 0
        presentationFPS = skeletonFPS
        presentationFramePosition = 0
        presentationFrameCount = idleClip.frameCount
        presentationKeyframeIndex = -1
        presentationNextKeyframeIndex = -1
        presentationKeyframeBlend = 0
        let ordered = idleClip.keyframes.sorted { $0.frame < $1.frame }
        apply(ordered, atFrame: 0)
        let update = SKAction.customAction(withDuration: presentationDuration) { [weak self] _, elapsed in
            guard let self else { return }
            let position = min(Double(idleClip.frameCount - 1), max(0, Double(elapsed) * skeletonFPS))
            self.apply(ordered, atFrame: position)
        }
        node.run(.repeatForever(.sequence([update])), withKey: actionKey)
        let frameDuration = 1 / spec.fps
        let frameSteps = walkCandidateTextures.enumerated().map { index, texture in
            SKAction.customAction(withDuration: frameDuration) { [weak self] node, _ in
                guard let sprite = node as? SKSpriteNode else { return }
                sprite.texture = texture
                self?.walkCandidateFrameIndex = index
            }
        }
        candidate.run(.repeatForever(.sequence(frameSteps)), withKey: walkOverlayActionKey)
        return true
    }

    private func playWalkFourLegR064(restart: Bool) -> Bool {
        guard let mount = walkFourLegR064Mount,
              let body = partNodes["body4legs_tail"],
              let idle = definition.clips["idle"], idle.loop,
              idle.frameCount > 0, !idle.keyframes.isEmpty else { return false }
        if activeState == "walk" && walkFourLegR064Active && !restart { return true }
        stop()
        guard mount.mount(), mount.startLoop() else { mount.unmount(); return false }
        activeState = "walk"
        walkFourLegR064Active = true
        presentationStatus = "playing"
        presentationDuration = GaitContactScheduleR064.periodSeconds
        presentationElapsed = 0
        presentationFPS = 10
        presentationFramePosition = 0
        presentationFrameCount = 12
        presentationKeyframeIndex = -1
        presentationNextKeyframeIndex = -1
        presentationKeyframeBlend = 0
        let ordered = idle.keyframes.sorted { $0.frame < $1.frame }
        let closedLoop = ordered + [EnemyRigKeyframe(frame: Double(idle.frameCount), poseByPart: ordered[0].poseByPart)]
        let skeleton = SKAction.customAction(withDuration: GaitContactScheduleR064.periodSeconds) { [weak self] _, elapsed in
            guard let self, self.walkFourLegR064Active else { return }
            let progress = min(1, max(0, Double(elapsed) / GaitContactScheduleR064.periodSeconds))
            self.apply(closedLoop, atFrame: progress * Double(idle.frameCount))
            self.presentationElapsed = Double(elapsed)
            self.presentationFramePosition = progress * 12
        }
        node.run(.repeatForever(skeleton), withKey: actionKey)
        return body.action(forKey: DragonFourLegStanceMountR064.actionKey) != nil
    }

    private func stopWalkFourLegR064() {
        restoreNormalEntryFootpathR068R002()
        guard let mount = walkFourLegR064Mount else { walkFourLegR064Active = false; return }
        partNodes["body4legs_tail"]?.removeAction(forKey: DragonFourLegStanceMountR064.actionKey)
        mount.unmount()
        walkFourLegR064Active = false
    }

    private func playWalkDistalR007(restart: Bool) -> Bool {
        guard walkDistalR007Mount != nil,
              let body = partNodes["body4legs_tail"],
              let idle = definition.clips["idle"], idle.loop,
              idle.frameCount > 0, !idle.keyframes.isEmpty else { return false }
        let fps = idle.fps ?? definition.fps
        let ordered = idle.keyframes.sorted { $0.frame < $1.frame }
        guard fps.isFinite, fps > 0,
              ordered.first?.frame ?? -1 >= 0,
              ordered.last?.frame ?? Double(idle.frameCount) < Double(idle.frameCount) else { return false }
        if activeState == "walk" && walkDistalR007Active && !restart { return true }
        stop()
        guard let refreshed = walkDistalR007Mount else { return false }
        refreshed.mount()
        guard refreshed.isMounted else { return false }
        activeState = "walk"
        walkDistalR007Active = true
        presentationStatus = "playing"
        presentationDuration = Double(DragonDistalLegRigCandidateR007.duration)
        presentationElapsed = 0
        presentationFPS = 10
        presentationFramePosition = 0
        presentationFrameCount = 13
        presentationKeyframeIndex = -1
        presentationNextKeyframeIndex = -1
        presentationKeyframeBlend = 0
        let closedLoop = ordered + [EnemyRigKeyframe(frame: Double(idle.frameCount), poseByPart: ordered[0].poseByPart)]
        let skeletonUpdate = SKAction.customAction(withDuration: presentationDuration) { [weak self] _, elapsed in
            guard let self, self.walkDistalR007Active else { return }
            let progress = min(1, max(0, Double(elapsed) / self.presentationDuration))
            self.apply(closedLoop, atFrame: progress * Double(idle.frameCount))
            self.presentationElapsed = Double(elapsed)
            self.presentationFramePosition = progress * 12
        }
        let distalUpdate = SKAction.customAction(withDuration: presentationDuration) { [weak refreshed] _, elapsed in
            refreshed?.applyPose(elapsed: Double(elapsed))
        }
        node.run(.repeatForever(skeletonUpdate), withKey: actionKey)
        body.run(.repeatForever(distalUpdate), withKey: walkDistalR007ActionKey)
        return true
    }

    private func stopWalkDistalR007() {
        guard let mount = walkDistalR007Mount else { walkDistalR007Active = false; return }
        partNodes["body4legs_tail"]?.removeAction(forKey: walkDistalR007ActionKey)
        mount.unmount()
        walkDistalR007Active = false
    }

    private func playWalkGaitR038(restart: Bool) -> Bool {
        guard let frames = walkGaitR038Frames, frames.count >= 2,
              let body = partNodes[DragonLocalizedLegWarpCandidateR003.bodyPartID],
              let idle = definition.clips["idle"], idle.loop,
              idle.frameCount > 0, !idle.keyframes.isEmpty else { return false }
        let grids = frames.map(\.geometry)
        let times = frames.map { NSNumber(value: Double($0.time)) }
        guard grids.count == times.count,
              times.first?.doubleValue == 0,
              times.last?.doubleValue == Double(DragonLocalizedLegWarpCandidateR003.duration),
              let animation = SKAction.animate(withWarps: grids, times: times) else { return false }
        let fps = idle.fps ?? definition.fps
        let ordered = idle.keyframes.sorted { $0.frame < $1.frame }
        guard fps.isFinite, fps > 0,
              ordered.first?.frame ?? -1 >= 0,
              ordered.last?.frame ?? Double(idle.frameCount) < Double(idle.frameCount) else { return false }
        // Close the entire authored idle cycle at frameCount so the final
        // interpolation returns exactly to frame zero instead of holding frame
        // frameCount-1 and popping when the 1.2 s warp cycle wraps.
        let closedLoopKeyframes = ordered + [EnemyRigKeyframe(
            frame: Double(idle.frameCount), poseByPart: ordered[0].poseByPart)]
        if activeState == "walk" && walkGaitR038Active && !restart { return true }

        stop()
        // The loaded body texture contains all four fused legs; this candidate
        // must not show the A/B crop compositor over the warped sprite.
        setWalkLegOverlayActive(false)
        body.isHidden = false
        activeState = "walk"
        walkGaitR038Active = true
        presentationStatus = "playing"
        presentationDuration = Double(DragonLocalizedLegWarpCandidateR003.duration)
        presentationElapsed = 0
        presentationFPS = Double(frames.count - 1) / presentationDuration
        presentationFramePosition = 0
        presentationFrameCount = frames.count
        presentationKeyframeIndex = -1
        presentationNextKeyframeIndex = -1
        presentationKeyframeBlend = 0
        body.subdivisionLevels = 0
        body.warpGeometry = grids[0]
        apply(ordered, atFrame: 0)
        let update = SKAction.customAction(withDuration: presentationDuration) { [weak self] _, elapsed in
            guard let self, self.walkGaitR038Active else { return }
            let cycleProgress = min(1, max(0, Double(elapsed) / presentationDuration))
            // Retain the full idle transform loop (body, wings, head) but map it
            // onto the 1.2 s gait period and interpolate frame 23 -> repeated
            // frame 24 (= frame 0). This prevents a clamped tail hold/pop.
            let idlePoseFrame = cycleProgress * Double(idle.frameCount)
            self.apply(closedLoopKeyframes, atFrame: idlePoseFrame)
            // apply(_:atFrame:) owns pose/keyframe bookkeeping. Restore phase
            // telemetry afterwards so it describes the warp action rather than
            // the differently-clocked idle skeleton pose.
            self.presentationElapsed = Double(elapsed)
            self.presentationFramePosition = cycleProgress * Double(frames.count - 1)
        }
        node.run(.repeatForever(update), withKey: actionKey)
        body.run(.repeatForever(animation), withKey: walkGaitR038ActionKey)
        return true
    }

    private func stopWalkGaitR038() {
        guard walkGaitR038Active,
              let body = partNodes[DragonLocalizedLegWarpCandidateR003.bodyPartID] else { return }
        node.removeAction(forKey: actionKey)
        body.removeAction(forKey: walkGaitR038ActionKey)
        body.warpGeometry = nil
        body.subdivisionLevels = walkGaitR038OriginalSubdivision
        body.isHidden = false
        walkGaitR038Active = false
    }

    private func playWalkMeshCandidate(restart: Bool) -> Bool {
        guard let candidate = walkMeshCandidate,
              let body = partNodes[DragonWalkMeshCandidate.bodyPartID],
              let idle = definition.clips["idle"], idle.loop,
              idle.frameCount > 0, !idle.keyframes.isEmpty,
              let animation = SKAction.animate(withWarps: candidate.grids, times: candidate.times) else { return false }
        let fps = idle.fps ?? definition.fps
        let ordered = idle.keyframes.sorted { $0.frame < $1.frame }
        guard fps.isFinite, fps > 0,
              ordered.first?.frame ?? -1 >= 0,
              ordered.last?.frame ?? Double(idle.frameCount) < Double(idle.frameCount) else { return false }
        if activeState == "walk" && walkMeshActive && !restart { return true }
        stop()
        activeState = "walk"
        walkMeshActive = true
        presentationStatus = "playing"
        presentationDuration = Double(idle.frameCount) / fps
        presentationFPS = fps
        presentationFrameCount = idle.frameCount
        body.isHidden = false
        body.subdivisionLevels = 0
        body.warpGeometry = candidate.grids[0]
        apply(ordered, atFrame: 0)
        let update = SKAction.customAction(withDuration: presentationDuration) { [weak self] _, elapsed in
            guard let self, self.walkMeshActive else { return }
            self.apply(ordered, atFrame: min(Double(idle.frameCount - 1), max(0, Double(elapsed) * fps)))
        }
        node.run(.repeatForever(update), withKey: actionKey)
        body.run(.repeatForever(animation), withKey: walkMeshActionKey)
        return true
    }

    func playGroundedEntryCandidate() -> Bool {
        guard let body = partNodes[DragonWalkMeshCandidate.bodyPartID],
              let candidate = try? DragonGroundedEntryCandidate(),
              let animation = SKAction.animate(withWarps: candidate.grids, times: candidate.times),
              playWalkMeshCandidate(restart: true) else { return false }
        groundedEntryActive = true
        body.removeAction(forKey: walkMeshActionKey)
        body.warpGeometry = candidate.grids[0]
        body.run(animation, withKey: walkMeshActionKey)
        return true
    }

    func groundedEntryOffset(in scene: SKScene) -> CGPoint? {
        guard groundedEntryActive, walkMeshActive,
              let body = partNodes[DragonWalkMeshCandidate.bodyPartID],
              let grid = body.warpGeometry as? SKWarpGeometryGrid,
              grid.vertexCount == DragonWalkMeshCandidate.vertexCount else { return nil }
        let index = DragonGroundedEntryCandidate.referenceVertexIndex
        let source = grid.sourcePosition(at: index), destination = grid.destPosition(at: index)
        func point(_ value: SIMD2<Float>) -> CGPoint {
            body.convert(CGPoint(x: (CGFloat(value.x) - body.anchorPoint.x) * body.size.width,
                                 y: (CGFloat(value.y) - body.anchorPoint.y) * body.size.height), to: scene)
        }
        let a = point(source), b = point(destination)
        return CGPoint(x: b.x - a.x, y: b.y - a.y)
    }

    private func stopWalkMeshCandidate() {
        groundedEntryActive = false
        guard walkMeshCandidate != nil,
              let body = partNodes[DragonWalkMeshCandidate.bodyPartID] else { return }
        body.removeAction(forKey: walkMeshActionKey)
        body.warpGeometry = nil
        body.subdivisionLevels = walkMeshOriginalSubdivision
        walkMeshActive = false
    }

    private func setWalkLegOverlayActive(_ active: Bool) {
        guard let spec = walkLegOverlay,
              let body = partNodes[spec.bodyPartID] else { return }
        body.isHidden = active
        walkCoreCrop?.isHidden = !active
        walkCandidateCrop?.isHidden = !active
        syncWalkLegOverlayTransform(from: body)
    }

    private func syncWalkLegOverlayTransform(from body: SKSpriteNode) {
        for crop in [walkCoreCrop, walkCandidateCrop].compactMap({ $0 }) {
            crop.position = body.position
            crop.zRotation = body.zRotation
            crop.xScale = body.xScale
            crop.yScale = body.yScale
        }
    }

    private func makeWalkMask(polygons: [[[Double]]], keepInside: Bool) -> CGImage? {
        let width = 455, height = 157
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(UIColor.white.cgColor)
        if !keepInside {
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setBlendMode(.clear)
        }
        let path = CGMutablePath()
        for polygon in polygons where polygon.count >= 3 {
            for (index, point) in polygon.enumerated() {
                let p = CGPoint(x: point[0], y: point[1])
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
        context.addPath(path)
        context.drawPath(using: .fill)
        return context.makeImage()
    }

    private static func interpolatePose(partID: String, frame: Double,
                                         keyframes: [EnemyRigKeyframe]) -> EnemyRigPartPose {
        let left = keyframes.last(where: { $0.frame <= frame }) ?? keyframes[0]
        let right = keyframes.first(where: { $0.frame >= frame }) ?? keyframes[keyframes.count - 1]
        if left.frame == right.frame {
            return left.poseByPart[partID] ?? EnemyRigPartPose(translationPx: nil,
                                                              rotationDeg: nil,
                                                              scaleXy: nil)
        }
        let t = (frame - left.frame) / (right.frame - left.frame)
        let a = left.poseByPart[partID]
        let b = right.poseByPart[partID]
        return EnemyRigPartPose(
            translationPx: Self.mixPair(a?.translationPx, b?.translationPx, t: t),
            rotationDeg: Self.mix(a?.rotationDeg, b?.rotationDeg, t: t),
            scaleXy: Self.mixPair(a?.scaleXy, b?.scaleXy, t: t)
        )
    }

    private static func mix(_ a: Double?, _ b: Double?, t: Double) -> Double? {
        guard let a, let b else { return a ?? b }
        return a + (b - a) * t
    }

    private static func mixPair(_ a: [Double]?, _ b: [Double]?, t: Double) -> [Double]? {
        guard let a, let b else { return a ?? b }
        guard a.count >= 2, b.count >= 2 else { return a }
        return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
    }

    private static func scenePoint(sourcePx: [Double], rootAnchorPx: [Double],
                                   scaleX: Double, scaleY: Double) -> CGPoint {
        let x = sourcePx[0] - rootAnchorPx[0]
        let y = rootAnchorPx[1] - sourcePx[1]
        return CGPoint(x: CGFloat(x * scaleX), y: CGFloat(y * scaleY))
    }
}
