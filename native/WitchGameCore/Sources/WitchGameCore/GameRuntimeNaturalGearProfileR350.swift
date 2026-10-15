import CryptoKit
import Foundation

/// An explicit candidate envelope; the R098 and R230 fingerprints keep their original meaning.
public struct GameRuntimeNaturalGearProfileR350: Sendable {
    public let base: GameRuntimeEnhancementProfileR230
    public let policy: NaturalGearDiscoveryPolicyR350
    public let profileID: String
    public let configurationFingerprint: String
    public let canonicalManifest: Data

    public init(base: GameRuntimeEnhancementProfileR230) {
        self.base = base
        let policy = NaturalGearDiscoveryPolicyR350()
        self.policy = policy
        profileID = base.profileID + "-natural-r350-v1"
        let canonical = "schema=natural-runtime-r350-v1\nbaseFingerprint=\(base.configurationFingerprint)\nnaturalPolicyFingerprint=\(policy.policyFingerprint)\nprofileID=\(profileID)\n"
        canonicalManifest = Data(canonical.utf8)
        configurationFingerprint = SHA256.hash(data: canonicalManifest)
            .map { String(format: "%02x", $0) }.joined()
    }
}
