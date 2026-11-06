import CryptoKit
import Foundation

/// Explicit refund profile; earlier refinement and natural-work fingerprints retain their meaning.
public struct GameRuntimeDismantleProfileR353: Sendable {
    public let base: GameRuntimeRefinementProfileR352
    public let policy: GearDismantleRefundPolicyR353
    public let profileID: String
    public let configurationFingerprint: String
    public let canonicalManifest: Data

    public init(base: GameRuntimeRefinementProfileR352) {
        self.base = base
        let policy = GearDismantleRefundPolicyR353()
        self.policy = policy
        profileID = base.profileID + "-dismantle-r353-v2"
        let canonical = "schema=dismantle-runtime-r353-v2\nbaseFingerprint=\(base.configurationFingerprint)\ndismantlePolicyFingerprint=\(policy.policyFingerprint)\nprofileID=\(profileID)\n"
        canonicalManifest = Data(canonical.utf8)
        configurationFingerprint = SHA256.hash(data: canonicalManifest)
            .map { String(format: "%02x", $0) }.joined()
    }
}
