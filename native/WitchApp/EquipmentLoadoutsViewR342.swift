import SwiftUI

/// Explicit development capability; creating a candidate does not adopt its scope.
enum EquipmentLoadoutsBuildPolicyR342 {
    static var enabled: Bool {
        #if STANDARD_PLAY_R169 && EQUIPMENT_LOADOUTS_R342
        true
        #else
        false
        #endif
    }
}

struct EquipmentLoadoutsViewR342: View {
    @ObservedObject var model: GameModel
    @State private var pending: PendingAction?

    private enum Kind { case save, apply, clear }
    private struct PendingAction {
        let kind: Kind
        let slot: GearLoadoutSlotR342
        var title: String {
            switch kind {
            case .save: "装備セット\(slot.rawValue)を上書きしますか？"
            case .apply: "装備セット\(slot.rawValue)に着替えますか？"
            case .clear: "装備セット\(slot.rawValue)の登録を解除しますか？"
            }
        }
        var button: String {
            switch kind {
            case .save: "現在の構成で上書きする"
            case .apply: "このセットを装備する"
            case .clear: "登録を解除する"
            }
        }
        var message: String {
            switch kind {
            case .save: "仲間全員の現在の装備を記録します。以前のセット登録は置き換わります。"
            case .apply: "仲間全員の装備をまとめて切り替えます。記録にない装備枠は外れます。装備の強化・進化は現在の状態が反映されます。"
            case .clear: "このセットの登録だけを解除します。装備と現在の構成はそのまま残ります。"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("旅の装備をまとめる").font(.system(.title, design: .serif))
            Text("仲間全員の装備を記録して、次の冒険に合わせて切り替えられます。")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("現在の構成：\(model.state.equippedGearIDs.count)点")
                .font(.caption).foregroundStyle(Palette.gold)
                .accessibilityIdentifier("loadout_current_count")
            ForEach([GearLoadoutSlotR342.first, .second], id: \.rawValue) { slot in
                slotCard(slot)
            }
            Text("セットへの登録だけでは分解を防げません。残したい装備は、持ちもの画面で保護してください。")
                .font(.caption).foregroundStyle(Palette.gold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(pending?.title ?? "装備セット", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible, presenting: pending) { action in
            Button(action.button, role: action.kind == .clear ? .destructive : nil) {
                execute(action)
            }
            Button("キャンセル", role: .cancel) { pending = nil }
        } message: { action in
            Text(action.message)
        }
    }

    private func slotCard(_ slot: GearLoadoutSlotR342) -> some View {
        let loadout = model.state.gearLoadoutsR342?.loadout(for: slot)
        let ids = Set(loadout?.gearByActorSlot.values.map { $0 } ?? [])
        let missing = ids.subtracting(Set(model.state.gear.map(\.id))).count
        let current = loadout?.gearByActorSlot == model.state.equippedGearIDs
        return VStack(alignment: .leading, spacing: 12) {
            Text("装備セット\(slot.rawValue)").font(.headline)
            if let loadout {
                Text(current ? "現在の構成と同じ" : "登録済み：\(loadout.gearByActorSlot.count)点")
                    .font(.caption).foregroundStyle(Palette.gold)
                    .accessibilityIdentifier("loadout_status_\(slot.rawValue)")
                ForEach(model.state.partyActorIDs, id: \.self) { actorID in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(GameModel.actorNames[actorID] ?? actorID).font(.subheadline)
                        Text(gearNames(for: actorID, loadout: loadout))
                            .font(.caption).foregroundStyle(Palette.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if missing > 0 {
                    Text("登録した装備が\(missing)点ありません。持ちものを確認し、現在の構成で登録し直してください。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("loadout_missing_\(slot.rawValue)")
                }
                Button { pending = PendingAction(kind: .apply, slot: slot) } label: {
                    actionText("このセットを装備する")
                }
                .disabled(model.busy || model.fighting || current || missing > 0)
                .accessibilityIdentifier("loadout_apply_\(slot.rawValue)")
            } else {
                Text("まだ登録されていません").font(.caption).foregroundStyle(Palette.gold)
                    .accessibilityIdentifier("loadout_status_\(slot.rawValue)")
            }
            Button {
                if loadout == nil { execute(PendingAction(kind: .save, slot: slot)) }
                else { pending = PendingAction(kind: .save, slot: slot) }
            } label: {
                actionText(loadout == nil ? "現在の構成を登録する" : "現在の構成で上書きする")
            }
            .disabled(model.busy || model.fighting || model.state.equippedGearIDs.isEmpty || current)
            .accessibilityIdentifier("loadout_save_\(slot.rawValue)")
            if loadout != nil {
                Button { pending = PendingAction(kind: .clear, slot: slot) } label: {
                    actionText("登録を解除する")
                }
                .disabled(model.busy || model.fighting)
                .accessibilityIdentifier("loadout_clear_\(slot.rawValue)")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 14))
        .buttonStyle(.bordered)
    }

    private func gearNames(for actorID: String, loadout: GearLoadoutR342) -> String {
        let names = loadout.gearByActorSlot.keys.sorted().filter { $0.hasPrefix(actorID + "|") }.map { key in
            guard let id = loadout.gearByActorSlot[key],
                  let item = model.state.gear.first(where: { $0.id == id }),
                  let definition = model.catalog?.gear.first(where: { $0.id == item.definitionID }) else {
                return "所持していない装備"
            }
            return "\(definition.name)（\(GameText.quality(item.qualityID))・+\(item.enhancement)・研成\(item.refinement)）"
        }
        return names.isEmpty ? "装備の登録なし" : names.joined(separator: "・")
    }

    private func actionText(_ value: String) -> some View {
        Text(value).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
    }

    private func execute(_ action: PendingAction) {
        guard EquipmentLoadoutsBuildPolicyR342.enabled, !model.busy, !model.fighting else { return }
        pending = nil
        switch action.kind {
        case .save:
            model.act(.saveGearLoadoutR342(slot: action.slot), "装備セット\(action.slot.rawValue)を登録しました。")
        case .apply:
            model.act(.applyGearLoadoutR342(slot: action.slot), "装備セット\(action.slot.rawValue)に切り替えました。")
        case .clear:
            model.act(.clearGearLoadoutR342(slot: action.slot), "装備セット\(action.slot.rawValue)の登録を解除しました。")
        }
    }
}
