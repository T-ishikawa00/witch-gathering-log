import SwiftUI
import SpriteKit

extension GameModel {
    var recyclableGearIDs:[UUID] {
        GearInventoryIndexR374(state.gear).recyclableIDs(
            in: state.gear,
            equippedIDs: Set(state.equippedGearIDs.values),
            savedLoadoutIDs: state.gearLoadoutsR342?.referencedGearIDs ?? [])
    }
    func salvage(_ ids:[UUID], allowSelectedSubset: Bool = false) {
        guard !busy,let engine else{return}
        let displayedIndex = GearInventoryIndexR374(state.gear)
        let displayedEligible = displayedIndex.recyclableIDs(
            in: state.gear, equippedIDs: Set(state.equippedGearIDs.values),
            savedLoadoutIDs: state.gearLoadoutsR342?.referencedGearIDs ?? [])
        guard !ids.isEmpty, Set(ids).count == ids.count,
              (allowSelectedSubset ? Set(ids).isSubset(of: Set(displayedEligible)) : Set(displayedEligible) == Set(ids)) else {
            error = "対象が更新されたか、分解できない装備が含まれています。一覧を確認し直してください。"
            return
        }
        let displayedRefundR353 = engine.gearDismantleRefundPolicyR353.flatMap {
            displayedIndex.refundSummary(ids: ids, policy: $0)
        }
        if GearDismantleBuildPolicyR353.enabled,
           displayedRefundR353 == nil {
            error = "返却量を安全に確認できないため、一括分解できません。"
            return
        }
        busy=true
        Task {var count=0
            do {
                let latest = await engine.snapshot()
                let latestIndex = GearInventoryIndexR374(latest.gear)
                let latestEligible = latestIndex.recyclableIDs(
                    in: latest.gear, equippedIDs: Set(latest.equippedGearIDs.values),
                    savedLoadoutIDs: latest.gearLoadoutsR342?.referencedGearIDs ?? [])
                guard (allowSelectedSubset ? Set(ids).isSubset(of: Set(latestEligible)) : Set(latestEligible) == Set(ids)) else {
                    self.error = "対象が更新されました。一覧を確認し直してください。"
                    await refresh(); busy = false; return
                }
                if GearDismantleBuildPolicyR353.enabled {
                    guard let displayedRefund = displayedRefundR353,
                          let refundPolicy = engine.gearDismantleRefundPolicyR353,
                          let latestRefund = latestIndex.refundSummary(ids: ids, policy: refundPolicy),
                          latestRefund == displayedRefund else {
                        self.error = "返却量が更新されたか確認できません。一覧を確認し直してください。"
                        await refresh(); busy = false; return
                    }
                }
                for id in ids {
                let current=await engine.snapshot()
                guard let item=current.gear.first(where:{$0.id==id}),item.qualityID=="Q0",!item.protected,
                      !current.equippedGearIDs.values.contains(id),
                      !(current.gearLoadoutsR342?.referencedGearIDs.contains(id) ?? false),
                      current.gear.filter({$0.definitionID==item.definitionID}).count>1 else{continue}
                _ = try await engine.dispatchConfirmingSavedReceipt(.dismantle(gearID:id),operationID:UUID(),expectedRevision:current.revision);count+=1
            };notice = GearDismantleBuildPolicyR353.enabled
                ? "\(count)個の装備を分解し、研成の粉を受け取りました。"
                : "\(count)個の装備を研成の粉に戻しました。"}
            catch{self.error="\(count)個を分解しました。残りは保持しています。\n"+commandErrorText(error)}
            await refresh();busy=false
        }
    }

    /// Each step is separately durable. Retry is safe and never grants a purchased entitlement.
    func wearCandidate(_ id:String,kind:String,actorID:String? = nil,onSuccess:(()->Void)? = nil) {
        guard !busy,let engine else{return}
        if [WardrobeCandidateResolverR128.lunaID, WardrobeCandidateResolverR128.noirID].contains(id),
           !WardrobeCandidateCatalogR128.enabled(arguments: ProcessInfo.processInfo.arguments, developmentEnabled: wardrobeCandidateDevelopmentR169Enabled) {
            self.error = "この見た目候補は隔離したローカル確認でのみ選べます。"
            return
        }
        if id == WardrobeCandidateCatalogR130.appearanceID,
           !WardrobeCandidateCatalogR130.enabled(arguments: ProcessInfo.processInfo.arguments, developmentEnabled: wardrobeCandidateDevelopmentR169Enabled) {
            self.error = "AIRAの衣装候補は追加の隔離ローカル確認でのみ選べます。"
            return
        }
        busy=true
        let recipient = actorID ?? selectedActor
        Task {do {
            if !state.ownedCosmeticIDs.contains(id) {
                _ = try await engine.dispatchConfirmingSavedReceipt(.setCosmetic(id,owned:true),operationID:UUID(),expectedRevision:state.revision);await refresh()
            }
            let cmd:GameCommand = kind=="weapon" ? .selectWeaponAppearance(actorID:recipient,appearanceID:id):.selectCosmetic(actorID:recipient,cosmeticID:id)
            _ = try await engine.dispatchConfirmingSavedReceipt(cmd,operationID:UUID(),expectedRevision:state.revision)
            await refresh();notice="旅支度を保存しました。";onSuccess?()
        }catch{self.error=commandErrorText(error);await refresh()};busy=false}
    }
    func resetWardrobeAppearance(_ command:GameCommand,message:String,onSuccess:(()->Void)? = nil) {
        guard !busy,let engine else{return};busy=true
        Task {do {
            _ = try await engine.dispatchConfirmingSavedReceipt(command,operationID:UUID(),expectedRevision:state.revision)
            await refresh();notice=message;onSuccess?()
        }catch{self.error=commandErrorText(error);await refresh()};busy=false}
    }
    func challenge(_ challenge:ChallengeDefinition){
        guard !busy,let engine else{return}
        // Start this presentation at zero, matching the ordinary fight path.
        battleElapsed=0
        busy=true;fighting=true
        chosenRegion=challenge.region;tab="探索";sheet=nil
        activeAreaFightEnemyID=challenge.enemyIDs.first
        syncScene()
        scene.setEnemies(challenge.enemyIDs)
        playbackTask=Task {do {
            let r=try await engine.dispatchConfirmingSavedReceipt(.resolveChallenge(challengeID:challenge.id,seed:UInt64(bitPattern: state.revision) &+ 1001),operationID:UUID(),expectedRevision:state.revision)
            await refresh()
            if let battle=state.lastCombatResult {await play(battle);await presentBattleResolution(won:battle.won);notice=battle.won ? "研究課題を達成しました。":"装備を整え、もう一度挑戦しよう。"}
            writeReceipt("challenge",challenge.id+":"+r.result);writeReceipt("challenge_art",scene.artAuditJSON())
        }catch{self.error=commandErrorText(error)};activeAreaFightEnemyID=nil;busy=false;fighting=false
            // A research challenge temporarily changes the displayed field only.
            // Return to the saved expedition without resetting its gathering clock.
            chosenRegion=state.activeRegionID ?? challenge.region
            syncScene()}

    }
    func compare(_ item:GearInstance){
        guard let catalog, canWearDefinition(item.definitionID) else {
            error="選んだ仲間が装備できる品ではありません。";return
        }
        let usableGearIDs=Set(state.gear.filter{canEquip($0)}.map(\.id))
        guard let otherID=GearComparisonPartnerSelectionR210.selectCounterpart(
            itemID:item.id,actorID:selectedActor,gear:state.gear,definitions:catalog.gear,
            equippedGearIDs:state.equippedGearIDs,usableGearIDs:usableGearIDs), otherID != item.id else {
            error="同じ部位の比較対象がありません。";return
        }
        comparison=[item.id,otherID];sheet="比較"
    }
    func finishGearComparison(_ comparedItems: [GearInstance]) {
        guard !busy, comparedItems.count == 2 else { return }
        // Do not dispatch a second completion after both persisted tutorial flags are set.
        // That would create a redundant receipt/revision even though no reward is repeated.
        if state.gearComparisonSeen && state.gachaUnlocked {
            sheet = "装備"
            return
        }
        act(.markGearComparisonSeen(firstGearID: comparedItems[0].id, secondGearID: comparedItems[1].id),
            "装備の違いを発見しました。魔導庫で無料鑑定ができます。")
        sheet = "装備"
    }
}

struct WardrobeView:View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model:GameModel
    let names=["ERNA_TRAVEL":"露草色の旅支度","STAFF_BRANCH":"若枝の杖","STAFF_MOON":"月環の杖", WardrobeCandidateResolverR128.lunaID:"ルナ・苔色の肩掛け（候補）", WardrobeCandidateResolverR128.noirID:"ノワール・苔色の首元飾り（候補）", WardrobeCandidateCatalogR130.appearanceID:"アイラ・採集工房の前掛け（候補・未承認）"]
    @State private var previewSelection = WardrobePreviewSelectionR094()
    @State private var wardrobeActorID:String?
    private var appearanceActorIDs:[String] {
        model.state.partyActorIDs.filter { actor in model.catalog?.appearances.contains(where:{$0.actorIDs.contains(actor)}) ?? false }
    }
    private var activeWardrobeActorID:String {
        if let wardrobeActorID, appearanceActorIDs.contains(wardrobeActorID) { return wardrobeActorID }
        if appearanceActorIDs.contains(model.selectedActor) { return model.selectedActor }
        return appearanceActorIDs.first ?? model.selectedActor
    }
    private var actorBinding:Binding<String> {
        Binding(get:{activeWardrobeActorID},set:{wardrobeActorID=$0;previewSelection.clear()})
    }
    private var previewOverrides:[String:String] {
        if let id = previewSelection.appearanceID, id == WardrobeCandidateCatalogR130.appearanceID {
            return WardrobeCandidateCatalogR130.preview(base: model.sceneAppearance, actorID: activeWardrobeActorID,
                appearanceID: id, kind: previewSelection.kind ?? "",
                enabled: WardrobeCandidateCatalogR130.enabled(arguments: ProcessInfo.processInfo.arguments,
                    developmentEnabled: model.wardrobeCandidateDevelopmentR169Enabled))
        }
        if let id = previewSelection.appearanceID,
           [WardrobeCandidateResolverR128.lunaID, WardrobeCandidateResolverR128.noirID].contains(id) {
            return WardrobeCandidateResolverR128.preview(base: model.sceneAppearance, actorID: activeWardrobeActorID,
                appearanceID: id, kind: previewSelection.kind ?? "",
                enabled: WardrobeCandidateCatalogR128.enabled(arguments: ProcessInfo.processInfo.arguments,
                    developmentEnabled: model.wardrobeCandidateDevelopmentR169Enabled))
        }
        return previewSelection.applying(to:model.sceneAppearance,actorID:activeWardrobeActorID)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("旅支度").font(.system(.title,design:.serif))
            Text("見た目を変えても、装備の性能は変わりません。").font(.caption).foregroundStyle(Palette.gold)
            let layout:AnyLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)):AnyLayout(HStackLayout(spacing:12))
            layout {
                WardrobePortrait(model:model,actorID:activeWardrobeActorID,appearanceOverrides:previewOverrides).frame(width:170,height:220).clipShape(RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:10) {
                    if !appearanceActorIDs.isEmpty {
                        Picker("試着する仲間",selection:actorBinding) {
                            ForEach(appearanceActorIDs,id:\.self) { actor in Text(GameModel.actorNames[actor] ?? "仲間").tag(actor) }
                        }.pickerStyle(.menu).accessibilityIdentifier("wardrobe_actor_picker")
                    }
                    Text(GameModel.actorNames[activeWardrobeActorID] ?? "仲間")
                    Button {
                        model.resetWardrobeAppearance(.selectCosmetic(actorID:activeWardrobeActorID,cosmeticID:nil),message:"標準衣装に戻しました。",onSuccess:{previewSelection.clear()})
                    } label: {
                        Text(activeWardrobeActorID == "C_FAMILIAR" ? "標準の装飾に戻す":"標準衣装に戻す").frame(minWidth:44,minHeight:44).contentShape(.interaction,Rectangle())
                    }
                    Button {
                        model.resetWardrobeAppearance(.selectWeaponAppearance(actorID:activeWardrobeActorID,appearanceID:nil),message:"標準の武器外観に戻しました。",onSuccess:{previewSelection.clear()})
                    } label: {
                        Text("標準の武器外観に戻す").frame(minWidth:44,minHeight:44).contentShape(.interaction,Rectangle())
                    }.accessibilityIdentifier("reset_weapon_appearance")
                }.fixedSize(horizontal:false,vertical:true)
            }
            if appearanceActorIDs.isEmpty { Text("試着できる見た目はありません。").font(.caption) }
            ForEach(model.catalog?.appearances.filter{$0.actorIDs.contains(activeWardrobeActorID)} ?? []){a in
                let selected = model.state.selectedCosmeticIDs[activeWardrobeActorID] == a.id || model.state.selectedWeaponAppearanceIDs[activeWardrobeActorID] == a.id
                HStack(alignment:.center,spacing:10) {
                    WardrobeCandidateThumbnailR130(id:a.id,fallbackAssetID:WardrobeCandidateResolverR128.iconAssetID(for:a.id) ?? (a.kind=="costume" ? a.id+"__idle":a.id),size:64).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:5) {
                        Text(names[a.id] ?? a.id)
                        Text(a.kind=="costume" ? "衣装":(a.kind=="accessory" ? "装飾":"武器の見た目")).font(.caption).foregroundStyle(Palette.gold)
                        Button {
                            previewSelection.show(appearanceID:a.id,kind:a.kind)
                        } label: {
                            Text(previewSelection.appearanceID == a.id ? "試着中":"この見た目を試す")
                                .frame(minWidth:44,minHeight:44).contentShape(.interaction,Rectangle())
                        }.accessibilityIdentifier("preview_appearance_"+a.id)
                        Button {
                            model.wearCandidate(a.id,kind:a.kind,actorID:activeWardrobeActorID,onSuccess:{previewSelection.clear()})
                        } label: {
                            Text(selected ? "選択中":"この見た目を使う")
                                .frame(minWidth:44,minHeight:44).contentShape(.interaction,Rectangle())
                        }.disabled(selected).accessibilityIdentifier("use_appearance_"+a.id)
                    }
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("appearance_"+a.id)
            }
            Text("追加衣装・武器は制作検証用です。正式販売品ではありません。").font(.caption).foregroundStyle(Palette.gold)
        }.disabled(model.busy)
        .onChange(of:activeWardrobeActorID){_,_ in previewSelection.clear()}
    }
}

/// Uses the same body, weapon anchor and hand occlusion as home and combat.
struct WardrobePortrait:View {
    @ObservedObject var model:GameModel
    let actorID:String
    let appearanceOverrides:[String:String]
    var spotlight = false
    // Keep the portrait scene close to its display size so the active actor,
    // costume layers, and weapon occupy the preview instead of shrinking into
    // the room-scale character proportions.
    @State private var preview=LivingScene(size:CGSize(width:360,height:440))
    var body:some View {
        SpriteView(scene:preview).accessibilityElement(children:.ignore).accessibilityLabel((GameModel.actorNames[actorID] ?? "仲間")+"の試着見本").onAppear{update()}
            .onChange(of:appearanceOverrides){_,_ in update()}
            .onChange(of:actorID){_,_ in update()}
            .onChange(of:model.wardrobeCandidateDevelopmentR169Enabled){_,_ in update()}
    }
    private func update(){preview.scaleMode = .resizeFill;preview.ui48PortraitSpotlight = spotlight;preview.configure(place:.portrait(GameModel.spriteIDs[actorID] ?? "ERNA"),cosmetics:appearanceOverrides,furniture:[],
        wardrobeCandidateDevelopmentEnabled:model.wardrobeCandidateDevelopmentR169Enabled)}
}

struct InventoryView:View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model:GameModel
    let opening:Bool
    @State private var dismantleTarget:UUID?
    @State private var quality="すべて"
    @State private var search=""
    @FocusState private var inventorySearchFocused: Bool
    @State private var searchFieldGeneration = 0
    @State private var showBulk=false
    @State private var upgradeRequestR218: GearUpgradeRequestR218?
    private var activeDismantleRefundR353: GearDismantleRefundPolicyR353.RefundBreakdown? {
        guard let dismantleTarget, model.dismantleBlockReasonR353(for: dismantleTarget) == nil else { return nil }
        return model.dismantleRefundBreakdownR353(for: dismantleTarget)
    }
    private var activeDismantleReasonR353: String? {
        guard let dismantleTarget else { return nil }
        return model.dismantleBlockReasonR353(for: dismantleTarget)
    }
    private func indexedDismantleBlockReasonR374(for gearID: UUID, index: GearInventoryIndexR374) -> String? {
        guard let item = index.firstGear(id: gearID) else { return "装備を確認できません。" }
        if item.protected { return "保護中の装備は分解できません。" }
        if model.state.equippedGearIDs.values.contains(gearID) { return "使用中の装備は分解できません。" }
        if model.state.gearLoadoutsR342?.referencedGearIDs.contains(gearID) ?? false {
            return "保存セットに登録中の装備は分解できません。先にセット登録を解除してください。"
        }
        if GearDismantleBuildPolicyR353.enabled {
            if index.isLastCopy(item) { return "各種類の最後の1個は残ります。" }
            guard let policy = model.engine?.gearDismantleRefundPolicyR353,
                  (try? policy.refundBreakdown(gearID: item.id, qualityID: item.qualityID, investmentDust: item.investmentDust)) != nil else {
                return "返却量を安全に確認できないため、分解できません。"
            }
        }
        return nil
    }
    var body:some View {
        let inventory = model.state.gear
        let inventoryIndex = GearInventoryIndexR374(inventory)
        let equippedIDs = Set(model.state.equippedGearIDs.values)
        let savedLoadoutIDs = model.state.gearLoadoutsR342?.referencedGearIDs ?? []
        let recyclableIDs = inventoryIndex.recyclableIDs(in: inventory, equippedIDs: equippedIDs,
                                                          savedLoadoutIDs: savedLoadoutIDs)
        let visible = inventory.reversed().filter{g in (!opening || model.opening.contains(g.id)) && (quality=="すべて" || g.qualityID==quality) && (search.isEmpty || (model.catalog?.gear.first{$0.id==g.definitionID}?.name ?? g.definitionID).localizedCaseInsensitiveContains(search))}
        let refundPolicy = GearDismantleBuildPolicyR353.enabled ? model.engine?.gearDismantleRefundPolicyR353 : nil
        let bulkRefundSummary = refundPolicy.flatMap { inventoryIndex.refundSummary(ids: recyclableIDs, policy: $0) }
        VStack(alignment:.leading,spacing:14){
            Text(opening ? "届いた装備":"持ちもの").font(.system(.title,design:.serif))
            if dynamicTypeSize.isAccessibilitySize {
                Picker("装備する仲間",selection:$model.selectedActor){ForEach(model.state.partyActorIDs,id:\.self){Text(GameModel.actorNames[$0] ?? $0).tag($0)}}.pickerStyle(.menu).accessibilityIdentifier("inventory_actor_picker")
            } else {
                Picker("装備する仲間",selection:$model.selectedActor){ForEach(model.state.partyActorIDs,id:\.self){Text(GameModel.actorNames[$0] ?? $0).tag($0)}}.pickerStyle(.segmented)
            }
            Text("研成の粉  \(model.state.materials["refine_dust",default:0])").font(.caption).foregroundStyle(Palette.gold)
            Text(dynamicTypeSize.isAccessibilitySize
                 ? "所持 \(model.state.gear.count)\n表示 \(visible.count)"
                 : "所持 \(model.state.gear.count) / 表示 \(visible.count)")
                .font(.caption)
                .accessibilityIdentifier("inventory_count")
            TextField("装備名で探す", text: $search,
                      prompt: Text(dynamicTypeSize.isAccessibilitySize ? "装備名" : "装備名で探す")
                        .foregroundColor(Palette.text.opacity(0.8)))
                .textFieldStyle(.roundedBorder)
                .focused($inventorySearchFocused)
                .id(searchFieldGeneration)
                .onSubmit { inventorySearchFocused = false }
                .accessibilityLabel("装備名で探す")
                .accessibilityIdentifier("inventory_search")
            if dynamicTypeSize.isAccessibilitySize {
                Picker("品質",selection:$quality){Text("すべて").tag("すべて");ForEach(["Q0","Q1","Q2","Q3","Q4"],id:\.self){Text(GameText.quality($0)).tag($0)}}.pickerStyle(.menu).accessibilityIdentifier("inventory_quality_picker")
            } else {
                Picker("品質",selection:$quality){Text("すべて").tag("すべて");ForEach(["Q0","Q1","Q2","Q3","Q4"],id:\.self){Text(GameText.quality($0)).tag($0)}}.pickerStyle(.segmented)
            }
            if visible.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(!search.isEmpty || quality != "すべて"
                         ? "条件に合う装備が見つかりません。"
                         : (opening ? "新しく届いた装備はありません。" : "まだ装備を持っていません。探索や制作で手に入れましょう。"))
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inventory_empty_message")
                    if !search.isEmpty || quality != "すべて" {
                        Button {
                            inventorySearchFocused = false
                            search = ""
                            quality = "すべて"
                            // Recreate the native field so marked IME text cannot outlive the reset.
                            searchFieldGeneration &+= 1
                        } label: {
                            Text("検索と品質の条件を解除")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 44)
                        }.buttonStyle(.bordered).accessibilityIdentifier("inventory_clear_filters")
                    }
                }
            }
            if !opening && quality == "Q4", let catalog = model.catalog {
                LRCollectionViewR384(catalog: catalog, state: model.state,
                    policyEnabled: NaturalGearBuildPolicyR350.enabled) { regionID in
                        // This navigation does not change the saved gathering region or target.
                        model.chosenRegion = regionID
                        model.tab = "探索"
                        model.sheet = nil
                    }
            }
            if !opening && !recyclableIDs.isEmpty {Button("未保護のC装備をまとめて分解（\(recyclableIDs.count)個）"){showBulk=true}.font(.caption).frame(minHeight:44).disabled(model.busy).accessibilityIdentifier("bulk_salvage")}
            LazyVStack(spacing:14){ForEach(visible){g in gearRow(g,index:inventoryIndex)}}
        }.sheet(item: $upgradeRequestR218) { request in
            if request.action == .refine, NaturalGearRefinementBuildPolicyR352.enabled {
                if let policy = model.naturalGearRefinementPolicyR352,
                   let catalog = model.catalog, let item = model.state.gear.first(where: { $0.id == request.gearID }) {
                    GearRefinementConfirmationR352(model: model, catalog: catalog,
                        gearID: request.gearID, actorID: model.selectedActor, policy: policy,
                        actorCanUseGear: model.canEquip(item), isBusy: model.busy,
                        onApply: {
                            model.act(.refine(gearID: request.gearID), "研成段階を上げました。")
                            upgradeRequestR218 = nil
                        }, onCancel: { upgradeRequestR218 = nil })
                        .id(request.id + ":R352")
                } else {
                    VStack(spacing: 12) {
                        Text("研成の条件を安全に確認できません。操作は保存していません。")
                            .fixedSize(horizontal: false, vertical: true)
                        Button("閉じる") { upgradeRequestR218 = nil }.frame(minHeight: 44)
                    }.padding(24)
                }
            } else {
                GearUpgradeConfirmationR218(model: model, request: request).id(request.id)
            }
        }
        .confirmationDialog("この装備を分解しますか？",isPresented:Binding(get:{dismantleTarget != nil},set:{if !$0{dismantleTarget=nil}}),titleVisibility:.visible){
            Button("分解する",role:.destructive){
                if let id=dismantleTarget {
                    if model.dismantleBlockReasonR353(for:id) == nil {
                        model.act(.dismantle(gearID:id), GearDismantleBuildPolicyR353.enabled ? "研成の粉を受け取りました。" : "研成の粉を取り出しました。")
                    } else { model.error=model.dismantleBlockReasonR353(for:id) ?? "分解できません。" }
                }
                dismantleTarget=nil
            }.disabled(dismantleTarget.map { model.dismantleBlockReasonR353(for:$0) != nil } ?? true)
            Button("キャンセル",role:.cancel){dismantleTarget=nil}
        }message:{
            if GearDismantleBuildPolicyR353.enabled {
                if let refund = activeDismantleRefundR353 {
                    Text("分解した装備は元に戻せません。返却：基礎分 \(refund.baseSalvageDust) 個、育成分 \(refund.investmentRefundDust) 個。合計 \(refund.totalDust) 個の研成の粉を受け取ります。")
                } else { Text(activeDismantleReasonR353 ?? "返却量を確認できないため、分解できません。") }
            } else { Text("この装備は元に戻せません。保護中・使用中の装備は分解できません。") }
        }
        .alert("未保護・未使用のC装備を\(recyclableIDs.count)個分解しますか？",isPresented:$showBulk){
            Button("まとめて分解する",role:.destructive){model.salvage(recyclableIDs)}
                .disabled(GearDismantleBuildPolicyR353.enabled && bulkRefundSummary == nil)
            Button("キャンセル",role:.cancel){}
        }message:{
            if GearDismantleBuildPolicyR353.enabled {
                if let summary = bulkRefundSummary {
                    Text("\(summary.itemCount)個：基礎分 \(summary.baseSalvageDust) 個、育成分 \(summary.investmentRefundDust) 個。合計 \(summary.totalDust) 個の研成の粉を受け取ります。分解した装備は元に戻せません。保護中・使用中の装備と各種類の最後の1個は対象外です。")
                } else { Text("返却量をすべて確認できないため、一括分解できません。") }
            } else { Text("保護中・使用中の装備と、各種類の最後の1個は残ります。分解は取り消せません。") }
        }

    }
    func gearRow(_ g:GearInstance,index:GearInventoryIndexR374)->some View {
        let def=model.catalog?.gear.first{$0.id==g.definitionID}
        let evolution=model.catalog?.recipes.filter{$0.parentTemplateID==g.definitionID && $0.kind=="evolve_in_place"} ?? []
        return VStack(alignment:.leading,spacing:10){
            HStack{AssetIcon(id:"ICO_"+g.definitionID,size:52).accessibilityHidden(true);VStack(alignment:.leading,spacing:4){Text(def?.name ?? g.definitionID).font(.subheadline);Text("\(GameText.quality(g.qualityID))  +\(g.enhancement)").font(.caption).foregroundStyle(Palette.gold);if model.naturalGearRefinementPolicyR352 != nil { Text("研成段階 \(GearRefinementPresentationR352.rankName(model.state.naturalGearRefinementR352?.rank(for:g.id) ?? 1))").font(.caption).foregroundStyle(Palette.gold);if g.refinement > 0 { Text("従来の研成補正 +\(g.refinement)（保持）").font(.caption) } } else { Text("研成\(g.refinement)").font(.caption).foregroundStyle(Palette.gold) };if g.ownerID != nil{Text("使用中").font(.caption)}};Spacer();Button{model.act(.protect(gearID:g.id,protected:!g.protected),g.protected ? "保護を解除しました。":"保護しました。")}label:{Image(systemName:g.protected ? "lock.fill":"lock.open").frame(width:44,height:44)}.accessibilityLabel(g.protected ? "\(def?.name ?? "装備")の保護を解除":"\(def?.name ?? "装備")を保護").accessibilityValue(g.protected ? "保護中":"保護なし").accessibilityHint("誤分解を防ぐ設定です")}
            GearLatentDetailsView(model: model, item: g)
            Group {
                if dynamicTypeSize >= .accessibility3 {
                    VStack(spacing:10) { gearActions(g,definition:def,evolution:evolution,index:index) }
                } else if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                        gearActions(g,definition:def,evolution:evolution,index:index)
                    }
                } else { HStack { gearActions(g,definition:def,evolution:evolution,index:index) } }
            }.font(.caption).buttonStyle(.bordered).disabled(model.busy)
        }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("gear_"+g.id.uuidString)
    }
    @ViewBuilder private func gearActions(_ item:GearInstance,definition:GearDefinition?,evolution:[RecipeDefinition],index:GearInventoryIndexR374)->some View {
        Button { model.compare(item) } label: { actionLabel("比較") }
        Button { model.act(.equip(gearID:item.id,actorID:model.selectedActor),"装備を更新しました。") } label: { actionLabel("装備") }
            .disabled(!model.canEquip(item))
        Menu {
            Button("強化") { upgradeRequestR218 = GearUpgradeRequestR218(gearID: item.id, action: .enhance) }
            Button("研成") { upgradeRequestR218 = GearUpgradeRequestR218(gearID: item.id, action: .refine) }
            Button("品質を昇格") { upgradeRequestR218 = GearUpgradeRequestR218(gearID: item.id, action: .promoteQuality) }
            ForEach(evolution) { recipe in
                Button("進化: "+(model.catalog?.gear.first{$0.id==recipe.outputGearID}?.name ?? recipe.id)) {
                    model.showRecipeGoal(recipe.id, gearID: item.id)
                }
            }
        } label: { actionLabel("育てる") }
        Button(role:.destructive) { dismantleTarget=item.id } label: { actionLabel("分解") }
            .disabled(indexedDismantleBlockReasonR374(for:item.id,index:index) != nil)
        if GearDismantleBuildPolicyR353.enabled && index.isLastCopy(index.firstGear(id:item.id) ?? item) && !item.protected && !model.state.equippedGearIDs.values.contains(item.id) {
            Text("各種類の最後の1個は残ります。").font(.caption).foregroundStyle(Palette.gold)
                .accessibilityIdentifier("r353_last_copy_refusal_\(item.id.uuidString)")
        }
    }
    private func actionLabel(_ title:String)->some View {
        Text(title).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44)
    }

}

struct GearComparisonView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: GameModel
    var items: [GearInstance] { model.comparison.compactMap { id in model.state.gear.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("装備を比べる").font(.system(.title, design: .serif))
            if dynamicTypeSize.isAccessibilitySize {
                Text("比べる仲間：" + (GameModel.actorNames[model.selectedActor] ?? "仲間"))
                    .font(.headline).foregroundStyle(Palette.gold)
                    .fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("gear_comparison_actor_context")
            }
            Text("装備全体の性能と、選んだ仲間に有効な潜在効果を比べられます。")
                .font(.caption).foregroundStyle(Palette.gold)
            let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout { ForEach(items) { item in comparisonCard(item) } }
            if items.count == 2 { GearComparisonR136Section(model: model, items: items) }
            if items.count == 2 {
                Button {
                    model.finishGearComparison(items)
                } label: {
                    Text(model.state.gearComparisonSeen && model.state.gachaUnlocked ? "閉じる" : "比較を終える")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                .accessibilityIdentifier("finish_comparison").disabled(model.busy)
            }
        }
    }

    private func comparisonCard(_ item: GearInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AssetIcon(id: "ICO_" + item.definitionID, size: 100)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(model.catalog?.gear.first { $0.id == item.definitionID }?.name ?? item.definitionID)
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            let slot = model.catalog?.gear.first { $0.id == item.definitionID }?.slot
            let isSelected = model.comparison.first == item.id
            let isEquipped = slot.flatMap { model.state.equippedGearIDs["\(model.selectedActor)|\($0)"] } == item.id
            Text(isSelected && isEquipped ? "選んだ装備・現在装備中" : isSelected ? "選んだ装備" : isEquipped ? "現在装備中" : "比較候補")
                .font(.caption).foregroundStyle(Palette.gold)
            LabeledContent("品質", value: GameText.quality(item.qualityID))
            LabeledContent("強化", value: "+\(item.enhancement)")
            if model.naturalGearRefinementPolicyR352 != nil {
                LabeledContent("研成段階", value: GearRefinementPresentationR352.rankName(model.state.naturalGearRefinementR352?.rank(for:item.id) ?? 1))
                if item.refinement > 0 { LabeledContent("従来の研成補正", value: "+\(item.refinement)（保持）") }
            } else {
                LabeledContent("研成", value: "\(item.refinement)")
            }
            Divider()
            switch Result(catching: { try model.comparisonStats(item) }) {
            case .success(let preview):
                Text("装着時の仲間の性能").foregroundStyle(Palette.gold)
                LabeledContent("攻撃", value: "\(preview.combatant.attack)")
                LabeledContent("体力", value: "\(preview.combatant.maxHP)")
                LabeledContent("防御", value: "\(preview.combatant.defense)")
                ForEach(preview.combatant.effectIDs.sorted().filter { !$0.hasPrefix("AF_") }, id: \.self) {
                    Text(GameText.effect($0)).fixedSize(horizontal: false, vertical: true)
                }
                if let latent = preview.latent { GearLatentAggregateView(projection: latent, actorID: model.selectedActor, effectIDs: preview.combatant.effectIDs) }
            case .failure(let error):
                Text(GameText.error(error)).foregroundStyle(Palette.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            GearLatentDetailsView(model: model, item: item)
            Button {
                model.act(.equip(gearID: item.id, actorID: model.selectedActor), "装備を更新しました。")
            } label: {
                Text("こちらを装備").fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.bordered).disabled(model.busy || !model.canEquip(item))
            .accessibilityIdentifier("compare_equip_" + item.id.uuidString)
        }
        .font(.caption).padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
        // A parent identifier propagates to child rows/buttons in SwiftUI; keep their individual IDs.
    }
}

struct ResearchView:View {
    @ObservedObject var model:GameModel
    var onGatherSource:(ResearchGatherHandoffR310)->Void
    var scrollToSection:(String)->Void
    @State private var challengeRegionFilterR251:String? = nil
    @State private var researchCardJumpSelectionR286:String? = nil
    private var continuation:PostClearGoalProjectionR122.Summary? {
        guard let catalog=model.catalog else{return nil}
        return PostClearGoalProjectionR122.project(catalog:catalog,state:model.state)
    }
    private func challengeAvailability(_ id:String)->PostClearGoalProjectionR122.ChallengeAvailability? {
        continuation?.challenges.first{$0.id==id}?.availability
    }
    private var challengeRegionOptionsR251:[RegionDefinition] {
        let challengeRegionIDs=Set((model.catalog?.challenges ?? []).map(\.region))
        return (model.catalog?.regions ?? []).filter{challengeRegionIDs.contains($0.id)}
    }
    private var selectedChallengeRegionNameR251:String {
        guard let selected=challengeRegionFilterR251,
              let region=challengeRegionOptionsR251.first(where:{$0.id==selected}) else {
            return "すべての地域"
        }
        return region.name
    }
    private var selectedResearchCardJumpValueR286:String {
        guard let selected=researchCardJumpSelectionR286,
              let research=model.catalog?.research.first(where:{$0.id==selected}) else {
            return "移動先未選択"
        }
        return research.name + (model.state.completedResearchIDs.contains(research.id) ? "・習得済み" : "・未習得")
    }
    private func researchCardJumpMenuR286()->some View {
        Menu {
            ForEach(model.catalog?.research ?? []) { research in
                let completed=model.state.completedResearchIDs.contains(research.id)
                Button {
                    researchCardJumpSelectionR286=research.id
                    scrollToSection("research_card_r286_\(research.id)")
                } label: {
                    Text("\(research.name)（\(completed ? "習得済み" : "未習得")）")
                        .fixedSize(horizontal:false,vertical:true)
                }
                .accessibilityIdentifier("research_card_jump_option_r286_"+research.id)
            }
        } label: {
            HStack {
                Text("研究を選ぶ").fixedSize(horizontal:false,vertical:true)
                Spacer()
                Image(systemName:"chevron.up.chevron.down")
            }
            .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("research_card_jump_r286")
        .accessibilityValue(selectedResearchCardJumpValueR286)
    }
    private var visibleChallengesR251:[ChallengeDefinition] {
        let challenges=model.catalog?.challenges ?? []
        guard let selected=challengeRegionFilterR251,
              challengeRegionOptionsR251.contains(where:{$0.id==selected}) else {
            return challenges
        }
        return challenges.filter{$0.region==selected}
    }
    private func regionName(_ id:String)->String {
        model.catalog?.regions.first{$0.id==id}?.name ?? "地域"
    }
    private func trackedGateName(_ id:String)->String {
        let parts=id.split(separator:"_")
        guard parts.count==3,parts[0]=="G" else{return "解放条件を確認できません。"}
        let enemyID="B_\(parts[1])_\(parts[2])"
        let name=model.catalog?.enemies.first{$0.id==enemyID}?.name ?? "手前のボス"
        return name+"の討伐で解放されます。"
    }
    private func sectionJumpButton(_ title:String, identifier:String, target:String)->some View {
        Button { scrollToSection(target) } label: {
            Text(title).fixedSize(horizontal:false,vertical:true)
                .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
    }
    private func openTrackedRecipe(_ recipeID:String) {
        model.tab="工房"
        model.showRecipeGoal(recipeID)
    }
    private func openGearReview() {
        if let first=model.state.partyActorIDs.first { model.selectedActor=first }
        model.tab="仲間"
        model.sheet="装備"
    }
    private func benefit(_ research:ResearchDefinition)->String {
        guard let effect=model.catalog?.researchEffects[research.effectID] else { return "効果を確認できません" }
        var values:[String]=[]
        if effect.partyAttack > 0 { values.append("攻撃 +\(effect.partyAttack)") }
        if effect.partyMaxHP > 0 { values.append("体力 +\(effect.partyMaxHP)") }
        if effect.partyDefense > 0 { values.append("防御 +\(effect.partyDefense)") }
        return "仲間全員の"+values.joined(separator:"・")
    }
    private func lockReason(_ research:ResearchDefinition)->String? {
        if let gate=model.catalog?.recipes.first(where:{$0.id==research.id})?.gateID,gate != "G_START" {
            let parts=gate.split(separator:"_")
            guard parts.count==3,parts[0]=="G" else { return "解放条件を確認できません" }
            let enemyID="B_\(parts[1])_\(parts[2])"
            if !model.state.completedEncounterIDs.contains(enemyID) {
                let name=model.catalog?.enemies.first(where:{$0.id==enemyID})?.name ?? "手前のボス"
                return name+"の討伐で解放"
            }
        }
        if research.cost.contains(where:{model.state.materials[$0.key,default:0] < $0.value}) {
            return "必要な素材を集めると研究できます"
        }
        return nil
    }
    @ViewBuilder
    private func materialGuidance(_ research: ResearchDefinition) -> some View {
        let rows = ResearchMaterialGuidanceR280.project(catalog: model.catalog, state: model.state, research: research)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(GameText.name(row.materialID))：あと \(row.missing)")
                            .font(.caption)
                        switch row.availability {
                        case .unknownMaterial:
                            Text("素材の採集先を確認できません。")
                        case .noGatherRegion:
                            Text("この素材の採集地域は設定されていません。")
                        case .regions(let sources):
                            ForEach(sources) { source in
                                Text("\(source.regionName)：\(source.status.label)")
                                if case .available = source.status {
                                    Button {
                                        onGatherSource(ResearchGatherHandoffR310(researchID:research.id,
                                            materialID:row.materialID,regionID:source.regionID))
                                    } label: {
                                        Label("採集先を見る",systemImage:"map")
                                            .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(model.busy || model.fighting)
                                    .accessibilityLabel("\(GameText.name(row.materialID))の採集先を見る、\(source.regionName)")
                                    .accessibilityIdentifier("research_gather_source_r310_\(research.id)_\(row.materialID)_\(source.regionID)")
                                }
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("research_material_guidance_r280_\(research.id)_\(row.materialID)")
                }
            }
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("採集帳").font(.system(.title,design:.serif))
            VStack(alignment:.leading,spacing:8) {
                sectionJumpButton("暮らしと冒険の研究へ", identifier:"research_section_jump_life_r125", target:"research_section_life_r125")
                sectionJumpButton("深まる森の課題へ", identifier:"research_section_jump_challenges_r125", target:"research_section_challenges_r125")
                researchCardJumpMenuR286()
            }
            if let continuation {
                VStack(alignment:.leading,spacing:10) {
                    Text(continuation.campaignComplete ? "五つの地域を踏破しました" : "地域の記録")
                        .font(.headline)
                    Text("討伐した魔物 \(continuation.campaignCleared) / \(continuation.campaignTotal)")
                        .font(.caption).foregroundStyle(Palette.gold)
                    if continuation.campaignComplete {
                        Text("次は研究課題や、まだ持っていない装備づくりを試せます。")
                            .font(.caption).fixedSize(horizontal:false,vertical:true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Button(action:openGearReview) { Text("仲間の装備を見直す").frame(minHeight:44) }
                                .buttonStyle(.bordered).frame(minHeight:44)
                                .accessibilityIdentifier("post_clear_gear_review")
                            Button(action:{model.tab="工房"}) { Text("工房へ").frame(minHeight:44) }
                                .buttonStyle(.bordered).frame(minHeight:44)
                                .accessibilityIdentifier("post_clear_workshop")
                        }
                        VStack(alignment:.leading,spacing:8) {
                            Button(action:openGearReview) { Text("仲間の装備を見直す").frame(minHeight:44) }
                                .buttonStyle(.bordered).frame(minHeight:44)
                                .accessibilityIdentifier("post_clear_gear_review")
                            Button(action:{model.tab="工房"}) { Text("工房へ").frame(minHeight:44) }
                                .buttonStyle(.bordered).frame(minHeight:44)
                                .accessibilityIdentifier("post_clear_workshop")
                        }
                    }
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                    .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))

                if let goal=continuation.trackedRecipe {
                    VStack(alignment:.leading,spacing:8) {
                        Text("選んだ装備目標").font(.headline)
                        Text(model.recipeGearName(goal.outputGearID)).foregroundStyle(Palette.gold)
                        if let gate=goal.gateID,!goal.gateCleared {
                            Label(trackedGateName(gate),systemImage:"lock.fill")
                                .font(.caption).fixedSize(horizontal:false,vertical:true)
                        }
                        if goal.parentOwned == false {
                            Text("進化元の装備を集めましょう。")
                                .font(.caption).fixedSize(horizontal:false,vertical:true)
                        }
                        if goal.outputOwned {
                            Text("完成品を所持しています。別の装備や構成も比べられます。")
                                .font(.caption).fixedSize(horizontal:false,vertical:true)
                        }
                        if goal.dustMissing > 0 {
                            Text("研成の粉が不足しています：あと \(goal.dustMissing)")
                                .font(.caption).foregroundStyle(Palette.gold)
                        }
                        ForEach(goal.requirements.filter{$0.missing>0},id:\.materialID) { requirement in
                            VStack(alignment:.leading,spacing:3) {
                                Text("\(GameText.name(requirement.materialID))：あと \(requirement.missing)")
                                    .font(.caption)
                                if !requirement.availableGatherRegions.isEmpty {
                                    Text("採集先："+requirement.availableGatherRegions.map(regionName).joined(separator:"・"))
                                        .font(.caption2).fixedSize(horizontal:false,vertical:true)
                                }
                                if !requirement.availableEnemyDropRegions.isEmpty {
                                    Text("討伐先："+requirement.availableEnemyDropRegions.map(regionName).joined(separator:"・"))
                                        .font(.caption2).fixedSize(horizontal:false,vertical:true)
                                    if model.sharedPartyWorkR146Enabled {
                                        Text("初回討伐では通常報酬を1度獲得。討伐した魔物は探索で再調査できます。")
                                            .font(.caption2).fixedSize(horizontal:false,vertical:true)
                                    }
                                }
                                if !requirement.lockedGatherRegions.isEmpty {
                                    Text("未解放の採集先："+requirement.lockedGatherRegions.map(regionName).joined(separator:"・"))
                                        .font(.caption2).foregroundStyle(Palette.gold).fixedSize(horizontal:false,vertical:true)
                                }
                                if !requirement.lockedEnemyDropRegions.isEmpty {
                                    Text("未解放の討伐先："+requirement.lockedEnemyDropRegions.map(regionName).joined(separator:"・"))
                                        .font(.caption2).foregroundStyle(Palette.gold).fixedSize(horizontal:false,vertical:true)
                                }
                            }
                        }
                        if goal.ready {
                            Text("必要な条件が揃っています。工房で制作・進化できます。")
                                .font(.caption).foregroundStyle(Palette.gold).fixedSize(horizontal:false,vertical:true)
                        }
                        Button { openTrackedRecipe(goal.recipeID) } label: { Text("工房で目標の詳細を見る").frame(minHeight:44) }
                            .buttonStyle(.bordered).frame(minHeight:44)
                            .accessibilityIdentifier("post_clear_recipe_detail")
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))
                } else {
                    VStack(alignment:.leading,spacing:8) {
                        Text("装備の次の目標を選ぶ").font(.headline)
                        Text("工房で制作・進化レシピを選ぶと、必要素材と採集先を確認できます。")
                            .font(.caption).fixedSize(horizontal:false,vertical:true)
                        Button(action:{model.tab="工房"}) { Text("工房で装備目標を選ぶ").frame(minHeight:44) }
                            .buttonStyle(.bordered).frame(minHeight:44)
                            .accessibilityIdentifier("post_clear_choose_recipe")
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))
                }
            }
            Text("暮らしと冒険の研究").font(.title3)
                .id("research_section_life_r125")
                .accessibilityIdentifier("research_section_life_r125")
            ForEach(model.catalog?.research ?? []) { r in
                VStack(alignment:.leading,spacing:10) {
                    Text(r.name).font(.headline)
                    Text(benefit(r)).foregroundStyle(Palette.text)
                        .accessibilityIdentifier("research_benefit_"+r.id)
                    if !model.state.completedResearchIDs.contains(r.id) {
                        Text(r.cost.isEmpty ? "素材消費なし" : r.cost.sorted{$0.key<$1.key}.map{"\(GameText.name($0.key)) \(model.state.materials[$0.key,default:0])/\($0.value)"}.joined(separator:" · "))
                            .font(.caption).foregroundStyle(Palette.gold).fixedSize(horizontal:false,vertical:true)
                    }
                    if !model.state.completedResearchIDs.contains(r.id) { materialGuidance(r) }
                    if model.state.completedResearchIDs.contains(r.id) {
                        Label("習得済み",systemImage:"checkmark.seal.fill")
                            .foregroundStyle(Palette.gold).frame(minHeight:44)
                            .accessibilityIdentifier("research_complete_"+r.id)
                    } else if let reason=lockReason(r) {
                        Label(reason,systemImage:"lock.fill").font(.caption)
                            .foregroundStyle(Palette.text).fixedSize(horizontal:false,vertical:true)
                            .frame(minHeight:44,alignment:.leading)
                            .accessibilityIdentifier("research_lock_"+r.id)
                    } else {
                        Button { model.act(.completeResearch(r.id),"研究の成果を記録しました。") } label: {
                            Text("研究する").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                        .disabled(model.busy)
                        .accessibilityIdentifier("research_action_"+r.id)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
                    .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))
                    .id("research_card_r286_\(r.id)")
            }
            Text("深まる森の課題").font(.title3)
                .id("research_section_challenges_r125")
                .accessibilityIdentifier("research_section_challenges_r125")
            if let continuation {
                Text("達成 \(continuation.challengesCleared) / \(continuation.challenges.count)\(continuation.challenges.count > 0 && continuation.challengesCleared == continuation.challenges.count ? "・達成済みの課題にも再挑戦できます" : "・第五地域の最終ボスを越えると挑めます")")
                    .font(.caption).foregroundStyle(Palette.gold).fixedSize(horizontal:false,vertical:true)
            }
            Menu {
                Button("すべての地域") { challengeRegionFilterR251=nil }
                    .accessibilityIdentifier("challenge_filter_all")
                ForEach(challengeRegionOptionsR251) { region in
                    Button(region.name) { challengeRegionFilterR251=region.id }
                        .accessibilityIdentifier("challenge_filter_"+region.id)
                }
            } label: {
                HStack {
                    Text("地域")
                    Spacer()
                    Text(selectedChallengeRegionNameR251)
                    Image(systemName:"chevron.up.chevron.down")
                }
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("research_challenge_region_filter_r251")
            .accessibilityValue(selectedChallengeRegionNameR251)
            Text("表示中：\(selectedChallengeRegionNameR251)（\(visibleChallengesR251.count)件）")
                .font(.caption).foregroundStyle(Palette.text)
                .accessibilityIdentifier("research_challenge_filter_status_r251")
            ForEach(visibleChallengesR251) { c in
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text(c.name).font(.headline)
                        Spacer()
                        if model.state.completedEncounterIDs.contains("CHALLENGE_CLEAR|"+c.id) {
                            Image(systemName:"checkmark.seal.fill").foregroundStyle(Palette.gold).accessibilityLabel("達成済み")
                        }
                    }
                    Text(GameText.challengeMechanic(c.id,fallback:c.mechanic)).font(.caption).foregroundStyle(Palette.gold)
                    if let availability=challengeAvailability(c.id),availability != .locked {
                        if availability == .cleared {
                            Text("達成済み・再挑戦できます。初回達成報酬は再付与されません。")
                                .font(.caption).foregroundStyle(Palette.gold)
                                .fixedSize(horizontal:false,vertical:true)
                                .accessibilityIdentifier("challenge_replay_note_"+c.id)
                        } else {
                            Text("初回達成時に課題の報酬を受け取れます。")
                                .font(.caption).foregroundStyle(Palette.gold)
                                .fixedSize(horizontal:false,vertical:true)
                        }
                        Button { model.challenge(c) } label: { Text(availability == .cleared ? "もう一度挑む" : "研究課題に挑む").frame(minHeight:44) }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Palette.ink)
                            .disabled(model.busy)
                            .frame(minHeight:44)
                            .accessibilityIdentifier("challenge_"+c.id)
                    } else {
                        Label("第五地域の最終ボス討伐で解放",systemImage:"lock.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal:false,vertical:true)
                            .frame(minHeight:44,alignment:.leading)
                            .accessibilityElement(children:.combine)
                            .accessibilityIdentifier("challenge_lock_"+c.id)
                    }
                }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))
            }
        }
    }
}
