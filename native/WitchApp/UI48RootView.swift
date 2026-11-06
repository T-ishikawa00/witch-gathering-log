import SwiftUI
import SpriteKit

struct UI48RootView: View {
    @ObservedObject var model: GameModel
    @StateObject private var flow = UI48Flow()
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var fixtureApplied = false
    @State private var showNotice = false
    private var baseScreen: Int { ["家":1,"探索":4,"仲間":13,"工房":19,"採集帳":28][model.tab] ?? 1 }
    private var screen: Int {
        if model.startupState != .ready {return flow.path.last == 47 ? 47:48}
        if model.fighting { return 8 }
        if let routed = flow.path.last { return routed }
        if baseScreen == 1, let c=model.catalog, let progress=SharedPartyWorkProgressR146.project(state:model.state,catalog:c,now:Date()), progress.ready > 0 {return 2}
        return baseScreen
    }
    private var isBase: Bool { flow.path.isEmpty || [1,2,4,8,13,19,28].contains(screen) }
    private var title: String {
        let names=[1:"魔女の家",2:"魔女の家",3:"森からの持ち帰り",4:regionName,5:"旅の地図",6:"森でできること",7:enemyName,8:regionName,9:"戦いの記録",10:"戦いの記録",11:"新しい地域",12:"採集先を変える",13:"仲間",14:"持ちもの",15:"装備の詳細",16:"装備を比べる",17:"装備セット",18:"持ちものを整理",19:"小さな工房",20:"制作の準備",21:"制作する",22:"分岐進化",23:"装備の強化",24:"装備の研成",25:"品質を高める",26:"工房からの贈りもの",27:"持ちもの",28:"採集帳",29:"素材の記録",30:"魔物の記録",31:"暮らしと冒険の研究",32:"研究の準備",33:"15の研究課題",34:"研究課題",35:"LR装備の収集帳",36:"星灯りの魔導庫",37:"探す装備を選ぶ",38:"提供割合と保証",39:"鑑定の結果",40:"衣装の試着",41:"武器の外観",42:"模様替え",43:"森の小さな商店",44:"商品の詳細",45:"購入の確認",46:"設定",47:"保存の確認",48:"魔女の採集帳"]
        return names[screen] ?? "魔女の採集帳"
    }
    private var regionName: String { model.catalog?.regions.first{$0.id==model.chosenRegion}?.name ?? "探索" }
    private var enemyName: String { model.catalog?.enemies.first{$0.id==flow.enemyID}?.name ?? "魔物" }
    var body: some View {
        VStack(spacing:0) {
            // Navigation chrome stays compact; scrollable game content follows the full user text size.
            if screen != 48 { header.dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
            content.id(screen).frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
            if [1,2,4,8,13,19,28,31,33].contains(screen) { footer.dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
        }.background(UI48Theme.ink.ignoresSafeArea()).foregroundStyle(UI48Theme.ivory).tint(UI48Theme.gold)
            .environmentObject(model.productCommerce)
            .overlay(alignment:.bottom){ if model.busy && !model.fighting { HStack{ProgressView().tint(UI48Theme.gold);Text("処理しています…").font(.footnote)}.padding(12).background(UI48Theme.ink).clipShape(Capsule()).padding(.bottom,12).accessibilityIdentifier("ui48_busy") } }
            .alert("確認が必要です",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("閉じる",role:.cancel){model.error=nil}}message:{Text(model.error ?? "")}
            .task { await model.load(); await model.reconcileExpiredCommerceOwnershipR1(); await model.productCommerce.refreshCatalogAndRecover(); applyQARoute() }
            .onChange(of:model.notice){_,_ in showNotice=true}
            .overlay(alignment:.top) {if showNotice {Text(model.notice).font(.footnote).dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(12).background(UI48Theme.enamel).clipShape(UI48Frame()).padding(.top,70).padding(.horizontal).accessibilityIdentifier("ui48_notice").allowsHitTesting(false).task {try? await Task.sleep(for:.seconds(3));showNotice=false}}}
            .onChange(of:model.sheet){_,sheet in route(sheet)}
            .onChange(of:model.tab){_,_ in model.syncScene()}
            .onChange(of:model.selectedActor){_,_ in model.syncScene()}
            .onChange(of:model.saveRecoveryMessage){_,message in if message != nil {flow.go(47)}}
            .onChange(of:model.fighting){_,active in
                if active {flow.battleBefore=model.ui48BattleBaseline ?? model.state;flow.battleSummary=nil;flow.newRegionIDs=[]}
                else if let before=flow.battleBefore, model.error==nil,let battle=model.state.lastCombatResult {
                    flow.battleSummary=GatheringSummary(before:before,after:model.state,catalog:model.catalog)
                    flow.newRegionIDs=Array(model.state.unlockedRegionIDs.subtracting(before.unlockedRegionIDs)).sorted()
                    flow.go(battle.won ? 9:10);flow.battleBefore=nil
                }
            }
            .onChange(of:phase){_,p in model.sceneActive=p == .active; if p == .active {Task{await model.reconcileExpiredCommerceOwnershipR1();await model.refresh()}}}
            .onChange(of:model.startupState){_,value in if value == .ready {route(model.sheet);if model.saveRecoveryMessage != nil {flow.go(47)};applyQARoute()}}

    }
    @ViewBuilder private var content: some View {
        switch screen {
        case 1...12: UI48AdventureView(model:model,flow:flow,screen:screen)
        case 13...27: UI48EquipmentView(model:model,flow:flow,screen:screen)
        case 28...39: UI48JournalView(model:model,flow:flow,screen:screen)
        default: UI48LifestyleView(model:model,flow:flow,screen:screen)
        }
    }
    private var header: some View {
        HStack(spacing:12) {
            if isBase && (screen == 1 || screen == 2) {Image(systemName:"moon").font(.title).foregroundStyle(UI48Theme.gold).frame(width:32).accessibilityHidden(true)}
            else {Button {if flow.path.isEmpty {flow.home(model)} else {flow.back()}} label:{Image(systemName:"chevron.left").font(.title2).frame(width:44,height:44)}.disabled(model.busy).accessibilityLabel("戻る").accessibilityIdentifier("ui48_back")}
            VStack(alignment:.leading,spacing:4){Text(title).accessibilityIdentifier(String(format:"ui48_screen_%02d",screen)).font(.system(.title3,design:.serif,weight:.semibold)).fixedSize(horizontal:false,vertical:true);if screen == 1 || screen == 2 {Text("小さな発見を、またひとつ。").font(.caption2).foregroundStyle(UI48Theme.gold)}}
            Spacer(minLength:0)
            if screen == 1 || screen == 2 {
                Button{flow.go(36)}label:{Label("\(model.state.currency["ticket_free",default:0])",systemImage:"star").font(.caption).frame(minWidth:44,minHeight:44)}.accessibilityLabel("無料鑑定券 \(model.state.currency["ticket_free",default:0])枚、魔導庫を開く")
                Button{flow.go(46)}label:{Image(systemName:"gearshape").font(.title2).frame(width:44,height:44)}.accessibilityLabel("設定").accessibilityIdentifier("settings")
            } else if !isBase {
                Button{flow.home(model,tab:model.tab)}label:{Image(systemName:"xmark").font(.title2).frame(width:44,height:44)}.disabled(model.busy).accessibilityLabel("閉じる").accessibilityIdentifier("ui48_close")
            }
        }.padding(.horizontal,12).padding(.vertical,7).frame(minHeight:64).background(LinearGradient(colors:[Color(hex48:0x122728),Color(hex48:0x102122)],startPoint:.top,endPoint:.bottom)).overlay(alignment:.bottom){Rectangle().fill(UI48Theme.gold).frame(height:1)}
    }
    private var footer: some View {
        HStack(spacing:0) {
            ForEach(Array(zip(["家","探索","仲間","工房","採集帳"],["house","safari","person.2","hammer","book"])),id:\.0) { tab,symbol in
                Button { flow.home(model,tab:tab) } label: {
                    VStack(spacing:5) {
                        Image(systemName:symbol).font(.system(size:24))
                        Text(tab).font(.caption2).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,minHeight:58).contentShape(Rectangle())
                        .overlay(alignment:.top) {
                            if model.tab==tab {Text("◆").font(.system(size:7)).offset(y:-5).accessibilityHidden(true)}
                        }
                }.buttonStyle(.plain).accessibilityLabel(tab)
                    .foregroundStyle(model.tab==tab ? UI48Theme.gold:Color(hex48:0xaaad96))
                    .disabled(model.fighting || model.busy)
                    .accessibilityIdentifier("tab_"+tab)
                    .accessibilityValue(model.tab==tab ? "選択中":"")
            }
        }.padding(.top,9).padding(.horizontal,5)
            .background(UI48Theme.enamel.opacity(0.4))
            .overlay(alignment:.top){Rectangle().fill(UI48Theme.gold).frame(height:1)}
    }
    /// Direct capture routes are available only inside the validated Simulator QA
    /// namespace. Result screens use real commands against that isolated save.
    private func applyQARoute() {
        #if targetEnvironment(simulator)
        let arguments=ProcessInfo.processInfo.arguments
        guard !fixtureApplied, model.startupState == .ready,
              UI48QALaunchGate.isValid(arguments:arguments),
              let raw=arguments.first(where:{$0.hasPrefix("--ui48-screen=")}),
              let requested=Int(raw.dropFirst("--ui48-screen=".count)),let c=model.catalog else{return}
        fixtureApplied=true
        let firstGear=model.state.gear.first { item in
            !model.state.equippedGearIDs.values.contains(item.id) && c.gear.first(where:{$0.id==item.definitionID})?.actorIDs.contains(model.selectedActor) == true
        } ?? model.state.gear.first
        flow.gearID=firstGear?.id
        flow.enemyID=c.enemies.first?.id
        flow.regionID=c.regions.first?.id
        if requested == 11 { flow.regionID = c.regions.dropFirst().first?.id }
        flow.materialID=c.regions.first?.gatherMaterialIDs.first
        flow.workTarget=flow.materialID.map(PartyWorkTargetR144.gather)
        flow.researchID=c.research.first?.id
        flow.challengeID=c.challenges.first?.id
        flow.targetID=c.gear.first?.id
        flow.appearanceID=c.appearances.first?.id
        model.previewRecipeID=(requested == 20 ? model.recipeGoals.first(where:{!$0.ready}):model.recipeGoals.first(where:{$0.kind=="craft_new" && $0.ready}))?.recipeID ?? model.recipeGoals.first?.recipeID
        if let firstGear {model.previewRecipeGearID=firstGear.id}
        if [4,5,6,7,8,9,10,11,12].contains(requested) {model.tab="探索"}
        else if (13...18).contains(requested) {model.tab="仲間"}
        else if (19...27).contains(requested) {model.tab="工房"}
        else if (28...39).contains(requested) {model.tab="採集帳"}
        else {model.tab="家"}
        // Result capture waits for the ordinary command's completion route. A
        // rejected command must never leave a success/result screen underneath.
        let preparationScreen = [3:2, 8:7, 9:7, 10:7, 26:21, 39:36][requested] ?? requested
        flow.go(preparationScreen);model.syncScene()
        model.writeReceipt("ui48_capture_route","ISOLATED_STATE_CAPTURE_NOT_ORDINARY_PLAY",metadata:["screen":requested])
        if requested == 3 {model.collect()}
        if [8,9,10].contains(requested),let e=(requested == 10 ? c.enemies.last:c.enemies.first),let engine=model.engine {
            flow.enemyID=e.id
            Task {
                do {
                    if model.state.activeRegionID != e.regionID {
                        _ = try await engine.dispatch(.startExpeditionAt(regionID:e.regionID,now:Date()),operationID:UUID(),expectedRevision:model.state.revision)
                        await model.refresh()
                    }
                    model.chosenRegion=e.regionID;model.fight(e)
                } catch {model.error=model.commandErrorText(error)}
            }
        }
        if requested == 26,let recipeID=model.previewRecipeID {flow.commit(.craftRecipe(recipeID),model:model,title:"制作が完成しました")}
        if requested == 39 {model.summon(5)}
        #endif
    }
    private func route(_ sheet: String?) {
        guard let sheet else{return}
        let mapping=["共同作業の成果":3,"採集の成果":3,"装備":14,"開封":39,"魔導庫":36,"確率":38,"模様替え":42,"試着":40,"比較":16,"装備セット":17,"制作目標":20,"商店":43,"設定":46]
        if let id=mapping[sheet] {flow.go(id)}
        model.sheet=nil
    }
}
