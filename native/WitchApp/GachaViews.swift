import SwiftUI

struct GachaView:View {
    @ObservedObject var model:GameModel
    @State private var pendingTarget:String?
    var targetName:String{model.catalog?.gear.first{$0.id==model.state.gachaPity.targetTemplateID}?.name ?? "指定なし"}
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("星灯りの魔導庫").font(.system(.title,design:.serif))
            Text("まだ見ぬ装備との出会い。無料券で鑑定できます。").font(.caption).foregroundStyle(Palette.gold)
            AssetIcon(id:"ICO_"+(model.state.gachaPity.targetTemplateID ?? "EQ_W_01"),size:140).frame(maxWidth:.infinity).accessibilityLabel("目標装備の見本: \(targetName)")
            Text("無料鑑定券  \(model.state.currency["ticket_free",default:0])").font(.title3)
            Menu {ForEach(model.catalog?.gear ?? []){g in Button(g.name){if model.state.gachaPity.targetTemplateID != g.id {if model.state.gachaPity.guaranteeTargetOnNextTop{pendingTarget=g.id}else{model.act(.setGachaTarget(templateID:g.id),"目標装備を保存しました。")}}}.accessibilityIdentifier("gacha_target_"+g.id)}} label:{Label("目標装備: "+targetName,systemImage:"scope").frame(minHeight:44)}.disabled(!model.state.gachaUnlocked).accessibilityLabel("鑑定の目標装備、\(targetName)").accessibilityHint(!model.state.gachaUnlocked ? "装備を制作し、同じ部位を比べると選べます":"目標にする装備を選びます。次のLR保証が有効な場合は変更を確認します").accessibilityIdentifier("gacha_target")
            Text("LR保証まで最大\(max(1,100-model.state.gachaPity.drawsSinceTop))回 ・ UR以上まで最大\(max(1,20-model.state.gachaPity.drawsSinceMid))回").font(.caption).foregroundStyle(Palette.gold).accessibilityLabel("LR保証まで最大\(max(1,100-model.state.gachaPity.drawsSinceTop))回、UR以上保証まで最大\(max(1,20-model.state.gachaPity.drawsSinceMid))回")
            if model.state.gachaPity.guaranteeTargetOnNextTop {Text("次のLRは選んだ目標装備を保証").font(.caption).accessibilityLabel("目標保証中。次のLRは選んだ目標装備です")}
            if !model.state.gachaUnlocked {Text("工房で装備を制作し、仲間画面で同じ部位の装備を比較すると鑑定できます。").font(.callout)}
            ForEach([5,50],id:\.self){count in Button{model.summon(count)}label:{HStack{Image(systemName:"sparkles").accessibilityHidden(true);Text("\(count)個をまとめて鑑定");Spacer();Text("券 \(count)")}.padding(14).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:10))}.disabled(!model.state.gachaUnlocked || model.state.currency["ticket_free",default:0]<count).accessibilityLabel("無料鑑定券を\(count)枚使ってまとめて鑑定").accessibilityHint(!model.state.gachaUnlocked ? "鑑定は工房制作と装備比較の後に解放されます":model.state.currency["ticket_free",default:0]<count ? "無料鑑定券が足りません":"確認画面を開かずに鑑定します").accessibilityIdentifier("summon\(count)")}
            Button("今日の無料券を受け取る（\(model.catalog?.dailyFreeTicketGrant ?? 0)枚）"){model.daily()}.frame(minHeight:44).disabled(!model.state.gachaUnlocked).accessibilityIdentifier("daily_free_claim").accessibilityHint(model.state.gachaUnlocked ? "本日の無料分を受け取ります":"装備を制作し、同じ部位を比べると受け取れます")
            Button("確率と保証を見る"){model.sheet="確率"}.frame(minHeight:44)
        }.disabled(model.busy)
        .alert("目標装備を変更しますか？",isPresented:Binding(get:{pendingTarget != nil},set:{if !$0{pendingTarget=nil}})){Button("目標を変更する"){if let id=pendingTarget{model.act(.setGachaTarget(templateID:id),"目標装備を保存しました。")};pendingTarget=nil};Button("キャンセル",role:.cancel){pendingTarget=nil}}message:{Text("LR・UR保証までの回数は維持されます。現在の「次のLRで目標を保証」は解除されます。")}
    }
}

struct GachaRulesView:View {
    @ObservedObject var model:GameModel
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("鑑定の仕組み").font(.system(.title,design:.serif))
            Text("ローカル試験中の設定").foregroundStyle(Palette.gold)
            ForEach(["Q0","Q1","Q2","Q3","Q4"],id:\.self){id in LabeledContent(GameText.quality(id),value:String(format:"%.2f%%",Double(model.catalog?.gachaOddsBasisPoints[id] ?? 0)/100))}
            Text("LRは最大100回、UR以上は最大20回以内に保証します。該当品質の装備が出ると、それぞれの回数がリセットされます。")
            Text("目標を指定すると、LRが出た際に50%で目標装備になります。外れた場合、次のLRで目標を保証します。目標を変更すると、この目標保証だけが解除されます。")
            Text("全\(model.catalog?.gear.count ?? 0)種が候補です。品質とは別に種類を抽選するため、上の数値は種類別確率ではありません。")
            Text("このビルドの実設定です。正式な販売用確率・保証・商品構成は未確定です。").font(.caption).foregroundStyle(Palette.gold)
        }
    }
}
