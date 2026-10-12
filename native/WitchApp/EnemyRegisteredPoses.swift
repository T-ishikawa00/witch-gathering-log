import SpriteKit
import ImageIO

struct RegisteredPosePreparationResult: Codable {
    let outcome: String
    let clipCount: Int
    let texturePaths: [String]
    let snapshotCount: Int
    let successfulSnapshotCount: Int
    let texturePreparationMilliseconds: Double
    let snapshotDurationMilliseconds: Double
    let snapshotCallMilliseconds: Double
    let durationMilliseconds: Double
    let failureReason: String?
}

/// Registered, authored full-body poses may override named rig states. This
/// interpolates only declared transforms and short dissolves, never anatomy.
/// Each image keeps its own ground anchor; gameplay owns the enclosing node.
@MainActor
final class EnemyRegisteredPoses {
    let node = SKNode()
    private let root: URL
    private let referenceCanvas: CGSize
    private let surface = SKSpriteNode()
    private let nextTexture = SKUniform(name: "u_next", texture: nil)
    private let progress = SKUniform(name: "u_progress", float: 0)
    private let renderSize = SKUniform(name: "u_render_size", vectorFloat2: SIMD2<Float>(1, 1))
    private let renderAnchor = SKUniform(name: "u_render_anchor", vectorFloat2: SIMD2<Float>(0, 0))
    private let leftSize = SKUniform(name: "u_left_size", vectorFloat2: SIMD2<Float>(1, 1))
    private let rightSize = SKUniform(name: "u_right_size", vectorFloat2: SIMD2<Float>(1, 1))
    private let leftAnchor = SKUniform(name: "u_left_anchor", vectorFloat2: SIMD2<Float>(0, 0))
    private let rightAnchor = SKUniform(name: "u_right_anchor", vectorFloat2: SIMD2<Float>(0, 0))
    private let key = "witch.enemy.registered-poses"
    private var generation = 0
    private var textures: [String: SKTexture] = [:]
    private var originalSizes: [String: CGSize] = [:]
    private var presentationStatus = "not_started"
    private var presentationDuration = 0.0
    private var presentationElapsed = 0.0
    private var presentationTimelineIndex = -1
    private var presentationPoseIndex = -1
    private var presentationNextPoseIndex = -1
    private var presentationBlend = 0.0
    private let frameStallTelemetry = FrameStallTelemetry.shared

    private struct Pose {
        let texture: SKTexture
        let size: CGSize
        let anchor: CGPoint
    }
    private struct Frame {
        let time: Double
        let pose: Int
        let position: CGPoint
        let rotation: CGFloat
    }
    private struct PreparedClip {
        let poses: [Pose]
        let frames: [Frame]
        let duration: Double
        let dissolve: Double
        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
    }

    init(root: URL, referenceCanvas: CGSize) {
        self.root = root
        self.referenceCanvas = referenceCanvas
        node.name = "authored-registered-poses"
        node.addChild(surface)
        // One premultiplied fragment mix avoids the 25% opaque-pixel alpha
        // loss of placing two complementary-alpha sprites over each other.
        // Apple: Creating a Custom Fragment Shader (SpriteKit), v_tex_coord
        // uses bottom-left UVs; output colors must remain premultiplied.
        surface.shader = SKShader(source: """
        void main() {
            vec2 p = (v_tex_coord - u_render_anchor) * u_render_size;
            vec2 aUV = p / u_left_size + u_left_anchor;
            vec2 bUV = p / u_right_size + u_right_anchor;
            float aMask = step(0.0,aUV.x)*step(aUV.x,1.0)*step(0.0,aUV.y)*step(aUV.y,1.0);
            float bMask = step(0.0,bUV.x)*step(bUV.x,1.0)*step(0.0,bUV.y)*step(bUV.y,1.0);
            vec4 a = texture2D(u_texture, clamp(aUV,0.0,1.0)) * aMask;
            vec4 b = texture2D(u_next, clamp(bUV,0.0,1.0)) * bMask;
            gl_FragColor = mix(a,b,u_progress) * v_color_mix;
        }
        """, uniforms: [nextTexture, progress, renderSize, renderAnchor,
                         leftSize, rightSize, leftAnchor, rightAnchor])
        node.isHidden = true
    }

    /// Validation and texture loading finish before the current visual changes.
    func play(_ clip: [String: Any], completion: @escaping () -> Void) -> Bool {
        guard let prepared = load(clip) else { return false }
        stop()
        configureCanvas(for: prepared)
        generation += 1
        let token = generation
        presentationStatus = "playing"
        presentationDuration = prepared.duration
        presentationElapsed = 0
        presentationTimelineIndex = -1
        presentationPoseIndex = -1
        presentationNextPoseIndex = -1
        presentationBlend = 0
        node.isHidden = false
        apply(poses: prepared.poses, frames: prepared.frames, time: 0, dissolve: prepared.dissolve)
        let animate = SKAction.customAction(withDuration: prepared.duration) { [weak self] _, time in
            self?.apply(poses: prepared.poses, frames: prepared.frames, time: Double(time), dissolve: prepared.dissolve)
        }
        node.run(.sequence([animate, .run { [weak self] in
            guard let self, self.generation == token else { return }
            self.apply(poses: prepared.poses, frames: prepared.frames, time: prepared.duration, dissolve: prepared.dissolve)
            self.presentationStatus = "completed"
            completion()
        }]), withKey: key)
        return true
    }

    /// Read-only playback evidence for QA. Values are updated from the same
    /// timeline sample that drives the rendered pose; this does not drive time.
    var presentationSnapshot: [String: Any] {
        ["status": presentationStatus,
         "durationSeconds": presentationDuration,
         "elapsedSeconds": presentationElapsed,
         "normalizedProgress": presentationDuration > 0 ? presentationElapsed / presentationDuration : 0,
         "timelineIndex": presentationTimelineIndex,
         "poseIndex": presentationPoseIndex,
         "nextPoseIndex": presentationNextPoseIndex,
         "poseBlend": presentationBlend,
         "completed": presentationStatus == "completed",
         "isHidden": node.isHidden,
         "actionRunning": node.action(forKey: key) != nil,
         "generation": generation]
    }

    /// Load through the same validation and cache path used by play, then render
    /// every unique registered texture through this renderer's existing shader
    /// on an off-scene snapshot node. The actor's visible rig is never animated.
    func prepareForFirstRender(clips: [[String: Any]], in view: SKView,
                               captureSnapshots: Bool = true,
                               shouldContinue: @escaping () -> Bool = { true }) async -> RegisteredPosePreparationResult {
        let started = FrameStallTelemetry.nowNanoseconds()
        let registered = clips.filter { $0["mode"] as? String == "registered_keyposes_v1" }
        guard !registered.isEmpty else {
            return result("not_applicable", clips: 0, paths: [], attempted: 0, succeeded: 0, textureMilliseconds: 0, snapshotMilliseconds: 0, snapshotCallMilliseconds: 0,
                          started: started, failure: nil)
        }
        guard node.action(forKey: key) == nil else {
            return result("failed", clips: registered.count, paths: [], attempted: 0, succeeded: 0, textureMilliseconds: 0, snapshotMilliseconds: 0, snapshotCallMilliseconds: 0,
                          started: started, failure: "registered_renderer_active")
        }
        guard !Task.isCancelled, shouldContinue() else {
            return result(Task.isCancelled ? "cancelled" : "stale_scene_discarded", clips: registered.count,
                          paths: [], attempted: 0, succeeded: 0, textureMilliseconds: 0, snapshotMilliseconds: 0,
                          snapshotCallMilliseconds: 0, started: started,
                          failure: Task.isCancelled ? "cancelled" : "scene_reconfigured")
        }
        let textureStarted = FrameStallTelemetry.nowNanoseconds()
        var parsed: [PreparedClip] = []
        var byPath: [String: Pose] = [:]
        var orderedPaths: [String] = []
        for clip in registered {
            guard let value = load(clip) else {
                return result("failed", clips: registered.count, paths: [], attempted: 0, succeeded: 0,
                              textureMilliseconds: elapsedMilliseconds(from: textureStarted), snapshotMilliseconds: 0, snapshotCallMilliseconds: 0,
                              started: started, failure: "clip_validation_or_texture_load")
            }
            parsed.append(value)
            let rawPoses = clip["registeredPoses"] as? [[String: Any]] ?? []
            for (poseIndex, raw) in rawPoses.enumerated() {
                guard let path = raw["path"] as? String, poseIndex < value.poses.count else { continue }
                if byPath[path] == nil {
                    byPath[path] = value.poses[poseIndex]
                    orderedPaths.append(path)
                }
            }
        }
        let textureMilliseconds = elapsedMilliseconds(from: textureStarted)
        guard !Task.isCancelled, shouldContinue() else {
            return result(Task.isCancelled ? "cancelled" : "stale_scene_discarded", clips: registered.count,
                          paths: orderedPaths, attempted: 0, succeeded: 0, textureMilliseconds: textureMilliseconds,
                          snapshotMilliseconds: 0, snapshotCallMilliseconds: 0, started: started,
                          failure: Task.isCancelled ? "cancelled" : "scene_reconfigured")
        }
        guard orderedPaths.count > 0, let parent = node.parent else {
            return result("failed", clips: registered.count, paths: orderedPaths, attempted: 0, succeeded: 0,
                          textureMilliseconds: textureMilliseconds, snapshotMilliseconds: 0, snapshotCallMilliseconds: 0,
                          started: started, failure: node.parent == nil ? "renderer_not_attached" : "no_registered_textures")
        }
        let poses = orderedPaths.compactMap { byPath[$0] }
        guard poses.count == orderedPaths.count else {
            return result("failed", clips: registered.count, paths: orderedPaths, attempted: 0, succeeded: 0,
                          textureMilliseconds: textureMilliseconds, snapshotMilliseconds: 0, snapshotCallMilliseconds: 0,
                          started: started, failure: "pose_path_resolution")
        }
        guard captureSnapshots else {
            return result("textures_prepared_snapshot_skipped", clips: registered.count, paths: orderedPaths,
                          attempted: 0, succeeded: 0, textureMilliseconds: textureMilliseconds,
                          snapshotMilliseconds: 0, snapshotCallMilliseconds: 0, started: started, failure: nil)
        }

        let minX = poses.map { -$0.anchor.x * $0.size.width }.min() ?? 0
        let maxX = poses.map { (1 - $0.anchor.x) * $0.size.width }.max() ?? 1
        let minY = poses.map { -$0.anchor.y * $0.size.height }.min() ?? 0
        let maxY = poses.map { (1 - $0.anchor.y) * $0.size.height }.max() ?? 1
        let oldHidden = node.isHidden
        let oldPosition = node.position
        let oldZ = node.zPosition
        let oldSize = surface.size
        let oldAnchor = surface.anchorPoint
        let oldSurfacePosition = surface.position
        let oldRotation = surface.zRotation
        let oldTexture = surface.texture
        let oldNextTexture = nextTexture.textureValue
        let oldProgress = progress.floatValue
        let oldRenderSize = renderSize.vectorFloat2Value
        let oldRenderAnchor = renderAnchor.vectorFloat2Value
        let oldLeftSize = leftSize.vectorFloat2Value
        let oldRightSize = rightSize.vectorFloat2Value
        let oldLeftAnchor = leftAnchor.vectorFloat2Value
        let oldRightAnchor = rightAnchor.vectorFloat2Value
        var attempted = 0
        var succeeded = 0
        var snapshotCallMilliseconds = 0.0
        var snapshots: [SKTexture] = []
        let snapshotStarted = FrameStallTelemetry.nowNanoseconds()

        // Detach before making the renderer visible. Even a delayed presentation
        // cannot expose a preparation pose in the live scene.
        node.removeFromParent()
        node.isHidden = false
        defer {
            node.removeFromParent()
            node.position = oldPosition
            node.zPosition = oldZ
            surface.size = oldSize
            surface.anchorPoint = oldAnchor
            surface.position = oldSurfacePosition
            surface.zRotation = oldRotation
            surface.texture = oldTexture
            nextTexture.textureValue = oldNextTexture
            progress.floatValue = oldProgress
            renderSize.vectorFloat2Value = oldRenderSize
            renderAnchor.vectorFloat2Value = oldRenderAnchor
            leftSize.vectorFloat2Value = oldLeftSize
            rightSize.vectorFloat2Value = oldRightSize
            leftAnchor.vectorFloat2Value = oldLeftAnchor
            rightAnchor.vectorFloat2Value = oldRightAnchor
            node.isHidden = oldHidden
            parent.addChild(node)
        }

        surface.size = CGSize(width: maxX - minX, height: maxY - minY)
        surface.anchorPoint = CGPoint(x: -minX / surface.size.width, y: -minY / surface.size.height)
        surface.position = .zero
        renderSize.vectorFloat2Value = vector(surface.size)
        renderAnchor.vectorFloat2Value = vector(surface.anchorPoint)
        let pairs: [(Pose, Pose)] = poses.count == 1
            ? [(poses[0], poses[0])]
            : (0..<(poses.count - 1)).map { (poses[$0], poses[$0 + 1]) }
        for (a, b) in pairs {
            if Task.isCancelled || !shouldContinue() { break }
            surface.texture = a.texture
            nextTexture.textureValue = b.texture
            leftSize.vectorFloat2Value = vector(a.size)
            rightSize.vectorFloat2Value = vector(b.size)
            leftAnchor.vectorFloat2Value = vector(a.anchor)
            rightAnchor.vectorFloat2Value = vector(b.anchor)
            progress.floatValue = a.texture === b.texture ? 0 : 0.5
            let crop = surface.frame.insetBy(dx: -1, dy: -1)
            attempted += 1
            let callStarted = FrameStallTelemetry.nowNanoseconds()
            if let snapshot = view.texture(from: node, crop: crop) {
                snapshots.append(snapshot)
                succeeded += 1
            }
            snapshotCallMilliseconds += elapsedMilliseconds(from: callStarted)
            await Task.yield()
        }
        let cancelled = Task.isCancelled
        let stale = !shouldContinue()
        let snapshotMilliseconds = elapsedMilliseconds(from: snapshotStarted)
        let outcome = cancelled ? "cancelled" : (stale ? "stale_scene_discarded" : (succeeded == attempted && attempted > 0 ? "prepared" : "failed"))
        return result(outcome, clips: registered.count, paths: orderedPaths, attempted: attempted, succeeded: succeeded,
                      textureMilliseconds: textureMilliseconds, snapshotMilliseconds: snapshotMilliseconds,
                      snapshotCallMilliseconds: snapshotCallMilliseconds,
                      started: started, failure: cancelled ? "cancelled" : (stale ? "scene_reconfigured" : (succeeded == attempted && attempted > 0 ? nil : "offscreen_snapshot_failed")))
    }

    private func result(_ outcome: String, clips: Int, paths: [String], attempted: Int, succeeded: Int,
                        textureMilliseconds: Double, snapshotMilliseconds: Double, snapshotCallMilliseconds: Double,
                        started: UInt64, failure: String?) -> RegisteredPosePreparationResult {
        let elapsed = Double(FrameStallTelemetry.nowNanoseconds() - started) / 1_000_000
        return RegisteredPosePreparationResult(outcome: outcome, clipCount: clips, texturePaths: paths,
                                               snapshotCount: attempted, successfulSnapshotCount: succeeded,
                                               texturePreparationMilliseconds: textureMilliseconds,
                                               snapshotDurationMilliseconds: snapshotMilliseconds,
                                               snapshotCallMilliseconds: snapshotCallMilliseconds,
                                               durationMilliseconds: elapsed, failureReason: failure)
    }

    private func elapsedMilliseconds(from started: UInt64) -> Double {
        Double(FrameStallTelemetry.nowNanoseconds() - started) / 1_000_000
    }

    private func load(_ clip: [String: Any]) -> PreparedClip? {
        guard let rawPoses = clip["registeredPoses"] as? [[String: Any]], !rawPoses.isEmpty,
              let rawFrames = clip["poseTimeline"] as? [[String: Any]], !rawFrames.isEmpty,
              let duration = finite(clip["duration"]), duration > 0,
              let dissolve = finite(clip["dissolveSeconds"]), dissolve >= 0, dissolve <= 0.12 else { return nil }
        var poses: [Pose] = []
        for raw in rawPoses {
            guard let path = raw["path"] as? String, !path.hasPrefix("/"),
                  !path.split(separator: "/").contains(".."),
                  let canvas = pair(raw["canvas_px"]), canvas.x > 0, canvas.y > 0,
                  let anchor = pair(raw["anchor_px"]),
                  anchor.x >= 0, anchor.x <= canvas.x, anchor.y >= 0, anchor.y <= canvas.y,
                  let scale = finite(raw["display_scale"]), (0.5...1.5).contains(scale),
                  let texture = texture(for: path, expectedCanvas: canvas) else { return nil }
            poses.append(Pose(texture: texture,
                              size: CGSize(width: referenceCanvas.height * canvas.x / canvas.y * scale,
                                           height: referenceCanvas.height * scale),
                              anchor: CGPoint(x: anchor.x / canvas.x, y: 1 - anchor.y / canvas.y)))
        }
        var frames: [Frame] = []
        for raw in rawFrames {
            guard let time = finite(raw["time"]), time >= 0, time <= duration,
                  let indexValue = finite(raw["pose"]), indexValue.rounded() == indexValue,
                  indexValue >= 0, indexValue < Double(poses.count),
                  let position = pair(raw["translation_reference_px"]),
                  let rotation = finite(raw["rotation_deg"]) else { return nil }
            if let last = frames.last, time <= last.time { return nil }
            frames.append(Frame(time: time, pose: Int(indexValue),
                                position: CGPoint(x: position.x, y: -position.y),
                                rotation: -rotation * .pi / 180))
        }
        guard frames.first?.time == 0, frames.last?.time == duration else { return nil }
        // Include every registered image canvas so a pose with a different
        // anchor/scale is not cropped at the original rig's rectangle.
        let minX = poses.map { -$0.anchor.x * $0.size.width }.min() ?? 0
        let maxX = poses.map { (1 - $0.anchor.x) * $0.size.width }.max() ?? 1
        let minY = poses.map { -$0.anchor.y * $0.size.height }.min() ?? 0
        let maxY = poses.map { (1 - $0.anchor.y) * $0.size.height }.max() ?? 1
        return PreparedClip(poses: poses, frames: frames, duration: duration, dissolve: dissolve,
                            minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private func configureCanvas(for clip: PreparedClip) {
        surface.size = CGSize(width: clip.maxX - clip.minX, height: clip.maxY - clip.minY)
        surface.anchorPoint = CGPoint(x: -clip.minX / surface.size.width, y: -clip.minY / surface.size.height)
        renderSize.vectorFloat2Value = vector(surface.size)
        renderAnchor.vectorFloat2Value = vector(surface.anchorPoint)
    }

    func stop() {
        generation += 1
        node.removeAction(forKey: key)
        node.isHidden = true
        presentationStatus = "stopped"
        presentationDuration = 0
        presentationElapsed = 0
        presentationTimelineIndex = -1
        presentationPoseIndex = -1
        presentationNextPoseIndex = -1
        presentationBlend = 0
    }

    private func apply(poses: [Pose], frames: [Frame], time: Double, dissolve: Double) {
        let leftIndex = frames.lastIndex(where: { $0.time <= time }) ?? 0
        let left = frames[leftIndex]
        let right = frames[min(leftIndex + 1, frames.count - 1)]
        let span = max(0.0001, right.time - left.time)
        let t = min(1, max(0, (time - left.time) / span))
        let eased = t * t * (3 - 2 * t)
        let position = CGPoint(x: left.position.x + (right.position.x - left.position.x) * eased,
                               y: left.position.y + (right.position.y - left.position.y) * eased)
        let rotation = left.rotation + (right.rotation - left.rotation) * eased
        let blend = left.pose != right.pose && dissolve > 0
            ? min(1, max(0, (time - (right.time - min(dissolve, span))) / min(dissolve, span))) : 0
        presentationElapsed = min(max(0, time), presentationDuration)
        presentationTimelineIndex = leftIndex
        presentationPoseIndex = left.pose
        presentationNextPoseIndex = right.pose
        presentationBlend = blend
        let a = poses[left.pose], b = poses[right.pose]
        surface.texture = a.texture
        nextTexture.textureValue = b.texture
        leftSize.vectorFloat2Value = vector(a.size)
        rightSize.vectorFloat2Value = vector(b.size)
        leftAnchor.vectorFloat2Value = vector(a.anchor)
        rightAnchor.vectorFloat2Value = vector(b.anchor)
        progress.floatValue = Float(blend)
        surface.position = position
        surface.zRotation = rotation
    }

    private func finite(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private func texture(for path: String, expectedCanvas: CGPoint) -> SKTexture? {
        let expected = CGSize(width: expectedCanvas.x, height: expectedCanvas.y)
        if let cached = textures[path] { return originalSizes[path] == expected ? cached : nil }
        let started = FrameStallTelemetry.nowNanoseconds()
        let sourceStarted = started
        guard let source = CGImageSourceCreateWithURL(root.appendingPathComponent(path) as CFURL, nil) else {
            recordTextureCreate(path: path, expected: expected, started: started,
                                sourceStarted: sourceStarted, sourceFinished: FrameStallTelemetry.nowNanoseconds(),
                                decodeStarted: nil, decodeFinished: nil, textureStarted: nil, textureFinished: nil,
                                sourceWidth: nil, sourceHeight: nil, succeeded: false, failureStage: "source_open")
            return nil
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = finite(properties[kCGImagePropertyPixelWidth]),
              let height = finite(properties[kCGImagePropertyPixelHeight]) else {
            recordTextureCreate(path: path, expected: expected, started: started,
                                sourceStarted: sourceStarted, sourceFinished: FrameStallTelemetry.nowNanoseconds(),
                                decodeStarted: nil, decodeFinished: nil, textureStarted: nil, textureFinished: nil,
                                sourceWidth: nil, sourceHeight: nil, succeeded: false, failureStage: "source_properties")
            return nil
        }
        let sourceFinished = FrameStallTelemetry.nowNanoseconds()
        guard CGSize(width: width, height: height) == expected else {
            recordTextureCreate(path: path, expected: expected, started: started,
                                sourceStarted: sourceStarted, sourceFinished: sourceFinished,
                                decodeStarted: nil, decodeFinished: nil, textureStarted: nil, textureFinished: nil,
                                sourceWidth: width, sourceHeight: height, succeeded: false, failureStage: "dimension_validation")
            return nil
        }
        let decodeStarted = FrameStallTelemetry.nowNanoseconds()
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
            recordTextureCreate(path: path, expected: expected, started: started,
                                sourceStarted: sourceStarted, sourceFinished: sourceFinished,
                                decodeStarted: decodeStarted, decodeFinished: FrameStallTelemetry.nowNanoseconds(),
                                textureStarted: nil, textureFinished: nil,
                                sourceWidth: width, sourceHeight: height, succeeded: false, failureStage: "thumbnail_decode")
            return nil
        }
        let decodeFinished = FrameStallTelemetry.nowNanoseconds()
        let textureStarted = decodeFinished
        let texture = SKTexture(cgImage: cg)
        texture.filteringMode = .linear
        textures[path] = texture
        originalSizes[path] = expected
        let textureFinished = FrameStallTelemetry.nowNanoseconds()
        recordTextureCreate(path: path, expected: expected, started: started,
                            sourceStarted: sourceStarted, sourceFinished: sourceFinished,
                            decodeStarted: decodeStarted, decodeFinished: decodeFinished,
                            textureStarted: textureStarted, textureFinished: textureFinished,
                            sourceWidth: width, sourceHeight: height, succeeded: true, failureStage: nil)
        return texture
    }
    private func recordTextureCreate(path: String, expected: CGSize, started: UInt64,
                                     sourceStarted: UInt64, sourceFinished: UInt64,
                                     decodeStarted: UInt64?, decodeFinished: UInt64?,
                                     textureStarted: UInt64?, textureFinished: UInt64?,
                                     sourceWidth: Double?, sourceHeight: Double?,
                                     succeeded: Bool, failureStage: String?) {
        guard frameStallTelemetry.enabled else { return }
        let now = FrameStallTelemetry.nowNanoseconds()
        func milliseconds(_ from: UInt64?, _ to: UInt64?) -> Double {
            guard let from, let to, to >= from else { return 0 }
            return Double(to - from) / 1_000_000
        }
        frameStallTelemetry.recordTextureCreate(.init(
            monotonicUptimeNanoseconds: now,
            context: frameStallTelemetry.currentContext,
            relativePath: path,
            expectedWidth: Int(expected.width), expectedHeight: Int(expected.height),
            sourceWidth: sourceWidth.map(Int.init), sourceHeight: sourceHeight.map(Int.init),
            sourceOpenAndPropertiesMilliseconds: milliseconds(sourceStarted, sourceFinished),
            thumbnailDecodeMilliseconds: milliseconds(decodeStarted, decodeFinished),
            spriteKitTextureMilliseconds: milliseconds(textureStarted, textureFinished),
            totalMilliseconds: milliseconds(started, now),
            succeeded: succeeded, failureStage: failureStage))
    }
    private func vector(_ p: CGPoint) -> SIMD2<Float> { SIMD2(Float(p.x), Float(p.y)) }
    private func vector(_ s: CGSize) -> SIMD2<Float> { SIMD2(Float(s.width), Float(s.height)) }
    private func pair(_ value: Any?) -> CGPoint? {
        guard let values = value as? [Any], values.count == 2,
              let x = finite(values[0]), let y = finite(values[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }
}
