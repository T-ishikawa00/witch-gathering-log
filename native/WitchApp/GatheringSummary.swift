import SwiftUI

struct GatheringSummary {
    let materials: [(String, Int)]
    let currency: [(String, Int)]
    let experience: [(String, Int)]

    init(before: GameSnapshot, after: GameSnapshot) {
        func changes(_ old: [String: Int], _ new: [String: Int]) -> [(String, Int)] {
            new.keys.sorted().compactMap { key in
                let gain = new[key, default: 0] - old[key, default: 0]
                return gain > 0 ? (key, gain) : nil
            }
        }
        materials = changes(before.materials, after.materials)
        currency = changes(before.currency, after.currency)
        experience = changes(before.characterXP, after.characterXP)
    }
    var isEmpty: Bool { materials.isEmpty && currency.isEmpty && experience.isEmpty }
}

struct GatheringSummaryView: View {
    let summary: GatheringSummary
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
