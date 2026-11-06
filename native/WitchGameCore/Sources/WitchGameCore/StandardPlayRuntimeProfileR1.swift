import CryptoKit
import Foundation

/// Explicit feature selection shared by the app and progression experiments.
/// Build-flag resolution stays at the app boundary; this value records the
/// resolved flags so a test cannot silently imply that candidates are approved.
public struct StandardPlayRuntimeOptionsR1: Codable, Equatable, Sendable {
    public let standardPlayEnabled: Bool
    public let sharedPartyWorkR144Enabled: Bool
    public let firstCraftAidR179Enabled: Bool
    public let enhancementR230Enabled: Bool
    public let equipmentLoadoutsR342Enabled: Bool
    public let naturalGearR350Enabled: Bool
    public let refinementR352Enabled: Bool
    public let dismantleRefundR353Enabled: Bool

    public init(standardPlayEnabled: Bool = false,
                sharedPartyWorkR144Enabled: Bool = false,
                firstCraftAidR179Enabled: Bool = false,
                enhancementR230Enabled: Bool = false,
                equipmentLoadoutsR342Enabled: Bool = false,
                naturalGearR350Enabled: Bool = false,
                refinementR352Enabled: Bool = false,
                dismantleRefundR353Enabled: Bool = false) throws {
        let developmentCandidates = firstCraftAidR179Enabled || enhancementR230Enabled
            || naturalGearR350Enabled || refinementR352Enabled || dismantleRefundR353Enabled
        guard !developmentCandidates || standardPlayEnabled,
              !naturalGearR350Enabled || enhancementR230Enabled,
              !refinementR352Enabled || naturalGearR350Enabled,
              !dismantleRefundR353Enabled || refinementR352Enabled else {
            throw StandardPlayRuntimeProfileErrorR1.invalidFeatureDependency
        }
        self.standardPlayEnabled = standardPlayEnabled
        self.sharedPartyWorkR144Enabled = sharedPartyWorkR144Enabled
        self.firstCraftAidR179Enabled = firstCraftAidR179Enabled
        self.enhancementR230Enabled = enhancementR230Enabled
        self.equipmentLoadoutsR342Enabled = equipmentLoadoutsR342Enabled
        self.naturalGearR350Enabled = naturalGearR350Enabled
        self.refinementR352Enabled = refinementR352Enabled
        self.dismantleRefundR353Enabled = dismantleRefundR353Enabled
    }

    public static let ordinary = try! Self()

    /// Exact feature-flag set recorded for the currently integrated local R020
    /// standard-play profile. Values remain candidates, not balance approval.
    public static let r020CurrentAppCandidate = try! Self(
        standardPlayEnabled: true, sharedPartyWorkR144Enabled: true,
        firstCraftAidR179Enabled: true, enhancementR230Enabled: true,
        equipmentLoadoutsR342Enabled: true, naturalGearR350Enabled: true,
        refinementR352Enabled: true, dismantleRefundR353Enabled: true)
}

public enum StandardPlayRuntimeProfileErrorR1: Error, Equatable {
    case invalidFeatureDependency
}

/// Resolves the same candidate profile chain used by App.swift without
/// modifying existing saves or changing legacy defaults. The caller supplies
/// the app's already-resolved compile gates and any appearance-only catalog.
public struct StandardPlayRuntimeProfileR1: Sendable {
    private struct ManifestPayload: Encodable {
        let schema: String
        let baseProfileID: String
        let baseConfigurationFingerprint: String
        let profileID: String
        let configurationFingerprint: String
        let options: StandardPlayRuntimeOptionsR1
        let r230Fingerprint: String
        let equipmentLoadoutsR342Enabled: Bool
        let r350Fingerprint: String
        let r352Fingerprint: String
        let r353Fingerprint: String
        let r144Fingerprint: String
        let r179Fingerprint: String
        let saveMigration: String
    }
    public let base: GameRuntimeConfigurationR098
    public let options: StandardPlayRuntimeOptionsR1
    public let enhancement: GameRuntimeEnhancementProfileR230?
    public let naturalGear: GameRuntimeNaturalGearProfileR350?
    public let refinement: GameRuntimeRefinementProfileR352?
    public let dismantle: GameRuntimeDismantleProfileR353?
    public let partyWork: PartyWorkPolicyR144?
    public let firstCraftAid: FirstCraftAidCapabilityR179
    public let canonicalManifest: Data

    public var profileID: String {
        dismantle?.profileID ?? refinement?.profileID ?? naturalGear?.profileID
            ?? enhancement?.profileID ?? base.profileID
    }

    public var configurationFingerprint: String {
        dismantle?.configurationFingerprint ?? refinement?.configurationFingerprint
            ?? naturalGear?.configurationFingerprint ?? enhancement?.configurationFingerprint
            ?? base.configurationFingerprint
    }

    public init(base: GameRuntimeConfigurationR098,
                options: StandardPlayRuntimeOptionsR1) throws {
        self.base = base
        self.options = options
        let enhancement = options.enhancementR230Enabled
            ? try GameRuntimeEnhancementProfileR230(base: base) : nil
        let naturalGear = options.naturalGearR350Enabled
            ? enhancement.map(GameRuntimeNaturalGearProfileR350.init(base:)) : nil
        let refinement = options.refinementR352Enabled
            ? naturalGear.map(GameRuntimeRefinementProfileR352.init(base:)) : nil
        let dismantle = options.dismantleRefundR353Enabled
            ? refinement.map(GameRuntimeDismantleProfileR353.init(base:)) : nil
        guard !options.enhancementR230Enabled || enhancement != nil,
              !options.naturalGearR350Enabled || naturalGear != nil,
              !options.refinementR352Enabled || refinement != nil,
              !options.dismantleRefundR353Enabled || dismantle != nil else {
            throw StandardPlayRuntimeProfileErrorR1.invalidFeatureDependency
        }
        self.enhancement = enhancement
        self.naturalGear = naturalGear
        self.refinement = refinement
        self.dismantle = dismantle
        let partyWork = options.sharedPartyWorkR144Enabled
            ? try PartyWorkPolicyR144(baseProfileID: base.profileID,
                                      baseConfigurationFingerprint: base.configurationFingerprint)
            : nil
        let firstCraftAid = options.firstCraftAidR179Enabled ? FirstCraftAidCapabilityR179.enabled : .disabled
        self.partyWork = partyWork
        self.firstCraftAid = firstCraftAid
        let resolvedProfileID = dismantle?.profileID ?? refinement?.profileID ?? naturalGear?.profileID
            ?? enhancement?.profileID ?? base.profileID
        let resolvedFingerprint = dismantle?.configurationFingerprint ?? refinement?.configurationFingerprint
            ?? naturalGear?.configurationFingerprint ?? enhancement?.configurationFingerprint
            ?? base.configurationFingerprint
        let payload = ManifestPayload(schema: "standard-play-runtime-profile-r1",
            baseProfileID: base.profileID,
            baseConfigurationFingerprint: base.configurationFingerprint,
            profileID: resolvedProfileID, configurationFingerprint: resolvedFingerprint,
            options: options,
            r230Fingerprint: enhancement.map { Self.sha256($0.canonicalManifest) } ?? "disabled",
            equipmentLoadoutsR342Enabled: options.equipmentLoadoutsR342Enabled,
            r350Fingerprint: naturalGear?.policy.policyFingerprint ?? "disabled",
            r352Fingerprint: refinement?.policy.policyFingerprint ?? "disabled",
            r353Fingerprint: dismantle?.policy.policyFingerprint ?? "disabled",
            r144Fingerprint: partyWork?.policyFingerprint ?? "disabled",
            r179Fingerprint: firstCraftAid.policyFingerprint,
            saveMigration: "none; absent optional values retain decoded defaults")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.canonicalManifest = try encoder.encode(payload)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Fresh-game factory mirrors the app's explicit first-craft stamp. It is
    /// opt-in and never applied while decoding or migrating a saved snapshot.
    public func makeNewSnapshot() throws -> GameSnapshot {
        var snapshot = try base.makeNewSnapshot()
        if options.standardPlayEnabled && firstCraftAid.isEnabled {
            snapshot.firstCraftAidEligibleR179 = true
        }
        return snapshot
    }

    /// Uses the same profile chain and policy arguments as the app. `appearanceCatalog`
    /// is accepted only by the existing gameplay-equivalence guard in Core.
    @MainActor
    public func makeEngine(saves: SaveRepository,
                           appearanceCatalog: GameCatalog? = nil) throws -> GameEngine {
        if let enhancement {
            return try enhancement.makeEngine(saves: saves,
                appearanceCatalog: appearanceCatalog,
                candidatePartyWorkPolicyR144: partyWork,
                firstCraftAidCapabilityR179: firstCraftAid,
                naturalGearDiscoveryPolicyR350: naturalGear?.policy,
                naturalGearRefinementPolicyR352: refinement?.policy,
                gearDismantleRefundPolicyR353: dismantle?.policy)
        }
        if let partyWork {
            _ = partyWork
            return try base.makeSharedPartyWorkEngineR146(saves: saves,
                appearanceCatalog: appearanceCatalog,
                firstCraftAidCapabilityR179: firstCraftAid)
        }
        return try base.makeEngine(saves: saves,
            appearanceCatalog: appearanceCatalog,
            firstCraftAidCapabilityR179: firstCraftAid)
    }
}
