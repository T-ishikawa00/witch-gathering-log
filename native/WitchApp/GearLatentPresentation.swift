import Foundation

/// Display-only values. The Core policy owns activation and actor compatibility.
struct GearLatentRowModel: Identifiable, Equatable {
    enum Availability: Equatable {
        case active
        case locked(unlockQuality: String)
        case otherActor
        case invalidStored
        case unavailableLoadout
    }
    let id: Int
    let affixID: String
    let valueBP: Int
    let availability: Availability
    let hasQualityFloor: Bool

    var title: String { GearLatentText.name(affixID) }
    var value: String { "+" + GearLatentText.percent(valueBP) }
    var status: String {
        switch availability {
        case .active: return "有効"
        case .locked(let quality): return quality + "で解放"
        case .otherActor: return "他の仲間向け"
        case .invalidStored: return "装備の効果を確認できません"
        case .unavailableLoadout: return "構成待ち"
        }
    }
    var detail: String {
        switch availability {
        case .active: return hasQualityFloor ? "LRの最低値を適用" : GearLatentText.explanation(affixID)
        case .locked: return "今は性能に加算されません"
        case .otherActor: return "選んだ仲間には加算されません"
        case .invalidStored: return "この装備の情報を確認する必要があります"
        case .unavailableLoadout: return "今の装備構成では発動しません"
        }
    }
}

enum GearLatentText {
    static func statName(_ id: String) -> String {
        let names = ["hp_pct": "生命", "power_pct": "威力", "defense_pct": "防護",
                     "crit_chance_bp": "会心率", "crit_multiplier_bp": "会心時の倍率",
                     "haste_bp": "手数", "cdr_bp": "再使用短縮", "direct_bonus_bp": "直接攻撃",
                     "dot_bonus_bp": "呪毒", "heal_bonus_bp": "回復", "barrier_bonus_bp": "結界",
                     "guard_chance_bp": "受け流し", "counter_bonus_bp": "反撃", "chase_bonus_bp": "追撃",
                     "debuff_duration_resist_bp": "弱体耐性", "periodic_resist_bp": "持続耐性"]
        return names[id] ?? "効果"
    }

    static func mechanicAvailable(_ affixID: String, actorID: String, effectIDs: Set<String>) -> Bool {
        switch affixID {
        case "AF_DOT": return actorID == "C_WITCH" && effectIDs.contains("POISON_STACK") && !effectIDs.contains("WARD_REPLACES_SEED")
        case "AF_WARD": return actorID == "C_APPRENTICE" || (actorID == "C_WITCH" && effectIDs.contains("BARRIER_WARD"))
        case "AF_CHASE": return actorID == "C_FAMILIAR" && effectIDs.contains("FAMILIAR_CHASE")
        default: return true
        }
    }

    static func rows(from display: CandidateLatentItemDisplayR005, effectIDs: Set<String>) -> [GearLatentRowModel] {
        display.slots.map { slot in
            let state: GearLatentRowModel.Availability
            switch slot.state {
            case .active:
                state = mechanicAvailable(slot.affixID, actorID: display.actorID, effectIDs: effectIDs) ? .active : .unavailableLoadout
            case .qualityLocked:
                state = .locked(unlockQuality: ["R", "SR", "UR"].indices.contains(slot.id) ? ["R", "SR", "UR"][slot.id] : "上位品質")
            case .actorIncompatible: state = .otherActor
            case .invalidStored: state = .invalidStored
            }
            return GearLatentRowModel(id: slot.id, affixID: slot.affixID, valueBP: slot.valueBP,
                                      availability: state, hasQualityFloor: slot.effectiveQ > slot.rawQ)
        }
    }

    static func name(_ id: String) -> String {
        ["AF_HP": "生命", "AF_POWER": "威力", "AF_DEF": "防護",
         "AF_CRIT": "会心率", "AF_CRIT_DMG": "会心威力", "AF_HASTE": "手数",
         "AF_CDR": "再使用短縮", "AF_DIRECT": "直接攻撃", "AF_DOT": "呪毒",
         "AF_HEAL": "回復", "AF_WARD": "結界", "AF_GUARD": "受け流し",
         "AF_COUNTER": "反撃", "AF_CHASE": "追撃", "AF_STATUS_RESIST": "弱体耐性",
         "AF_DOT_RESIST": "持続耐性"][id] ?? "効果を確認できません"
    }

    static func explanation(_ id: String) -> String {
        switch id {
        case "AF_HP": return "最大体力を増やす"
        case "AF_POWER": return "攻撃の威力を増やす"
        case "AF_DEF": return "防御を増やす"
        case "AF_CRIT": return "会心の確率に加算"
        case "AF_CRIT_DMG": return "会心時の倍率に加算"
        case "AF_HASTE": return "通常攻撃の間隔を短くする"
        case "AF_CDR": return "技能の再使用を早める"
        case "AF_DIRECT": return "直接与えるダメージを増やす"
        case "AF_DOT": return "呪毒のダメージを増やす"
        case "AF_HEAL": return "回復量を増やす"
        case "AF_WARD": return "結界の吸収量を増やす"
        case "AF_GUARD": return "受け流しの確率に加算"
        case "AF_COUNTER": return "受け流し・かばう時の反撃を強める"
        case "AF_CHASE": return "毒・印と味方の技能が揃った時の追撃を強める"
        case "AF_STATUS_RESIST": return "弱体の持続時間を短くする"
        case "AF_DOT_RESIST": return "受ける持続ダメージを減らす"
        default: return "効果を確認できません"
        }
    }

    /// Exact integer basis points, without locale-dependent rounding or Int.min abs.
    static func percent(_ basisPoints: Int) -> String {
        let magnitude = basisPoints.magnitude
        let whole = magnitude / 100
        let fraction = magnitude % 100
        let sign = basisPoints < 0 ? "−" : ""
        if fraction == 0 { return "\(sign)\(whole)%" }
        if fraction % 10 == 0 { return "\(sign)\(whole).\(fraction / 10)%" }
        return "\(sign)\(whole)." + (fraction < 10 ? "0" : "") + "\(fraction)%"
    }
}
