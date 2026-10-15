import Foundation
import CryptoKit
import SpriteKit
import simd
import ImageIO

/// Off-live renderer candidate for ACT_E_R02_03. It uses the existing
/// alpha-matted source texture and authored per-vertex weight channels. It
/// changes mesh coordinates only; it never edits or rasterizes the source.
///
/// `walk` is a separate, unapproved sinusoidal profile over the existing idle
/// clip. The current catalog has five full-body walk PNGs but no editable walk
/// transform clip, so this candidate is explicitly an experiment rather than a
/// source-derived reproduction of those five images.
@MainActor
final class JellyfishMeshRigR254QA {
    static let actorID = "ACT_E_R02_03"
    static let candidateID = "jellyfish_weighted_mesh_r254_phase_lag_bell_response_candidate"
    static let status = "UNAPPROVED_OFFLIVE_RENDERER_CANDIDATE"
    static let candidateMatteSHA256 = "32e1118976c177fdb54a48204ae4643f112414588e4d70bbcc9dd651328de2c3"
    static let silhouetteMaskSHA256 = "4fb98e44f65d25b10df906c9654ef6a10955a484ae47b229b693f76ae5071117"
    static let meshSHA256 = "d7b0b96c1077711e8160966d8c8fb8cbbd726f7c6f2ed2800cc356c3e5dab2dd"
    static let clipsSHA256 = "fd1ea3234046bb1cf4234f33e18ff4292441180d65092295a5de5fa311d622b3"
    static let walkDuration: Float = 0.5
    static let walkFrameCount = 13
    static let maxWalkTentacleAmplitudeDegrees: Float = 10.0
    static let walkActionKey = "qa.jellyfish.mesh.walk.r254.candidate"

    /// Two deliberate timing profiles for a later frozen native comparison.
    /// Both preserve the same source, maximum tentacle rotation, duration and
    /// idle endpoints; only left/right phase lag and bell response differ.
    enum WalkProfile: String, CaseIterable {
        case quadrature = "quadrature"
        case travelingWave = "traveling_wave"

        var rightPhaseLag: Float {
            switch self {
            case .quadrature: return .pi / 2
            case .travelingWave: return 2 * .pi / 3
            }
        }

        var bellResponseDegrees: Float {
            switch self {
            case .quadrature: return 1.0
            case .travelingWave: return 1.5
            }
        }
    }

    struct Frame {
        let phase: Float
        let time: Float
        let geometry: SKWarpGeometryGrid
        let maxDisplacementSourcePixels: Float
        let destinationPoints: [SIMD2<Float>]
    }

    enum CandidateError: Error {
        case malformedMesh
        case malformedClip(String)
        case unavailableWalkInput
        case nonFinitePoint(Int)
        case pointOutOfBounds(Int)
        case inconsistentMeshOrder
    }

    private struct Mesh: Decodable {
        let source_canvas_px: [Double]
        let vertex_count: Int
        let triangle_count: Int
        let vertices_source_px: [[Double]]
        let triangles: [[Int]]
        let bones: [String: Bone]
        let weight_order: [String]
        let weights_by_bone: [String: [Double]]

        struct Bone: Decodable {
            let pivot_source_px: [Double]?
        }
    }

    private struct ClipFile: Decodable {
        let clips: [Clip]
    }

    private struct Clip: Decodable {
        let clip_id: String
        let duration_seconds: Double
        let loop: Bool
        let normalized_phase_keys: [PoseKey]
    }

    private struct PoseKey: Decodable {
        let phase: Double
        let pose_by_bone: [String: BoneTransform]
    }

    private struct BoneTransform: Decodable {
        var rotation_deg: Double
        var scale_xy: [Double]
        var translation_source_px: [Double]
    }

    private let mesh: Mesh
    private let clips: [String: Clip]
    private let columns: Int
    private let rows: Int
    private let width: Double
    private let height: Double
    private let sourceGrid: [SIMD2<Float>]
    private let sourceIndexOrder: [Int]
    private(set) var currentFrameIndex = -1
    private(set) var currentPhase: Float = .nan
    private(set) var currentGeometryFingerprint = ""
    private(set) var sourceTexture: SKTexture?
    private(set) var seamEndpointEqualsStart = false
    private(set) var observedWrapCount = 0
    private(set) var activeWalkProfile: WalkProfile?
    private var originalSubdivisionLevels: Int?
    private var originalTexture: SKTexture?
    private var originalSize: CGSize?
    private var originalAnchor: CGPoint?
    private var originalWarpGeometry: SKWarpGeometry?

    init(sourceTextureData: Data, meshData: Data, clipsData: Data) throws {
        guard Self.sha256(sourceTextureData) == Self.candidateMatteSHA256,
              Self.sha256(meshData) == Self.meshSHA256,
              Self.sha256(clipsData) == Self.clipsSHA256 else {
            throw CandidateError.malformedMesh
        }
        guard let imageSource = CGImageSourceCreateWithData(sourceTextureData as CFData, nil),
              CGImageSourceGetCount(imageSource) == 1,
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              image.width == 1536, image.height == 1024 else {
            throw CandidateError.unavailableWalkInput
        }
        let decodedTexture = SKTexture(cgImage: image)
        let mesh = try JSONDecoder().decode(Mesh.self, from: meshData)
        let clipFile = try JSONDecoder().decode(ClipFile.self, from: clipsData)
        guard mesh.source_canvas_px.count == 2,
              mesh.source_canvas_px.allSatisfy({ $0.isFinite && $0 > 0 }),
              mesh.vertex_count == 875,
              mesh.vertices_source_px.count == mesh.vertex_count,
              mesh.triangles.count == 1_632,
              mesh.weight_order == ["bell", "tentacle_left", "tentacle_right"],
              mesh.weight_order.allSatisfy({ mesh.weights_by_bone[$0]?.count == mesh.vertex_count }),
              mesh.bones["bell"]?.pivot_source_px?.count == 2,
              mesh.bones["tentacle_left"]?.pivot_source_px?.count == 2,
              mesh.bones["tentacle_right"]?.pivot_source_px?.count == 2 else {
            throw CandidateError.malformedMesh
        }

        let width = mesh.source_canvas_px[0]
        let height = mesh.source_canvas_px[1]
        let xValues = Array(Set(mesh.vertices_source_px.map { $0[0] })).sorted()
        let yValues = Array(Set(mesh.vertices_source_px.map { $0[1] })).sorted()
        guard xValues.count == 35, yValues.count == 25,
              mesh.vertices_source_px.count == xValues.count * yValues.count,
              mesh.triangles.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0 >= 0 && $0 < mesh.vertex_count } }) else {
            throw CandidateError.inconsistentMeshOrder
        }

        // SpriteKit's host renderer returned fully transparent snapshots for
        // the 34x24 grid (R135 resolution probe). Keep all 25 source rows and
        // select 25 monotonic original columns from the 35-column authored
        // mesh. This is mesh resampling only: source pixels, weights and clip
        // transforms remain untouched. The resulting 24x24 warp grid is a
        // bounded compatibility experiment, not an art-approval claim.
        let sampledColumns = (0...24).map { i in
            Int((Double(i) * Double(xValues.count - 1) / 24.0).rounded())
        }
        guard sampledColumns.count == 25,
              sampledColumns.first == 0,
              sampledColumns.last == 34,
              Set(sampledColumns).count == 25,
              zip(sampledColumns, sampledColumns.dropFirst()).allSatisfy({ pair in pair.0 < pair.1 }) else {
            throw CandidateError.inconsistentMeshOrder
        }

        // SpriteKit's warp grid is row-major from bottom to top. The authored
        // vertices are top-left-origin row-major, so reverse only row order.
        var order: [Int] = []
        var source: [SIMD2<Float>] = []
        order.reserveCapacity((sampledColumns.count) * yValues.count)
        source.reserveCapacity((sampledColumns.count) * yValues.count)
        for gridRow in 0..<yValues.count {
            let topRow = yValues.count - 1 - gridRow
            for column in sampledColumns {
                let sourceIndex = topRow * xValues.count + column
                let point = mesh.vertices_source_px[sourceIndex]
                guard point.count == 2,
                      abs(point[0] - xValues[column]) < 0.001,
                      abs(point[1] - yValues[topRow]) < 0.001 else {
                    throw CandidateError.inconsistentMeshOrder
                }
                order.append(sourceIndex)
                source.append(SIMD2(Float(point[0] / width), Float(1 - point[1] / height)))
            }
        }

        var clipMap: [String: Clip] = [:]
        for clip in clipFile.clips {
            guard !clip.normalized_phase_keys.isEmpty,
                  clip.normalized_phase_keys.first?.phase == 0,
                  clip.normalized_phase_keys.last?.phase == 1,
                  zip(clip.normalized_phase_keys, clip.normalized_phase_keys.dropFirst()).allSatisfy({ pair in pair.0.phase < pair.1.phase }) else {
                throw CandidateError.malformedClip(clip.clip_id)
            }
            clipMap[clip.clip_id] = clip
        }
        guard Set(clipMap.keys) == Set(["idle", "anticipate", "execute", "recover", "hit", "resolve"]) else {
            throw CandidateError.malformedClip("expected_existing_six_clips_only")
        }
        self.mesh = mesh
        self.clips = clipMap
        self.columns = sampledColumns.count - 1
        self.rows = yValues.count - 1
        self.width = width
        self.height = height
        self.sourceGrid = source
        self.sourceIndexOrder = order
        self.sourceTexture = decodedTexture
    }

    /// Renders one existing authored mesh clip at normalized phase 0...1.
    func grid(state: String, phase: Float) throws -> SKWarpGeometryGrid {
        guard let clip = clips[state] else { throw CandidateError.malformedClip(state) }
        return try makeGrid(pose: interpolatedPose(clip, phase: Double(min(1, max(0, phase)))))
    }

    /// Installs the unapproved walk experiment on one sprite. The caller must
    /// have already set the catalog walk size/anchor, and must clear on state exit.
    /// Playback samples are 0...11 (12 samples at 24Hz); sample 12 is the exact
    /// seam endpoint equal to sample 0 and is retained as a validation control.
    func installWalk(on node: SKSpriteNode, profile: WalkProfile) throws {
        let frames = try walkFrames(profile: profile)
        if currentToken != nil { clear(on: node) }
        guard frames.count == Self.walkFrameCount,
              frames.first?.time == 0,
              frames.last?.time == Self.walkDuration,
              let sourceTexture, let textureBefore = node.texture else {
            throw CandidateError.unavailableWalkInput
        }
        node.removeAction(forKey: Self.walkActionKey)
        originalTexture = textureBefore
        originalSize = node.size
        originalAnchor = node.anchorPoint
        originalWarpGeometry = node.warpGeometry
        originalSubdivisionLevels = node.subdivisionLevels
        node.texture = sourceTexture
        node.warpGeometry = frames[0].geometry
        currentFrameIndex = 0
        currentPhase = frames[0].phase
        currentGeometryFingerprint = Self.sha256(points: frames[0].destinationPoints)
        let token = UUID()
        seamEndpointEqualsStart = Self.sha256(points: frames.last!.destinationPoints) ==
            Self.sha256(points: frames.first!.destinationPoints)
        currentToken = token
        activeWalkProfile = profile
        observedWrapCount = 0
        let playable = Array(frames.dropLast())
        let steps = playable.enumerated().map { index, frame in
            SKAction.sequence([
                SKAction.run { [weak self, weak node] in
                    guard let self, let node, self.currentToken == token else { return }
                    if self.currentFrameIndex == Self.walkFrameCount - 2 && index == 0 {
                        self.observedWrapCount += 1
                    }
                    node.texture = sourceTexture
                    node.warpGeometry = frame.geometry
                    self.currentFrameIndex = index
                    self.currentPhase = frame.phase
                    self.currentGeometryFingerprint = Self.sha256(points: frame.destinationPoints)
                },
                SKAction.wait(forDuration: 1.0 / 24.0)
            ])
        }
        node.run(.repeatForever(.sequence(steps)), withKey: Self.walkActionKey)
    }

    private var currentToken: UUID?

    func clear(on node: SKSpriteNode) {
        guard currentToken != nil else { return }
        node.removeAction(forKey: Self.walkActionKey)
        node.texture = originalTexture
        if let originalSize { node.size = originalSize }
        if let originalAnchor { node.anchorPoint = originalAnchor }
        node.warpGeometry = originalWarpGeometry
        if let originalSubdivisionLevels {
            node.subdivisionLevels = originalSubdivisionLevels
        }
        currentToken = nil
        activeWalkProfile = nil
        currentFrameIndex = -1
        currentPhase = .nan
        currentGeometryFingerprint = ""
        seamEndpointEqualsStart = false
        observedWrapCount = 0
    }

    func snapshot(on node: SKSpriteNode) -> [String: Any] {
        let grid = node.warpGeometry as? SKWarpGeometryGrid
        let actualPoints: [SIMD2<Float>] = (0..<(grid?.vertexCount ?? 0)).map { index in
            guard let point = grid?.destPosition(at: index) else { return .zero }
            return SIMD2<Float>(point.x, point.y)
        }
        let actualFingerprint = actualPoints.isEmpty ? "" : Self.sha256(points: actualPoints)
        let originalWarpRestored: Bool
        if let originalWarpGeometry {
            originalWarpRestored = node.warpGeometry === originalWarpGeometry
        } else {
            originalWarpRestored = node.warpGeometry == nil
        }
        return [
            "candidateID": Self.candidateID,
            "walkProfile": activeWalkProfile?.rawValue ?? "none",
            "enabled": currentToken != nil,
            "frameIndex": currentFrameIndex,
            "phase": currentPhase.isFinite ? Double(currentPhase) : -1.0,
            "observedWrapCount": observedWrapCount,
            "expectedPeriodSeconds": Self.walkDuration,
            "playbackSampleCount": Self.walkFrameCount - 1,
            "sourceTextureSHA256": Self.candidateMatteSHA256,
            "sourceTextureIdentityMatches": node.texture === sourceTexture,
            "geometryPresent": grid != nil,
            "actualGridColumns": grid?.numberOfColumns ?? 0,
            "actualGridRows": grid?.numberOfRows ?? 0,
            "actualGridVertexCount": grid?.vertexCount ?? 0,
            "actualGridFingerprint": actualFingerprint,
            "actualGridMatchesExpectedFingerprint": !actualFingerprint.isEmpty && actualFingerprint == currentGeometryFingerprint,
            "actualSubdivisionLevels": node.subdivisionLevels,
            "originalSubdivisionLevels": originalSubdivisionLevels ?? node.subdivisionLevels,
            "subdivisionLevelsMatchesOriginal": originalSubdivisionLevels.map { node.subdivisionLevels == $0 } ?? true,
            "subdivisionLevelsRestored": currentToken == nil && (originalSubdivisionLevels.map { node.subdivisionLevels == $0 } ?? true),
            "originalTextureRestored": currentToken == nil && (originalTexture.map { node.texture === $0 } ?? false),
            "originalSizeRestored": currentToken == nil && (originalSize.map { node.size == $0 } ?? false),
            "originalAnchorRestored": currentToken == nil && (originalAnchor.map { node.anchorPoint == $0 } ?? false),
            "originalWarpRestored": currentToken == nil && originalWarpRestored,
            "geometryFingerprint": currentGeometryFingerprint,
            "seamEndpointIndex": Self.walkFrameCount - 1,
            "seamEndpointEqualsStart": seamEndpointEqualsStart
        ]
    }

    private static func sha256(points: [SIMD2<Float>]) -> String {
        var bytes = Data()
        for point in points {
            var x = point.x.bitPattern.littleEndian
            var y = point.y.bitPattern.littleEndian
            withUnsafeBytes(of: &x) { bytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { bytes.append(contentsOf: $0) }
        }
        return sha256(bytes)
    }

    /// Builds a 0.5-second walk loop at 24 Hz using the already-authored idle
    /// breathing clip plus opposite left/right tentacle rotation. Both ends
    /// exactly return to idle phase zero. This is new, unapproved motion data.
    func walkFrames(profile: WalkProfile) throws -> [Frame] {
        guard let idle = clips["idle"] else { throw CandidateError.unavailableWalkInput }
        return try (0..<Self.walkFrameCount).map { index in
            let phase = Float(index) / Float(Self.walkFrameCount - 1)
            var pose = (index == 0 || index == Self.walkFrameCount - 1)
                ? idle.normalized_phase_keys[0].pose_by_bone
                : interpolatedPose(idle, phase: Double(phase))
            let gaitPhase = 2 * Float.pi * phase
            // Gate the phase-lagged stroke to exact idle at both ends; without
            // this envelope a nonzero phase lag creates a visible loop pop.
            let strokeEnvelope = sin(Float.pi * phase)
            let amplitude = Double(Self.maxWalkTentacleAmplitudeDegrees)
            let leftGait = amplitude * Double(strokeEnvelope * sin(gaitPhase))
            let rightGait = amplitude * Double(strokeEnvelope * sin(gaitPhase + profile.rightPhaseLag))
            pose["tentacle_left"]?.rotation_deg += leftGait
            pose["tentacle_right"]?.rotation_deg += rightGait
            // A small counter-phase bell pitch makes the tentacle sweep read as
            // propulsion. Rotation is about the existing bell registration;
            // no root or registration translation is introduced. Endpoints are
            // explicitly restored to the exact idle mesh.
            if index != 0 && index != Self.walkFrameCount - 1 {
                pose["bell"]?.rotation_deg += Double(profile.bellResponseDegrees * strokeEnvelope * sin(gaitPhase - .pi / 2))
            }
            let result = try makeFrame(pose: pose, phase: phase, time: Self.walkDuration * phase,
                                       forceIdentity: index == 0 || index == Self.walkFrameCount - 1)
            return result
        }
    }

    private func interpolatedPose(_ clip: Clip, phase: Double) -> [String: BoneTransform] {
        let keys = clip.normalized_phase_keys
        guard let right = keys.firstIndex(where: { $0.phase >= phase }), right > 0 else {
            return keys.first?.pose_by_bone ?? [:]
        }
        let left = right - 1
        let a = keys[left]
        let b = keys[right]
        let t = (phase - a.phase) / (b.phase - a.phase)
        return Dictionary(uniqueKeysWithValues: mesh.weight_order.compactMap { bone in
            guard let start = a.pose_by_bone[bone], let end = b.pose_by_bone[bone] else { return nil }
            return (bone, BoneTransform(
                rotation_deg: start.rotation_deg + t * (end.rotation_deg - start.rotation_deg),
                scale_xy: zip(start.scale_xy, end.scale_xy).map { pair in pair.0 + t * (pair.1 - pair.0) },
                translation_source_px: zip(start.translation_source_px, end.translation_source_px).map { pair in pair.0 + t * (pair.1 - pair.0) }
            ))
        })
    }

    private func makeGrid(pose: [String: BoneTransform]) throws -> SKWarpGeometryGrid {
        let frame = try makeFrame(pose: pose, phase: 0, time: 0)
        return frame.geometry
    }

    private func makeFrame(pose: [String: BoneTransform], phase: Float, time: Float,
                           forceIdentity: Bool = false) throws -> Frame {
        var destination: [SIMD2<Float>] = forceIdentity ? sourceGrid : []
        destination.reserveCapacity(sourceIndexOrder.count)
        var maxDisplacement: Float = 0
        if !forceIdentity {
        for (gridIndex, sourceIndex) in sourceIndexOrder.enumerated() {
            let p = mesh.vertices_source_px[sourceIndex]
            var warpedX = 0.0
            var warpedY = 0.0
            for bone in mesh.weight_order {
                guard let transform = pose[bone],
                      let pivot = mesh.bones[bone]?.pivot_source_px,
                      transform.scale_xy.count == 2,
                      transform.translation_source_px.count == 2 else {
                    throw CandidateError.malformedClip("missing_transform_\(bone)")
                }
                let weight = mesh.weights_by_bone[bone]![sourceIndex]
                let transformed = Self.transform(
                    point: SIMD2<Double>(p[0], p[1]),
                    pivot: SIMD2<Double>(pivot[0], pivot[1]),
                    transform: transform
                )
                warpedX += weight * transformed.x
                warpedY += weight * transformed.y
            }
            guard warpedX.isFinite, warpedY.isFinite else {
                throw CandidateError.nonFinitePoint(gridIndex)
            }
            // Test SpriteKit's treatment of source-space mesh vertices that move
            // beyond the transparent source canvas. Visible-alpha safety is
            // checked from the rendered frames, not inferred from the mesh.
            let displacement = hypot(Float(warpedX - p[0]), Float(warpedY - p[1]))
            maxDisplacement = max(maxDisplacement, displacement)
            destination.append(SIMD2(Float(warpedX / width), Float(1 - warpedY / height)))
        }
        }
        return Frame(
            phase: phase,
            time: time,
            geometry: SKWarpGeometryGrid(__columns: columns, rows: rows,
                                         sourcePositions: sourceGrid, destPositions: destination),
            maxDisplacementSourcePixels: maxDisplacement,
            destinationPoints: destination
        )
    }

    private static func transform(point: SIMD2<Double>, pivot: SIMD2<Double>, transform: BoneTransform) -> SIMD2<Double> {
        let dx = (point.x - pivot.x) * transform.scale_xy[0]
        let dy = (point.y - pivot.y) * transform.scale_xy[1]
        let angle = transform.rotation_deg * .pi / 180
        return SIMD2(
            pivot.x + dx * cos(angle) - dy * sin(angle) + transform.translation_source_px[0],
            pivot.y + dx * sin(angle) + dy * cos(angle) + transform.translation_source_px[1]
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
