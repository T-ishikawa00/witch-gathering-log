import Foundation

public enum CandidateLatentModifierValidationErrorR005: Error, Equatable, Sendable {
    case unexpectedStat(String)
    case belowZero(String)
    case aboveCap(String, value: Int, cap: Int)
    case invalidCritMultiplier(Int)
    case legacyProjectionCannotBecomeCandidate
}

public enum CandidateLatentSlotDisplayStateR005: String, Codable, Sendable {
    case active
    case qualityLocked
    case actorIncompatible
    case invalidStored
}

public enum CandidateLatentCapabilityReasonR005: String, Codable, Sendable {
    case requiredActorNotSelected
    case affixNotCompatibleWithTemplate
}

public struct CandidateLatentSlotDisplayR005: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let affixID: String
    public let rawQ: Int
    public let effectiveQ: Int
    public let valueBP: Int
    public let qualityActive: Bool
    public let actorCompatible: Bool
    public let storedCompatible: Bool
    public let capabilityReason: CandidateLatentCapabilityReasonR005?

    public var state: CandidateLatentSlotDisplayStateR005 {
        if !storedCompatible { return .invalidStored }
        if !actorCompatible { return .actorIncompatible }
        return qualityActive ? .active : .qualityLocked
    }
    public var isActive: Bool { state == .active }
}

/// A nil payload is explicitly represented as legacy-unknown, with no fabricated slots.
public struct CandidateLatentItemDisplayR005: Codable, Sendable, Equatable {
    public let templateID: String
    public let qualityID: String
    public let actorID: String
    public let payloadPresent: Bool
    public let activeSlotCount: Int
    public let slots: [CandidateLatentSlotDisplayR005]

    public var isLegacyUnknown: Bool { !payloadPresent }
}

public struct CandidateLatentEquippedItemR005: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let templateID: String
    public let qualityID: String
    public let candidateSlots: CandidateLatentSlotsR003?

    public init(id: UUID, templateID: String, qualityID: String,
                candidateSlots: CandidateLatentSlotsR003?) {
        self.id = id
        self.templateID = templateID
        self.qualityID = qualityID
        self.candidateSlots = candidateSlots
    }
}

public struct CandidateLatentActorProjectionR005: Codable, Sendable, Equatable {
    public let uncappedValuesBP: [String: Int]
    public let cappedValuesBP: [String: Int]
    public let overflowBP: [String: Int]
    public let modifiers: CandidateLatentCombatModifiersR005
    public let itemDisplays: [UUID: CandidateLatentItemDisplayR005]
}

/// Isolated-domain adapter result. Timeline integration attaches `modifiers` to
/// its candidate Combatant field; maxHP/attack/defense already include the three
/// primary percentage stats exactly once.
public struct CandidateLatentCombatantProjectionR005: Sendable, Equatable {
    public let combatant: Combatant
    public let latent: CandidateLatentActorProjectionR005?
}

/// Validated, serializable actor-level candidate modifiers. All ordinary fields are
/// aggregate basis points (100 bp = 1%). `critMultiplierBP` is the total multiplier,
/// whose base is 15000 and authored cap is 22500. This R005 type replaces the
/// non-Codable, nonvalidating R004 transport shell at integration.
public struct CandidateLatentCombatModifiersR005: Codable, Sendable, Equatable {
    public let hpPercentBP: Int
    public let powerPercentBP: Int
    public let defensePercentBP: Int
    public let critChanceBP: Int
    public let critMultiplierBP: Int
    public let hasteBP: Int
    public let cooldownReductionBP: Int
    public let directBonusBP: Int
    public let dotBonusBP: Int
    public let healBonusBP: Int
    public let barrierBonusBP: Int
    public let guardChanceBP: Int
    public let counterBonusBP: Int
    public let chaseBonusBP: Int
    public let debuffDurationResistBP: Int
    public let periodicResistBP: Int

    private enum CodingKeys: String, CodingKey {
        case hpPercentBP, powerPercentBP, defensePercentBP, critChanceBP, critMultiplierBP
        case hasteBP, cooldownReductionBP, directBonusBP, dotBonusBP, healBonusBP
        case barrierBonusBP, guardChanceBP, counterBonusBP, chaseBonusBP
        case debuffDurationResistBP, periodicResistBP
    }

    private static let caps: [String: Int] = [
        "hp_pct": 10_000, "power_pct": 8_000, "defense_pct": 10_000,
        "crit_chance_bp": 6_000, "haste_bp": 5_000, "cdr_bp": 2_500,
        "direct_bonus_bp": 6_000, "dot_bonus_bp": 10_000, "heal_bonus_bp": 10_000,
        "barrier_bonus_bp": 10_000, "guard_chance_bp": 4_500,
        "counter_bonus_bp": 10_000, "chase_bonus_bp": 10_000,
        "debuff_duration_resist_bp": 5_000, "periodic_resist_bp": 5_000,
        "crit_multiplier_bp": 22_500
    ]

    /// Baseline candidate inputs before item slots. Caller adds legacy/equipment
    /// guard chance once; all latent values are then aggregated and capped by policy.
    public static func baseValuesBP(actorID: String, existingGuardChanceBP: Int = 0) -> [String: Int] {
        [
            "hp_pct": 0, "power_pct": 0, "defense_pct": 0,
            "crit_chance_bp": actorID == "C_FAMILIAR" ? 1_000 : 500,
            "crit_multiplier_bp": 15_000,
            "haste_bp": 0, "cdr_bp": 0, "direct_bonus_bp": 0, "dot_bonus_bp": 0,
            "heal_bonus_bp": 0, "barrier_bonus_bp": 0,
            "guard_chance_bp": existingGuardChanceBP,
            "counter_bonus_bp": 0, "chase_bonus_bp": 0,
            "debuff_duration_resist_bp": 0, "periodic_resist_bp": 0
        ]
    }

    public init(validating valuesBP: [String: Int]) throws {
        for key in valuesBP.keys where Self.caps[key] == nil {
            throw CandidateLatentModifierValidationErrorR005.unexpectedStat(key)
        }
        for (key, value) in valuesBP {
            guard value >= 0 else { throw CandidateLatentModifierValidationErrorR005.belowZero(key) }
            guard let cap = Self.caps[key], value <= cap else {
                throw CandidateLatentModifierValidationErrorR005.aboveCap(key, value: value, cap: Self.caps[key] ?? 0)
            }
        }
        let critMultiplier = valuesBP["crit_multiplier_bp", default: 15_000]
        guard (15_000...22_500).contains(critMultiplier) else {
            throw CandidateLatentModifierValidationErrorR005.invalidCritMultiplier(critMultiplier)
        }
        hpPercentBP = valuesBP["hp_pct", default: 0]
        powerPercentBP = valuesBP["power_pct", default: 0]
        defensePercentBP = valuesBP["defense_pct", default: 0]
        critChanceBP = valuesBP["crit_chance_bp", default: 0]
        critMultiplierBP = critMultiplier
        hasteBP = valuesBP["haste_bp", default: 0]
        cooldownReductionBP = valuesBP["cdr_bp", default: 0]
        directBonusBP = valuesBP["direct_bonus_bp", default: 0]
        dotBonusBP = valuesBP["dot_bonus_bp", default: 0]
        healBonusBP = valuesBP["heal_bonus_bp", default: 0]
        barrierBonusBP = valuesBP["barrier_bonus_bp", default: 0]
        guardChanceBP = valuesBP["guard_chance_bp", default: 0]
        counterBonusBP = valuesBP["counter_bonus_bp", default: 0]
        chaseBonusBP = valuesBP["chase_bonus_bp", default: 0]
        debuffDurationResistBP = valuesBP["debuff_duration_resist_bp", default: 0]
        periodicResistBP = valuesBP["periodic_resist_bp", default: 0]
    }

    public init(validating projection: CandidateLatentStatProjectionR004) throws {
        guard projection.route == .versionedCandidate else {
            throw CandidateLatentModifierValidationErrorR005.legacyProjectionCannotBecomeCandidate
        }
        try self.init(validating: projection.valuesBP)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hpPercentBP, forKey: .hpPercentBP)
        try c.encode(powerPercentBP, forKey: .powerPercentBP)
        try c.encode(defensePercentBP, forKey: .defensePercentBP)
        try c.encode(critChanceBP, forKey: .critChanceBP)
        try c.encode(critMultiplierBP, forKey: .critMultiplierBP)
        try c.encode(hasteBP, forKey: .hasteBP)
        try c.encode(cooldownReductionBP, forKey: .cooldownReductionBP)
        try c.encode(directBonusBP, forKey: .directBonusBP)
        try c.encode(dotBonusBP, forKey: .dotBonusBP)
        try c.encode(healBonusBP, forKey: .healBonusBP)
        try c.encode(barrierBonusBP, forKey: .barrierBonusBP)
        try c.encode(guardChanceBP, forKey: .guardChanceBP)
        try c.encode(counterBonusBP, forKey: .counterBonusBP)
        try c.encode(chaseBonusBP, forKey: .chaseBonusBP)
        try c.encode(debuffDurationResistBP, forKey: .debuffDurationResistBP)
        try c.encode(periodicResistBP, forKey: .periodicResistBP)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let values: [String: Int] = [
            "hp_pct": try c.decode(Int.self, forKey: .hpPercentBP),
            "power_pct": try c.decode(Int.self, forKey: .powerPercentBP),
            "defense_pct": try c.decode(Int.self, forKey: .defensePercentBP),
            "crit_chance_bp": try c.decode(Int.self, forKey: .critChanceBP),
            "crit_multiplier_bp": try c.decode(Int.self, forKey: .critMultiplierBP),
            "haste_bp": try c.decode(Int.self, forKey: .hasteBP),
            "cdr_bp": try c.decode(Int.self, forKey: .cooldownReductionBP),
            "direct_bonus_bp": try c.decode(Int.self, forKey: .directBonusBP),
            "dot_bonus_bp": try c.decode(Int.self, forKey: .dotBonusBP),
            "heal_bonus_bp": try c.decode(Int.self, forKey: .healBonusBP),
            "barrier_bonus_bp": try c.decode(Int.self, forKey: .barrierBonusBP),
            "guard_chance_bp": try c.decode(Int.self, forKey: .guardChanceBP),
            "counter_bonus_bp": try c.decode(Int.self, forKey: .counterBonusBP),
            "chase_bonus_bp": try c.decode(Int.self, forKey: .chaseBonusBP),
            "debuff_duration_resist_bp": try c.decode(Int.self, forKey: .debuffDurationResistBP),
            "periodic_resist_bp": try c.decode(Int.self, forKey: .periodicResistBP)
        ]
        do { try self.init(validating: values) }
        catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "candidate latent combat modifiers failed validation: \(error)"))
        }
    }
}
