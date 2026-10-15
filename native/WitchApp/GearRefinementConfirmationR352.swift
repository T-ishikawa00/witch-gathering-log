import SwiftUI

/// Opt-in, read-only preview for the separately versioned R352 rank track.
/// Dispatch remains the existing `.refine(gearID:)`; Core recomputes and validates the transition.
@MainActor
struct GearRefinementConfirmationR352: View {
    @ObservedObject var model: GameModel
    let catalog: GameCatalog
    let gearID: UUID
    let actorID: String
    let policy: NaturalGearRefinementPolicyR352
    let actorCanUseGear: Bool
    let isBusy: Bool
    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var openedRevision: Int64
    @State private var openedActorID: String

    private struct Projection {
        let gear: GearInstance
        let rank: Int
        let transition: NaturalGearRefinementPolicyR352.Transition
        let currentEnhancementCap: Int
        let nextEnhancementCap: Int
        let dustOwned: Int
        let gateEncounterID: String
        let gateName: String
        let gateComplete: Bool
        let materialRows: [(id: String, required: Int, owned: Int)]
        let blockers: [String]
        let before: GearStatsPresentation
        let after: GearStatsPresentation
    }

    private enum Evaluation {
        case projection(Projection)
        case blocked(String)
    }

    init(model: GameModel, catalog: GameCatalog, gearID: UUID, actorID: String,
         policy: NaturalGearRefinementPolicyR352, actorCanUseGear: Bool, isBusy: Bool,
         onApply: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.catalog = catalog
        self.gearID = gearID
        self.actorID = actorID
        self.policy = policy
        self.actorCanUseGear = actorCanUseGear
        self.isBusy = isBusy
        self.onApply = onApply
        self.onCancel = onCancel
        _openedRevision = State(initialValue: model.state.revision)
        _openedActorID = State(initialValue: actorID)
    }

    private var evaluation: Evaluation {
        guard model.state.revision == openedRevision, actorID == openedActorID else {
            return .blocked("所持品か仲間の選択が更新されました。閉じて開き直してください。")
        }
        guard model.state.partyActorIDs.contains(actorID), actorCanUseGear else {
            return .blocked("選んだ仲間はこの装備を使えません。")
        }
        guard let gear = model.state.gear.first(where: { $0.id == gearID }),
              catalog.gear.contains(where: { $0.id == gear.definitionID }) else {
            return .blocked("装備の情報を確認できません。")
        }
        let rank = model.state.naturalGearRefinementR352?.rank(for: gearID) ?? 1
        guard let transition = policy.transition(from: rank),
              transition.fromRank == rank, transition.toRank == rank + 1,
              transition.dustCost >= 0,
              transition.materialCosts.values.allSatisfy({ $0 >= 0 }) else {
            return .blocked("次の研成段階を安全に確認できません。")
        }
        let gateParts = transition.gateID.split(separator: "_")
        guard gateParts.count == 3, gateParts[0] == "G" else {
            return .blocked("次の解放条件を確認できません。")
        }
        let gateEncounterID = "B_\(gateParts[1])_\(gateParts[2])"
        guard let gateEnemy = catalog.enemies.first(where: { $0.id == gateEncounterID }),
              transition.materialCosts.keys.allSatisfy({ catalog.materialIDs.contains($0) }),
              let currentCap = policy.maximumEnhancement(forRank: rank),
              let nextCap = policy.maximumEnhancement(forRank: transition.toRank),
              policy.multiplierBasisPoints(forRank: rank) != nil,
              policy.multiplierBasisPoints(forRank: transition.toRank) != nil else {
            return .blocked("次の研成段階の性能上限を確認できません。")
        }
        let materials = transition.materialCosts.keys.sorted().map { id in
            (id: id, required: transition.materialCosts[id, default: 0], owned: model.state.materials[id, default: 0])
        }
        let dustOwned = model.state.materials["refine_dust", default: 0]
        guard dustOwned >= 0, materials.allSatisfy({ $0.owned >= 0 }) else {
            return .blocked("所持素材の情報を安全に確認できません。")
        }
        var blockers: [String] = []
        let gateComplete = model.state.completedEncounterIDs.contains(gateEncounterID)
        if !gateComplete {
            blockers.append("先に「\(gateEnemy.name)」を攻略してください。")
        }
        if dustOwned < transition.dustCost {
            blockers.append("研成の粉が不足しています（\(transition.dustCost - dustOwned) 個）。")
        }
        for row in materials where row.owned < row.required {
            blockers.append("\(GameText.name(row.id))が不足しています（\(row.required - row.owned) 個）。")
        }
        guard let before = try? model.comparisonStatsR352(gear, actorID: actorID, rank: rank),
              let after = try? model.comparisonStatsR352(gear, actorID: actorID, rank: transition.toRank) else {
            return .blocked("仲間の性能差を安全に計算できません。操作は保存していません。")
        }
        return .projection(Projection(gear: gear, rank: rank, transition: transition,
            currentEnhancementCap: currentCap, nextEnhancementCap: nextCap,
            dustOwned: dustOwned, gateEncounterID: gateEncounterID,
            gateName: gateEnemy.name, gateComplete: gateComplete,
            materialRows: materials, blockers: blockers, before: before, after: after))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(itemTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("次の研成段階と必要な条件を確認します。適用するまで保存されません。")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    switch evaluation {
                    case .blocked(let reason):
                        Text(reason).foregroundStyle(Palette.gold).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("r352_refine_blocked")
                    case .projection(let value):
                        projectionContent(value)
                    }
                    Button("適用する") { onApply() }
                        .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .disabled(isBusy || !isApplicable)
                        .accessibilityIdentifier("r352_refine_apply_\(gearID.uuidString)")
                    Button("キャンセル", role: .cancel) { onCancel() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("r352_refine_cancel_\(gearID.uuidString)")
                }.padding(20)
            }
            .navigationTitle("装備の研成")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }

    private var isApplicable: Bool {
        if case .projection(let value) = evaluation { return value.blockers.isEmpty }
        return false
    }

    private var itemTitle: String {
        guard let gear = model.state.gear.first(where: { $0.id == gearID }) else { return "装備" }
        return catalog.gear.first(where: { $0.id == gear.definitionID })?.name ?? gear.definitionID
    }

    @ViewBuilder private func projectionContent(_ value: Projection) -> some View {
        LabeledContent("研成段階", value: "\(rankName(value.rank)) → \(rankName(value.transition.toRank))")
        LabeledContent("次段階の強化上限", value: "+\(value.nextEnhancementCap)")
        Text("選んだ仲間に装備した場合").font(.subheadline).foregroundStyle(Palette.gold)
        LabeledContent("攻撃", value: "\(value.before.combatant.attack) → \(value.after.combatant.attack)")
        LabeledContent("体力", value: "\(value.before.combatant.maxHP) → \(value.after.combatant.maxHP)")
        LabeledContent("防御", value: "\(value.before.combatant.defense) → \(value.after.combatant.defense)")
        if value.before.combatant.attack == value.after.combatant.attack,
           value.before.combatant.maxHP == value.after.combatant.maxHP,
           value.before.combatant.defense == value.after.combatant.defense {
            Text("今回は能力値の増加はありません。研成後は強化上限が +\(value.currentEnhancementCap) から +\(value.nextEnhancementCap) になります。")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("r352_refine_cap_only_notice")
        }
        LabeledContent("攻略条件", value: "\(value.gateName)・\(value.gateComplete ? "達成済み" : "未達成")")
        LabeledContent("研成の粉", value: "必要 \(value.transition.dustCost) 個 / 所持 \(value.dustOwned) 個")
        ForEach(value.materialRows.indices, id: \.self) { index in
            let row = value.materialRows[index]
            LabeledContent(GameText.name(row.id), value: "必要 \(row.required) 個 / 所持 \(row.owned) 個")
        }
        if value.gear.refinement > 0 {
            Text("従来の研成補正 +\(value.gear.refinement)（保持）")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("r352_legacy_refinement_preserved")
        }
        if value.blockers.isEmpty {
            Text("必要な条件を満たしています。")
                .foregroundStyle(Palette.gold).accessibilityIdentifier("r352_refine_ready")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("適用には次の条件が必要です。")
                ForEach(value.blockers.indices, id: \.self) { index in
                    Text("• \(value.blockers[index])").fixedSize(horizontal: false, vertical: true)
                }
            }.foregroundStyle(Palette.gold).accessibilityIdentifier("r352_refine_blockers")
        }
    }

    private func rankName(_ rank: Int) -> String {
        switch rank {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        default: return "不明"
        }
    }
}
