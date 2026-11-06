import SwiftUI
import SpriteKit

/// S40–S48 of the approved UI48 set. This view owns screen content only; the
/// shared UI48 shell supplies navigation, title, and the five game entrances.
struct UI48LifestyleView: View {
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    let screen: Int

    @ViewBuilder var body: some View {
        switch screen {
        case 40: UI48WardrobeScreen(model: model, flow: flow, weapon: false)
        case 41: UI48WardrobeScreen(model: model, flow: flow, weapon: true)
        case 42: UI48FurnitureScreen(model: model)
        case 43: UI48ShopScreen(model: model, flow: flow)
        case 44: UI48ProductScreen(model: model, flow: flow)
        case 45: UI48PurchaseScreen(model: model, flow: flow)
        case 46: UI48SettingsScreen(model: model, flow: flow)
        case 47: UI48RecoveryScreen(model: model, flow: flow)
        case 48: UI48StartupScreen(model: model, flow: flow)
        default:
            UI48Page { UI48Note(text: "この画面は準備中です。") }
        }
    }
}

@MainActor private enum UI48LifestyleNames {
    static let appearances: [String: String] = [
        "ERNA_TRAVEL": "露草色の旅支度",
        "STAFF_BRANCH": "若枝の杖",
        "STAFF_MOON": "月環の杖"
    ]

    static func appearance(_ id: String) -> String {
        appearances[id] ?? id
    }

    static func catalogAppearance(_ appearance: AppearanceDefinition) -> String {
        if let known = appearances[appearance.id] { return known }
        let actor = appearance.actorIDs.first.flatMap { GameModel.actorNames[$0] } ?? "仲間"
        return "\(actor)の\(appearance.kind == "weapon" ? "武器外観" : "衣装")候補"
    }

    static func isUnapproved(_ appearance: AppearanceDefinition) -> Bool {
        appearance.status.uppercased().contains("UNAPPROVED") ||
            appearance.status.uppercased().contains("CANDIDATE")
    }
}

@MainActor
private struct UI48WardrobeScreen: View {
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let weapon: Bool
    @State private var actorID = "C_WITCH"
    @State private var previewID: String?
    @State private var applying = false

    private var kind: String { weapon ? "weapon" : "costume" }
    private var availableActors: [String] {
        model.state.partyActorIDs
    }
    private var appearances: [AppearanceDefinition] {
        (model.catalog?.appearances ?? [])
            .filter { $0.kind == kind && $0.actorIDs.contains(actorID) }
            .sorted { $0.id < $1.id }
    }
    private func displayName(_ appearance: AppearanceDefinition) -> String {
        UI48LifestyleNames.catalogAppearance(appearance)
    }
    private var previewOverrides: [String: String] {
        var result = model.sceneAppearance
        if let previewID {
            if weapon {
                result["WITCH_WEAPON"] = previewID
            } else {
                result[actorID] = previewID
            }
        }
        return result
    }
    private var selectedID: String? {
        weapon ? model.state.selectedWeaponAppearanceIDs[actorID]
            : model.state.selectedCosmeticIDs[actorID]
    }

    private var weaponPreviewAssetID: String? {
        if let previewID { return previewID }
        if let selectedID { return selectedID }
        if actorID == "C_WITCH", let resolved = model.sceneAppearance["WITCH_WEAPON"] {
            return resolved
        }
        guard let equippedID = model.state.equippedGearIDs[actorID + "|weapon"],
              let item = model.state.gear.first(where: { $0.id == equippedID }) else { return nil }
        return "ICO_" + item.definitionID
    }

    var body: some View {
        UI48Page {
            supportedActorStrip
                .onChange(of: model.selectedActor) { _, newValue in
                    if availableActors.contains(newValue) { actorID = newValue }
                    previewID = nil
                }
                .onChange(of: actorID) { _, _ in previewID = nil }

            UI48Panel {
                if weapon {
                    ZStack {
                        Circle().stroke(UI48Theme.gold.opacity(0.35), lineWidth: 1)
                            .frame(width: 232, height: 232)
                        Circle().stroke(UI48Theme.gold.opacity(0.15), lineWidth: 1)
                            .frame(width: 252, height: 252)
                        if let assetID = weaponPreviewAssetID {
                            AssetIcon(id: assetID, size: 230)
                                .accessibilityIdentifier("ui48_weapon_preview_art_" + assetID)
                        } else {
                            Text("装備中の武器はありません").font(.body)
                        }
                    }.frame(maxWidth: .infinity).frame(height: 280)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("武器の見た目")
                        .accessibilityIdentifier("ui48_weapon_hero_" + (weaponPreviewAssetID ?? "empty"))
                } else {
                WardrobePortrait(model: model, actorID: actorID, appearanceOverrides: previewOverrides, spotlight: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(UI48Frame(radius: 18))
                    .overlay(UI48Frame(radius: 18).stroke(UI48Theme.gold, lineWidth: 1))
                }
                Text(previewID == nil ? "現在の見た目" : "試着中／まだ保存していません")
                    .font(.caption).foregroundStyle(UI48Theme.gold).frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                wardrobeTab("衣装", selected: !weapon) { flow.go(40) }
                wardrobeTab("武器の見た目", selected: weapon) { flow.go(41) }
            }
            .padding(3)
            .background(UI48Theme.ink)
            .clipShape(UI48Frame(radius: 12))
            .overlay(UI48Frame(radius: 12).stroke(UI48Theme.gold.opacity(0.55), lineWidth: 1))

            if let previewID, let appearance = appearances.first(where: { $0.id == previewID }) {
                let owned = model.state.ownedCosmeticIDs.contains(appearance.id)
                UI48Panel(title: displayName(appearance)) {
                    Text("\(weapon ? "武器の見た目" : "衣装") · \(GameModel.actorNames[actorID] ?? "仲間")")
                        .font(.subheadline)
                    if UI48LifestyleNames.isUnapproved(appearance) {
                        UI48Note(text: "試着用の見た目です。試着だけでは所持状態や現在の衣装は変わりません。")
                    }
                    if !owned {
                        UI48Note(text: "未所有のため保存できません。試着だけ行えます。")
                    }
                }
            }
            if appearances.isEmpty {
                UI48Panel(title: "試着できる見た目") {
                    UI48Note(text: "この仲間の着替えは、まだ用意されていません。")
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 150), spacing: 10)], spacing: 10) {
                    ForEach(appearances) { appearance in
                        let owned = model.state.ownedCosmeticIDs.contains(appearance.id)
                        let isSelected = selectedID == appearance.id
                        Button {
                            previewID = appearance.id
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    UI48Frame(radius: 10).fill(UI48Theme.ink)
                                    AssetIcon(id: appearance.id + (appearance.kind == "costume" ? "__idle" : ""), size: 82)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    if !owned {
                                        Image(systemName: "lock.fill").font(.caption2).padding(6)
                                            .foregroundStyle(UI48Theme.ivory).accessibilityHidden(true)
                                    }
                                }
                                .frame(width: 88, height: 88)
                                .overlay(UI48Frame(radius: 10).stroke(UI48Theme.gold.opacity(0.7), lineWidth: 1))
                Text(displayName(appearance))
                                    .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                Text(isSelected ? "適用中" : (owned ? "所持済み" : "未所有・試着のみ"))
                                    .font(.caption2).foregroundStyle(UI48Theme.muted)
                                if UI48LifestyleNames.isUnapproved(appearance) {
                                    Text("開発候補")
                                        .font(.caption2).foregroundStyle(UI48Theme.gold)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
                            .padding(9)
                            .background(UI48Theme.raised.opacity(0.75))
                            .clipShape(UI48Frame(radius: 13))
                        .overlay(UI48Frame(radius: 13).stroke(previewID == appearance.id ? UI48Theme.gold : UI48Theme.gold.opacity(0.55), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ui48_preview_\(appearance.id)")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let previewID, let appearance = appearances.first(where: { $0.id == previewID }) {
                let owned = model.state.ownedCosmeticIDs.contains(appearance.id)
                UI48ActionDock {
                    if owned {
                        UI48Action(title: applying ? "保存しています…" : "この見た目を使う", symbol: "checkmark",
                                   disabled: applying || model.busy || isSelected(appearance.id),
                                   id: "ui48_wardrobe_apply_\(appearance.id)") {
                            apply(appearance)
                        }
                    }
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 8) { wardrobeSecondaryActions }
                        } else {
                            HStack(spacing: 8) { wardrobeSecondaryActions }
                        }
                    }
                }
            }
        }
        .onAppear {
            if availableActors.contains(model.selectedActor) {
                actorID = model.selectedActor
            } else if let first = availableActors.first {
                actorID = first
                model.selectedActor = first
            }
        }
    }

    private var supportedActorStrip: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(availableActors, id: \.self) { actor in wardrobeActorButton(actor, large: true) }
                    }
                    .padding(.horizontal, 2)
                }
                .accessibilityIdentifier("ui48_wardrobe_actor_strip_large_text")
            } else {
                HStack(spacing: 8) {
                    ForEach(availableActors, id: \.self) { actor in wardrobeActorButton(actor, large: false) }
                }
            }
        }
    }

    @ViewBuilder private var wardrobeSecondaryActions: some View {
        UI48Action(title: "試着を取り消す", symbol: "xmark", secondary: true,
                   disabled: applying || model.busy, id: "ui48_wardrobe_cancel_trial") {
            previewID = nil
        }
        UI48Action(title: "標準の見た目に戻す", symbol: "arrow.uturn.backward", secondary: true,
                   disabled: applying || model.busy || selectedID == nil, id: "ui48_wardrobe_reset") {
            reset()
        }
    }

    private func wardrobeActorButton(_ actor: String, large: Bool) -> some View {
        Button {
            actorID = actor
            model.selectedActor = actor
        } label: {
            VStack(spacing: large ? 9 : 5) {
                UI48Portrait(actorID: actor, size: large ? 72 : 43)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(UI48Theme.gold, lineWidth: actorID == actor ? 2 : 0.6))
                Text(GameModel.actorNames[actor] ?? actor)
                    .font(large ? .body : .caption2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: large, vertical: !large)
            }
            .frame(minWidth: large ? 170 : nil, maxWidth: large ? nil : .infinity, minHeight: large ? 118 : 64)
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) { if actorID == actor { Rectangle().fill(UI48Theme.gold).frame(height: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui48_wardrobe_actor_\(actor)")
        .accessibilityAddTraits(actorID == actor ? .isSelected : [])
    }

    private func isSelected(_ id: String) -> Bool { selectedID == id }

    private func wardrobeTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? UI48Theme.paperInk : UI48Theme.ivory)
                .background(selected ? UI48Theme.gold : Color.clear)
                .clipShape(UI48Frame(radius: 9))
        }.buttonStyle(.plain)
    }

    private func apply(_ appearance: AppearanceDefinition) {
        guard !applying, !model.busy, model.state.ownedCosmeticIDs.contains(appearance.id),
              appearance.actorIDs.contains(actorID), let engine = model.engine else { return }
        applying = true
        model.busy = true
        let before = model.state
        let command: GameCommand = weapon
            ? .selectWeaponAppearance(actorID: actorID, appearanceID: appearance.id)
            : .selectCosmetic(actorID: actorID, cosmeticID: appearance.id)
        Task {
            do {
                _ = try await engine.dispatchConfirmingSavedReceipt(command, operationID: UUID(), expectedRevision: before.revision)
                await model.refresh()
                previewID = nil
                model.notice = "見た目を保存しました。装備性能は変わりません。"
            } catch {
                model.error = model.commandErrorText(error)
                await model.refresh()
            }
            applying = false
            model.busy = false
        }
    }

    private func reset() {
        guard !applying, !model.busy, let engine = model.engine else { return }
        applying = true
        model.busy = true
        let before = model.state
        let command: GameCommand = weapon
            ? .selectWeaponAppearance(actorID: actorID, appearanceID: nil)
            : .selectCosmetic(actorID: actorID, cosmeticID: nil)
        Task {
            do {
                _ = try await engine.dispatchConfirmingSavedReceipt(command, operationID: UUID(), expectedRevision: before.revision)
                await model.refresh()
                previewID = nil
                model.notice = "標準の見た目に戻しました。"
            } catch {
                model.error = model.commandErrorText(error)
                await model.refresh()
            }
            applying = false
            model.busy = false
        }
    }
}

@MainActor
private struct UI48FurnitureScreen: View {
    @ObservedObject var model: GameModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedID: String?
    @State private var previewingID: String?
    @State private var previewScene = LivingScene(size: CGSize(width: 360, height: 430))
    @State private var applying = false

    private var furnitureIDs: [String] { model.catalog?.furnitureIDs.sorted() ?? [] }
    private var activeID: String? { selectedID ?? model.state.placedFurnitureIDs.sorted().first ?? furnitureIDs.first }
    private var previewFurniture: Set<String> {
        guard let previewingID else { return model.state.placedFurnitureIDs }
        return model.state.placedFurnitureIDs.union([previewingID])
    }

    var body: some View {
        UI48Page {
            UI48Heading(title: "暮らしを整える", subtitle: "配置を試してから、所持済みの家具だけ保存できます。")
            UI48Panel {
                if furnitureIDs.isEmpty {
                    UI48Note(text: "いま表示できる家具がありません。")
                } else {
                    if previewingID == nil, let activeID {
                        UI48Action(title: "家具を選んで試し置き", symbol: "chair.lounge.fill", id: "ui48_furniture_start_trial") {
                            selectedID = activeID
                            previewingID = activeID
                        }
                    }
                    SpriteView(scene: previewScene)
                        .frame(maxWidth: .infinity).frame(height: 270)
                        .clipShape(UI48Frame(radius: 17))
                        .overlay(UI48Frame(radius: 17).stroke(UI48Theme.gold, lineWidth: 1))
                    HStack {
                        Image(systemName: "chair.lounge.fill").foregroundStyle(UI48Theme.gold)
                        Text(previewingID == nil ? "現在の配置" : "試し置き／未保存").font(.subheadline)
                    }.frame(maxWidth: .infinity)
                }
            }
            if let activeID {
                UI48Panel(title: "家具の見本") {
                    HStack(spacing: 12) {
                        AssetIcon(id: activeID, size: 64).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                        Text(furnitureName(activeID))
                                .font(.headline)
                            let owned = model.state.ownedFurnitureIDs.contains(activeID)
                            Text(owned
                                 ? (model.state.placedFurnitureIDs.contains(activeID) ? "所持済み／配置中" : (previewingID == activeID ? "所持済み／試し置き中" : "所持済み／未配置"))
                                 : (previewingID == activeID ? "未所有／試し置きのみ" : "未所有"))
                                .font(.caption).foregroundStyle(UI48Theme.muted)
                        }
                    }
                    UI48Note(text: previewingID == activeID
                             ? "試し置きは部屋の表示だけが変わります。所持品や保存状態は変わりません。"
                             : "家具を選ぶと試し置きできます。所持品や配置は、明示的に適用するまで変わりません。")
                }
                if model.state.ownedFurnitureIDs.contains(activeID) {
                    UI48Action(
                        title: applying ? "保存しています…" : (model.state.placedFurnitureIDs.contains(activeID) ? "配置済み" : "この配置を使う"),
                        symbol: "chair.lounge.fill",
                        disabled: applying || model.busy || model.state.placedFurnitureIDs.contains(activeID),
                        id: "ui48_furniture_apply"
                    ) { apply(activeID, placed: true) }
                    if model.state.placedFurnitureIDs.contains(activeID) {
                        UI48Action(title: "配置を解除する", symbol: "arrow.uturn.backward", secondary: true, disabled: applying || model.busy) {
                            apply(activeID, placed: false)
                        }
                    }
                } else {
                    UI48Note(text: "所持していない家具は試せますが、適用して保存することはできません。")
                    if activeID == FurniturePresentationR094.botanicalDeskID {
                        UI48Action(title: applying ? "受け取っています…" : "無料の初期家具を受け取る", symbol: "gift", disabled: applying || model.busy, id: "ui48_furniture_claim_initial") {
                            claimInitialFurniture(activeID)
                        }
                    }
                }
                if previewingID != nil {
                    UI48Action(title: "試し置きを取り消す", symbol: "arrow.uturn.backward", secondary: true, disabled: applying || model.busy, id: "ui48_furniture_cancel") {
                        previewingID = nil
                        selectedID = model.state.placedFurnitureIDs.sorted().first
                    }
                }
            }
            if !furnitureIDs.isEmpty {
                UI48Panel(title: "家具を選ぶ") {
                    LazyVGrid(columns: furnitureGridColumns, spacing: 9) {
                        ForEach(furnitureIDs, id: \.self) { id in
                            Button {
                                selectedID = id
                                previewingID = id
                            } label: {
                                Group {
                                    if dynamicTypeSize.isAccessibilitySize {
                                        HStack(spacing: 14) {
                                            AssetIcon(id: id, size: 76)
                                            VStack(alignment: .leading, spacing: 7) {
                                                Text(id == FurniturePresentationR094.botanicalDeskID ? "植物研究の机" : id)
                                                    .font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                                                Text(model.state.ownedFurnitureIDs.contains(id) ? "所持済み" : "試し置き")
                                                    .font(.subheadline).foregroundStyle(UI48Theme.muted)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: selectedID == id ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(UI48Theme.gold).accessibilityHidden(true)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                                    } else {
                                        VStack(spacing: 6) {
                                            AssetIcon(id: id, size: 54)
                                            Text(id == FurniturePresentationR094.botanicalDeskID ? "植物研究の机" : id)
                                                .font(.caption2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                            Text(model.state.ownedFurnitureIDs.contains(id) ? "所持済み" : "試し置き")
                                                .font(.caption2).foregroundStyle(UI48Theme.muted)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 104)
                                    }
                                }
                                .padding(7)
                                .background(UI48Theme.raised.opacity(0.75))
                                .clipShape(UI48Frame(radius: 12))
                                .overlay(UI48Frame(radius: 12).stroke(selectedID == id ? UI48Theme.gold : UI48Theme.gold.opacity(0.45), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ui48_furniture_\(id)")
                        }
                    }
                }
            }

        }
        .onAppear { updatePreview() }
        .onChange(of: activeID) { _, _ in updatePreview() }
        .onChange(of: previewingID) { _, _ in updatePreview() }
        .onChange(of: model.state.placedFurnitureIDs) { _, _ in updatePreview() }
    }

    private var furnitureGridColumns: [GridItem] {
        [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 105), spacing: 9)]
    }

    private func updatePreview() {
        previewScene.scaleMode = .resizeFill
        previewScene.configure(place: .home, cosmetics: model.sceneAppearance, furniture: previewFurniture,
                               wardrobeCandidateDevelopmentEnabled: model.wardrobeCandidateDevelopmentR169Enabled)
    }

    private func furnitureName(_ id: String) -> String {
        id == FurniturePresentationR094.botanicalDeskID ? "植物研究の机" : "家具の見本"
    }

    private func apply(_ id: String, placed: Bool) {
        guard !applying, !model.busy, model.state.ownedFurnitureIDs.contains(id), let engine = model.engine else { return }
        applying = true
        model.busy = true
        let before = model.state
        Task {
            do {
                _ = try await engine.dispatchConfirmingSavedReceipt(.placeFurniture(id, placed: placed), operationID: UUID(), expectedRevision: before.revision)
                await model.refresh()
                previewingID = nil
                selectedID = placed ? id : model.state.placedFurnitureIDs.sorted().first
                model.notice = placed ? "家具の配置を保存しました。" : "家具の配置を解除しました。"
            } catch {
                model.error = model.commandErrorText(error)
                await model.refresh()
            }
            applying = false
            model.busy = false
        }
    }

    private func claimInitialFurniture(_ id: String) {
        guard id == FurniturePresentationR094.botanicalDeskID,
              !model.state.ownedFurnitureIDs.contains(id),
              !applying, !model.busy, let engine = model.engine else { return }
        applying = true
        model.busy = true
        let before = model.state
        Task {
            do {
                _ = try await engine.dispatchConfirmingSavedReceipt(.setFurniture(id, owned: true), operationID: UUID(), expectedRevision: before.revision)
                await model.refresh()
                previewingID = nil
                selectedID = id
                model.notice = "無料の初期家具を受け取りました。部屋で試し置きしてみましょう。"
            } catch {
                model.error = model.commandErrorText(error)
                await model.refresh()
            }
            applying = false
            model.busy = false
        }
    }
}

@MainActor
private struct UI48ShopScreen: View {
    @EnvironmentObject private var commerce: ProductCommerceModelR1
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var category = "衣装"
    @State private var appearanceKind = "衣装"

    private var categoryAppearances: [AppearanceDefinition] {
        let wanted = appearanceKind == "武器外観" ? "weapon" : "costume"
        return (model.catalog?.appearances ?? []).filter { $0.kind == wanted }.sorted {
            let knownL = UI48LifestyleNames.appearances[$0.id] != nil
            let knownR = UI48LifestyleNames.appearances[$1.id] != nil
            return knownL == knownR ? $0.id < $1.id : knownL
        }
    }

    var body: some View {
        UI48Page {
            UI48Heading(title: "森の小さな商店", subtitle: "お気に入りを、暮らしに。商品情報を確認できます。")
            UI48Note(text: commerce.shopStatus)
            shopCategoryTabs
            if category == "衣装" {
                HStack(spacing: 8) {
                    ForEach(["衣装", "武器外観"], id: \.self) { kind in
                        Button { appearanceKind = kind } label: {
                            Label(kind, systemImage: kind == "衣装" ? "tshirt" : "wand.and.stars")
                                .font(.caption).padding(.horizontal, 14).padding(.vertical, 10)
                                .foregroundStyle(appearanceKind == kind ? UI48Theme.gold : UI48Theme.muted)
                                .background(UI48Theme.raised.opacity(appearanceKind == kind ? 1 : 0.25))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("ui48_shop_appearance_\(kind)")
                    }
                    Spacer(minLength: 0)
                }
            }
            if category == "家具" {
                if let id = model.catalog?.furnitureIDs.sorted().first {
                    shopRow(id: id, title: id == FurniturePresentationR094.botanicalDeskID ? "植物研究の机" : "家具の見本",
                            detail: model.state.ownedFurnitureIDs.contains(id) ? "所持済み" : "家具の見本 · 未所有") {
                        flow.targetID = id
                        flow.appearanceID = nil
                        flow.go(44)
                    }
                } else {
                    UI48Panel { UI48Note(text: "家具の商品情報はありません。") }
                }
            } else if category == "鑑定券" {
                UI48Panel(title: "装備の鑑定券") {
                    Label("販売準備中", systemImage: "sparkles").font(.title3).foregroundStyle(UI48Theme.gold)
                    Text("販売する内容と価格は、まだ設定されていません。現在は購入できません。")
                        .font(.subheadline).accessibilityIdentifier("ui48_shop_tickets_unavailable")
                    Text("ゲーム内で獲得した無料鑑定券は、魔導庫で使えます。解放条件と現在の所持数を確認しましょう。")
                        .font(.caption).foregroundStyle(UI48Theme.muted)
                    UI48Action(title: "魔導庫を確認する", symbol: "sparkles", secondary: true) { flow.go(36) }
                    UI48Action(title: "提供割合・保証を見る", symbol: "info.circle", secondary: true) { flow.go(38) }
                }
            } else if category == "便利機能" {
                UI48Panel(title: "便利機能") {
                    Label("準備中", systemImage: "leaf").font(.title3).foregroundStyle(UI48Theme.gold)
                    Text("商品内容はまだ設定されていません。購入や機能の追加は行われません。")
                        .font(.subheadline).accessibilityIdentifier("ui48_shop_convenience_unavailable")
                    UI48Note(text: "音楽・効果音や保存状態は、設定から確認できます。")
                    UI48Action(title: "設定を開く", symbol: "gearshape", secondary: true) { flow.go(46) }
                }
            } else if categoryAppearances.isEmpty {
                UI48Panel { UI48Note(text: "この種類の商品は、まだ用意されていません。") }
            } else {
                if let featured = categoryAppearances.first {
                    let owned = model.state.ownedCosmeticIDs.contains(featured.id)
                    shopRow(id: featured.id, title: shopAppearanceName(featured),
                            detail: owned ? "所持済みの見た目" : "見た目の候補 · 未所有", featured: true) {
                        flow.appearanceID = featured.id
                        flow.targetID = nil
                        flow.go(44)
                    }
                }
                ForEach(Array(categoryAppearances.dropFirst())) { appearance in
                    let owned = model.state.ownedCosmeticIDs.contains(appearance.id)
                    shopRow(id: appearance.id, title: shopAppearanceName(appearance),
                            detail: owned ? "所持済みの見た目" : "見た目の候補 · 未所有") {
                        flow.appearanceID = appearance.id
                        flow.targetID = nil
                        flow.go(44)
                    }
                }
            }
        }
    }

    private func shopAppearanceName(_ appearance: AppearanceDefinition) -> String {
        UI48LifestyleNames.catalogAppearance(appearance)
    }

    @ViewBuilder private var shopCategoryTabs: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(["衣装", "家具", "鑑定券", "便利機能"], id: \.self) { item in
                        shopCategoryButton(item, largeText: true)
                    }
                }
                .padding(.horizontal, 2)
            }
            .accessibilityIdentifier("ui48_shop_categories_large_text")
        } else {
            HStack(spacing: 8) {
                ForEach(["衣装", "家具", "鑑定券", "便利機能"], id: \.self) { item in
                    shopCategoryButton(item, largeText: false)
                }
            }
        }
    }

    private func shopCategoryButton(_ item: String, largeText: Bool) -> some View {
        Button { category = item } label: {
            Text(item)
                .font(largeText ? .body.weight(.semibold) : .caption.weight(.semibold))
                .frame(maxWidth: largeText ? 210 : .infinity, minHeight: largeText ? 72 : 48)
                .foregroundStyle(category == item ? UI48Theme.paperInk : UI48Theme.ivory)
                .background(category == item ? UI48Theme.gold : UI48Theme.raised)
                .clipShape(UI48Frame(radius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui48_shop_category_\(item)")
    }

    private func shopRow(id: String, title: String, detail: String, featured: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if featured {
                    VStack(alignment: .leading, spacing: 9) {
                        ZStack(alignment: .bottomLeading) {
                            AssetIcon(id: id + (id == "ERNA_TRAVEL" ? "__idle" : ""), size: 220)
                                .frame(maxWidth: .infinity).frame(height: 250).clipped()
                                .background(UI48Theme.ink)
                            LinearGradient(colors: [.clear, UI48Theme.ink.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                                .frame(height: 112)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail).font(.caption).foregroundStyle(UI48Theme.gold)
                                Text(title).font(.system(.title2, design: .serif, weight: .semibold))
                                Text("暮らしの見た目 · 詳細を確認できます").font(.caption)
                            }.padding(14)
                        }.clipShape(UI48Frame(radius: 15))
                        Text(commerce.price(contentID:id)).font(.caption).foregroundStyle(UI48Theme.gold)
                    }
                } else {
                    HStack(spacing: 12) {
                        AssetIcon(id: id + (id == "ERNA_TRAVEL" ? "__idle" : ""), size: 54).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(UI48Theme.muted)
                    Text(commerce.price(contentID:id)).font(.caption2).foregroundStyle(UI48Theme.gold)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(UI48Theme.gold)
                    }.padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                }
            }
            .background(UI48Theme.enamel.opacity(0.48)).clipShape(UI48Frame(radius: 14))
            .overlay(UI48Frame(radius: 14).stroke(UI48Theme.gold.opacity(0.7), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

@MainActor
private struct UI48ProductScreen: View {
    @EnvironmentObject private var commerce: ProductCommerceModelR1
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow

    private var appearance: AppearanceDefinition? {
        model.catalog?.appearances.first { $0.id == flow.appearanceID }
    }
    private var furnitureID: String? {
        if let targetID = flow.targetID, model.catalog?.furnitureIDs.contains(targetID) == true { return targetID }
        return nil
    }
    private var productID: String? { appearance?.id ?? furnitureID }
    private var productTitle: String {
        guard let productID else { return "商品情報はありません" }
        if productID == FurniturePresentationR094.botanicalDeskID { return "植物研究の机" }
        if let appearance { return UI48LifestyleNames.catalogAppearance(appearance) }
        return "家具の見本"
    }

    var body: some View {
        UI48Page {
            UI48Heading(title: "商品の詳細", subtitle: "見た目と内容を確認できます。")
            if let productID {
                UI48Hero(assetID: productID + (productID == "ERNA_TRAVEL" ? "__idle" : ""), title: productTitle,
                         subtitle: appearance?.kind == "costume" ? "衣装の見本／開発候補" : appearance?.kind == "weapon" ? "武器外観の見本／開発候補" : "家具の見本")
                UI48Panel(title: "内容") {
                    detailRow("商品", productTitle)
                    detailRow("所有状態", owned ? "所持済み" : "未所有")
                    detailRow("価格", commerce.price(contentID:productID))
                    detailRow("購入", commerce.connected ? "App Storeで確認" : "現行版は未接続")
                    Text(appearance == nil ? "家具の見た目を確認できます。" : "性能・戦闘・進行には影響しません。")
                        .font(.caption).foregroundStyle(UI48Theme.muted)
                }
                UI48Note(text: "未所有でも試着できます。価格や購入権利はこの画面から発生しません。")
                if appearance != nil {
                    UI48Action(title: "試着する", symbol: "tshirt", secondary: true) {
                        flow.go(appearance?.kind == "weapon" ? 41 : 40)
                    }
                } else {
                    UI48Action(title: "家具を試し置きする", symbol: "chair.lounge.fill", secondary: true) { flow.go(42) }
                }
                UI48Action(title: "購入状態を見る", symbol: "shield", disabled: false) { flow.go(45) }
            } else {
                UI48Panel(title: "商品情報") {
                    UI48Note(text: "商品を読み込めませんでした。商店で選び直してください。", warning: true)
                    UI48Action(title: "商店へ戻る", secondary: true) { flow.back() }
                }
            }
        }
    }

    private var owned: Bool {
        guard let productID else { return false }
        return model.state.ownedCosmeticIDs.contains(productID) || model.state.ownedFurnitureIDs.contains(productID)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(UI48Theme.muted)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(UI48Theme.gold)
        }
        .font(.subheadline).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(UI48Theme.gold.opacity(0.2)).frame(height: 1) }
    }
}

private enum UI48PurchaseState: String, CaseIterable, Identifiable {
    case disconnected = "購入未接続"
    case confirming = "確認中"
    case completed = "完了表示"
    case cancelled = "キャンセル表示"
    case pending = "保留表示"
    case failed = "失敗表示"
    case restored = "復元表示"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .disconnected: "nosign"
        case .confirming, .pending: "clock"
        case .completed, .restored: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }
    var detail: String {
        switch self {
        case .disconnected: "正式な購入接続と商品設定はありません。"
        case .confirming: "隔離したUI表示例です。実取引を開始していません。"
        case .completed: "完了表示の確認例です。購入権利や商品は付与されません。"
        case .cancelled: "キャンセル表示の確認例です。ゲーム状態は変更されません。"
        case .pending: "保留表示の確認例です。再購入を促しません。"
        case .failed: "失敗表示の確認例です。取引結果は作成されません。"
        case .restored: "復元表示の確認例です。権利の復元や付与は行いません。"
        }
    }
}

@MainActor
private struct UI48PurchaseScreen: View {
    @EnvironmentObject private var commerce: ProductCommerceModelR1
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    @State private var displayState: UI48PurchaseState = .disconnected

    private var isolatedFixtureAllowed: Bool {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        return UI48QALaunchGate.isValid(arguments: args) && args.contains("--ui48-screen=45")
        #else
        return false
        #endif
    }
    private var productTitle: String {
        if let id = flow.appearanceID, let appearance = model.catalog?.appearances.first(where: { $0.id == id }) {
            return UI48LifestyleNames.catalogAppearance(appearance)
        }
        if flow.targetID == FurniturePresentationR094.botanicalDeskID { return "植物研究の机" }
        return "選択した見本"
    }

    var body: some View {
        UI48Page {
            UI48Heading(title: "購入内容の確認", subtitle: "取引を開始する前に、内容と状態を確認します。")
            UI48Panel(title: "選んだ商品") {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack").font(.title2).foregroundStyle(UI48Theme.gold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(productTitle).font(.headline)
                        Text("見本表示／所有権は変更されません").font(.caption).foregroundStyle(UI48Theme.muted)
                    }
                }
            }
            UI48Panel(title: "お支払い") {
                HStack { Text("価格").foregroundStyle(UI48Theme.muted); Spacer(); Text(commerce.price(contentID:flow.appearanceID ?? flow.targetID)).foregroundStyle(UI48Theme.gold) }
                Text(commerce.connected ? "表示された価格と内容をApp Storeの確認画面で確かめてください。" : "正式な商品・価格・決済接続はまだありません。購入権利は付与されません。")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            UI48Note(text: isolatedFixtureAllowed && displayState != .disconnected ? displayState.detail : commerce.status,
                       warning: displayState == .failed || displayState == .pending)
            UI48Action(title: "購入確認へ", symbol: "shield", disabled: !commerce.canPurchase(contentID:flow.appearanceID ?? flow.targetID), id:"ui48_purchase_commit") {
                Task {await commerce.purchase(contentID:flow.appearanceID ?? flow.targetID)}
            }
            UI48Action(title: "戻る", symbol: "chevron.left", secondary: true, disabled:commerce.busy) { flow.back() }
            if isolatedFixtureAllowed {
                UI48Panel(title: "隔離UI表示試験") {
                    Text("状態を選んでも取引・所持権利・通常セーブは変わりません。")
                        .font(.caption).foregroundStyle(UI48Theme.muted)
                    HStack(spacing: 8) {
                        purchaseStateCell(.confirming)
                        purchaseStateCell(.completed)
                        purchaseStateCell(.pending)
                    }
                    ForEach(UI48PurchaseState.allCases.filter { $0 != .disconnected }) { state in
                        Button { displayState = state } label: {
                            Label(state.rawValue, systemImage: state.symbol)
                                .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .foregroundStyle(displayState == state ? UI48Theme.gold : UI48Theme.ivory)
                        }.buttonStyle(.plain).accessibilityIdentifier("ui48_purchase_fixture_\(state.id)")
                    }
                    UI48Action(title: "未接続表示に戻す", symbol: "arrow.uturn.backward", secondary: true) { displayState = .disconnected }
                }
            } else {
                purchaseStateCell(.disconnected)
            }
        }
    }

    private func purchaseStateCell(_ state: UI48PurchaseState) -> some View {
        VStack(spacing: 7) {
            Image(systemName: state.symbol).font(.title3).foregroundStyle(UI48Theme.gold)
            Text(state.rawValue).font(.caption2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct UI48SettingsScreen: View {
    @EnvironmentObject private var commerce: ProductCommerceModelR1
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    @ObservedObject private var sound = WitchAudioCoordinator.shared
    @ObservedObject private var music = WitchMusicCoordinator.shared

    var body: some View {
        UI48Page {
            UI48Heading(title: "設定", subtitle: "心地よい、旅の時間。")
            UI48Panel(title: "音") {
                volumeRow(title: "音楽", value: Float(music.volume)) { music.setVolume($0) }
                volumeRow(title: "効果音", value: Float(sound.volume)) { sound.setVolume($0) }
                Toggle("音楽を消音", isOn: Binding(get: { music.isMuted }, set: { music.setMuted($0) }))
                    .tint(UI48Theme.gold)
                    .accessibilityIdentifier("ui48_music_mute")
                Toggle("効果音を消音", isOn: Binding(get: { sound.isMuted }, set: { sound.setMuted($0) }))
                    .tint(UI48Theme.gold)
                    .accessibilityIdentifier("ui48_sfx_mute")
            }
            UI48Panel(title: "保存") {
                HStack { Text("進行状況").foregroundStyle(UI48Theme.muted); Spacer(); Text("自動で保存") }
                UI48Action(title: "保存状態を確認する", symbol: "shield", secondary: true) { flow.go(47) }
            }
            UI48Panel(title: "案内") {
                Button { flow.home(model, tab: "家") } label: {
                    settingsRow("遊び方", value: "目標から素材・制作へ")
                }.buttonStyle(.plain).accessibilityIdentifier("ui48_settings_guide_home")
                Button {Task {await commerce.restore()}} label: {
                    settingsRow("購入の復元", value: commerce.connected ? "確認する" : "未接続・理由を確認")
                }.buttonStyle(.plain).disabled(commerce.busy).accessibilityIdentifier("ui48_purchase_restore")
                settingsRow("利用条件・プライバシー", value: "この版では未接続").opacity(0.8)
            }
            UI48Note(text:commerce.status)
            if let rules=model.productRulesR1 {
                UI48Panel(title:"この版の設定") {
                    Text(rules.runtimeProfileID).font(.caption).textSelection(.enabled)
                    Text("設定識別 \(rules.runtimeConfigurationFingerprint.prefix(12))").font(.caption2)
                    Text("初期状態と成長・入手条件は、この版の設定で動作します。既存セーブの所持品を置き換えません。")
                        .font(.caption).fixedSize(horizontal:false,vertical:true)
                }
            }
            UI48Note(text: "音量設定はこの端末に保存されます。")
        }
    }

    private func volumeRow(title: String, value: Float, set: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).foregroundStyle(UI48Theme.ivory)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(UI48Theme.gold)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { Double(value) }, set: { set(Float($0)) }), in: 0...1)
                .tint(UI48Theme.gold)
                .accessibilityLabel(title)
                .accessibilityIdentifier(title == "音楽" ? "ui48_music_volume" : "ui48_sfx_volume")
                .frame(minHeight: 44)
        }
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            Text(value).font(.caption).foregroundStyle(UI48Theme.gold).multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(UI48Theme.gold)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(UI48Theme.gold.opacity(0.2)).frame(height: 1) }
    }
}

@MainActor
private struct UI48RecoveryScreen: View {
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow

    private var isFailed: Bool {
        if case .failed = model.startupState { return true }
        return false
    }
    private var isLoading: Bool {
        if case .loading = model.startupState { return true }
        return false
    }
    private var isReady: Bool {
        if case .ready = model.startupState { return true }
        return false
    }
    private var title: String {
        if isLoading { return "保存を読み込んでいます。" }
        if isFailed { return "保存の状態を確認できません。" }
        if model.saveRecoveryMessage != nil { return "セーブを復元しました。" }
        return "保存の確認"
    }
    private var detail: String {
        if isLoading { return "読み込み中です。完了するまで保存状態を確定しません。" }
        if isFailed { return "起動に失敗したため、復旧状態は確定していません。元の記録を保全してください。" }
        if let recovery = model.saveRecoveryMessage { return recovery }
        if isReady { return "復元の通知はありません。保存内容を読み込みました。" }
        return "読み込みが完了すると保存状態を確認できます。"
    }

    var body: some View {
        UI48Page {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(UI48Theme.gold.opacity(0.16)).frame(width: 112, height: 112)
                    Circle().stroke(UI48Theme.gold, lineWidth: 1.5).frame(width: 92, height: 92)
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 42)).foregroundStyle(UI48Theme.gold)
                }.accessibilityHidden(true)
                Text(title).font(.system(.title, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
                Text(detail).font(.subheadline).foregroundStyle(UI48Theme.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
            UI48Panel(title: "保存の状態") {
                if model.saveRecoveryMessage != nil && !isLoading {
                    detailRow("読み込んだ記録", "直前の正常な保存")
                    detailRow("元の記録", "保全しています")
                    UI48Note(text: "最後の保存にだけ含まれた操作は、戻っていない可能性があります。")
                } else if isFailed {
                    detailRow("読み込み", "失敗")
                    detailRow("復旧状態", "未確定")
                    if let diagnostic = model.startupDiagnostic, !diagnostic.isEmpty {
                        Text(diagnostic).font(.caption).textSelection(.enabled)
                    }
                } else if isReady {
                    detailRow("読み込み", "完了")
                    detailRow("復旧", "通知なし")
                    if let url = model.saveURL { detailRow("保存ファイル", url.lastPathComponent) }
                } else {
                    detailRow("読み込み", "確認中")
                    ProgressView().tint(UI48Theme.gold)
                }
            }
            UI48Note(text: "保存が不明なときは初期化や上書きを急がず、記録をそのまま保全してください。", warning: isFailed)
            if isFailed {
                UI48Action(title: "もう一度読み込む", symbol: "arrow.clockwise") { Task { await model.load() } }
            } else if isLoading {
                UI48Action(title: "読み込み中", symbol: "hourglass", disabled: true) {}
            } else {
                UI48Action(title: "内容を確認して続ける", symbol: "checkmark.shield", action: { flow.home(model) })
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(UI48Theme.muted)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(UI48Theme.gold).multilineTextAlignment(.trailing)
        }.font(.subheadline).padding(.vertical, 7)
    }
}

@MainActor
private struct UI48StartupScreen: View {
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow

    var body: some View {
        ZStack {
            if let background = ArtLibrary.image("BG_R05_FIELD") {
                Image(uiImage: background).resizable().scaledToFill().overlay(UI48Theme.ink.opacity(0.40))
                    .ignoresSafeArea()
            } else {
                UI48Theme.ink.ignoresSafeArea()
            }
            UI48Theme.background.opacity(0.58).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 54)).foregroundStyle(UI48Theme.gold).padding(.top, 24)
                    Text("魔女の採集帳").accessibilityIdentifier("ui48_screen_48").font(.system(.largeTitle, design: .serif, weight: .semibold))
                    switch model.startupState {
                    case .loading:
                        ProgressView().tint(UI48Theme.gold).scaleEffect(1.25).padding(.vertical, 12)
                        Text("暮らしの準備をしています…").foregroundStyle(UI48Theme.muted)
                            .accessibilityIdentifier("ui48_launch_loading")
                    case .ready:
                        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(UI48Theme.gold)
                        Text("準備ができました。旅を続けられます。").multilineTextAlignment(.center)
                        UI48Action(title: "家へ進む", symbol: "house") { flow.home(model) }
                    case .failed(let message):
                        UI48Panel(title: "準備を完了できませんでした") {
                            Text("セーブは変更していません。読み込みをやり直せます。")
                            Text(message).font(.caption).textSelection(.enabled)
                                .accessibilityIdentifier("ui48_launch_error")
                            if let diagnostic = model.startupDiagnostic, !diagnostic.isEmpty {
                                Text(diagnostic).font(.caption2).foregroundStyle(UI48Theme.muted).textSelection(.enabled)
                            }
                            UI48Action(title: "もう一度読み込む", symbol: "book") { Task { await model.load() } }
                            UI48Action(title: "詳しい状態を見る", symbol: "info.circle", secondary: true) { flow.go(47) }
                        }
                    }
                    if case .loading = model.startupState {
                        UI48Note(text: "旅の記録を読み込んでいます。保存内容を確認してから、家へ進みます。")
                    } else if case .ready = model.startupState {
                        UI48Note(text: "保存内容を確認しました。家から旅を再開できます。")
                    }
                }
                .padding(22).frame(maxWidth: .infinity)
            }
        }
    }
}
