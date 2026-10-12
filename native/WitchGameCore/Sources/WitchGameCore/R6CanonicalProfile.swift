import Foundation
import CryptoKit

/// Explicit fixed-point input from the locked R6-B/R5 reference profile.
/// It is a validation adapter only; campaign catalog values stay untouched.
public struct R6SourceActorInput: Codable, Sendable, Equatable {
    public let actorID: String
    public let level: Int
    public let hp: Int
    public let power: Int
    public let defense: Int
    public let combatStats: R6SourceCombatStats?

    public init(actorID: String, level: Int, hp: Int, power: Int, defense: Int, combatStats: R6SourceCombatStats? = nil) {
        self.actorID = actorID; self.level = level; self.hp = hp; self.power = power; self.defense = defense; self.combatStats = combatStats
    }
}

public struct R6SourceBattleInput: Codable, Sendable, Equatable {
    public let profileID: String
    public let unitScale: Int
    public let seed: String
    public let actors: [R6SourceActorInput]

    public init(seed: String, actors: [R6SourceActorInput], profileID: String = "R6B_FIXED_10000", unitScale: Int = 10_000) throws {
        guard unitScale == 10_000, !seed.isEmpty, actors.count == 4,
              Set(actors.map(\.actorID)).count == 4,
              actors.allSatisfy({ (1...60).contains($0.level) && $0.hp > 0 && $0.power >= 0 && $0.defense >= 0 }) else {
            throw CoreError.invalidCommand("invalid R6 fixed-point source input")
        }
        self.profileID = profileID; self.unitScale = unitScale; self.seed = seed; self.actors = actors
    }

    /// Converts source units without normalizing them into the campaign overlay.
    public func combatants() -> [Combatant] {
        actors.map { Combatant(id: $0.actorID, maxHP: $0.hp, attack: $0.power, defense: $0.defense, level: $0.level, r6SourceStats: $0.combatStats) }
    }
}

public struct R6IncomingDamageInput: Codable, Sendable, Equatable {
    public let power: Int
    public let coefficientBP: Int
    public let defense: Int
    public let attackerLevel: Int
    public let guarded: Bool
    public let specialReductionBP: Int

    public init(power: Int, coefficientBP: Int, defense: Int, attackerLevel: Int, guarded: Bool = false, specialReductionBP: Int = 0) {
        self.power = power; self.coefficientBP = coefficientBP; self.defense = defense
        self.attackerLevel = attackerLevel; self.guarded = guarded; self.specialReductionBP = specialReductionBP
    }
}

public struct R6NormalAttackInput: Codable, Sendable, Equatable {
    public let seed: String
    public let sourceID: String
    public let sourcePower: Int
    public let sourceLevel: Int
    public let targetID: String
    public let targetHP: Int
    public let targetDefense: Int
    public let rootActionID: String
    public let coefficientBP: Int
    public let directBonusBP: Int
    public let critChanceBP: Int
    public let critMultiplierBP: Int
    public let targetMarked: Bool

    public init(seed: String, sourceID: String, sourcePower: Int, sourceLevel: Int, targetID: String, targetHP: Int, targetDefense: Int, rootActionID: String, coefficientBP: Int = 10_000, directBonusBP: Int = 0, critChanceBP: Int, critMultiplierBP: Int = 15_000, targetMarked: Bool = false) {
        self.seed = seed; self.sourceID = sourceID; self.sourcePower = sourcePower; self.sourceLevel = sourceLevel
        self.targetID = targetID; self.targetHP = targetHP; self.targetDefense = targetDefense
        self.rootActionID = rootActionID; self.coefficientBP = coefficientBP; self.directBonusBP = directBonusBP
        self.critChanceBP = critChanceBP; self.critMultiplierBP = critMultiplierBP; self.targetMarked = targetMarked
    }
}

public struct R6NormalAttackTrace: Codable, Sendable, Equatable {
    public let sourceID: String
    public let targetID: String
    public let rootActionID: String
    public let rawPower: Int
    public let critRoll: Int
    public let critical: Bool
    public let damage: Int
    public let hpLoss: Int
    public init(sourceID: String, targetID: String, rootActionID: String, rawPower: Int, critRoll: Int, critical: Bool, damage: Int, hpLoss: Int) {
        self.sourceID = sourceID; self.targetID = targetID; self.rootActionID = rootActionID
        self.rawPower = rawPower; self.critRoll = critRoll; self.critical = critical; self.damage = damage; self.hpLoss = hpLoss
    }
}

public struct R6SmithGuardInput: Codable, Sendable, Equatable {
    public struct Telegraph: Codable, Sendable, Equatable {
        public let targetIsAlive: Bool
        public let isAOE: Bool
        public let impactOffsetsMs: [Int]
        public let targetIsDangerousWithoutCover: Bool
        public let redirectedIncomingDamage: [Int]
        public init(targetIsAlive: Bool, isAOE: Bool, impactOffsetsMs: [Int], targetIsDangerousWithoutCover: Bool, redirectedIncomingDamage: [Int]) {
            self.targetIsAlive = targetIsAlive; self.isAOE = isAOE; self.impactOffsetsMs = impactOffsetsMs
            self.targetIsDangerousWithoutCover = targetIsDangerousWithoutCover; self.redirectedIncomingDamage = redirectedIncomingDamage
        }
    }
    public let nowMs: Int
    public let smithHP: Int
    public let smithMaxHP: Int
    public let existingCoverCharges: Int
    public let coverExpiryMs: Int
    public let coverDisabled: Bool
    public let smithBarrier: Int
    public let telegraphs: [Telegraph]

    public init(nowMs: Int, smithHP: Int, smithMaxHP: Int, existingCoverCharges: Int = 0, coverExpiryMs: Int = 0, coverDisabled: Bool = false, smithBarrier: Int = 0, telegraphs: [Telegraph]) {
        self.nowMs = nowMs; self.smithHP = smithHP; self.smithMaxHP = smithMaxHP
        self.existingCoverCharges = existingCoverCharges; self.coverExpiryMs = coverExpiryMs
        self.coverDisabled = coverDisabled; self.smithBarrier = smithBarrier; self.telegraphs = telegraphs
    }
}

public struct R6HealCandidate: Codable, Sendable, Equatable {
    public let actorID: String
    public let hp: Int
    public let maxHP: Int
    public let reservedHealing: Int
    public let danger: Bool
    public let projectedHP: Int

    public init(actorID: String, hp: Int, maxHP: Int, reservedHealing: Int = 0, danger: Bool, projectedHP: Int) {
        self.actorID = actorID; self.hp = hp; self.maxHP = maxHP
        self.reservedHealing = reservedHealing; self.danger = danger; self.projectedHP = projectedHP
    }
}

public struct R6SupportAvailability: Codable, Sendable, Equatable {
    public let healReady: Bool
    public let wardReady: Bool
    public let wardTargetID: String?
    public let wardIsLethal: Bool
    public init(healReady: Bool, wardReady: Bool, wardTargetID: String?, wardIsLethal: Bool) {
        self.healReady = healReady; self.wardReady = wardReady; self.wardTargetID = wardTargetID; self.wardIsLethal = wardIsLethal
    }
}

public struct R6SupportChoice: Codable, Sendable, Equatable {
    public let skillID: String
    public let targetID: String
    public init(skillID: String, targetID: String) { self.skillID = skillID; self.targetID = targetID }
}

/// Stateless source-compatible trace primitives. Python R6-B labels each roll
/// by domain and root/index, so adding an unrelated event cannot shift RNG.
public enum R6CanonicalProfile {
    private static let actorOrder = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"]

    public static func keyedLabel(domain: String, index: String) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode([domain, index])
        guard let label = String(data: data, encoding: .utf8) else { throw CoreError.invalidCommand("R6 RNG label is not UTF-8") }
        return label
    }

    public static func keyedLabel(domain: String, index: Int) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode([domain, String(index)])
        // Convert the second JSON element back to a JSON integer because the
        // Python reference canonicalizes enemy target indices as numbers.
        let encoded = String(data: data, encoding: .utf8) ?? ""
        let stringSuffix = ",\"\(index)\"]"
        guard encoded.hasSuffix(stringSuffix) else { throw CoreError.invalidCommand("R6 integer RNG label encoding failed") }
        return String(encoded.dropLast(stringSuffix.count)) + ",\(index)]"
    }

    public static func keyedInt(seed: String, label: String, upperBound: Int) throws -> Int {
        guard !seed.isEmpty, upperBound > 0, upperBound <= Int32.max else { throw CoreError.invalidCommand("invalid R6 keyed RNG input") }
        let bound = UInt64(upperBound)
        let remainder = pow2Mod256(bound)
        let limit = remainder == 0 ? nil : twosComplement256(remainder)
        for counter in 0..<1_000 {
            let digest = Array(SHA256.hash(data: Data("\(seed)|\(label)|\(counter)".utf8)))
            if let limit, !lexicographicallyLess(digest, limit) { continue }
            var residue: UInt64 = 0
            for byte in digest { residue = (residue * 256 + UInt64(byte)) % bound }
            return Int(residue)
        }
        throw CoreError.invalidCommand("R6 keyed RNG rejection limit")
    }

    /// Exact R5 fixed-point formula: floor(power * coefficient / 10,000),
    /// followed by defense, guard (65%), then special reduction (capped 30%).
    public static func incomingDamage(_ input: R6IncomingDamageInput) throws -> Int {
        guard input.power >= 0, input.coefficientBP >= 0, input.defense >= 0,
              (1...60).contains(input.attackerLevel) else { throw CoreError.invalidCommand("invalid R6 damage input") }
        let raw = input.power.multipliedReportingOverflow(by: input.coefficientBP)
        guard !raw.overflow else { throw CoreError.invalidCommand("R6 damage overflow") }
        let rawDamage = raw.partialValue / 10_000
        let k = (100 + 8 * (input.attackerLevel - 1)) * 10_000
        let reduction = max(0, min(3_000, input.specialReductionBP))
        let defenseCapped = Int64(input.defense) * 3 > Int64(k) * 7
        var numeratorFactors: [Int64] = [Int64(rawDamage), defenseCapped ? 3 : Int64(k), input.guarded ? 65 : 1, Int64(10_000 - reduction)]
        var denominatorFactors: [Int64] = [defenseCapped ? 10 : Int64(input.defense + k), input.guarded ? 100 : 1, 10_000]
        for ni in numeratorFactors.indices {
            for di in denominatorFactors.indices {
                let divisor = gcd(numeratorFactors[ni], denominatorFactors[di])
                numeratorFactors[ni] /= divisor; denominatorFactors[di] /= divisor
            }
        }
        var numerator: Int64 = 1, denominator: Int64 = 1
        for factor in numeratorFactors {
            let product = numerator.multipliedReportingOverflow(by: factor)
            guard !product.overflow else { throw CoreError.invalidCommand("R6 damage numerator overflow") }
            numerator = product.partialValue
        }
        for factor in denominatorFactors {
            let product = denominator.multipliedReportingOverflow(by: factor)
            guard !product.overflow else { throw CoreError.invalidCommand("R6 damage denominator overflow") }
            denominator = product.partialValue
        }
        return Int(numerator / denominator)
    }

    /// Emits the calculation record for one Python-R5 normal action using its
    /// stateless `crit.<actor>`/root label and post-defense HP-loss ordering.
    public static func normalAttackTrace(_ input: R6NormalAttackInput) throws -> R6NormalAttackTrace {
        guard !input.seed.isEmpty, !input.sourceID.isEmpty, !input.targetID.isEmpty,
              input.sourcePower >= 0, (1...60).contains(input.sourceLevel), input.targetHP >= 0,
              input.targetDefense >= 0, (0...10_000).contains(input.critChanceBP),
              input.critMultiplierBP >= 0, input.coefficientBP >= 0 else {
            throw CoreError.invalidCommand("invalid R6 normal attack trace input")
        }
        let label = try keyedLabel(domain: "crit.\(input.sourceID)", index: input.rootActionID)
        let roll = try keyedInt(seed: input.seed, label: label, upperBound: 10_000)
        let critical = roll < input.critChanceBP
        guard input.directBonusBP >= -10_000 else { throw CoreError.invalidCommand("negative R6 direct power") }
        var numeratorFactors = [input.coefficientBP, 10_000 + input.directBonusBP]
        var denominatorFactors = [10_000, 10_000]
        if critical { numeratorFactors.append(input.critMultiplierBP); denominatorFactors.append(10_000) }
        if input.targetMarked { numeratorFactors.append(10_600); denominatorFactors.append(10_000) }
        let raw = try multiplyDivideFloor(base: input.sourcePower, numeratorFactors: numeratorFactors, denominatorFactors: denominatorFactors)
        let damage = try incomingDamage(.init(power: raw, coefficientBP: 10_000, defense: input.targetDefense, attackerLevel: input.sourceLevel))
        return R6NormalAttackTrace(sourceID: input.sourceID, targetID: input.targetID, rootActionID: input.rootActionID,
                                   rawPower: raw, critRoll: roll, critical: critical, damage: damage, hpLoss: min(damage, input.targetHP))
    }

    public static func multiplyDivideFloor(base: Int, numeratorFactors: [Int], denominatorFactors: [Int]) throws -> Int {
        guard base >= 0, numeratorFactors.allSatisfy({ $0 >= 0 }), denominatorFactors.allSatisfy({ $0 > 0 }) else {
            throw CoreError.invalidCommand("invalid R6 rational product")
        }
        var numerators = [Int64(base)] + numeratorFactors.map(Int64.init)
        var denominators = denominatorFactors.map(Int64.init)
        for ni in numerators.indices {
            for di in denominators.indices {
                let divisor = gcd(numerators[ni], denominators[di])
                numerators[ni] /= divisor; denominators[di] /= divisor
            }
        }
        var numerator: Int64 = 1, denominator: Int64 = 1
        for factor in numerators {
            let result = numerator.multipliedReportingOverflow(by: factor)
            guard !result.overflow else { throw CoreError.invalidCommand("R6 rational numerator overflow") }
            numerator = result.partialValue
        }
        for factor in denominators {
            let result = denominator.multipliedReportingOverflow(by: factor)
            guard !result.overflow else { throw CoreError.invalidCommand("R6 rational denominator overflow") }
            denominator = result.partialValue
        }
        return Int(numerator / denominator)
    }

    /// Matches R6-B `guard_needed` once its forecast has computed danger and
    /// redirected incoming values. Returns a decision, not a live GameCommand.
    public static func smithShouldGuard(_ input: R6SmithGuardInput) -> Bool {
        guard !input.coverDisabled, input.smithHP > 0, input.smithMaxHP > 0,
              input.smithHP * 10_000 > input.smithMaxHP * 3_500,
              !(input.coverExpiryMs > input.nowMs && input.existingCoverCharges > 0) else { return false }
        return input.telegraphs.contains { telegraph in
            guard telegraph.targetIsAlive, !telegraph.isAOE,
                  telegraph.impactOffsetsMs.contains(where: { $0 >= 0 && $0 <= 1_500 }),
                  telegraph.targetIsDangerousWithoutCover else { return false }
            let estimated = telegraph.redirectedIncomingDamage.reduce(0, +)
            return max(0, estimated - input.smithBarrier) < input.smithHP
        }
    }

    /// Matches the R6-B non-urgent healing predicate and lowest-ratio,
    /// canonical actor-order tie break after already-reserved heals are applied.
    public static func apprenticeHealTarget(_ candidates: [R6HealCandidate]) -> String? {
        let eligible = candidates.compactMap { candidate -> (String, Int, Int)? in
            guard actorOrder.contains(candidate.actorID), candidate.maxHP > 0, candidate.hp > 0 else { return nil }
            let projectedAfterReserved = min(candidate.maxHP, candidate.hp + max(0, candidate.reservedHealing))
            guard projectedAfterReserved < candidate.maxHP,
                  (projectedAfterReserved * 10_000 <= candidate.maxHP * 7_000 || (candidate.danger && candidate.projectedHP * 10_000 <= candidate.maxHP * 3_500)) else { return nil }
            return (candidate.actorID, projectedAfterReserved, candidate.maxHP)
        }
        return eligible.min { lhs, rhs in
            let l = Int64(lhs.1) * Int64(rhs.2), r = Int64(rhs.1) * Int64(lhs.2)
            return l == r ? actorOrder.firstIndex(of: lhs.0)! < actorOrder.firstIndex(of: rhs.0)! : l < r
        }?.0
    }

    /// Matches `choose`: only a lethal ward outranks an available heal;
    /// otherwise heal precedes the ordinary predictive ward.
    public static func apprenticeChoice(healTargetID: String?, support: R6SupportAvailability) -> R6SupportChoice? {
        if support.wardReady, support.wardIsLethal, let target = support.wardTargetID {
            return R6SupportChoice(skillID: "SK_A_WARD", targetID: target)
        }
        if support.healReady, let target = healTargetID { return R6SupportChoice(skillID: "SK_A_HEAL", targetID: target) }
        if support.wardReady, let target = support.wardTargetID { return R6SupportChoice(skillID: "SK_A_WARD", targetID: target) }
        return nil
    }

    private static func pow2Mod256(_ modulus: UInt64) -> UInt64 {
        var value: UInt64 = 1
        for _ in 0..<256 { value = (value * 2) % modulus }
        return value
    }

    private static func twosComplement256(_ value: UInt64) -> [UInt8] {
        var output = Array(repeating: UInt8(0), count: 32)
        var remainder = value - 1
        for index in stride(from: 31, through: 0, by: -1) {
            output[index] = UInt8(truncatingIfNeeded: remainder)
            remainder >>= 8
        }
        return output.map { ~$0 }
    }

    private static func lexicographicallyLess(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        for index in lhs.indices where lhs[index] != rhs[index] { return lhs[index] < rhs[index] }
        return false
    }

    private static func gcd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = lhs, b = rhs
        while b != 0 { (a, b) = (b, a % b) }
        return max(1, a)
    }
}
