import SwiftUI

/// Uses the saved gathering start/remainder; it does not advance the game clock.
struct GatheringProgressViewR041: View {
    let catalog: GameCatalog
    let state: GameSnapshot
    var showMaterialName = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = GatheringProgressProjectionR041.read(catalog: catalog, state: state, now: context.date)
            Group {
                switch status {
                case .collecting(let reading):
                    VStack(alignment: .leading, spacing: 4) {
                        if showMaterialName {
                            Text(reading.readyUnits > 0
                                 ? "持ち帰れる\(GameText.name(reading.materialID)): \(reading.readyUnits)個"
                                 : "\(GameText.name(reading.materialID))を探しています")
                        } else if reading.readyUnits > 0 {
                            Text("持ち帰れる素材: \(reading.readyUnits)個")
                        }
                        if reading.reachedCap {
                            Text("採集の保管上限です。成果を受け取ると、また蓄えられます。")
                        } else {
                            Text("次の素材まで " + duration(reading.secondsUntilNextUnit))
                                .monospacedDigit()
                        }
                    }
                case .clockBehind:
                    Text("採集時刻を確認できません。端末の日時をご確認ください。")
                case .unavailable:
                    Text("探索で採集する素材を選んでください。")
                case .inactive:
                    Text("探索に出発すると、素材が少しずつ集まります。")
                }
            }
            .font(.caption).foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gathering_progress")
        }
    }

    private func duration(_ seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600)時間\((seconds % 3600) / 60)分" }
        return "\(seconds / 60)分\(seconds % 60)秒"
    }
}
