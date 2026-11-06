import CryptoKit
import Foundation

/// Provenance attached to product-rule snapshots. `humanApproved` is only data;
/// callers must provide a durable approval reference and this type never changes
/// a runtime profile or save.
public enum ProductRuleDispositionR1: String, Codable, Sendable {
    case candidate
    case testOnly
    case humanApproved
}

public struct ProductRuleRecordR1: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let disposition: ProductRuleDispositionR1
    public let sourceProfileID: String
    public let sourceFingerprint: String
    public let values: [String: String]
    public let approvalReference: String?

    public init(id: String, disposition: ProductRuleDispositionR1,
                sourceProfileID: String, sourceFingerprint: String,
                values: [String: String], approvalReference: String? = nil) throws {
        guard !id.isEmpty, !sourceProfileID.isEmpty, !sourceFingerprint.isEmpty,
              disposition != .humanApproved || !(approvalReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              disposition == .humanApproved || approvalReference == nil else {
            throw ProductProgressionRulesErrorR1.invalidProvenance
        }
        self.id = id
        self.disposition = disposition
        self.sourceProfileID = sourceProfileID
        self.sourceFingerprint = sourceFingerprint
        self.values = values
        self.approvalReference = approvalReference
    }
}

public enum ProductProgressionRulesErrorR1: Error, Equatable {
    case invalidProvenance
}

/// A read-only, canonical record of the exact candidate policies used for a
/// progression experiment. It deliberately does not become a runtime setting.
public struct ProductProgressionRulesManifestR1: Codable, Equatable, Sendable {
    public static let schema = "witch-product-progression-rules-r1"
    public let schema: String
    public let schemaVersion: Int
    public let runtimeProfileID: String
    public let runtimeConfigurationFingerprint: String
    public let catalogSHA256: String
    public let runtimeOptions: StandardPlayRuntimeOptionsR1
    public let rules: [ProductRuleRecordR1]

    public init(runtimeProfileID: String, runtimeConfigurationFingerprint: String,
                catalogSHA256: String, runtimeOptions: StandardPlayRuntimeOptionsR1 = .ordinary,
                rules: [ProductRuleRecordR1]) throws {
        guard !runtimeProfileID.isEmpty, !runtimeConfigurationFingerprint.isEmpty,
              !catalogSHA256.isEmpty, !rules.isEmpty,
              Set(rules.map(\.id)).count == rules.count else {
            throw ProductProgressionRulesErrorR1.invalidProvenance
        }
        self.schema = Self.schema
        self.schemaVersion = 1
        self.runtimeProfileID = runtimeProfileID
        self.runtimeConfigurationFingerprint = runtimeConfigurationFingerprint
        self.catalogSHA256 = catalogSHA256
        self.runtimeOptions = runtimeOptions
        self.rules = rules.sorted { $0.id < $1.id }
    }

    /// Captures the exact resolved profile chain and switches used by a caller.
    /// No runtime policy is inferred from a profile name or silently enabled.
    public static func candidate(profile: StandardPlayRuntimeProfileR1) throws -> Self {
        var rules: [ProductRuleRecordR1] = []
        func append(_ id: String, _ source: String, _ fingerprint: String,
                    _ values: [String: String]) throws {
            rules.append(try ProductRuleRecordR1(id: id, disposition: .candidate,
                sourceProfileID: source, sourceFingerprint: fingerprint, values: values))
        }
        let runtime = profile.base
        let options = profile.options
        try append("runtime-growth", runtime.profileID, runtime.configurationFingerprint,
            ["strengthBasisPoints": String(runtime.growth.strengthBP), "status": runtime.growth.status])
        try append("summon-economy", runtime.profileID, runtime.configurationFingerprint,
            ["dailyFreeTicketGrant": String(runtime.catalog.dailyFreeTicketGrant),
             "qualityOddsBasisPoints": runtime.catalog.gachaOddsBasisPoints.keys.sorted()
                .map { "\($0):\(runtime.catalog.gachaOddsBasisPoints[$0] ?? 0)" }.joined(separator: ",")])
        try append("runtime-feature-gates", profile.profileID, profile.configurationFingerprint,
            ["standardPlayR169": String(options.standardPlayEnabled),
             "partyWorkR144": String(options.sharedPartyWorkR144Enabled),
             "firstCraftAidR179": String(options.firstCraftAidR179Enabled),
             "enhancementR230": String(options.enhancementR230Enabled),
             "equipmentLoadoutsR342": String(options.equipmentLoadoutsR342Enabled),
             "naturalGearR350": String(options.naturalGearR350Enabled),
             "refinementR352": String(options.refinementR352Enabled),
             "dismantleRefundR353": String(options.dismantleRefundR353Enabled),
             "saveMigration": "none; absent new values do not alter decoded saves"])
        if let work = profile.partyWork {
            try append("party-work", work.baseProfileID, work.policyFingerprint,
                ["policyID": PartyWorkPolicyR144.policyID,
                 "materialPerCompletedUnit": String(PartyWorkPolicyR144.materialPerCompletedUnit),
                 "offlineCapSeconds": String(Int(PartyWorkPolicyR144.offlineCapSeconds)),
                 "immediateRepeatMaterial": String(PartyWorkPolicyR144.immediateRepeatMaterial),
                 "immediateRepeatCoins": String(PartyWorkPolicyR144.immediateRepeatCoins)])
        }
        if let natural = profile.naturalGear {
            try append("natural-gear", NaturalGearDiscoveryPolicyR350.policyID,
                natural.policy.policyFingerprint,
                ["workSeconds": String(NaturalGearDiscoveryPolicyR350.workSeconds),
                 "workUnitsPerDrop": String(NaturalGearDiscoveryPolicyR350.workUnitsPerDrop),
                 "offlineCapSeconds": String(NaturalGearDiscoveryPolicyR350.unattendedCapSeconds),
                 "legendaryPityRolls": String(NaturalGearDiscoveryPolicyR350.legendaryPityRolls),
                 "localPoolBasisPoints": String(NaturalGearDiscoveryPolicyR350.localPoolBasisPoints),
                 "globalPoolBasisPoints": String(NaturalGearDiscoveryPolicyR350.globalPoolBasisPoints),
                 "desiredTemplateRule": "unresolved; stored preference does not bias template draw"])
        }
        if let refinement = profile.refinement {
            try append("natural-gear-refinement", NaturalGearRefinementPolicyR352.policyID,
                refinement.policy.policyFingerprint,
                ["sourceSHA256": NaturalGearRefinementPolicyR352.sourceSHA256,
                 "rankMultipliers": "10000,16000,24000,34000,46000"])
        }
        if let dismantle = profile.dismantle {
            try append("dismantle-refund", GearDismantleRefundPolicyR353.policyID,
                dismantle.policy.policyFingerprint,
                ["investmentReturnBasisPoints": String(GearDismantleRefundPolicyR353.investmentReturnBasisPoints),
                 "automaticSalvage": "false"])
        }
        try append("first-craft-aid", profile.firstCraftAid.policyID,
            profile.firstCraftAid.policyFingerprint,
            ["enabled": String(profile.firstCraftAid.isEnabled),
             "freshR169SaveEligibility": "stamped only by makeNewSnapshot; no save migration"])
        return try Self(runtimeProfileID: profile.profileID,
            runtimeConfigurationFingerprint: profile.configurationFingerprint,
            catalogSHA256: runtime.catalogSHA256, runtimeOptions: options, rules: rules)
    }

    /// Resolves actual runtime values and existing versioned policy fingerprints;
    /// it never substitutes product-approved defaults for candidate values.
    public static func candidate(runtime: GameRuntimeConfigurationR098,
                                 work: PartyWorkPolicyR144,
                                 naturalGear: NaturalGearDiscoveryPolicyR350,
                                 refinement: NaturalGearRefinementPolicyR352? = nil,
                                 dismantle: GearDismantleRefundPolicyR353? = nil) throws -> Self {
        var rules: [ProductRuleRecordR1] = []
        func append(_ id: String, _ profile: String, _ fingerprint: String,
                    _ values: [String: String], disposition: ProductRuleDispositionR1 = .candidate) throws {
            rules.append(try ProductRuleRecordR1(id: id, disposition: disposition,
                                                 sourceProfileID: profile, sourceFingerprint: fingerprint,
                                                 values: values))
        }
        try append("runtime-growth", runtime.profileID, runtime.configurationFingerprint,
                   ["strengthBasisPoints": String(runtime.growth.strengthBP),
                    "status": runtime.growth.status])
        try append("summon-economy", runtime.profileID, runtime.configurationFingerprint,
                   ["dailyFreeTicketGrant": String(runtime.catalog.dailyFreeTicketGrant),
                    "qualityOddsBasisPoints": runtime.catalog.gachaOddsBasisPoints.keys.sorted()
                        .map { "\($0):\(runtime.catalog.gachaOddsBasisPoints[$0] ?? 0)" }.joined(separator: ",")])
        try append("party-work", work.baseProfileID, work.policyFingerprint,
                   ["policyID": PartyWorkPolicyR144.policyID,
                    "materialPerCompletedUnit": String(PartyWorkPolicyR144.materialPerCompletedUnit),
                    "offlineCapSeconds": String(Int(PartyWorkPolicyR144.offlineCapSeconds)),
                    "immediateRepeatMaterial": String(PartyWorkPolicyR144.immediateRepeatMaterial),
                    "immediateRepeatCoins": String(PartyWorkPolicyR144.immediateRepeatCoins)])
        try append("natural-gear", NaturalGearDiscoveryPolicyR350.policyID,
                   naturalGear.policyFingerprint,
                   ["workSeconds": String(NaturalGearDiscoveryPolicyR350.workSeconds),
                    "workUnitsPerDrop": String(NaturalGearDiscoveryPolicyR350.workUnitsPerDrop),
                    "offlineCapSeconds": String(NaturalGearDiscoveryPolicyR350.unattendedCapSeconds),
                    "legendaryPityRolls": String(NaturalGearDiscoveryPolicyR350.legendaryPityRolls),
                    "localPoolBasisPoints": String(NaturalGearDiscoveryPolicyR350.localPoolBasisPoints),
                    "globalPoolBasisPoints": String(NaturalGearDiscoveryPolicyR350.globalPoolBasisPoints),
                    "desiredTemplateRule": "unresolved; stored in pinned pool but not used to bias template draw"])
        if let refinement {
            try append("natural-gear-refinement", NaturalGearRefinementPolicyR352.policyID,
                       refinement.policyFingerprint,
                       ["sourceSHA256": NaturalGearRefinementPolicyR352.sourceSHA256,
                        "rankMultipliers": "10000,16000,24000,34000,46000"])
        }
        if let dismantle {
            try append("dismantle-refund", GearDismantleRefundPolicyR353.policyID,
                       dismantle.policyFingerprint,
                       ["investmentReturnBasisPoints": String(GearDismantleRefundPolicyR353.investmentReturnBasisPoints),
                        "automaticSalvage": "false"])
        }
        return try Self(runtimeProfileID: runtime.profileID,
                        runtimeConfigurationFingerprint: runtime.configurationFingerprint,
                        catalogSHA256: runtime.catalogSHA256, rules: rules)
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func sha256() throws -> String {
        SHA256.hash(data: try canonicalData()).map { String(format: "%02x", $0) }.joined()
    }

    public var hasHumanApprovedRules: Bool {
        rules.contains { $0.disposition == .humanApproved && $0.approvalReference != nil }
    }
}

/// State-derived reporting for a natural-acquisition experiment. This projection
/// counts only UUIDs in the natural-acquisition ledger, never QA fixture items.
public struct NaturalAcquisitionProjectionR1: Codable, Equatable, Sendable {
    public let naturalRollIndex: Int
    public let qualityCounts: [String: Int]
    public let templateCounts: [String: Int]
    public let retainedRecordCount: Int
    public let totalOwnedGear: Int
    public let naturalOwnedGearCount: Int
    public let workUnitsIntoNextDrop: Int
    public let missesSinceQ4: Int

    public static func project(_ state: GameSnapshot) -> Self {
        let records = state.naturalGearDiscoveryR350?.acquisitionRecords ?? []
        return Self(
            naturalRollIndex: state.naturalGearDiscoveryR350?.naturalRollIndex ?? 0,
            qualityCounts: records.reduce(into: [:]) { $0[$1.qualityID, default: 0] += 1 },
            templateCounts: records.reduce(into: [:]) { $0[$1.templateID, default: 0] += 1 },
            retainedRecordCount: records.count,
            totalOwnedGear: state.gear.count,
            naturalOwnedGearCount: Set(records.map(\.gearInstanceID)).intersection(Set(state.gear.map(\.id))).count,
            workUnitsIntoNextDrop: state.naturalGearDiscoveryR350?.workUnitsIntoDrop ?? 0,
            missesSinceQ4: state.naturalGearDiscoveryR350?.missesSinceQ4 ?? 0)
    }
}
