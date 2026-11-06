import SwiftUI

struct GearLatentDetailsView: View {
    @ObservedObject var model: GameModel
    let item: GearInstance

    var body: some View {
        if item.candidateLatentSlots == nil {
            VStack(alignment: .leading, spacing: 5) {
                Text("潜在枠の情報なし").foregroundStyle(Palette.gold)
                if let oldEffect = item.latentEffectID { Text(GameText.effect(oldEffect)) }
                ForEach(Array(item.affixIDs.enumerated()), id: \.offset) { _, effect in
                    Text(GameText.effect(effect))
                }
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gear_" + item.id.uuidString + "_legacy_latent")
        } else if !model.canWearDefinition(item.definitionID) {
            Text("装備できる仲間を選ぶと、潜在効果を確認できます。")
                .font(.caption).foregroundStyle(Palette.gold)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            switch Result(catching: { (try model.latentDisplay(for: item), try model.comparisonStats(item)) }) {
            case .success(let (display, preview)):
                GearLatentSlotsView(rows: GearLatentText.rows(from: display, effectIDs: preview.combatant.effectIDs),
                    actorName: GameModel.actorNames[model.selectedActor] ?? "仲間",
                    identifier: "gear_" + item.id.uuidString)
            case .failure:
                Text("この装備の潜在効果を確認できません。")
                    .font(.caption).foregroundStyle(Palette.gold)
                    .accessibilityIdentifier("gear_" + item.id.uuidString + "_latent_error")
            }
        }
    }
}

struct GearLatentSlotsView: View {
    let rows: [GearLatentRowModel]
    let actorName: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("潜在効果").font(.subheadline).foregroundStyle(Palette.gold)
            Text(actorName + "が装備したとき").font(.caption).foregroundStyle(Palette.text)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbol(row.availability)).accessibilityHidden(true)
                        Text("\(row.id + 1). " + row.title).fontWeight(.medium)
                        Spacer(minLength: 0)
                    }
                    Text(row.value + " · " + row.status).foregroundStyle(row.availability == .active ? Palette.gold : Palette.text)
                    Text(row.detail).foregroundStyle(Palette.text)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Palette.gold.opacity(row.availability == .active ? 0.09 : 0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier + "_latent_\(row.id)")
            }
        }
    }

    private func symbol(_ state: GearLatentRowModel.Availability) -> String {
        switch state {
        case .active: return "sparkle"
        case .locked: return "lock"
        case .otherActor: return "person.2"
        case .invalidStored: return "exclamationmark.triangle"
        case .unavailableLoadout: return "pause.circle"
        }
    }
}

/// Totals already capped by the shared combat projector. Never recompute combat here.
struct GearLatentAggregateView: View {
    let projection: CandidateLatentActorProjectionR005
    let actorID: String
    let effectIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("装着時の補正・確率").foregroundStyle(Palette.gold)
            Text("仲間の基礎値を含みます。").foregroundStyle(Palette.text)
            ForEach(projection.cappedValuesBP.keys.sorted(), id: \.self) { stat in
                if let value = projection.cappedValuesBP[stat], value > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(GearLatentText.statName(stat) + " " + GearLatentText.percent(value))
                        if let affixID = ["dot_bonus_bp": "AF_DOT", "barrier_bonus_bp": "AF_WARD", "chase_bonus_bp": "AF_CHASE"][stat],
                           !GearLatentText.mechanicAvailable(affixID, actorID: actorID, effectIDs: effectIDs) {
                            Text("今の装備構成では発動しません").foregroundStyle(Palette.gold)
                        }
                        if let overflow = projection.overflowBP[stat], overflow > 0 {
                            Text("上限に到達 · " + GearLatentText.percent(overflow) + "分は加算されません")
                                .foregroundStyle(Palette.gold)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
        }.font(.caption)
    }
}
