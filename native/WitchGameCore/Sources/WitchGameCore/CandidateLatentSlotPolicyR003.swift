import CryptoKit
import Foundation

public struct CandidateLatentSlotR003: Codable, Sendable, Equatable {
    public let affixID: String
    public let rawQ: Int

    public init(affixID: String, rawQ: Int) {
        self.affixID = affixID
        self.rawQ = rawQ
    }
}

public struct CandidateLatentSlotsR003: Codable, Sendable, Equatable {
    public let version: Int
    public let slots: [CandidateLatentSlotR003]

    enum CodingKeys: String, CodingKey { case version, slots }

    public init(version: Int = 1, slots: [CandidateLatentSlotR003]) throws {
        guard version == 1 else { throw CandidateLatentPolicyErrorR003.unsupportedVersion(version) }
        guard slots.count == 3 else { throw CandidateLatentPolicyErrorR003.slotCount(slots.count) }
        guard slots.allSatisfy({ (0...1000).contains($0.rawQ) }) else {
            throw CandidateLatentPolicyErrorR003.rawQOutOfRange
        }
        self.version = version
        self.slots = slots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let slots = try container.decode([CandidateLatentSlotR003].self, forKey: .slots)
        do {
            try self.init(version: version, slots: slots)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: String(describing: error))
        }
    }
}

/// Compatibility shell for isolated migration tests. Missing candidateLatentSlots means
/// legacy-unknown. This type never maps or rewrites the old singular latentEffectID.
public struct CandidateLatentItemEnvelopeR003: Codable, Sendable, Equatable {
    public var latentEffectID: String?
    public var candidateLatentSlots: CandidateLatentSlotsR003?

    public init(latentEffectID: String? = nil, candidateLatentSlots: CandidateLatentSlotsR003? = nil) {
        self.latentEffectID = latentEffectID
        self.candidateLatentSlots = candidateLatentSlots
    }

    public var isLegacyUnknown: Bool { candidateLatentSlots == nil }
}

public enum CandidateLatentPolicyErrorR003: Error, Equatable, Sendable {
    case missingPolicyResource
    case unknownTemplate(String)
    case unknownAffix(String)
    case unsupportedVersion(Int)
    case slotCount(Int)
    case rawQOutOfRange
    case belowMinimumRawQ(minimum: Int)
    case duplicateGroup(String)
    case ineligibleAcquisition(String)
    case incompatibleEvolution(String)
    case incompatibleStoredPayload(String)
    case unknownEvolution(String, String)
    case invalidQuality(String)
    case invalidRange
    case arithmeticOverflow
    case insufficientEligibleGroups
}

private struct LatentAffixRuleR003: Decodable, Sendable {
    let id: String
    let group: String
    let capability: Capability
    let stat: String
    let minBP: Int
    let maxBP: Int
    let stepBP: Int
    let aggregateCapStat: String
    let aggregateCapBP: Int
    let scalesWithRank: Bool

    enum Capability: Sendable {
        case all
        case actors(Set<String>)
    }

    enum CodingKeys: String, CodingKey {
        case id, group, capability, stat, minBP, maxBP, stepBP, aggregateCapStat, aggregateCapBP, scalesWithRank
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        group = try container.decode(String.self, forKey: .group)
        stat = try container.decode(String.self, forKey: .stat)
        minBP = try container.decode(Int.self, forKey: .minBP)
        maxBP = try container.decode(Int.self, forKey: .maxBP)
        stepBP = try container.decode(Int.self, forKey: .stepBP)
        aggregateCapStat = try container.decode(String.self, forKey: .aggregateCapStat)
        aggregateCapBP = try container.decode(Int.self, forKey: .aggregateCapBP)
        scalesWithRank = try container.decode(Bool.self, forKey: .scalesWithRank)
        if let token = try? container.decode(String.self, forKey: .capability), token == "all" {
            capability = .all
        } else {
            capability = .actors(Set(try container.decode([String].self, forKey: .capability)))
        }
    }
}

private struct LatentTemplateRuleR003: Decodable, Sendable {
    let id: String
    let slot: String
    let actorIDs: [String]
    let candidateAcquisitionExcludedAffixIDs: [String]
    let candidateStoredCompatibleAffixIDs: [String]
    let status: String
}

private struct LatentEvolutionEdgeR003: Decodable, Sendable, Hashable {
    let from: String
    let to: String
}

private struct LatentQualityRuleR003: Decodable, Sendable {
    let activeSlots: Int
    let floorQ: Int
}

private struct LatentCraftRuleR003: Decodable, Sendable {
    let quality: String
    let minimumRawQ: Int
}

private struct LatentPolicyDocumentR003: Decodable, Sendable {
    let schemaVersion: Int
    let rawQRange: [Int]
    let statCapsBP: [String: Int]
    let craftNewCandidate: LatentCraftRuleR003
    let qualities: [String: LatentQualityRuleR003]
    let affixes: [LatentAffixRuleR003]
    let templates: [LatentTemplateRuleR003]
    let evolutionEdges: [LatentEvolutionEdgeR003]
}

public enum CandidateLatentStatIDR004: String, Codable, Sendable, CaseIterable {
    case hpPercent = "hp_pct"
    case powerPercent = "power_pct"
    case defensePercent = "defense_pct"
    case critChance = "crit_chance_bp"
    case critDamageExtra = "crit_damage_extra_bp"
    case haste = "haste_bp"
    case cooldownReduction = "cdr_bp"
    case directBonus = "direct_bonus_bp"
    case dotBonus = "dot_bonus_bp"
    case healBonus = "heal_bonus_bp"
    case barrierBonus = "barrier_bonus_bp"
    case guardChance = "guard_chance_bp"
    case counterBonus = "counter_bonus_bp"
    case chaseBonus = "chase_bonus_bp"
    case debuffDurationResist = "debuff_duration_resist_bp"
    case periodicResist = "periodic_resist_bp"
}

/// Typed aggregate presented to the candidate combat adapter. `critMultiplierBP`
/// is the final multiplier (R2 baseline 15000 + AF_CRIT_DMG extra, capped at 22500).
public struct CandidateLatentCombatModifiersR004: Equatable, Sendable {
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

    public init(valuesBP: [String: Int]) {
        hpPercentBP = valuesBP[CandidateLatentStatIDR004.hpPercent.rawValue, default: 0]
        powerPercentBP = valuesBP[CandidateLatentStatIDR004.powerPercent.rawValue, default: 0]
        defensePercentBP = valuesBP[CandidateLatentStatIDR004.defensePercent.rawValue, default: 0]
        critChanceBP = valuesBP[CandidateLatentStatIDR004.critChance.rawValue, default: 0]
        critMultiplierBP = valuesBP["crit_multiplier_bp", default: 15_000]
        hasteBP = valuesBP[CandidateLatentStatIDR004.haste.rawValue, default: 0]
        cooldownReductionBP = valuesBP[CandidateLatentStatIDR004.cooldownReduction.rawValue, default: 0]
        directBonusBP = valuesBP[CandidateLatentStatIDR004.directBonus.rawValue, default: 0]
        dotBonusBP = valuesBP[CandidateLatentStatIDR004.dotBonus.rawValue, default: 0]
        healBonusBP = valuesBP[CandidateLatentStatIDR004.healBonus.rawValue, default: 0]
        barrierBonusBP = valuesBP[CandidateLatentStatIDR004.barrierBonus.rawValue, default: 0]
        guardChanceBP = valuesBP[CandidateLatentStatIDR004.guardChance.rawValue, default: 0]
        counterBonusBP = valuesBP[CandidateLatentStatIDR004.counterBonus.rawValue, default: 0]
        chaseBonusBP = valuesBP[CandidateLatentStatIDR004.chaseBonus.rawValue, default: 0]
        debuffDurationResistBP = valuesBP[CandidateLatentStatIDR004.debuffDurationResist.rawValue, default: 0]
        periodicResistBP = valuesBP[CandidateLatentStatIDR004.periodicResist.rawValue, default: 0]
    }
}

public struct CandidateLatentAffixContributionR004: Equatable, Sendable {
    public let affixID: String
    public let statID: CandidateLatentStatIDR004
    public let valueBP: Int
    public let aggregateCapStatID: String
    public let aggregateCapBP: Int
}

public enum CandidateLatentProjectionRouteR004: Equatable, Sendable {
    case legacyUnchanged
    case versionedCandidate
}

public struct CandidateLatentStatProjectionR004: Equatable, Sendable {
    public let route: CandidateLatentProjectionRouteR004
    public let valuesBP: [String: Int]
    public let combatModifiers: CandidateLatentCombatModifiersR004?
}

public struct CandidateLatentSlotPolicyR003: Sendable {
    public let sourceSHA256: String
    private let document: LatentPolicyDocumentR003
    private let affixesByID: [String: LatentAffixRuleR003]
    private let templatesByID: [String: LatentTemplateRuleR003]
    private let evolutionEdges: Set<LatentEvolutionEdgeR003>

    private init(document: LatentPolicyDocumentR003, sourceSHA256: String) throws {
        guard document.schemaVersion == 1, document.rawQRange == [0, 1000] else {
            throw CandidateLatentPolicyErrorR003.invalidRange
        }
        guard Set(document.affixes.map(\.id)).count == document.affixes.count,
              Set(document.templates.map(\.id)).count == document.templates.count else {
            throw CandidateLatentPolicyErrorR003.invalidRange
        }
        self.document = document
        self.sourceSHA256 = sourceSHA256
        self.affixesByID = Dictionary(uniqueKeysWithValues: document.affixes.map { ($0.id, $0) })
        self.templatesByID = Dictionary(uniqueKeysWithValues: document.templates.map { ($0.id, $0) })
        self.evolutionEdges = Set(document.evolutionEdges)
    }

    public static func loadBundledR004() throws -> CandidateLatentSlotPolicyR003 {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "candidate_latent_policy_r004", withExtension: "json") else {
            throw CandidateLatentPolicyErrorR003.missingPolicyResource
        }
        return try load(data: Data(contentsOf: url))
    }

    public static func load(data: Data) throws -> CandidateLatentSlotPolicyR003 {
        let sourceSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try CandidateLatentSlotPolicyR003(
            document: JSONDecoder().decode(LatentPolicyDocumentR003.self, from: data),
            sourceSHA256: sourceSHA256)
    }

    public var templateIDs: Set<String> { Set(templatesByID.keys) }
    public var evolutionEdgePairs: Set<String> { Set(evolutionEdges.map { "\($0.from)->\($0.to)" }) }
    public var familiarProposedTemplateIDs: Set<String> {
        Set(templatesByID.values.filter { $0.status == "R2_PROPOSED_CANDIDATE" }.map(\.id))
    }

    public func acquisitionEligibleAffixIDs(templateID: String, joinedActorIDs: Set<String>) throws -> Set<String> {
        guard let template = templatesByID[templateID] else { throw CandidateLatentPolicyErrorR003.unknownTemplate(templateID) }
        let eligibleActors = Set(template.actorIDs).intersection(joinedActorIDs)
        return Set(affixesByID.values.compactMap { affix in
            if template.candidateAcquisitionExcludedAffixIDs.contains(affix.id) { return nil }
            switch affix.capability {
            case .all: return affix.id
            case .actors(let required): return eligibleActors.isDisjoint(with: required) ? nil : affix.id
            }
        })
    }

    public func validateNewInstanceSlots(templateID: String, joinedActorIDs: Set<String>,
                                         slots: CandidateLatentSlotsR003, minimumRawQ: Int = 0) throws {
        guard (0...1000).contains(minimumRawQ) else { throw CandidateLatentPolicyErrorR003.invalidRange }
        let eligible = try acquisitionEligibleAffixIDs(templateID: templateID, joinedActorIDs: joinedActorIDs)
        try validateGroupsAndRange(slots)
        for slot in slots.slots {
            guard eligible.contains(slot.affixID) else { throw CandidateLatentPolicyErrorR003.ineligibleAcquisition(slot.affixID) }
            guard slot.rawQ >= minimumRawQ else { throw CandidateLatentPolicyErrorR003.belowMinimumRawQ(minimum: minimumRawQ) }
        }
    }

    public func validateCraftNewCandidate(templateID: String, joinedActorIDs: Set<String>,
                                          slots: CandidateLatentSlotsR003) throws {
        try validateNewInstanceSlots(templateID: templateID, joinedActorIDs: joinedActorIDs,
                                     slots: slots, minimumRawQ: document.craftNewCandidate.minimumRawQ)
    }

    public func validateStoredPayload(templateID: String, slots: CandidateLatentSlotsR003) throws {
        guard let template = templatesByID[templateID] else {
            throw CandidateLatentPolicyErrorR003.unknownTemplate(templateID)
        }
        try validateGroupsAndRange(slots)
        let legalStored = Set(template.candidateStoredCompatibleAffixIDs)
        for slot in slots.slots where !legalStored.contains(slot.affixID) {
            throw CandidateLatentPolicyErrorR003.incompatibleStoredPayload(slot.affixID)
        }
    }

    /// Deterministic candidate-only acquisition factory. An operation UUID and stable
    /// domain salt make a retried command produce the same three stored rolls without
    /// consuming or perturbing the product summon RNG stream.
    public func generateNewInstanceSlots(templateID: String, joinedActorIDs: Set<String>,
                                         operationID: UUID, domainSalt: String,
                                         minimumRawQ: Int = 0) throws -> CandidateLatentSlotsR003 {
        guard (0...1000).contains(minimumRawQ) else { throw CandidateLatentPolicyErrorR003.invalidRange }
        let eligible = try acquisitionEligibleAffixIDs(templateID: templateID, joinedActorIDs: joinedActorIDs)
        var remaining = eligible.sorted()
        var random = CandidateLatentStableRandomR004(seed: operationID.uuidString + "|" + domainSalt)
        var selected: [CandidateLatentSlotR003] = []
        var groups = Set<String>()
        while selected.count < 3 {
            let choices = remaining.filter { id in
                guard let rule = affixesByID[id] else { return false }
                return !groups.contains(rule.group)
            }
            guard !choices.isEmpty else { throw CandidateLatentPolicyErrorR003.insufficientEligibleGroups }
            let index = Int(random.next(upperBound: UInt64(choices.count)))
            let id = choices[index]
            guard let rule = affixesByID[id] else { throw CandidateLatentPolicyErrorR003.unknownAffix(id) }
            groups.insert(rule.group)
            remaining.removeAll { $0 == id }
            let rawQ = minimumRawQ + Int(random.next(upperBound: UInt64(1001 - minimumRawQ)))
            selected.append(CandidateLatentSlotR003(affixID: id, rawQ: rawQ))
        }
        let result = try CandidateLatentSlotsR003(slots: selected)
        try validateNewInstanceSlots(templateID: templateID, joinedActorIDs: joinedActorIDs,
                                     slots: result, minimumRawQ: minimumRawQ)
        return result
    }

    public func activeSlotCount(qualityID: String) throws -> Int {
        guard let quality = document.qualities[qualityID] else { throw CandidateLatentPolicyErrorR003.invalidQuality(qualityID) }
        return quality.activeSlots
    }

    public func effectiveQ(rawQ: Int, qualityID: String) throws -> Int {
        guard (0...1000).contains(rawQ) else { throw CandidateLatentPolicyErrorR003.rawQOutOfRange }
        guard let quality = document.qualities[qualityID] else { throw CandidateLatentPolicyErrorR003.invalidQuality(qualityID) }
        return max(rawQ, quality.floorQ)
    }

    /// Read-only UI projection for one equipped/previewed item. It never rerolls,
    /// repairs, or mutates stored slots. Legacy nil payloads return zero rows.
    public func slotPresentation(templateID: String, qualityID: String, actorID: String,
                                 candidateSlots: CandidateLatentSlotsR003?) throws -> CandidateLatentItemDisplayR005 {
        guard let template = templatesByID[templateID] else {
            throw CandidateLatentPolicyErrorR003.unknownTemplate(templateID)
        }
        let activeCount = try activeSlotCount(qualityID: qualityID)
        guard let candidateSlots else {
            return CandidateLatentItemDisplayR005(templateID: templateID, qualityID: qualityID,
                                                   actorID: actorID, payloadPresent: false,
                                                   activeSlotCount: activeCount, slots: [])
        }
        try validateGroupsAndRange(candidateSlots)
        let storedCompatible = Set(template.candidateStoredCompatibleAffixIDs)
        let rows = try candidateSlots.slots.enumerated().map { index, slot in
            guard let rule = affixesByID[slot.affixID] else {
                throw CandidateLatentPolicyErrorR003.unknownAffix(slot.affixID)
            }
            let compatibleWithTemplate = storedCompatible.contains(slot.affixID)
            let actorCompatible: Bool
            let reason: CandidateLatentCapabilityReasonR005?
            switch rule.capability {
            case .all:
                actorCompatible = true
                reason = compatibleWithTemplate ? nil : .affixNotCompatibleWithTemplate
            case .actors(let requiredActors):
                actorCompatible = requiredActors.contains(actorID)
                if !compatibleWithTemplate {
                    reason = .affixNotCompatibleWithTemplate
                } else if !actorCompatible {
                    reason = .requiredActorNotSelected
                } else {
                    reason = nil
                }
            }
            let effectiveQ = try self.effectiveQ(rawQ: slot.rawQ, qualityID: qualityID)
            let valueBP = try self.valueBP(rawQ: slot.rawQ, qualityID: qualityID,
                                           minimumBP: rule.minBP, maximumBP: rule.maxBP)
            return CandidateLatentSlotDisplayR005(id: index, affixID: slot.affixID,
                                                   rawQ: slot.rawQ, effectiveQ: effectiveQ,
                                                   valueBP: valueBP, qualityActive: index < activeCount,
                                                   actorCompatible: actorCompatible,
                                                   storedCompatible: compatibleWithTemplate,
                                                   capabilityReason: reason)
        }
        return CandidateLatentItemDisplayR005(templateID: templateID, qualityID: qualityID,
                                               actorID: actorID, payloadPresent: true,
                                               activeSlotCount: activeCount, slots: rows)
    }

    /// Aggregates all candidate-payload items for one actor, then applies each
    /// R2 cap once at actor scope. Legacy items are deliberately excluded here and
    /// remain on the caller's unchanged legacy projection path.
    public func projectActorModifiers(actorID: String, baseValuesBP: [String: Int],
                                      equippedItems: [CandidateLatentEquippedItemR005]) throws -> CandidateLatentActorProjectionR005 {
        for (stat, value) in baseValuesBP {
            guard let cap = document.statCapsBP[stat], value >= 0, value <= cap else {
                throw CandidateLatentPolicyErrorR003.invalidRange
            }
        }
        var uncapped = baseValuesBP
        var displays: [UUID: CandidateLatentItemDisplayR005] = [:]
        for item in equippedItems {
            let display = try slotPresentation(templateID: item.templateID, qualityID: item.qualityID,
                                               actorID: actorID, candidateSlots: item.candidateSlots)
            displays[item.id] = display
            guard display.payloadPresent else { continue }
            for row in display.slots {
                guard row.storedCompatible else {
                    throw CandidateLatentPolicyErrorR003.incompatibleStoredPayload(row.affixID)
                }
                guard row.qualityActive && row.actorCompatible else { continue }
                let contribution = try self.contribution(affixID: row.affixID, rawQ: row.rawQ,
                                                         qualityID: item.qualityID)
                let stat = contribution.aggregateCapStatID
                let initial = uncapped[stat] ?? (stat == "crit_multiplier_bp" ? 15_000 : 0)
                let (sum, overflow) = initial.addingReportingOverflow(contribution.valueBP)
                guard !overflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
                uncapped[stat] = sum
            }
        }
        let capped = uncapped.mapValues { $0 }
        var values = capped
        var overflowByStat: [String: Int] = [:]
        for (stat, value) in uncapped {
            guard let cap = document.statCapsBP[stat] else { throw CandidateLatentPolicyErrorR003.invalidRange }
            values[stat] = min(value, cap)
            if value > cap { overflowByStat[stat] = value - cap }
        }
        let modifiers = try CandidateLatentCombatModifiersR005(validating: values)
        return CandidateLatentActorProjectionR005(uncappedValuesBP: uncapped,
                                                  cappedValuesBP: values,
                                                  overflowBP: overflowByStat,
                                                  modifiers: modifiers,
                                                  itemDisplays: displays)
    }

    public func valueBP(rawQ: Int, qualityID: String, minimumBP: Int, maximumBP: Int) throws -> Int {
        guard minimumBP >= 0, maximumBP >= minimumBP else { throw CandidateLatentPolicyErrorR003.invalidRange }
        let q = try effectiveQ(rawQ: rawQ, qualityID: qualityID)
        let delta = maximumBP - minimumBP
        let (scaled, overflow) = delta.multipliedReportingOverflow(by: q)
        guard !overflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
        return minimumBP + scaled / 1000
    }

    /// R2-authored numeric contribution; caps apply to the final accumulated stat,
    /// not independently to each slot. No rank scaling is authored for these 16 IDs.
    public func contribution(affixID: String, rawQ: Int, qualityID: String) throws -> CandidateLatentAffixContributionR004 {
        guard let rule = affixesByID[affixID] else { throw CandidateLatentPolicyErrorR003.unknownAffix(affixID) }
        guard rule.stepBP == 1, rule.minBP >= 0, rule.maxBP >= rule.minBP,
              document.statCapsBP[rule.aggregateCapStat] == rule.aggregateCapBP else {
            throw CandidateLatentPolicyErrorR003.invalidRange
        }
        let value = try valueBP(rawQ: rawQ, qualityID: qualityID, minimumBP: rule.minBP, maximumBP: rule.maxBP)
        guard let statID = CandidateLatentStatIDR004(rawValue: rule.stat) else {
            throw CandidateLatentPolicyErrorR003.invalidRange
        }
        return CandidateLatentAffixContributionR004(affixID: affixID, statID: statID, valueBP: value,
                                                     aggregateCapStatID: rule.aggregateCapStat,
                                                     aggregateCapBP: rule.aggregateCapBP)
    }

    /// Candidate payload is an exclusive replacement for this item's legacy affix/latent
    /// numeric route. With nil payload, the caller receives the exact legacy input map.
    public func projectStatsR004(legacyProjectedValuesBP: [String: Int],
                                 candidateBaseValuesBP: [String: Int],
                                 candidateSlots: CandidateLatentSlotsR003?,
                                 qualityID: String) throws -> CandidateLatentStatProjectionR004 {
        guard let candidateSlots else {
            return CandidateLatentStatProjectionR004(route: .legacyUnchanged, valuesBP: legacyProjectedValuesBP,
                                                       combatModifiers: nil)
        }
        try validateGroupsAndRange(candidateSlots)
        let activeCount = try activeSlotCount(qualityID: qualityID)
        var result = candidateBaseValuesBP
        for slot in candidateSlots.slots.prefix(activeCount) {
            let c = try contribution(affixID: slot.affixID, rawQ: slot.rawQ, qualityID: qualityID)
            let defaultAggregate = c.aggregateCapStatID == "crit_multiplier_bp" ? 15_000 : 0
            let current = result[c.aggregateCapStatID] ?? defaultAggregate
            let (sum, overflow) = current.addingReportingOverflow(c.valueBP)
            guard !overflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
            result[c.aggregateCapStatID] = min(sum, c.aggregateCapBP)
        }
        return CandidateLatentStatProjectionR004(route: .versionedCandidate, valuesBP: result,
                                                   combatModifiers: CandidateLatentCombatModifiersR004(valuesBP: result))
    }

    public enum EvolutionCompatibility: Equatable, Sendable {
        case candidateSlotsChecked
        case legacyUnknownPreserved
    }

    @discardableResult
    public func validateEvolution(from sourceTemplateID: String, to destinationTemplateID: String,
                                  legacyEnvelope: CandidateLatentItemEnvelopeR003) throws -> EvolutionCompatibility {
        let edge = LatentEvolutionEdgeR003(from: sourceTemplateID, to: destinationTemplateID)
        guard evolutionEdges.contains(edge) else {
            throw CandidateLatentPolicyErrorR003.unknownEvolution(sourceTemplateID, destinationTemplateID)
        }
        guard let payload = legacyEnvelope.candidateLatentSlots else { return .legacyUnknownPreserved }
        do { try validateStoredPayload(templateID: destinationTemplateID, slots: payload) }
        catch CandidateLatentPolicyErrorR003.incompatibleStoredPayload(let id) {
            throw CandidateLatentPolicyErrorR003.incompatibleEvolution(id)
        }
        return .candidateSlotsChecked
    }

    private func validateGroupsAndRange(_ slots: CandidateLatentSlotsR003) throws {
        guard slots.slots.count == 3 else { throw CandidateLatentPolicyErrorR003.slotCount(slots.slots.count) }
        var groups = Set<String>()
        for slot in slots.slots {
            guard (0...1000).contains(slot.rawQ) else { throw CandidateLatentPolicyErrorR003.rawQOutOfRange }
            guard let definition = affixesByID[slot.affixID] else { throw CandidateLatentPolicyErrorR003.unknownAffix(slot.affixID) }
            guard groups.insert(definition.group).inserted else { throw CandidateLatentPolicyErrorR003.duplicateGroup(definition.group) }
        }
    }
}

private struct CandidateLatentStableRandomR004 {
    private var state: UInt64
    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        state = hash == 0 ? 0x9E3779B97F4A7C15 : hash
    }
    mutating func next(upperBound: UInt64) -> UInt64 {
        precondition(upperBound > 0)
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state % upperBound
    }
}
