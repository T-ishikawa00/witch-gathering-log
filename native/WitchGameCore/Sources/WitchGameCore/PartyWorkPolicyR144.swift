import CryptoKit
import Foundation

/// Unapproved comparison policy. It is opt-in on GameEngine; nil preserves the
/// current runtime behavior byte-for-byte at the policy branch boundary.
public struct PartyWorkPolicyR144: Sendable, Equatable {
    public static let policyID = "shared-party-work-r144-one-material-per-region-work-unit"
    public static let expectedBaseProfileID = "app-candidate-r098-v1-growth-500bp"
    public static let expectedBaseConfigurationFingerprint = "4b556e250948bd35ff31a7bdc9dbbc01a671e358565182f556ab1d8d3bf4efb0"
    public static let materialPerCompletedUnit = 1
    public static let immediateRepeatMaterial = 0
    public static let immediateRepeatCoins = 0
    public static let investigationCoinsPerUnit = 0
    public static let offlineCapSeconds: TimeInterval = 48 * 3600

    public let baseProfileID: String
    public let baseConfigurationFingerprint: String
    public let policyFingerprint: String

    public enum ConfigurationError: Error, Equatable {
        case baseProfileMismatch
        case baseFingerprintMismatch
    }

    public init(baseProfileID: String = expectedBaseProfileID,
                baseConfigurationFingerprint: String = expectedBaseConfigurationFingerprint) throws {
        guard baseProfileID == Self.expectedBaseProfileID else { throw ConfigurationError.baseProfileMismatch }
        guard baseConfigurationFingerprint == Self.expectedBaseConfigurationFingerprint else {
            throw ConfigurationError.baseFingerprintMismatch
        }
        self.baseProfileID = baseProfileID
        self.baseConfigurationFingerprint = baseConfigurationFingerprint
        let canonical = [
            "schema=party-work-policy-r144-v1",
            "baseProfileID=\(baseProfileID)",
            "baseConfigurationFingerprint=\(baseConfigurationFingerprint)",
            "policyID=\(Self.policyID)",
            "materialPerCompletedUnit=\(Self.materialPerCompletedUnit)",
            "immediateRepeatMaterial=\(Self.immediateRepeatMaterial)",
            "immediateRepeatCoins=\(Self.immediateRepeatCoins)",
            "investigationCoinsPerUnit=\(Self.investigationCoinsPerUnit)",
            "offlineCapSeconds=\(Int(Self.offlineCapSeconds))"
        ].joined(separator: "\n") + "\n"
        self.policyFingerprint = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

enum PartyWorkR144Validation {
    static func declaredDropMaterialID(for enemy: EnemyDefinition, catalog: GameCatalog) throws -> String {
        guard let materialID = enemy.dropMaterialID, catalog.materialIDs.contains(materialID) else {
            throw CoreError.invalidCommand("R144 investigation target has no declared catalog material reward")
        }
        return materialID
    }
}
