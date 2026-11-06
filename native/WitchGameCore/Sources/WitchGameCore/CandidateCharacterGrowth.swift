import Foundation

/// An explicit experiment bridging R2 relative growth into the smaller campaign
/// stat scale. This is not an adopted balance profile or a save-format change.
public struct CandidateCharacterGrowth: Sendable, Equatable {
    public struct Progress: Sendable, Equatable {
        public let level: Int
        public let totalXP: Int
        public let xpIntoLevel: Int
        public let xpToNextLevel: Int?
        public let levelStartXP: Int
    }

    public let strengthBP: Int
    public var id: String { "R017_R2_RELATIVE_GROWTH_\(strengthBP)BP" }
    public let status = "UNAPPROVED_TEST_OVERLAY"
    public static let levelCap = 60
    public static let fullRelativeR2 = CandidateCharacterGrowth(strengthBP: 10_000)
    public static let quarterRelativeR2 = CandidateCharacterGrowth(strengthBP: 2_500)
    public static let zeroStatControl = CandidateCharacterGrowth(strengthBP: 0)

    public init(strengthBP: Int) {
        self.strengthBP = min(10_000, max(0, strengthBP))
    }

    /// At most 59 iterations, including Int.max XP. Surplus XP is retained.
    public static func progress(totalXP: Int) -> Progress {
        let total = max(0, totalXP)
        var level = 1
        var start = 0
        while level < levelCap {
            let step = level - 1
            let required = 100 + 30 * step + 4 * step * step
            if total - start < required {
                return Progress(level: level, totalXP: total, xpIntoLevel: total - start,
                                xpToNextLevel: required - (total - start), levelStartXP: start)
            }
            start += required
            level += 1
        }
        return Progress(level: level, totalXP: total, xpIntoLevel: total - start,
                        xpToNextLevel: nil, levelStartXP: start)
    }

    public struct BaseStats: Sendable, Equatable {
        public let hp: Int
        public let attack: Int
        public let defense: Int
    }

    /// Preserves the campaign's Lv1 base, applying the R2 actor-specific ratio
    /// before existing gear and research additions. Fixed-profile R6 is separate.
    public func projectBase(actorID: String, totalXP: Int,
                            nativeHP: Int, nativeAttack: Int, nativeDefense: Int) -> BaseStats {
        let source: (hp: Int, power: Int, defense: Int, hpGain: Int, powerGain: Int, defenseGain: Int)
        switch actorID {
        case "C_WITCH": source = (420, 38, 28, 32, 4, 4)
        case "C_APPRENTICE": source = (360, 30, 26, 28, 3, 4)
        case "C_SMITH": source = (620, 28, 52, 44, 3, 6)
        case "C_FAMILIAR": source = (390, 32, 30, 30, 3, 4)
        default: return BaseStats(hp: nativeHP, attack: nativeAttack, defense: nativeDefense)
        }
        let steps = Self.progress(totalXP: totalXP).level - 1
        func scaled(_ base: Int, _ sourceBase: Int, _ gain: Int) -> Int {
            // Real native bases are small constants. Saturating arithmetic also
            // prevents malformed diagnostic inputs from trapping this projection.
            let multiplier = gain * steps * strengthBP
            let (product, overflow) = base.multipliedReportingOverflow(by: multiplier)
            guard !overflow else { return base >= 0 ? Int.max : Int.min }
            let delta = product / (sourceBase * 10_000)
            let (result, additionOverflow) = base.addingReportingOverflow(delta)
            return additionOverflow ? (base >= 0 ? Int.max : Int.min) : result
        }
        return BaseStats(hp: scaled(nativeHP, source.hp, source.hpGain),
                         attack: scaled(nativeAttack, source.power, source.powerGain),
                         defense: scaled(nativeDefense, source.defense, source.defenseGain))
    }
}
