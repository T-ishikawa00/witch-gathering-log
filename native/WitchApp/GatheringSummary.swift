import SwiftUI

struct GatheringSummary {
    let materials: [(String, Int)]
    let currency: [(String, Int)]
    let experience: [(String, Int)]
    let gainedGear: [GearInstance]
    private let gearNamesByDefinitionID: [String: String]

    init(before: GameSnapshot, after: GameSnapshot, catalog: GameCatalog? = nil) {
        func changes(_ old: [String: Int], _ new: [String: Int]) -> [(String, Int)] {
            new.keys.sorted().compactMap { key in
                let gain = new[key, default: 0] - old[key, default: 0]
                return gain > 0 ? (key, gain) : nil
            }
        }
        materials = changes(before.materials, after.materials)
        currency = changes(before.currency, after.currency)
        experience = changes(before.characterXP, after.characterXP)
        let priorGearIDs = Set(before.gear.map(\.id))
        gainedGear = after.gear.filter { !priorGearIDs.contains($0.id) }
        gearNamesByDefinitionID = Dictionary(uniqueKeysWithValues: (catalog?.gear ?? []).map { ($0.id, $0.name) })
    }

    func gearName(_ item: GearInstance) -> String {
        gearNamesByDefinitionID[item.definitionID] ?? item.definitionID
    }

    var isEmpty: Bool { materials.isEmpty && currency.isEmpty && experience.isEmpty && gainedGear.isEmpty }
}

struct GatheringSummaryView: View {
    let summary: GatheringSummary
    var onInspectAllNewGear: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(summary.isEmpty ? "採集は、ゆっくり進行中" : "今日も、小さな発見を。")
                .font(.system(size: 25, design: .serif))
            Text(summary.isEmpty ? "新しい成果はまだありません。探索先や採集する素材を選んで、仲間たちの帰りを待ちましょう。" : "仲間が持ち帰った成果をしまいました。")
                .font(.callout).foregroundStyle(Palette.gold)
            ForEach(summary.materials.map(\.0), id: \.self) { id in
                HStack {
                    AssetIcon(id: "ICO_" + id, size: 48)
                    Text(GameText.name(id)); Spacer()
                    Text("+\(summary.materials.first { $0.0 == id }?.1 ?? 0)").monospacedDigit()
                }
            }
            ForEach(summary.currency.map(\.0), id: \.self) { id in
                HStack { Text(GameText.name(id)); Spacer(); Text("+\(summary.currency.first { $0.0 == id }?.1 ?? 0)").monospacedDigit() }
            }
            if !summary.gainedGear.isEmpty {
                GainedGearSummaryR350(summary: summary, onInspectAll: onInspectAllNewGear)
            }
            if !summary.experience.isEmpty {
                Divider()
                ForEach(summary.experience.map(\.0), id: \.self) { id in
                    HStack {
                        Text(GameModel.actorNames[id] ?? id); Spacer()
                        Text("EXP +\(summary.experience.first { $0.0 == id }?.1 ?? 0)").monospacedDigit()
                    }.font(.caption)
                }
            }
            Text("成果は保存済みです。この画面を閉じても失われません。")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("gathering_summary")
    }
}


/// Shows only UUIDs newly present in the committed after-snapshot. The action is
/// navigation-only; callers may route these exact IDs to the existing opening inventory.
struct GainedGearSummaryR350: View {
    let summary: GatheringSummary
    var onInspectAll: (() -> Void)? = nil

    private var shown: [GearInstance] { Array(summary.gainedGear.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("新しく手に入れた装備 \(summary.gainedGear.count)点")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            ForEach(shown) { item in
                HStack(alignment: .center, spacing: 10) {
                    AssetIcon(id: "ICO_" + item.definitionID, size: 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.gearName(item))
                            .font(.body).fixedSize(horizontal: false, vertical: true)
                        Text(GameText.quality(item.qualityID))
                            .font(.caption).foregroundStyle(Palette.gold)
                    }
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("新しい装備、\(summary.gearName(item))、品質\(GameText.quality(item.qualityID))")
            }
            if let onInspectAll {
                Button(action: onInspectAll) {
                    Text("届いた装備をすべて見る（\(summary.gainedGear.count)）")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("gathering_inspect_all_new_gear_r350")
            }
        }
        .accessibilityIdentifier("gained_gear_summary_r350")
    }
}
