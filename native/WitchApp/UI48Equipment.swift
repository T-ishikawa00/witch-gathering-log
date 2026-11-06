import SwiftUI

/// Native screens S13-S27. The host owns navigation chrome; this view owns only
/// the screen body and delegates durable mutations to GameModel/Core.
struct UI48EquipmentView: View {
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    let screen: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var qualityFilter = "すべて"
    @State private var searchText = ""
    @FocusState private var inventorySearchFocused: Bool
    @State private var selectedInventoryID: UUID?
    @State private var inventorySort = "入手した順"
    @State private var workshopMode = "制作"
    @State private var selectedEvolutionID: String?
    @State private var selectedDismantleIDs = Set<UUID>()
    @State private var showBulkDismantleConfirmation = false
    @State private var confirmingLoadout: GearLoadoutSlotR342?
    @State private var pendingLoadoutAction: String?

    private let qualities = ["すべて", "Q0", "Q1", "Q2", "Q3", "Q4"]
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 7), count: count)
    }

    var body: some View {
        Group {
            switch screen {
            case 13: companionBody
            case 14: inventoryBody(emptyOnly: false)
            case 15: detailBody
            case 16: comparisonBody
            case 17: loadoutBody
            case 18: dismantleBody
            case 19: workshopBody
            case 20: recipeGoalBody(confirmation: false)
            case 21: recipeGoalBody(confirmation: true)
            case 22: evolutionBody
            case 23: upgradeBody(action: .enhance)
            case 24: refinementBody
            case 25: upgradeBody(action: .promoteQuality)
            case 26: resultBody
            case 27: inventoryBody(emptyOnly: true)
            default: UI48Page { UI48Note(text: "この画面は持ちものに戻ると表示できます。") }
            }
        }
        .confirmationDialog("保存セットを変更しますか？", isPresented: Binding(
            get: { confirmingLoadout != nil }, set: { if !$0 { confirmingLoadout = nil; pendingLoadoutAction = nil } }
        ), titleVisibility: .visible) {
            if let slot = confirmingLoadout, let action = pendingLoadoutAction {
                Button(action == "save" ? "現在の装備で上書きする" : "登録を解除する", role: action == "clear" ? .destructive : nil) {
                    if action == "save" {
                        flow.commit(.saveGearLoadoutR342(slot: slot), model: model, title: "装備セットを保存しました", resultScreen: nil)
                    } else {
                        flow.commit(.clearGearLoadoutR342(slot: slot), model: model, title: "装備セットを解除しました", resultScreen: nil)
                    }
                    confirmingLoadout = nil
                    pendingLoadoutAction = nil
                }
            }
            Button("キャンセル", role: .cancel) { confirmingLoadout = nil; pendingLoadoutAction = nil }
        } message: {
            Text(pendingLoadoutAction == "save" ? "選んだ枠の内容を現在の装備で置き換えます。" : "セットの登録を解除します。装備そのものは残ります。")
        }
        .confirmationDialog("選んだ装備を分解しますか？", isPresented: $showBulkDismantleConfirmation, titleVisibility: .visible) {
            Button("確認した装備を分解する", role: .destructive) { model.salvage(selectedDismantleIDs.sorted { $0.uuidString < $1.uuidString }, allowSelectedSubset: true) }
            Button("やめる", role: .cancel) { }
        } message: {
            Text("対象 \(selectedDismantleIDs.count) 点・\(dismantleRewardText)。保護品、使用中の品、保存セットの品、各種類の最後の1点は残します。")
        }
        .onChange(of: model.state.revision) { _, _ in
            selectedDismantleIDs.formIntersection(Set(batchEligibleGear.map(\.id)))
        }
        .onAppear {
            if screen == 18 { selectedDismantleIDs = Set(batchEligibleGear.map(\.id)) }
        }
    }

    private var companionBody: some View {
        UI48Page {
            UI48ActorStrip(model: model)
            if dynamicTypeSize.isAccessibilitySize {
                companionPortrait
                gearSlotGrid(for: model.selectedActor)
            } else {
            HStack(alignment: .center, spacing: 7) {
                VStack(spacing: 6) { ForEach(companionSlots.prefix(3), id: \.self) { slot in compactGearSlot(actor: model.selectedActor, slot: slot) } }
                companionPortrait
                VStack(spacing: 6) { ForEach(companionSlots.suffix(3), id: \.self) { slot in compactGearSlot(actor: model.selectedActor, slot: slot) } }
            }
            .padding(8).background(UI48Theme.enamel.opacity(0.38)).clipShape(UI48Frame(radius: 16))
            .overlay(UI48Frame(radius: 16).stroke(UI48Theme.gold.opacity(0.65), lineWidth: 1))
            }
            Text(GameModel.actorNames[model.selectedActor] ?? model.selectedActor).font(.system(.title3, design: .serif)).frame(maxWidth: .infinity)
            if let stats = actorStats(model.selectedActor) {
                UI48ResponsiveRow(spacing: 0) {
                    compactStat("攻撃", stats.attack)
                    compactStat("体力", stats.maxHP)
                    compactStat("防御", stats.defense)
                }
                .padding(.vertical, 8).background(UI48Theme.enamel.opacity(0.3)).clipShape(UI48Frame(radius: 12))
                if let effects = nonLatentEffects(stats), !effects.isEmpty {
                    Text(effects.map(GameText.effect).joined(separator: "・")).font(.caption2).foregroundStyle(UI48Theme.muted).lineLimit(1)
                }
            }
            let currentWeapon = equippedItem(for: model.selectedActor, slot: "weapon")
            UI48ResponsiveRow(spacing: 8) {
                UI48Action(title: "装備を比べる", symbol: "shield", disabled: currentWeapon == nil || model.state.gear.count < 2, id: "ui48_companion_compare") {
                    if let currentWeapon { beginComparison(currentWeapon) }
                }
                UI48Action(title: "試着する", symbol: "tshirt", secondary: true, id: "ui48_companion_try_on") { flow.go(40) }
            }
            UI48ResponsiveRow(spacing: 8) {
                UI48Action(title: "持ちものを見る", symbol: "square.grid.2x2", secondary: true, id: "ui48_companion_inventory") { flow.go(14) }
                UI48Action(title: "装備セット", symbol: "book", secondary: true, id: "ui48_companion_loadouts") { flow.go(17) }
            }
        }
    }

    private var companionPortrait: some View {
        Group {
            if model.selectedActor == "C_WITCH",
               model.state.selectedCosmeticIDs["C_WITCH"] == nil,
               model.state.selectedWeaponAppearanceIDs["C_WITCH"] == nil,
               let portrait = ArtLibrary.image("UI48_ERNA_PORTRAIT") {
                // The approved source contains a legacy level/copy strip in
                // its first 26 pixels. Preserve that source file, but exclude
                // the strip from the live character illustration.
                let visibleHeight = max(1, portrait.size.height - 26)
                Image(uiImage: portrait).resizable()
                    .frame(width: 260 * portrait.size.width / visibleHeight,
                           height: 260 * portrait.size.height / visibleHeight)
                    .offset(y: -260 * 26 / visibleHeight)
                    .frame(height: 260, alignment: .top).clipped()
            } else {
                WardrobePortrait(model: model, actorID: model.selectedActor,
                                 appearanceOverrides: model.sceneAppearance, spotlight: true)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 260).clipped()
        .accessibilityLabel(GameModel.actorNames[model.selectedActor] ?? model.selectedActor)
    }

    private var companionSlots: [String] { ["weapon", "body", "hands", "feet", "ring", "amulet"] }

    private func compactGearSlot(actor: String, slot: String) -> some View {
        let item = equippedItem(for: actor, slot: slot)
        return Button {
            model.selectedActor = actor
            if let item { flow.selectGear(item.id, screen: 15) } else { flow.go(14) }
        } label: {
            VStack(spacing: 1) {
                if let item { UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID, count: "+\(item.enhancement)", locked: item.protected, size: 42) }
                else { Image(systemName: "plus.circle").font(.title3).foregroundStyle(UI48Theme.gold).frame(width: 42, height: 42) }
                Text(slotName(slot)).font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(width: 64, height: 64).background(UI48Theme.ink.opacity(0.55)).clipShape(UI48Frame(radius: 9))
        }.buttonStyle(.plain).accessibilityLabel("\(slotName(slot)): \(item.map(gearName) ?? "空き部位")")
            .accessibilityIdentifier("ui48_slot_\(actor)_\(slot)")
    }

    private func gearSlotGrid(for actorID: String) -> some View {
        let definitions = model.catalog?.gear.filter { $0.actorIDs.isEmpty || $0.actorIDs.contains(actorID) } ?? []
        let availableSlots = ["weapon", "body", "hands", "feet", "ring", "amulet"]
            .filter { slot in definitions.contains(where: { $0.slot == slot }) }
        let slots = availableSlots.isEmpty ? ["weapon", "body", "hands", "feet", "ring", "amulet"] : availableSlots
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 10) {
            ForEach(slots, id: \.self) { slot in
                let item = equippedItem(for: actorID, slot: slot)
                Button {
                    model.selectedActor = actorID
                    if let item { flow.selectGear(item.id, screen: 15) } else { flow.go(14) }
                } label: {
                    VStack(spacing: 7) {
                        if let item {
                            UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID,
                                     count: "+\(item.enhancement)", locked: item.protected, size: 68)
                            Text(gearName(item)).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                        } else {
                            Image(systemName: "plus.circle").font(.title2).foregroundStyle(UI48Theme.gold).frame(height: 68)
                            Text("空き部位").font(.caption2)
                        }
                        Text(slotName(slot)).font(.caption2).foregroundStyle(UI48Theme.muted)
                    }.frame(maxWidth: .infinity, minHeight: 122).padding(7)
                        .background(UI48Theme.enamel.opacity(0.42)).clipShape(UI48Frame(radius: 12))
                        .overlay(UI48Frame(radius: 12).stroke(UI48Theme.gold.opacity(0.55)))
                }.buttonStyle(.plain).accessibilityIdentifier("ui48_slot_\(actorID)_\(slot)")
            }
        }
    }

    private func inventoryBody(emptyOnly: Bool) -> some View {
        let visible = filteredGear
        return UI48Page {
            UI48ActorStrip(model: model)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(UI48Theme.gold)
                TextField("装備名で探す", text: $searchText).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().focused($inventorySearchFocused).submitLabel(.done)
                    .onSubmit { inventorySearchFocused = false }.accessibilityIdentifier("ui48_gear_search")
                if !searchText.isEmpty { Button("消去") { searchText = "" }.font(.caption) }
            }.padding(12).background(UI48Theme.ink.opacity(0.6)).clipShape(UI48Frame(radius: 12))
                .overlay(UI48Frame(radius: 12).stroke(UI48Theme.gold.opacity(0.5)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(qualities, id: \.self) { quality in
                        Button(quality == "すべて" ? quality : GameText.quality(quality)) { qualityFilter = quality }
                            .buttonStyle(UI48ButtonStyle(secondary: quality != qualityFilter))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            HStack {
                Text("所持 \(model.state.gear.count) 点")
                Spacer()
                Menu {
                    ForEach(["入手した順", "品質順", "名前順"], id: \.self) { order in
                        Button { inventorySort = order } label: {
                            if inventorySort == order { Label(order, systemImage: "checkmark") } else { Text(order) }
                        }
                    }
                } label: { Label(inventorySort, systemImage: "arrow.up.arrow.down").font(.caption).foregroundStyle(UI48Theme.gold) }
                .accessibilityIdentifier("ui48_inventory_sort")
            }.font(.footnote).foregroundStyle(UI48Theme.muted)
            if emptyOnly || visible.isEmpty {
                noResults
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visible) { item in
                        Button {
                            inventorySearchFocused = false
                            selectedInventoryID = item.id
                            flow.gearID = item.id
                        } label: {
                            VStack(spacing: 6) {
                                UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID,
                                         count: "+\(item.enhancement)", locked: item.protected, size: 64)
                            }.padding(3).background((selectedID == item.id ? UI48Theme.gold.opacity(0.17) : .clear))
                                .clipShape(UI48Frame(radius: 10))
                        }.buttonStyle(.plain).accessibilityLabel("\(gearName(item)), \(GameText.quality(item.qualityID)), 強化 +\(item.enhancement)\(item.protected ? ", 保護中" : "")")
                            .accessibilityIdentifier("ui48_gear_\(item.id.uuidString)")
                    }
                }
                UI48Note(text: "使用中・ロック中・保存セットの装備、各種類の最後の1点は分解対象から除きます。")
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            if !emptyOnly, let selected = selectedInventoryItem {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                    UI48Item(assetID: "ICO_" + selected.definitionID, qualityID: selected.qualityID, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(gearName(selected)).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(inventoryStatus(selected))
                            .font(.caption2).foregroundStyle(UI48Theme.muted).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    }
                    HStack(spacing: 8) {
                    Button { flow.selectGear(selected.id) } label: {
                        Label("詳しく見る", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }.buttonStyle(UI48ButtonStyle(secondary: false))
                        .accessibilityIdentifier("ui48_inventory_detail")
                    Button { selectedDismantleIDs = Set(batchEligibleGear.map(\.id)); flow.go(18) } label: {
                        Label("整理する", systemImage: "hammer").frame(maxWidth: .infinity)
                    }.buttonStyle(UI48ButtonStyle(secondary: true))
                        .accessibilityIdentifier("ui48_inventory_dismantle")
                    }
                }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal, 12).padding(.vertical, 8).background(UI48Theme.ink.opacity(0.98))
                    .overlay(alignment: .top) { Rectangle().fill(UI48Theme.gold.opacity(0.7)).frame(height: 1) }
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: 14) {
            Image(systemName: "bag").font(.system(size: 56)).foregroundStyle(UI48Theme.gold.opacity(0.72)).padding(.top, 25)
            UI48Heading(title: "まだ、見つからないみたい。", subtitle: "検索条件に合う装備はありません。")
            Text("所持品は消えていません。検索と品質の条件を解除して、すべての装備を表示できます。")
                .font(.footnote).foregroundStyle(UI48Theme.muted).fixedSize(horizontal: false, vertical: true)
            UI48Action(title: "検索と品質の条件を解除", symbol: "magnifyingglass", id: "ui48_inventory_clear_filters") {
                searchText = ""; qualityFilter = "すべて"
            }
            UI48Action(title: "持ちものを閉じる", symbol: "chevron.left", secondary: true, id: "ui48_inventory_close") { flow.back() }
        }.padding(.vertical, 18)
    }

    private var detailBody: some View {
        UI48Page {
            if let item = selectedGear {
                UI48Hero(assetID: "ICO_" + item.definitionID, title: gearName(item),
                         subtitle: "\(GameText.quality(item.qualityID)) / \(item.ownerID.map { (GameModel.actorNames[$0] ?? $0) + "が装備中" } ?? "未装備") / 強化 +\(item.enhancement)")
                if let stats = previewStats(item) {
                    UI48Panel(title: "装着した時の仲間の性能") {
                        HStack(spacing: 0) {
                            compactStat("攻撃", stats.attack)
                            compactStat("体力", stats.maxHP)
                            compactStat("防御", stats.defense)
                        }
                        if let effects = nonLatentEffects(stats), !effects.isEmpty { Text(effects.map(GameText.effect).joined(separator: "・")).font(.footnote) }
                    }
                }
                UI48Panel { GearLatentDetailsView(model: model, item: item) }
                if item.ownerID != nil && item.ownerID != model.selectedActor {
                    UI48Note(text: "この装備は\(GameModel.actorNames[item.ownerID!] ?? "別の仲間")が使用中です。先にその仲間から外してください。", warning: true)
                }
                UI48ResponsiveRow(spacing: 10) {
                    UI48Action(title: "この仲間に装備", symbol: "shield",
                               disabled: model.busy || !model.canEquip(item) || (item.ownerID != nil && item.ownerID != model.selectedActor),
                               id: "ui48_detail_equip") {
                        flow.commit(.equip(gearID: item.id, actorID: model.selectedActor), model: model, title: "装備を更新しました", resultScreen: nil)
                    }
                    UI48Action(title: "装備を比べる", symbol: "square.split.2x1", secondary: true, id: "ui48_detail_compare") { beginComparison(item) }
                }
                UI48Action(title: item.protected ? "保護中" : "保護する", symbol: "lock", secondary: true,
                           disabled: item.protected || model.busy, id: "ui48_detail_protect") {
                    flow.commit(.protect(gearID: item.id, protected: true), model: model, title: "装備を保護しました", resultScreen: nil)
                }
                UI48Panel(title: "育てる") {
                    HStack(spacing: 8) {
                        smallRoute("強化", symbol: "hammer", id: 23) { flow.go(23) }
                        smallRoute("研成", symbol: "sparkles", id: 24) { flow.go(24) }
                        smallRoute("品質", symbol: "star", id: 25) { flow.go(25) }
                    }
                    let evolutions = evolutionRecipes(for: item)
                    if !evolutions.isEmpty { UI48Action(title: "進化を選ぶ", symbol: "arrow.triangle.branch", secondary: true, id: "ui48_detail_evolve") { selectedEvolutionID = nil; flow.go(22) } }
                }
                UI48Panel(title: "装備の状態") {
                    stateLine("部位", slotName(slot(for: item)))
                    stateLine("品質", GameText.quality(item.qualityID))
                    stateLine("強化", "+\(item.enhancement)")
                    stateLine("研成", rankDescription(item))
                    stateLine("保護", item.protected ? "保護中" : "未保護")
                    if !item.affixIDs.isEmpty { stateLine("付随効果", item.affixIDs.map(GameText.effect).joined(separator: "、")) }
                }
            } else {
                UI48Note(text: "装備を選び直してください。", warning: true)
                UI48Action(title: "持ちものへ", symbol: "square.grid.2x2", id: "ui48_detail_back") { flow.go(14) }
            }
        }
    }

    private var comparisonBody: some View {
        UI48Page {
            if let selectedGear, let other = comparisonPartner(for: selectedGear) {
                HStack(spacing: 10) { UI48Portrait(actorID: model.selectedActor, size: 42); Text("\(GameModel.actorNames[model.selectedActor] ?? model.selectedActor)の装備").font(.headline) }
                HStack(alignment: .top, spacing: 10) {
                    comparisonItemCard(other, title: isActuallyEquipped(other) ? "現在の装備" : "比較対象")
                    comparisonItemCard(selectedGear, title: "比べる装備")
                }
                if let before = previewStats(other), let after = previewStats(selectedGear) {
                    UI48Panel(title: "仲間の性能") {
                        HStack { Text("性能").frame(maxWidth: .infinity, alignment: .leading); Text(isActuallyEquipped(other) ? "現在" : "比較").frame(width: 52); Text("変更後").frame(width: 70) }.font(.caption).foregroundStyle(UI48Theme.gold)
                        compareStat("攻撃", before.attack, after.attack)
                        compareStat("体力", before.maxHP, after.maxHP)
                        compareStat("防御", before.defense, after.defense)
                    }
                    if !Set(before.effectIDs).subtracting(Set(after.effectIDs)).isEmpty || !Set(after.effectIDs).subtracting(Set(before.effectIDs)).isEmpty {
                        UI48Panel(title: "働き方の違い") {
                            Text("\(isActuallyEquipped(other) ? "現在" : "比較対象"): " + effectSummary(before)).font(.footnote)
                            Text("変更後: " + effectSummary(after)).font(.footnote)
                        }
                    }
                    UI48Action(title: "こちらの装備に替える", symbol: "shield", disabled: model.busy || !model.canEquip(selectedGear), id: "ui48_compare_equip") {
                        flow.commit(.equip(gearID: selectedGear.id, actorID: model.selectedActor), model: model, title: "装備を更新しました", resultScreen: nil)
                    }
                    UI48Action(title: "比較を閉じる", symbol: "chevron.left", secondary: true, id: "ui48_compare_close") {
                        if model.state.craftedGearOnce && !model.state.gearComparisonSeen, model.engine != nil {
                            let ids = [other.id, selectedGear.id]
                            flow.commit(.markGearComparisonSeen(firstGearID: ids[0], secondGearID: ids[1]), model: model, title: "比較を終えました。無料鑑定が解放されました", resultScreen: 36)
                        } else { flow.back() }
                    }
                }
            } else {
                UI48Note(text: "同じ部位の装備を2点そろえると、仲間の性能を比較できます。", warning: true)
                UI48Action(title: "持ちものを見る", symbol: "square.grid.2x2", id: "ui48_compare_inventory") { flow.go(14) }
            }
        }
    }

    private var loadoutBody: some View {
        UI48Page {
            UI48Heading(title: "次の旅に、すぐ切り替え。", subtitle: "4人それぞれの装備を2つのセットに保存します。道具を選ぶと詳細を確かめられます。")
            ForEach([GearLoadoutSlotR342.first, .second], id: \.rawValue) { slot in
                let loadout = model.state.gearLoadoutsR342?.loadout(for: slot)
                let savedIDs = loadout.map { saved in saved.gearByActorSlot.keys.sorted().compactMap { saved.gearByActorSlot[$0] } } ?? []
                let missingIDs = Set(savedIDs).subtracting(Set(model.state.gear.map(\.id)))
                let active = loadout?.gearByActorSlot == model.state.equippedGearIDs
                UI48Panel(title: "装備セット \(slot.rawValue)") {
                    HStack {
                        Text(loadout == nil ? "未登録" : active ? "現在使用中" : "保存済み")
                            .font(.caption.weight(.semibold)).foregroundStyle(UI48Theme.gold)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(UI48Theme.enamel).clipShape(Capsule())
                        Spacer()
                        if loadout != nil, !savedIDs.isEmpty {
                            Text("4人の登録装備").font(.caption2).foregroundStyle(UI48Theme.muted)
                        }
                    }
                    if let loadout {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 54), spacing: 7), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 10) {
                            ForEach(model.state.partyActorIDs, id: \.self) { actor in
                                loadoutActorCard(actor: actor, loadoutSlot: slot, loadout: loadout)
                            }
                        }
                        .padding(.vertical, 5)
                        .accessibilityIdentifier("ui48_loadout_party_grid_\(slot.rawValue)")
                    } else { UI48Note(text: "現在の装備を保存できます。") }
                    if !missingIDs.isEmpty { UI48Note(text: "登録された装備が見つかりません。現在の構成で保存し直してください。", warning: true) }
                    HStack(spacing: 8) {
                        if loadout == nil || !active {
                            UI48Action(title: loadout == nil ? "現在の構成を保存" : "このセットを使う", symbol: loadout == nil ? "square.and.arrow.down" : "checkmark.shield",
                                       disabled: model.busy || model.fighting || !missingIDs.isEmpty && loadout != nil, id: "ui48_loadout_primary_\(slot.rawValue)") {
                                if loadout == nil { flow.commit(.saveGearLoadoutR342(slot: slot), model: model, title: "装備セットを保存しました", resultScreen: nil) }
                                else { flow.commit(.applyGearLoadoutR342(slot: slot), model: model, title: "装備セットに切り替えました", resultScreen: nil) }
                            }
                        }
                        if let loadout {
                            UI48Action(title: "詳細", symbol: "magnifyingglass", secondary: true,
                                       disabled: savedIDs.allSatisfy { id in !model.state.gear.contains(where: { $0.id == id }) },
                                       id: "ui48_loadout_detail_\(slot.rawValue)") {
                                if let key = loadout.gearByActorSlot.keys.sorted().first(where: { key in
                                    loadout.gearByActorSlot[key].map { id in model.state.gear.contains { $0.id == id } } == true
                                }), let id = loadout.gearByActorSlot[key] {
                                    model.selectedActor = String(key.split(separator: "|").first ?? Substring(model.selectedActor))
                                    flow.selectGear(id, screen: 15)
                                }
                            }
                        }
                    }
                    UI48ResponsiveRow(spacing: 8) {
                        UI48Action(title: "現在の装備で上書き", symbol: "arrow.triangle.2.circlepath", secondary: true,
                                   disabled: model.busy || model.fighting || active, id: "ui48_loadout_save_\(slot.rawValue)") {
                            confirmingLoadout = slot; pendingLoadoutAction = "save"
                        }
                        if loadout != nil {
                            UI48Action(title: "解除", symbol: "trash", secondary: true, danger: true,
                                       disabled: model.busy || model.fighting, id: "ui48_loadout_clear_\(slot.rawValue)") {
                                confirmingLoadout = slot; pendingLoadoutAction = "clear"
                            }
                        }
                    }
                }
            }
            UI48Note(text: "登録中の装備は分解から保護します。登録解除を確認した後にだけ保護が外れます。")
        }
    }

    @ViewBuilder
    private func loadoutActorCard(actor: String, loadoutSlot: GearLoadoutSlotR342, loadout: GearLoadoutR342) -> some View {
        let slots = ["weapon", "body", "hands", "feet", "ring", "amulet"]
        VStack(spacing: 5) {
            WardrobePortrait(model: model, actorID: actor, appearanceOverrides: model.sceneAppearance)
                .frame(width: 39, height: 43).clipShape(Circle())
                .overlay(Circle().stroke(UI48Theme.gold.opacity(0.8), lineWidth: 1))
            Text(GameModel.actorNames[actor] ?? actor)
                .font(.system(size: 10, weight: .medium, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.75)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)], spacing: 4) {
                    ForEach(slots, id: \.self) { slot in
                        if let item = loadoutGear(actor: actor, slot: slot, loadout: loadout) {
                            Button {
                                model.selectedActor = actor
                                flow.selectGear(item.id, screen: 15)
                            } label: {
                                VStack(spacing: 1) {
                                    UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID,
                                             count: "+\(item.enhancement)", locked: item.protected || model.state.gearLoadoutsR342?.referencedGearIDs.contains(item.id) == true, size: 31)
                                    Text(slotName(slot)).font(.system(size: 7)).lineLimit(1).minimumScaleFactor(0.65)
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(GameModel.actorNames[actor] ?? actor)・\(slotName(slot))・\(gearName(item))・詳細")
                            .accessibilityIdentifier("ui48_loadout_item_\(loadoutSlot.rawValue)_\(actor)_\(slot)")
                        } else {
                            VStack(spacing: 1) {
                                Image(systemName: "plus.square.dashed").font(.system(size: 19)).foregroundStyle(UI48Theme.gold.opacity(0.48))
                                    .frame(width: 31, height: 31).background(UI48Theme.ink.opacity(0.32)).clipShape(UI48Frame(radius: 7))
                                Text(slotName(slot)).font(.system(size: 7)).lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(UI48Theme.muted)
                            }.frame(maxWidth: .infinity)
                                .accessibilityLabel("\(GameModel.actorNames[actor] ?? actor)・\(slotName(slot))・空き")
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity, minHeight: 157, alignment: .top)
        .padding(.vertical, 7).padding(.horizontal, 2)
        .background(UI48Theme.ink.opacity(0.28)).clipShape(UI48Frame(radius: 10))
    }

    private func loadoutGear(actor: String, slot: String, loadout: GearLoadoutR342) -> GearInstance? {
        guard let id = loadout.gearByActorSlot[actor + "|" + slot]
            ?? (slot == "hands" ? loadout.gearByActorSlot[actor + "|hand"] : nil) else { return nil }
        return model.state.gear.first { $0.id == id }
    }

    private var dismantleBody: some View {
        let candidates = batchEligibleGear
        return UI48Page {
            UI48Heading(title: "手放す前に、確認。", subtitle: "必要な道具は、ちゃんと残します。")
            if candidates.isEmpty {
                UI48Panel(title: "残す装備") {
                    Text("分解できる装備はありません。").font(.headline)
                    Text("保護中、使用中、保存セット登録中、各種類の最後の1点は対象外です。持ちものから保護状態やセット登録を見直せます。")
                        .font(.footnote).foregroundStyle(UI48Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Text("分解対象").font(.headline)
                    Spacer()
                    Button(selectedDismantleIDs.count == candidates.count ? "選択解除" : "すべて選ぶ") {
                        selectedDismantleIDs = selectedDismantleIDs.count == candidates.count ? [] : Set(candidates.map(\.id))
                    }.font(.caption).foregroundStyle(UI48Theme.gold)
                }
                ScrollView(.horizontal) { HStack(spacing: 6) {
                    ForEach(candidates) { item in
                        let selected = selectedDismantleIDs.contains(item.id)
                        Button {
                            if selected { selectedDismantleIDs.remove(item.id) } else { selectedDismantleIDs.insert(item.id) }
                        } label: {
                            UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID, count: selected ? "✓" : "", size: 76)
                                .padding(3).background(selected ? UI48Theme.gold.opacity(0.16) : UI48Theme.ink.opacity(0.25)).clipShape(UI48Frame(radius: 10))
                        }.buttonStyle(.plain).accessibilityIdentifier("ui48_dismantle_select_\(item.id.uuidString)")
                            .accessibilityLabel(gearName(item) + (selected ? "、分解対象に選択中" : "、選択していません"))
                    }
                } }.scrollIndicators(.visible)
                UI48Panel(title: "受け取るもの") {
                    stateLine("対象", "未保護・未使用のC装備 \(selectedDismantleIDs.count) 点")
                    stateLine("返却", dismantleRewardText)
                    if let policy = model.engine?.gearDismantleRefundPolicyR353,
                       let summary = GearInventoryIndexR374(model.state.gear).refundSummary(ids: selectedDismantleIDs.sorted { $0.uuidString < $1.uuidString }, policy: policy) {
                        stateLine("内訳", "基礎分 \(summary.baseSalvageDust) / 育成分 \(summary.investmentRefundDust)")
                    }
                }
            }
            UI48Panel(title: "残す装備") {
                ForEach(["ロック中", "現在装備中", "保存セットに登録中", "各種類の最後の1個"], id: \.self) { reason in
                    Label(reason, systemImage: "lock.fill").font(.footnote)
                }
            }
            UI48Note(text: "分解は元に戻せません。対象を選び、確認後にのみ実行します。", warning: true)
        }.safeAreaInset(edge: .bottom, spacing: 0) { UI48ActionDock {
            UI48Action(title: "選んだ \(selectedDismantleIDs.count) 点を分解する", symbol: "hammer", danger: true,
                       disabled: selectedDismantleIDs.isEmpty || !Set(selectedDismantleIDs).isSubset(of: Set(candidates.map(\.id))) || model.busy,
                       id: "ui48_dismantle_confirm") { showBulkDismantleConfirmation = true }
            UI48Action(title: "やめる", symbol: "chevron.left", secondary: true, id: "ui48_dismantle_cancel") { flow.back() }
        } }
    }

    private var workshopBody: some View {
        let goals = model.recipeGoals
        let filtered = goals.filter { workshopMode == "制作" ? $0.kind == "craft_new" : $0.kind == "evolve_in_place" }
        return UI48Page(transparent: true) {
            // Match the approved atelier composition while preserving the live HOME_BASE art.
            if !dynamicTypeSize.isAccessibilitySize {
                Text("発見を、次の道具に。").font(.system(.largeTitle, design: .serif, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(UI48Theme.gold.opacity(0.35)).frame(height: 1)
            }
            if let goal = model.trackedRecipeGoal, let definition = gearDefinition(goal.outputGearID) {
                UI48Goal(caption: "制作の目標", title: definition.name,
                         detail: goal.requirements.filter { $0.missing > 0 }.map { "\(GameText.name($0.materialID))があと\($0.missing)個" }.joined(separator: "・").ifEmpty("必要な素材は揃っています")) {
                    flow.recipe(goal.recipeID, model: model, gearID: model.previewRecipeGearID)
                }
            }
            HStack(spacing: 8) {
                ForEach(["制作", "進化"], id: \.self) { mode in
                    Button { workshopMode = mode } label: { Text(mode).font(.headline).frame(maxWidth: .infinity, minHeight: 42).foregroundStyle(workshopMode == mode ? UI48Theme.paperInk : UI48Theme.ivory).background(workshopMode == mode ? UI48Theme.gold : .clear).clipShape(UI48Frame(radius: 8)) }.buttonStyle(.plain)
                }
            }.padding(3).background(UI48Theme.ink.opacity(0.68)).clipShape(UI48Frame(radius: 10)).overlay(UI48Frame(radius: 10).stroke(UI48Theme.gold.opacity(0.45)))
            if filtered.isEmpty {
                UI48Panel(title: "今選べる道具") {
                    Text(workshopMode == "進化" ? "進化できる装備はありません。進化元の装備を持ちものから選んでください。" : "いま制作できる道具がありません。探索を進めて材料を集めましょう。")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    UI48Action(title: "持ちものを見る", symbol: "square.grid.2x2", id: "ui48_workshop_inventory") { flow.go(14) }
                }
            } else {
                ForEach(filtered.sorted { $0.firstCraftAidApplied && !$1.firstCraftAidApplied }, id: \.recipeID) { goal in recipeRow(goal) }
            }
            if let goal = model.trackedRecipeGoal {
                UI48Action(title: "目標の材料を見る", symbol: "leaf", id: "ui48_workshop_goal_materials") { flow.recipe(goal.recipeID, model: model, gearID: model.previewRecipeGearID) }
            }
            UI48Note(text: "制作には表示された現在の素材と解放条件を使います。目標を選ぶだけでは素材を消費しません。")
        }.background {
            ZStack { UI48BackgroundArt(id: "HOME_BASE").overlay(UI48Theme.ink.opacity(0.68)); UI48Theme.background.opacity(0.22) }
                .ignoresSafeArea()
        }
    }

    private func recipeRow(_ goal: RecipeGoalProjectionR035.Goal) -> some View {
        let definition = gearDefinition(goal.outputGearID)
        return Button { flow.recipe(goal.recipeID, model: model, gearID: model.previewRecipeGearID) } label: {
            HStack(spacing: 12) {
                UI48Item(assetID: "ICO_" + goal.outputGearID, qualityID: "Q0", size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(definition?.name ?? goal.outputGearID).font(.headline).foregroundStyle(UI48Theme.ivory)
                    Text(goal.requirements.map { "\(GameText.name($0.materialID)) \($0.owned)/\($0.required)" }.joined(separator: "・"))
                        .font(.caption2).foregroundStyle(UI48Theme.muted).lineLimit(2)
                    if !goal.gateCleared { Text("討伐条件が未解放").font(.caption2).foregroundStyle(UI48Theme.gold) }
                }
                Spacer(minLength: 2)
                Text(goal.ready ? "制作可能" : "材料を見る").font(.caption).foregroundStyle(UI48Theme.gold)
            }.padding(.vertical, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(UI48Theme.gold.opacity(0.24)).frame(height: 1) }
        }.buttonStyle(.plain).accessibilityIdentifier("ui48_recipe_\(goal.recipeID)")
    }

    private func recipeGoalBody(confirmation: Bool) -> some View {
        let presentation = WorkshopPresentationR1(liveGoal: currentGoal, confirmation: confirmation,
            operationPhase: flow.craftPhase, acceptedGoal: flow.acceptedCraftGoal)
        let processing = presentation.phase == .processing
        return UI48Page {
            if let goal = presentation.goal, let definition = gearDefinition(goal.outputGearID) {
                if confirmation {
                    VStack(spacing: 4) {
                        ZStack { Circle().stroke(UI48Theme.gold.opacity(0.24), lineWidth: 8).frame(width: 112, height: 112); AssetIcon(id: "ICO_" + goal.outputGearID, size: 92) }
                        Text(definition.name).font(.system(.title2, design: .serif, weight: .semibold))
                        Text(presentation.statusText).font(.footnote).foregroundStyle(UI48Theme.muted)
                            .accessibilityIdentifier("ui48_craft_status")
                    }.frame(maxWidth: .infinity)
                } else {
                    UI48Hero(assetID: "ICO_" + goal.outputGearID, title: definition.name,
                             subtitle: "\(goal.requirements.filter { $0.missing == 0 }.count) / \(goal.requirements.count)種類の素材が揃っています")
                }
                UI48Panel(title: processing ? "今回の制作で使用する素材" : (confirmation ? "使用する素材" : "必要な素材")) {
                    ForEach(goal.requirements, id: \.materialID) { requirement in
                        HStack(spacing: 10) {
                            AssetIcon(id: "ICO_" + requirement.materialID, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(GameText.name(requirement.materialID)).font(.subheadline)
                                Text("\(processing ? "制作前の所持" : "所持") \(requirement.owned) / 必要 \(requirement.required)").font(.caption).foregroundStyle(UI48Theme.muted)
                            }
                            Spacer()
                            Text(requirement.missing == 0 ? "✓" : "あと\(requirement.missing)")
                                .font(.caption).foregroundStyle(requirement.missing == 0 ? Color(hex48: 0xa6c88a) : Color(hex48: 0xe2a28b))
                        }.padding(.vertical, 5)
                    }
                    if goal.dustRequired > 0 { stateLine("研成の粉", "\(goal.dustOwned) / \(goal.dustRequired)") }
                }
                if confirmation {
                    if let failure = flow.craftFailure {
                        UI48Note(text: "制作できませんでした。\(failure) 現在の所持品を確認してから、もう一度お試しください。", warning: true)
                    }
                    UI48Note(text: processing ? "確定した今回の材料で処理しています。保存が終わると完成品を表示します。" : "制作すると、表示された素材を消費し、完成品を保存します。")
                    UI48Action(title: processing ? "保存しています…" : "この道具をつくる", symbol: "hammer", disabled: !goal.ready || !goal.dispatchCompatible || model.busy,
                               id: "ui48_craft_commit") {
                        flow.commit(.craftRecipe(goal.recipeID), model: model, title: "\(definition.name)を制作しました")
                    }
                    if !goal.ready && !processing {
                        UI48Action(title: "不足しているものを確認", symbol: "leaf", secondary: true, disabled: model.busy, id: "ui48_craft_requirements") { flow.craftPhase=nil;flow.go(20) }
                    }
                    UI48Action(title: "工房に戻る", symbol: "chevron.left", secondary: true, disabled: model.busy, id: "ui48_craft_back") { flow.go(19) }
                } else {
                    let missing = goal.requirements.filter { $0.missing > 0 }
                    if let requirement = missing.first {
                        UI48Goal(caption: "今、足りないもの", title: "\(GameText.name(requirement.materialID))をあと\(requirement.missing)個",
                                 detail: firstMaterialSource(requirement)) { routeToMaterial(goal, requirement) }
                    } else if !goal.gateCleared {
                        UI48Panel(title: "討伐条件") {
                            Text("必要な地域の主を倒すと、この制作が解放されます。")
                                .font(.footnote).fixedSize(horizontal: false, vertical: true)
                            UI48Action(title: "探索へ", symbol: "location.north.circle", id: "ui48_recipe_gate") { flow.go(5) }
                        }
                    }
                    UI48Note(text: goal.firstCraftAidApplied ? "初回制作の条件を表示しています。通常レシピと区別して案内します。" : "表示は現在の所持素材・解放条件です。目標を選ぶだけでは消費しません。")
                    if let requirement = missing.first {
                        UI48Action(title: "\(GameText.name(requirement.materialID))の入手先へ", symbol: "leaf", id: "ui48_recipe_gather") { routeToMaterial(goal, requirement) }
                    }
                    if goal.dustMissing > 0 {
                        UI48Goal(caption: "足りない制作道具", title: "研成の粉があと\(goal.dustMissing)個",
                                 detail: "不要な重複装備を整理すると、現在の分解ルールに応じて粉を受け取れます。") { flow.go(14) }
                        UI48Action(title: "持ちものから装備を整理", symbol: "hammer", id: "ui48_recipe_dust_route") { flow.go(14) }
                    }
                    UI48Action(title: "この道具を目標にする", symbol: "bookmark", secondary: true, disabled: model.busy, id: "ui48_recipe_track") {
                        model.previewRecipeID = goal.recipeID
                        model.previewRecipeGearID = flow.gearID
                        flow.commit(.setTrackedRecipe(goal.recipeID), model: model, title: "制作目標を保存しました", resultScreen: nil)
                    }
                    if goal.ready { UI48Action(title: "制作の内容を確認", symbol: "checkmark.circle", disabled: model.busy, id: "ui48_recipe_confirm") { flow.craftPhase=nil;flow.go(21) } }
                    UI48Action(title: "工房に戻る", symbol: "chevron.left", secondary: true, disabled: model.busy, id: "ui48_recipe_cancel") { flow.go(19) }
                }
            } else {
                UI48Note(text: "レシピの所持条件が変わりました。現在の工房一覧から選び直してください。", warning: true)
                UI48Action(title: "工房へ戻る", symbol: "chevron.left", id: "ui48_recipe_missing_back") { flow.go(19) }
            }
        }
    }

    private var evolutionBody: some View {
        UI48Page {
            if let item = selectedGear {
                UI48Heading(title: "どんな力を育てる？", subtitle: "同じ装備個体を、素材と条件を確かめて別の道具へ。")
                let recipes = evolutionRecipes(for: item)
                UI48Panel(title: "進化元") {
                    HStack(spacing: 14) {
                        UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID,
                                 count: "+\(item.enhancement)", locked: item.protected, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gearName(item)).font(.headline)
                            Text("\(GameText.quality(item.qualityID)) ・ 強化 +\(item.enhancement) ・ 研成 \(rankDescription(item))")
                                .font(.caption).foregroundStyle(UI48Theme.muted).fixedSize(horizontal: false, vertical: true)
                            Text("この装備個体の状態を引き継ぎます").font(.caption2)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if recipes.count == 2 {
                    Canvas { context, size in
                        var branch = Path()
                        branch.move(to: CGPoint(x: size.width / 2, y: 0))
                        branch.addLine(to: CGPoint(x: size.width / 2, y: 11))
                        branch.move(to: CGPoint(x: size.width * 0.25, y: 11))
                        branch.addLine(to: CGPoint(x: size.width * 0.75, y: 11))
                        branch.move(to: CGPoint(x: size.width * 0.25, y: 11))
                        branch.addLine(to: CGPoint(x: size.width * 0.25, y: size.height))
                        branch.move(to: CGPoint(x: size.width * 0.75, y: 11))
                        branch.addLine(to: CGPoint(x: size.width * 0.75, y: size.height))
                        context.stroke(branch, with: .color(UI48Theme.gold.opacity(0.8)), lineWidth: 1.4)
                    }.frame(height: 24).padding(.horizontal, 8)
                } else if !recipes.isEmpty {
                    HStack(spacing: 5) {
                        Rectangle().fill(UI48Theme.gold.opacity(0.5)).frame(width: 1, height: 16)
                        Image(systemName: "arrow.down").font(.caption2).foregroundStyle(UI48Theme.gold)
                        Text("実際に登録された進化先").font(.caption2).foregroundStyle(UI48Theme.muted)
                    }.frame(maxWidth: .infinity)
                }
                if recipes.isEmpty {
                    UI48Note(text: "この装備から進める進化先は登録されていません。持ちものから別の装備を選んでください。", warning: true)
                } else {
                    let branchColumns = recipes.count == 2 && dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : Array(repeating: GridItem(.flexible(), spacing: 10), count: min(2, recipes.count))
                    LazyVGrid(columns: branchColumns, spacing: 10) {
                        ForEach(recipes) { recipe in
                            let goal = model.recipeGoals.first { $0.recipeID == recipe.id }
                            evolutionBranchCard(recipe: recipe, source: item, goal: goal,
                                                selected: (selectedEvolutionID ?? recipes.first?.id) == recipe.id)
                        }
                    }
                }
                if let recipe = recipes.first(where: { $0.id == (selectedEvolutionID ?? recipes.first?.id) }),
                   let goal = model.recipeGoals.first(where: { $0.recipeID == recipe.id }) {
                    UI48Panel(title: "次の道具に必要なもの") {
                        Text(gearName(recipe.outputGearID ?? "")).font(.headline)
                        Text(goal.ready ? "素材と解放条件を満たしています。" : "不足分と次にできることを確認してください。")
                            .font(.caption).foregroundStyle(goal.ready ? UI48Theme.gold : UI48Theme.muted)
                        ForEach(goal.requirements, id: \.materialID) { row in stateLine(GameText.name(row.materialID), "\(row.owned) / \(row.required)") }
                        if goal.dustRequired > 0 { stateLine(GameText.name("refine_dust"), "\(goal.dustOwned) / \(goal.dustRequired)") }
                        if !goal.gateCleared { UI48Note(text: "必要な討伐条件が未達です。", warning: true) }
                    }
                    ForEach(goal.requirements.filter { $0.missing > 0 }, id: \.materialID) { requirement in
                        UI48Action(title: "\(GameText.name(requirement.materialID))の入手先へ", symbol: "leaf", secondary: true,
                                   id: "ui48_evolution_material_\(requirement.materialID)") { routeToMaterial(goal, requirement) }
                    }
                    if goal.dustMissing > 0 {
                        UI48Action(title: "研成の粉を得るため持ちものを整理", symbol: "hammer", secondary: true,
                                   id: "ui48_evolution_dust_route") { flow.go(14) }
                    }
                    if !goal.gateCleared {
                        UI48Action(title: "探索で討伐条件を確認", symbol: "location.north.circle", secondary: true,
                                   id: "ui48_evolution_gate_route") { flow.go(5) }
                    }
                    UI48Action(title: "進化の内容を確認", symbol: "arrow.triangle.branch", disabled: !goal.ready || !goal.dispatchCompatible || model.busy,
                               id: "ui48_evolution_confirm") {
                        flow.commit(.evolveGear(gearID: item.id, recipeID: recipe.id), model: model,
                                    title: "\(gearName(recipe.outputGearID ?? ""))へ進化しました")
                    }
                }
                UI48Action(title: "工房へ戻る", symbol: "chevron.left", secondary: true, id: "ui48_evolution_back") { flow.back() }
            } else { UI48Note(text: "進化元の装備を選び直してください。", warning: true) }
        }
    }

    private func evolutionBranchCard(recipe: RecipeDefinition, source: GearInstance,
                                     goal: RecipeGoalProjectionR035.Goal?, selected: Bool) -> some View {
        let outputID = recipe.outputGearID ?? ""
        let output = model.catalog?.gear.first { $0.id == outputID }
        return Button { selectedEvolutionID = recipe.id } label: {
            VStack(spacing: 7) {
                UI48Item(assetID: "ICO_" + outputID, qualityID: source.qualityID, size: 70)
                Text(gearName(outputID)).font(.system(.headline, design: .serif))
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let output {
                    Text(slotName(output.slot)).font(.caption2).foregroundStyle(UI48Theme.muted)
                }
                Text(goal?.ready == true ? "進化できます" : "必要なものを見る")
                    .font(.caption2.weight(.semibold)).foregroundStyle(goal?.ready == true ? UI48Theme.gold : UI48Theme.muted)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.caption).foregroundStyle(UI48Theme.gold)
            }
            .frame(maxWidth: .infinity, minHeight: 168)
            .padding(9)
            .background(selected ? UI48Theme.enamel : UI48Theme.ink.opacity(0.38))
            .clipShape(UI48Frame(radius: 18))
            .overlay(UI48Frame(radius: 18).stroke(selected ? UI48Theme.gold : UI48Theme.gold.opacity(0.55), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(goal == nil)
        .opacity(goal == nil ? 0.45 : 1)
        .accessibilityLabel("進化先 \(gearName(outputID))・\(goal?.ready == true ? "準備完了" : "必要条件を確認")")
        .accessibilityIdentifier("ui48_evolution_branch_\(recipe.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func upgradeBody(action: GearUpgradeActionR218) -> some View {
        UI48Page {
            if let item = selectedGear, let recipe = upgradeRecipe(action, item: item) {
                UI48Hero(assetID: "ICO_" + item.definitionID, title: gearName(item),
                         subtitle: action == .enhance ? "強化 +\(item.enhancement) → +\(item.enhancement + 1)" : "\(GameText.quality(item.qualityID)) → \(nextQuality(item.qualityID) ?? "上限")")
                if let current = projectedCombatStats(item), let next = projectedCombatStats(upgraded(item, action: action)) {
                    UI48Panel(title: "装備したときの変化") {
                        statDelta("\(GameModel.actorNames[model.selectedActor] ?? model.selectedActor)の攻撃", current.attack, next.attack)
                        statDelta("体力", current.maxHP, next.maxHP)
                        statDelta("防御", current.defense, next.defense)
                    }
                }
                let enhancementCap = model.naturalGearRefinementPolicyR352?.maximumEnhancement(
                    forRank: model.state.naturalGearRefinementR352?.rank(for: item.id) ?? 1)
                let enhancementAtCap = action == .enhance && enhancementCap.map { item.enhancement >= $0 } == true
                let refinementPolicyUnavailable = action == .enhance && NaturalGearRefinementBuildPolicyR352.enabled && model.naturalGearRefinementPolicyR352 == nil
                let enhancementCapUnavailable = action == .enhance && NaturalGearRefinementBuildPolicyR352.enabled && enhancementCap == nil
                UI48Panel(title: "使うもの") {
                    ForEach(recipe.costs.keys.sorted(), id: \.self) { materialID in
                        stateLine(GameText.name(materialID), "所持 \(model.state.materials[materialID, default: 0]) / 必要 \(recipe.costs[materialID, default: 0])")
                    }
                    if recipe.dustCost > 0 {
                        stateLine(GameText.name("refine_dust"), "所持 \(model.state.materials["refine_dust", default: 0]) / 必要 \(recipe.dustCost)")
                    }
                    if action == .enhance, NaturalGearRefinementBuildPolicyR352.enabled {
                        stateLine("現在の強化上限", enhancementCap.map { "+\($0)" } ?? "確認できません")
                    }
                }
                if action == .promoteQuality, recipe.qualityTo != nil {
                    UI48Note(text: "品質昇格の条件は調整中です。表示中の所持数と必要数を確認してください。")
                }
                if enhancementAtCap {
                    UI48Note(text: "現在の研成段階では強化上限 +\(enhancementCap ?? item.enhancement) です。研成を進めると上限が上がります。", warning: true)
                    UI48Action(title: "研成画面で次の段階を見る", symbol: "sparkles", secondary: true, id: "ui48_upgrade_refinement_route") { flow.go(24) }
                } else if refinementPolicyUnavailable || enhancementCapUnavailable {
                    UI48Note(text: "強化条件を安全に読み込めません。操作は保存していません。", warning: true)
                } else if let gate = unmetGate(recipe.gateID) {
                    UI48Note(text: gate, warning: true)
                    UI48Action(title: "探索で解放条件を確認", symbol: "location.north.circle", secondary: true, id: "ui48_upgrade_gate_route") { flow.go(5) }
                }
                else if model.state.materials["refine_dust", default: 0] < recipe.dustCost {
                    UI48Note(text: "研成の粉があと\(recipe.dustCost - model.state.materials["refine_dust", default: 0])個必要です。", warning: true)
                }
                if action == .promoteQuality {
                    UI48Panel(title: "引き継ぐもの") {
                        stateLine("装備の型・強化・研成", "そのまま")
                        stateLine("潜在効果の組合せ", "そのまま")
                        Text("確認して昇格すると、表示した素材を消費します。装備のロックやセット登録は引き継ぎます。")
                            .font(.footnote).foregroundStyle(UI48Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                UI48Note(text: "表示している性能差は、現在の仲間と装備構成から計算しています。確定するまで素材は消費しません。")
            } else {
                UI48Note(text: "現在の装備やレシピ条件を確認できません。持ちものから開き直してください。", warning: true)
                UI48Action(title: "持ちものへ", symbol: "square.grid.2x2", id: "ui48_upgrade_back") { flow.go(14) }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = selectedGear, let recipe = upgradeRecipe(action, item: item) {
                let enhancementCap = model.naturalGearRefinementPolicyR352?.maximumEnhancement(
                    forRank: model.state.naturalGearRefinementR352?.rank(for: item.id) ?? 1)
                let enhancementAtCap = action == .enhance && enhancementCap.map { item.enhancement >= $0 } == true
                let refinementPolicyUnavailable = action == .enhance && NaturalGearRefinementBuildPolicyR352.enabled && model.naturalGearRefinementPolicyR352 == nil
                let enhancementCapUnavailable = action == .enhance && NaturalGearRefinementBuildPolicyR352.enabled && enhancementCap == nil
                let canApply = !enhancementAtCap && !refinementPolicyUnavailable && !enhancementCapUnavailable && recipe.dustCost <= model.state.materials["refine_dust", default: 0] && unmetGate(recipe.gateID) == nil && actionCompatible(action, item: item)
                UI48ActionDock {
                    UI48Action(title: confirmationTitle(action, recipe: recipe), symbol: "hammer", disabled: !canApply || model.busy,
                               id: "ui48_upgrade_commit_\(action.rawValue)") {
                        flow.commit(action.command(gearID: item.id), model: model, title: "\(gearName(item))を\(action.title)しました")
                    }
                    UI48Action(title: "やめる", symbol: "chevron.left", secondary: true, id: "ui48_upgrade_cancel") { flow.back() }
                }
            }
        }
    }

    private var refinementBody: some View {
        UI48Page {
            if let item = selectedGear, let transition = refinementTransition(for: item) {
                UI48Hero(assetID: "ICO_" + item.definitionID, title: gearName(item), subtitle: "研成 \(transition.fromLabel) → \(transition.toLabel)")
                if transition.ranks.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { rank in
                            Text(GearRefinementPresentationR352.rankName(rank))
                                .font(.caption).frame(maxWidth: .infinity, minHeight: 38)
                                .background(rank == transition.nextRank ? UI48Theme.gold.opacity(0.3) : UI48Theme.ink.opacity(0.3))
                                .clipShape(Circle()).overlay(Circle().stroke(UI48Theme.gold.opacity(0.5)))
                        }
                    }
                }
                UI48Panel(title: "次の段階でできること") {
                    stateLine("強化できる上限", transition.capText)
                    stateLine("道具の個体", "同じ個体を維持")
                }
                UI48Panel(title: "必要な素材") {
                    ForEach(transition.materialCosts.keys.sorted(), id: \.self) { id in
                        stateLine(GameText.name(id), "\(model.state.materials[id, default: 0]) / \(transition.materialCosts[id, default: 0])")
                    }
                    stateLine(GameText.name("refine_dust"), "\(model.state.materials["refine_dust", default: 0]) / \(transition.dustCost)")
                }
                if let gate = unmetGate(transition.gateID) { UI48Note(text: gate, warning: true) }
                UI48Note(text: "条件を満たして確認した後に実行します。所持不足や未解放時は装備も素材も変わりません。")
            } else if let item = selectedGear, NaturalGearRefinementBuildPolicyR352.enabled {
                UI48Hero(assetID: "ICO_" + item.definitionID, title: gearName(item), subtitle: "研成段階を確認できません")
                UI48Note(text: model.naturalGearRefinementPolicyR352 == nil ? "研成条件を安全に読み込めません。操作は保存していません。" : "この装備は現在の研成上限に達しています。", warning: true)
                UI48Action(title: "装備の詳細へ戻る", symbol: "chevron.left", secondary: true, id: "ui48_refinement_unavailable_back") { flow.back() }
            } else if let item = selectedGear {
                UI48Hero(assetID: "ICO_" + item.definitionID, title: gearName(item), subtitle: "研成 \(item.refinement) → \(item.refinement + 1)")
                UI48Panel(title: "必要なもの") { stateLine(GameText.name("refine_dust"), "\(model.state.materials["refine_dust", default: 0]) / 5") }
                UI48Note(text: "現在の研成ルールを使います。研成の粉5個を消費して、この装備個体の研成を1段階上げます。")
                UI48Action(title: "研成する", symbol: "sparkles", disabled: model.state.materials["refine_dust", default: 0] < 5 || model.busy,
                           id: "ui48_refinement_legacy_commit") {
                    flow.commit(.refine(gearID: item.id), model: model, title: "研成しました")
                }
                UI48Action(title: "やめる", symbol: "chevron.left", secondary: true, id: "ui48_refinement_legacy_cancel") { flow.back() }
            } else { UI48Note(text: "装備を選び直してください。", warning: true) }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = selectedGear, let transition = refinementTransition(for: item) {
                UI48ActionDock {
                    UI48Action(title: "研成の内容を確認", symbol: "sparkles", disabled: !transition.ready || model.busy,
                               id: "ui48_refinement_commit") {
                        flow.commit(.refine(gearID: item.id), model: model, title: "研成段階を上げました")
                    }
                    UI48Action(title: "やめる", symbol: "chevron.left", secondary: true, id: "ui48_refinement_cancel") { flow.back() }
                }
            }
        }
    }

    private var resultBody: some View {
        UI48Page {
            Image(systemName: "hammer.circle").font(.system(size: 52)).foregroundStyle(UI48Theme.gold).frame(maxWidth: .infinity).padding(.top, 4)
            Text("次の冒険の、相棒に。").font(.system(.largeTitle, design: .serif, weight: .semibold)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text(flow.resultTitle).font(.footnote).foregroundStyle(UI48Theme.muted).frame(maxWidth: .infinity)
            if let item = flow.resultGearIDs.compactMap({ id in model.state.gear.first { $0.id == id } }).first {
                VStack(spacing: 4) {
                    ZStack { Circle().stroke(UI48Theme.gold.opacity(0.24), lineWidth: 8).frame(width: 150, height: 150); AssetIcon(id: "ICO_" + item.definitionID, size: 122) }
                    Text(gearName(item)).font(.system(.title2, design: .serif, weight: .semibold))
                    Text("\(GameText.quality(item.qualityID)) / \(flow.resultDetail)").font(.footnote).foregroundStyle(UI48Theme.muted)
                }.frame(maxWidth: .infinity)
                UI48Note(text: "完成品は持ちものに保存され、採集帳に記録されました。")
                UI48Action(title: "仲間の装備と比べる", symbol: "shield", id: "ui48_result_compare") { beginComparison(item) }
            } else {
                Text(flow.resultDetail.isEmpty ? "操作内容を保存しました。" : flow.resultDetail).font(.subheadline).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            UI48Action(title: "工房へ戻る", symbol: "chevron.left", secondary: true, id: "ui48_result_workshop") { flow.go(19) }
            UI48Action(title: "持ちものを見る", symbol: "square.grid.2x2", id: "ui48_result_inventory") { flow.go(14) }
        }
    }

    // MARK: Catalog-backed projections

    private var filteredGear: [GearInstance] {
        let filtered = model.state.gear.filter { item in
            let matchesQuality = qualityFilter == "すべて" || item.qualityID == qualityFilter
            let name = gearName(item)
            return matchesQuality && (searchText.isEmpty || name.localizedCaseInsensitiveContains(searchText))
        }
        switch inventorySort {
        case "品質順":
            let rank = ["Q0": 0, "Q1": 1, "Q2": 2, "Q3": 3, "Q4": 4]
            return filtered.sorted {
                let left = rank[$0.qualityID, default: -1], right = rank[$1.qualityID, default: -1]
                return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
            }
        case "名前順":
            return filtered.sorted { gearName($0).localizedStandardCompare(gearName($1)) == .orderedAscending }
        default:
            return Array(filtered.reversed())
        }
    }
    private var selectedID: UUID? { selectedInventoryID ?? flow.gearID }
    private var selectedInventoryItem: GearInstance? { selectedID.flatMap { id in model.state.gear.first { $0.id == id } } }
    private var selectedGear: GearInstance? { flow.gearID.flatMap { id in model.state.gear.first { $0.id == id } } ?? selectedInventoryItem }
    private var savedGearIDs: Set<UUID> { model.state.gearLoadoutsR342?.referencedGearIDs ?? [] }
    private var batchEligibleGear: [GearInstance] {
        let index = GearInventoryIndexR374(model.state.gear)
        return index.recyclableIDs(in: model.state.gear, equippedIDs: Set(model.state.equippedGearIDs.values),
                                   savedLoadoutIDs: savedGearIDs).compactMap(index.firstGear(id:))
    }
    private var dismantleRewardText: String {
        let ids = selectedDismantleIDs.sorted { $0.uuidString < $1.uuidString }
        if let policy = model.engine?.gearDismantleRefundPolicyR353,
           let summary = GearInventoryIndexR374(model.state.gear).refundSummary(ids: ids, policy: policy) {
            return "研成の粉 \(summary.totalDust) 個"
        }
        return "研成の粉 \(ids.count) 個"
    }
    private var currentGoal: RecipeGoalProjectionR035.Goal? { model.previewRecipeGoal }

    private func gearDefinition(_ id: String) -> GearDefinition? { model.catalog?.gear.first { $0.id == id } }
    private func gearName(_ item: GearInstance) -> String { gearName(item.definitionID) }
    private func gearName(_ id: String) -> String { gearDefinition(id)?.name ?? id }
    private func slot(for item: GearInstance) -> String { gearDefinition(item.definitionID)?.slot ?? "" }
    private func slotName(_ slot: String) -> String {
        ["weapon": "杖・武器", "body": "衣", "hands": "手", "hand": "手", "feet": "足", "ring": "指輪", "amulet": "首飾り"][slot] ?? slot
    }
    private func equippedItem(for actor: String, slot: String) -> GearInstance? {
        guard let id = model.state.equippedGearIDs["\(actor)|\(slot)"]
            ?? (slot == "hands" ? model.state.equippedGearIDs["\(actor)|hand"] : nil) else { return nil }
        return model.state.gear.first { $0.id == id }
    }
    private func actorStats(_ actor: String) -> Combatant? {
        let equipped = model.state.equippedGearIDs.filter { $0.key.hasPrefix(actor + "|") }.values
            .compactMap { id in model.state.gear.first { $0.id == id } }
        return try? model.gearStats(for: actor, with: equipped).combatant
    }
    private func previewStats(_ item: GearInstance) -> Combatant? { projectedCombatStats(item) }
    private func projectedCombatStats(_ candidate: GearInstance) -> Combatant? {
        guard let definition = gearDefinition(candidate.definitionID), definition.actorIDs.isEmpty || definition.actorIDs.contains(model.selectedActor) else { return nil }
        let equipped = model.state.equippedGearIDs.filter { $0.key.hasPrefix(model.selectedActor + "|") && $0.key != model.selectedActor + "|" + definition.slot }
            .values.compactMap { id in model.state.gear.first { $0.id == id } }
        var preview = candidate
        preview.ownerID = model.selectedActor
        return try? model.gearStats(for: model.selectedActor, with: equipped + [preview]).combatant
    }
    private func nonLatentEffects(_ stats: Combatant) -> [String]? { stats.effectIDs.sorted().filter { !$0.hasPrefix("AF_") } }
    private func effectSummary(_ stats: Combatant) -> String {
        let values = nonLatentEffects(stats) ?? []
        return values.isEmpty ? "有効な追加効果はありません" : values.map(GameText.effect).joined(separator: "・")
    }
    private func rankDescription(_ item: GearInstance) -> String {
        if model.naturalGearRefinementPolicyR352 != nil {
            return GearRefinementPresentationR352.rankName(model.state.naturalGearRefinementR352?.rank(for: item.id) ?? 1)
                + (item.refinement > 0 ? " / 従来補正 +\(item.refinement)" : "")
        }
        return "\(item.refinement)"
    }
    private func statLine(_ title: String, _ value: Int) -> some View {
        HStack { Text(title); Spacer(); Text("\(value)").font(.system(.title3, design: .serif)) }.padding(.vertical, 3)
    }
    private func compactStat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(UI48Theme.muted)
            Text("\(value)").font(.system(.title3, design: .serif)).monospacedDigit()
        }.frame(maxWidth: .infinity)
    }
    private func inventoryStatus(_ item: GearInstance) -> String {
        let equippedBy = model.state.equippedGearIDs.first(where: { $0.value == item.id })?.key.components(separatedBy: "|").first
        let conditions = [item.protected ? "保護中" : nil,
                          savedGearIDs.contains(item.id) ? "保存セット登録・分解保護" : nil,
                          equippedBy.map { "\(GameModel.actorNames[$0] ?? $0)が装備中" },
                          "\(GameText.quality(item.qualityID)) / 強化 +\(item.enhancement)"].compactMap { $0 }
        return conditions.joined(separator: "・")
    }
    private func stateLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) { Text(title).foregroundStyle(UI48Theme.muted); Spacer(minLength: 10); Text(value).multilineTextAlignment(.trailing) }.font(.footnote).padding(.vertical, 3)
    }
    private func compareStat(_ title: String, _ current: Int, _ after: Int) -> some View {
        let diff = after - current
        return HStack(spacing: 6) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(current)").frame(width: 52)
            HStack(spacing: 3) { Text("\(after)"); Text(diff == 0 ? "—" : diff > 0 ? "↑\(diff)" : "↓\(-diff)") }
                .foregroundStyle(diff >= 0 ? Color(hex48: 0xb8d99b) : Color(hex48: 0xe6a08c)).frame(width: 70, alignment: .trailing)
        }.font(.footnote).padding(.vertical, 6).overlay(alignment: .bottom) { Rectangle().fill(UI48Theme.gold.opacity(0.18)).frame(height: 1) }
    }
    private func statDelta(_ label: String, _ current: Int, _ next: Int) -> some View {
        HStack { Text(label); Spacer(); Text("\(current) → \(next)").foregroundStyle(next >= current ? UI48Theme.ivory : Color(hex48: 0xe6a08c)) }.font(.footnote).padding(.vertical, 5)
    }
    private func comparisonItemCard(_ item: GearInstance, title: String) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.caption).foregroundStyle(UI48Theme.gold)
            UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID, count: "+\(item.enhancement)", locked: item.protected, size: 78)
            Text(gearName(item)).font(.caption).multilineTextAlignment(.center).lineLimit(2)
            Text("\(GameText.quality(item.qualityID)) / 強化 +\(item.enhancement)").font(.caption2).foregroundStyle(UI48Theme.muted)
            Text("研成 \(rankDescription(item))").font(.caption2).foregroundStyle(UI48Theme.muted)
        }.frame(maxWidth: .infinity).padding(10).background(UI48Theme.ink.opacity(0.32)).clipShape(UI48Frame(radius: 12))
    }
    private func comparisonPartner(for item: GearInstance) -> GearInstance? {
        if let actual = equippedItem(for: model.selectedActor, slot: slot(for: item)), actual.id != item.id { return actual }
        guard let catalog = model.catalog else { return nil }
        let usable = Set(model.state.gear.filter { model.canEquip($0) }.map(\.id))
        guard let partnerID = GearComparisonPartnerSelectionR210.selectCounterpart(itemID: item.id, actorID: model.selectedActor,
            gear: model.state.gear, definitions: catalog.gear, equippedGearIDs: model.state.equippedGearIDs, usableGearIDs: usable),
              partnerID != item.id else { return nil }
        return model.state.gear.first { $0.id == partnerID && $0.id != item.id }
    }
    private func beginComparison(_ item: GearInstance) {
        let originalActor = model.selectedActor
        for actorID in model.state.partyActorIDs {
            model.selectedActor = actorID
            guard model.canEquip(item) else { continue }
            let actual = equippedItem(for: actorID, slot: slot(for: item))
            let candidate: GearInstance
            let baseline: GearInstance?
            if let actual, actual.id == item.id {
                guard let alternative = model.state.gear.first(where: { $0.id != item.id && slot(for: $0) == slot(for: item) && model.canEquip($0) }) else { continue }
                candidate = alternative
                baseline = actual
            } else {
                candidate = item
                baseline = actual ?? comparisonPartner(for: item)
            }
            guard let baseline, baseline.id != candidate.id else { continue }
            flow.gearID = candidate.id
            model.comparison = [baseline.id, candidate.id]
            flow.go(16)
            return
        }
        model.selectedActor = originalActor
        model.error = "装備できる仲間に、同じ部位の比較対象がありません。仲間か持ちものを確認してください。"
    }

    private func isActuallyEquipped(_ item: GearInstance) -> Bool {
        equippedItem(for: model.selectedActor, slot: slot(for: item))?.id == item.id
    }
    private func loadoutSummary(actor: String, loadout: GearLoadoutR342) -> String {
        let items = loadout.gearByActorSlot.filter { $0.key.hasPrefix(actor + "|") }.sorted { $0.key < $1.key }.map { key, id in
            let gear = model.state.gear.first { $0.id == id }
            return gear.map { "\(slotName(String(key.split(separator: "|").last ?? ""))): \(gearName($0))" } ?? "登録品なし"
        }
        return items.isEmpty ? "装備登録なし" : items.joined(separator: "・")
    }
    private func evolutionRecipes(for item: GearInstance) -> [RecipeDefinition] {
        model.catalog?.recipes.filter { $0.kind == "evolve_in_place" && $0.parentTemplateID == item.definitionID } ?? []
    }
    private func firstMaterialSource(_ requirement: RecipeGoalProjectionR035.Requirement) -> String {
        if let region = requirement.availableGatherRegions.first, let name = model.catalog?.regions.first(where: { $0.id == region })?.name {
            return "\(name)で採集できます"
        }
        if let region = requirement.availableEnemyDropRegions.first, let name = model.catalog?.regions.first(where: { $0.id == region })?.name {
            return "\(name)の魔物から入手できます"
        }
        if let region = requirement.lockedGatherRegions.first, let name = model.catalog?.regions.first(where: { $0.id == region })?.name {
            return "\(name)の解放後に採集できます"
        }
        return "現在利用できる入手先はありません。探索条件を確認してください。"
    }
    private func routeToMaterial(_ goal: RecipeGoalProjectionR035.Goal, _ requirement: RecipeGoalProjectionR035.Requirement) {
        flow.pendingRecipeGather = nil
        flow.pendingInvestigation = nil
        flow.pendingResearchGather = nil
        flow.pendingEncounterAfterSwitch = nil
        flow.workTarget = nil
        flow.materialID = requirement.materialID
        if let regionID = requirement.availableGatherRegions.first {
            flow.pendingRecipeGather = RecipeGatherHandoffR039(recipeID: goal.recipeID, materialID: requirement.materialID,
                                                               regionID: regionID, missing: requirement.missing)
            flow.go(12)
        } else if let catalog = model.catalog,
                  let route = RecipeInvestigationRouteR158.available(goal: goal, catalog: catalog,
                      state: model.state, sharedWorkEnabled: model.sharedPartyWorkR146Enabled).first(where: { $0.materialID == requirement.materialID }) {
            flow.pendingInvestigation = route
            flow.go(12)
        } else if let enemy = model.catalog?.enemies.first(where: { $0.dropMaterialID == requirement.materialID }) {
            // Unbeaten sources cannot be re-investigated yet. Present the real
            // prerequisite and a route to its encounter without changing work.
            flow.regionID = enemy.regionID
            flow.workTarget = .investigate(enemy.id)
            flow.go(12)
        } else if let region = requirement.lockedGatherRegions.first {
            flow.regionID = region
            flow.workTarget = .gather(requirement.materialID)
            flow.go(12)
        } else {
            model.error = "この素材の現在の入手先を確認できません。"
        }
    }
    private func goal(for recipeID: String) -> RecipeGoalProjectionR035.Goal? { model.recipeGoals.first { $0.recipeID == recipeID } }
    private func upgradeRecipe(_ action: GearUpgradeActionR218, item: GearInstance) -> RecipeDefinition? {
        switch action {
        case .enhance: return model.catalog?.recipes.first { $0.id == "ENHANCE_\(item.enhancement + 1)" && $0.kind == "enhance" }
        case .refine: return nil
        case .promoteQuality:
            let order = ["Q0", "Q1", "Q2", "Q3", "Q4"]
            guard let index = order.firstIndex(of: item.qualityID), index < 4 else { return nil }
            let id = ["QUALITY_Q0_Q1", "QUALITY_Q1_Q2", "QUALITY_Q2_Q3", "QUALITY_Q3_Q4"][index]
            return model.catalog?.recipes.first { $0.id == id && $0.kind == "quality" }
        }
    }
    private func upgraded(_ item: GearInstance, action: GearUpgradeActionR218) -> GearInstance {
        var next = item
        switch action {
        case .enhance: next.enhancement += 1
        case .refine: next.refinement += 1
        case .promoteQuality:
            let order = ["Q0", "Q1", "Q2", "Q3", "Q4"]
            if let i = order.firstIndex(of: item.qualityID), i < order.count - 1 { next.qualityID = order[i + 1] }
        }
        return next
    }
    private func nextQuality(_ id: String) -> String? {
        let order = ["Q0", "Q1", "Q2", "Q3", "Q4"]
        guard let index = order.firstIndex(of: id), index + 1 < order.count else { return nil }
        return GameText.quality(order[index + 1])
    }
    private func actionCompatible(_ action: GearUpgradeActionR218, item: GearInstance) -> Bool {
        switch action {
        case .refine: return model.state.materials["refine_dust", default: 0] >= 5
        case .enhance:
            guard let recipe = upgradeRecipe(action, item: item),
                  recipe.dustCost <= model.state.materials["refine_dust", default: 0],
                  unmetGate(recipe.gateID) == nil else { return false }
            if let policy = model.naturalGearRefinementPolicyR352 {
                let rank = model.state.naturalGearRefinementR352?.rank(for: item.id) ?? 1
                guard let cap = policy.maximumEnhancement(forRank: rank), item.enhancement < cap else { return false }
            } else if NaturalGearRefinementBuildPolicyR352.enabled { return false }
            return true
        case .promoteQuality:
            guard let recipe = upgradeRecipe(action, item: item) else { return false }
            return recipe.dustCost <= model.state.materials["refine_dust", default: 0] && unmetGate(recipe.gateID) == nil
        }
    }
    private func unmetGate(_ gateID: String?) -> String? {
        guard let gateID, gateID != "G_START" else { return nil }
        let parts = gateID.split(separator: "_")
        guard parts.count == 3 else { return "解放条件を読み取れません。操作できません。" }
        let encounterID = "B_\(parts[1])_\(parts[2])"
        guard model.state.completedEncounterIDs.contains(encounterID) else {
            let enemy = model.catalog?.enemies.first { $0.id == encounterID }?.name ?? "必要な魔物"
            return "先に\(enemy)を倒してください。"
        }
        return nil
    }
    private func confirmationTitle(_ action: GearUpgradeActionR218, recipe: RecipeDefinition) -> String {
        switch action {
        case .enhance: "粉 \(recipe.dustCost) 個で強化する"
        case .refine: "研成する"
        case .promoteQuality: "昇格内容を確認する"
        }
    }
    private struct RefinementTransition {
        let fromLabel: String
        let toLabel: String
        let nextRank: Int
        let dustCost: Int
        let materialCosts: [String: Int]
        let gateID: String?
        let capText: String
        let ready: Bool
        var ranks: [Int] { [1, 2, 3, 4, 5] }
    }
    private func refinementTransition(for item: GearInstance) -> RefinementTransition? {
        guard let policy = model.naturalGearRefinementPolicyR352 else { return nil }
        let rank = model.state.naturalGearRefinementR352?.rank(for: item.id) ?? 1
        guard let step = policy.transition(from: rank) else { return nil }
        let hasMaterials = step.materialCosts.allSatisfy { model.state.materials[$0.key, default: 0] >= $0.value }
        let hasDust = model.state.materials["refine_dust", default: 0] >= step.dustCost
        let gate = unmetGate(step.gateID)
        return RefinementTransition(fromLabel: GearRefinementPresentationR352.rankName(step.fromRank),
            toLabel: GearRefinementPresentationR352.rankName(step.toRank), nextRank: step.toRank,
            dustCost: step.dustCost, materialCosts: step.materialCosts, gateID: step.gateID,
            capText: "+\(policy.maximumEnhancement(forRank: step.toRank) ?? 0)", ready: hasMaterials && hasDust && gate == nil)
    }
    private func smallRoute(_ title: String, symbol: String, id: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 5) { Image(systemName: symbol); Text(title).font(.caption2) }.frame(maxWidth: .infinity, minHeight: 56) }
            .buttonStyle(.plain).background(UI48Theme.enamel.opacity(0.3)).clipShape(UI48Frame(radius: 9))
            .accessibilityIdentifier("ui48_route_\(id)_\(title)")
    }
}

private extension String {
    func ifEmpty(_ value: String) -> String { isEmpty ? value : self }
}
