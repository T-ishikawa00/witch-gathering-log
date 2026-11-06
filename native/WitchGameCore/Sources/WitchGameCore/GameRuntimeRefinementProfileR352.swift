import CryptoKit
import Foundation

/// Local candidate identity composed from the unchanged R350 and R352 policy identities.
public struct GameRuntimeRefinementProfileR352: Sendable {
    public let base: GameRuntimeNaturalGearProfileR350
    public let policy: NaturalGearRefinementPolicyR352
    public let profileID: String
    public let configurationFingerprint: String
    public let canonicalManifest: Data

    public init(base: GameRuntimeNaturalGearProfileR350) {
        self.base = base
        let policy = NaturalGearRefinementPolicyR352()
        self.policy = policy
        profileID = base.profileID + "-refinement-r352-v2"
        let canonical = "schema=refinement-runtime-r352-v2\nbaseFingerprint=\(base.configurationFingerprint)\nrefinementPolicyFingerprint=\(policy.policyFingerprint)\nprofileID=\(profileID)\n"
        canonicalManifest = Data(canonical.utf8)
        configurationFingerprint = SHA256.hash(data: canonicalManifest)
            .map { String(format: "%02x", $0) }.joined()
    }
}
