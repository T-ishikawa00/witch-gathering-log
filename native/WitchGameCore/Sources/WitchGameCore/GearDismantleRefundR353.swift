import CryptoKit
import Foundation

/// Explicit, opt-in interpretation of R2 quality salvage and investment return.
/// This policy changes only dismantle yield; it does not enable automatic salvage.
public struct GearDismantleRefundPolicyR353: Sendable, Equatable {
    public static let policyID = "gear-dismantle-refund-r353-r2-candidate"
    public static let r2SourcePath = "docs/production/current/qa_drafts/latent_combat_r030/source_refs/growth_gear_skills_R2.json"
    public static let r2SourceSHA256 = "70d36d335e69899f4232567d80e2dc17457d6baec1688590cf3757d8b0b4d874"
    public static let r3SourcePath = "docs/production/current/qa_drafts/natural_gear_acquisition_r350/core_candidate_r001/inputs/economy_R3.json"
    public static let r3SourceSHA256 = "b8ae30f04cf3077f4e8dabe0c575f6d02e43502642c36015201d750e41c03476"
    public static let starterGearUUIDs = [
        "10000000-0000-4000-8000-000000000001",
        "10000000-0000-4000-8000-000000000002",
        "10000000-0000-4000-8000-000000000003",
        "10000000-0000-4000-8000-000000000004"
    ]
    public static let investmentReturnBasisPoints = 8_000
    private static let salvageBaseByQuality = ["Q0": 1, "Q1": 2, "Q2": 4, "Q3": 8, "Q4": 12]

    public static let canonicalManifest = """
    {"investmentReturnBasisPoints":8000,"policyID":"gear-dismantle-refund-r353-r2-candidate","requiresPolicy":"natural-gear-refinement-r352-r2-candidate","salvageBaseByQuality":{"Q0":1,"Q1":2,"Q2":4,"Q3":8,"Q4":12},"schema":"gear-dismantle-refund-r353-v2","starterItems":{"baseSalvageDust":0,"identity":"preservedUUID","appliesAfterEvolutionAndQuality":true,"initialInvestmentDust":0,"protected":true,"qualityID":"Q0","sourceUUIDs":["10000000-0000-4000-8000-000000000001","10000000-0000-4000-8000-000000000002","10000000-0000-4000-8000-000000000003","10000000-0000-4000-8000-000000000004"]},"sources":{"economyR3":{"path":"docs/production/current/qa_drafts/natural_gear_acquisition_r350/core_candidate_r001/inputs/economy_R3.json","sha256":"b8ae30f04cf3077f4e8dabe0c575f6d02e43502642c36015201d750e41c03476"},"growthR2":{"path":"docs/production/current/qa_drafts/latent_combat_r030/source_refs/growth_gear_skills_R2.json","sha256":"70d36d335e69899f4232567d80e2dc17457d6baec1688590cf3757d8b0b4d874"}},"starterSourceDomainSHA256":"9e4df37260d5e39a8e6354121f9ccd5ad9a4202bf16b493f8878ce6480d92eda","formula":"(issuedStarterUUID ? 0 : baseSalvageByQuality) + floor(investmentDust * 8000 / 10000)","automaticSalvage":false}
    """
    public static let policySHA256 = SHA256.hash(data: Data(canonicalManifest.utf8)).map { String(format: "%02x", $0) }.joined()
    public let policyFingerprint = Self.policySHA256

    public struct RefundBreakdown: Sendable, Equatable {
        public let qualityID: String
        public let baseSalvageDust: Int
        public let investmentRefundDust: Int
        public let totalDust: Int
    }

    public init() {}

    /// Computes base quality salvage plus the floored candidate investment return.
    /// Invalid persisted values and arithmetic overflow are rejected before mutation.
    public func refundBreakdown(gearID: UUID, qualityID: String, investmentDust: Int) throws -> RefundBreakdown {
        guard let qualityBase = Self.salvageBaseByQuality[qualityID] else {
            throw CoreError.invalidCommand("R353 cannot refund unknown gear quality")
        }
        guard investmentDust >= 0 else {
            throw CoreError.invalidCommand("R353 cannot refund negative gear investment")
        }
        let issuedStarter = Self.starterGearUUIDs.contains(gearID.uuidString.lowercased())
        let base = issuedStarter ? 0 : qualityBase
        let denominator = 10_000
        let wholeUnits = investmentDust / denominator
        let remainder = investmentDust % denominator
        let (wholeReturn, wholeOverflow) = wholeUnits.multipliedReportingOverflow(by: Self.investmentReturnBasisPoints)
        let (remainderNumerator, remainderOverflow) = remainder.multipliedReportingOverflow(by: Self.investmentReturnBasisPoints)
        guard !wholeOverflow, !remainderOverflow else {
            throw CoreError.invalidCommand("R353 investment refund overflow")
        }
        let (investmentRefund, refundOverflow) = wholeReturn.addingReportingOverflow(remainderNumerator / denominator)
        guard !refundOverflow else { throw CoreError.invalidCommand("R353 investment refund overflow") }
        let (total, totalOverflow) = base.addingReportingOverflow(investmentRefund)
        guard !totalOverflow else { throw CoreError.invalidCommand("R353 total refund overflow") }
        return RefundBreakdown(qualityID: qualityID, baseSalvageDust: base,
                               investmentRefundDust: investmentRefund, totalDust: total)
    }
}
