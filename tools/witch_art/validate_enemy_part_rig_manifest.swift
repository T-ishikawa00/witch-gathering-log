import Foundation

// Contract smoke test mirroring the Decodable value models used by PartRig.swift.
struct RigManifest: Decodable {
    let actorId: String
    let canvasPx: [Double]
    let anchorPx: [Double]
    let fps: Double
    let parts: [RigPart]
    let clips: [String: RigClip]
}
struct RigPart: Decodable {
    let id: String
    let path: String
    let pivotInPartPx: [Double]
    let restPositionPx: [Double]
    let zPosition: Double
}
struct RigClip: Decodable {
    let fps: Double?
    let loop: Bool
    let frameCount: Int
    let keyframes: [RigKeyframe]
}
struct RigKeyframe: Decodable {
    let frame: Double
    let poseByPart: [String: RigPose]
}
struct RigPose: Decodable {
    let translationPx: [Double]?
    let rotationDeg: Double?
    let scaleXy: [Double]?
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let path = CommandLine.arguments.dropFirst().first ?? "native/Art/GeneratedCandidates/ACT_B_R04_B/rig_candidate_r001/rig_manifest_candidate_r001.json"
let data = try Data(contentsOf: URL(fileURLWithPath: path))
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let manifest = try decoder.decode(RigManifest.self, from: data)
require(manifest.actorId == "ACT_B_R04_B", "actor_id must decode to actorId")
require(manifest.canvasPx == [512, 341], "canvas_px must decode")
require(manifest.anchorPx == [256, 331], "anchor_px must decode")
require(manifest.parts.count == 4, "four source parts must decode")
let neck = manifest.parts.first(where: { $0.id == "neck_head" })!
require(neck.pivotInPartPx == [107, 189], "pivot_in_part_px must decode")
require(neck.restPositionPx == [124, 197], "rest_position_px must decode")
require(neck.zPosition == 4, "z_position must decode")
let execute = manifest.clips["execute"]!
require(execute.frameCount == 24 && execute.fps == 24, "execute timing must decode")
let pose = execute.keyframes[12].poseByPart["nearwing"]!
require(abs((pose.rotationDeg ?? 0) - (-3.35)) < 0.01, "rotation_deg value must be retained")
let bodyPose = execute.keyframes[12].poseByPart["body4legs_tail"]!
require(bodyPose.translationPx?.count == 2, "translation_px must decode")

// `scale_xy` is not present in this rig (no part scaling is authored); decode a
// non-default fixture to ensure the runtime model spelling is `scaleXy`.
let scaleFixture = Data(#"{"scale_xy":[0.875,1.125]}"#.utf8)
struct ScaleFixture: Decodable { let scaleXy: [Double]? }
let scale = try decoder.decode(ScaleFixture.self, from: scaleFixture).scaleXy
require(scale == [0.875, 1.125], "scale_xy must decode to scaleXy without silently defaulting")
print("PASS actorId/canvas/anchor/pivot/z/frame/translation/rotation/scale snake-case decode")
