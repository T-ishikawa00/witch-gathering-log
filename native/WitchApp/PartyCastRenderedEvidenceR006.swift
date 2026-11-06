import Foundation

/// QA evidence predicate for PartyAuthoredMotion, whose authored states share
/// `party_rest_clip` as the SpriteKit action key. This does not alter playback.
enum PartyCastRenderedEvidenceR006 {
    static func matches(actorID: String, poseState: String, assetID: String, frameIndex: Int,
                        castActionActive: Bool, restActionActive: Bool) -> Bool {
        guard ["ERNA", "LUNA", "AIRA", "NOIR"].contains(actorID),
              ["execute", "recover"].contains(poseState), frameIndex >= 0 else { return false }
        if castActionActive { return true }
        guard restActionActive else { return false }
        let prefix = "GeneratedArt/PartyAttack/\(actorID)__attack_"
        guard assetID.hasPrefix(prefix), assetID.hasSuffix(".png") else { return false }
        let start = assetID.index(assetID.startIndex, offsetBy: prefix.count)
        let end = assetID.index(assetID.endIndex, offsetBy: -4)
        guard start <= end else { return false }
        let suffix = assetID[start..<end]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber), let frame = Int(suffix) else { return false }
        return (0...99).contains(frame)
    }
}
