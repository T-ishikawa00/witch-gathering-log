import Foundation

enum GameText {
    static let materials:[String:String] = ["M_R01_G1": "しなり霊枝", "M_R01_G2": "露灯草", "M_R01_G3": "琥珀樹脂", "M_R01_G4": "月白苔", "M_R02_G1": "葦綿", "M_R02_G2": "月光花", "M_R02_G3": "澄み雫", "M_R02_G4": "霧結晶", "M_R03_G1": "響晶石", "M_R03_G2": "灰銀鉱", "M_R03_G3": "耐熱粘土", "M_R03_G4": "透光雲母", "M_R04_G1": "雪灯草", "M_R04_G2": "凍結晶", "M_R04_G3": "風編み麻", "M_R04_G4": "白陶石", "M_R05_G1": "古庭霊枝", "M_R05_G2": "月白糸", "M_R05_G3": "眠り種", "M_R05_G4": "月露晶", "M_R01_E1": "苔角片", "M_R01_E2": "灯糸", "M_R01_E3": "葉刃殻", "M_R01_E4": "琥珀の甲片", "M_R01_BA": "根絡みの牙", "M_R01_BB": "苔冠の生木核", "M_R02_E1": "眠り胞子", "M_R02_E2": "湿霧鱗", "M_R02_E3": "水鏡膜", "M_R02_E4": "月燐粉", "M_R02_BA": "夢茸の菌核", "M_R02_BB": "水鏡の冠鱗", "M_R03_E1": "銅殻片", "M_R03_E2": "鳴晶片", "M_R03_E3": "古合金の歯", "M_R03_E4": "磁紋鱗", "M_R03_BA": "連槌の駆動環", "M_R03_BB": "炉心晶", "M_R04_E1": "霜毛束", "M_R04_E2": "氷羽根", "M_R04_E3": "雪甲殻", "M_R04_E4": "霜晶歯輪", "M_R04_BA": "白角片", "M_R04_BB": "月氷の竜鱗", "M_R05_E1": "綴じ蔓", "M_R05_E2": "月銀片", "M_R05_E3": "封灯硝子", "M_R05_E4": "夜花蜜", "M_R05_BA": "剪定輪の欠片", "M_R05_BB": "月庭の種核", "refine_dust": "研成の粉", "coin": "コイン", "ticket_free": "無料鑑定券"]
    static func name(_ id:String)->String {materials[id] ?? id}
    static func quality(_ id:String)->String {["Q0":"C","Q1":"R","Q2":"SR","Q3":"UR","Q4":"LR"][id] ?? id}
    static func challengeMechanic(_ id:String,fallback:String)->String {
        ["CH_R01_01":"重い一撃と、攻撃後の長い隙",
         "CH_R03_01":"繰り返す攻撃と、一度に続く連撃",
         "CH_R04_01":"一体を狙う重い一撃と通常攻撃",
         "CH_R05_01":"身構え、攻撃、立て直しの拍子",
         "CH_R05_03":"これまで出会った仕掛けが二つずつ重なる"][id] ?? fallback
    }
    static func effect(_ id:String)->String {
        if id.hasPrefix("AF_"), GearLatentText.name(id) != "効果を確認できません" { return GearLatentText.name(id) }
        return ["ECHO_BONUS_2000BP":"こだまの威力強化","BARRIER_REFLECT":"結界反射","BARRIER_WARD":"結界の護り","WARD_REPLACES_SEED":"毒の種スキルを使わない","FAMILIAR_CHASE":"使い魔の追撃","FAMILIAR_CHASE_ICD_1500MS":"追撃の間隔短縮","FAMILIAR_DASH_BONUS_6000BP":"跳びかかり強化","FAMILIAR_MARK_10S":"追跡の印","HEAL_LINK":"回復の連鎖","HEAL_TO_BARRIER":"余剰回復の結界化","POISON_BURST_25_AT_5":"毒が深まった敵への追い打ち","POISON_SHATTER":"毒の崩壊","POISON_STACK":"毒の蓄積","POISON_STACK_CAP_2":"毒の上限拡張","SMITH_COVER_BARRIER":"かばう結界","SMITH_PRESSURE":"響き槌の蓄圧","AFFIX_POWER_TEST":"攻撃の副効果","AFFIX_GUARD_TEST":"守備の副効果","AFFIX_VITALITY_TEST":"体力の副効果","LATENT_TEST_01":"力の潜在","LATENT_POWER_TEST":"力の潜在","LATENT_GUARD_TEST":"守りの潜在","LATENT_VITALITY_TEST":"生命の潜在"][id] ?? id
    }
    static func error(_ value:Error)->String {
        if let latent = value as? CandidateLatentPolicyErrorR003 {
            if case .incompatibleEvolution(let id) = latent {
                return GearLatentText.name(id) + "を保持できない進化先です。別の装備を進化させてください。"
            }
            return "装備の潜在効果を確認できません。この操作は保存していません。"
        }
        guard let e=value as? CoreError else{return "操作を保存できませんでした。もう一度お試しください。"}
        switch e {
        case .insufficientResource(let id):return name(id.replacingOccurrences(of:"insufficient ",with:""))+"が足りません。採集・探索で集めましょう。"
        case .protectedGear:return "保護中の装備です。保護を解除してから分解してください。"
        case .gearInUse:return "使用中の装備です。別の装備へ変更してから分解してください。"
        case .revisionConflict:return "別の操作で保存が更新されました。最新の状態を読み直しました。"
        case .invalidCommand(let detail):
            if detail.hasPrefix("R342") {return "装備セットを使えませんでした。持ちものと装備できる仲間を確認し、現在の構成で登録し直してください。"}
            if detail.contains("gacha") || detail.contains("comparison"){return "まず工房で装備を作り、同じ部位の装備を比較しましょう。"}
            if detail.contains("gate") || detail.contains("previous encounter"){return "先に手前のボスを乗り越える必要があります。"}
            if detail.contains("daily"){return "今日の無料券は受取済みです。次の日をお待ちください。"}
            if detail.contains("work unit"){return "まだ採集の途中です。時間をおいて成果を受け取りましょう。"}
            if detail.contains("owner") || detail.contains("actor") {return "この仲間には装備できません。装備できる仲間を選んでください。"}
            return "この操作の条件をまだ満たしていません。装備・素材・探索の進み具合をご確認ください。"
        default:return "処理を完了できませんでした。保存データは保持しています。"
        }
    }
}
