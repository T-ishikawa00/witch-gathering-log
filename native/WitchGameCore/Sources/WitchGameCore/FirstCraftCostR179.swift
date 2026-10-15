import CryptoKit
import Foundation

/// Explicit capability passed only by the separately compiled R179 development route.
public struct FirstCraftAidCapabilityR179: Sendable, Equatable {
    public let isEnabled: Bool
    public let policyID: String
    public let policyFingerprint: String

    public static let disabled = FirstCraftAidCapabilityR179(isEnabled: false)
    public static let enabled = FirstCraftAidCapabilityR179(isEnabled: true)

    private init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        self.policyID = isEnabled ? "first-craft-rc-eq-f-01-r179-unapproved-v1" : "disabled"
        let material = isEnabled ? "first-craft-rc-eq-f-01-r179-unapproved-v1|M_R01_G1=1|M_R01_E2=1|catalog=M_R01_G1=6|M_R01_E2=6" : "disabled"
        self.policyFingerprint = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Shared cost projection for workshop readiness, displayed costs, and transactional spend.
public enum FirstCraftCostProjectionR179 {
    public struct Resolution: Equatable, Sendable {
        public let costs: [String: Int]
        public let dispatchCompatible: Bool
        public let aidApplied: Bool
    }

    public static let recipeID = "RC_EQ_F_01"
    public static let declaredBaseline = ["M_R01_G1": 6, "M_R01_E2": 6]
    public static let eligibleFirstCraft = ["M_R01_G1": 1, "M_R01_E2": 1]

    public static func validateCatalog(recipeID: String, declaredCosts: [String: Int],
                                       snapshot: GameSnapshot, capability: FirstCraftAidCapabilityR179) throws -> Resolution {
        let result = resolve(recipeID: recipeID, declaredCosts: declaredCosts,
                             firstCraftAidEligible: snapshot.firstCraftAidEligibleR179 == true,
                             craftedGearOnce: snapshot.craftedGearOnce, capability: capability)
        guard result.dispatchCompatible else {
            throw CoreError.invalidCatalog("R179 first-craft aid requires the unchanged RC_EQ_F_01 6/6 catalog baseline")
        }
        return result
    }

    /// Shared by read-only projection and transactional catalog validation.
    public static func resolve(recipeID: String, declaredCosts: [String: Int],
                               firstCraftAidEligible: Bool, craftedGearOnce: Bool,
                               capability: FirstCraftAidCapabilityR179) -> Resolution {
        guard capability.isEnabled, recipeID == Self.recipeID else {
            return Resolution(costs: declaredCosts, dispatchCompatible: true, aidApplied: false)
        }
        guard declaredCosts == declaredBaseline else {
            return Resolution(costs: declaredCosts, dispatchCompatible: false, aidApplied: false)
        }
        let applyAid = firstCraftAidEligible && !craftedGearOnce
        return Resolution(costs: applyAid ? eligibleFirstCraft : declaredCosts,
                          dispatchCompatible: true, aidApplied: applyAid)
    }
}
