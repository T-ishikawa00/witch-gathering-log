import Foundation
import StoreKit
import SwiftUI

extension GameModel {
    var localStoreKitQAEnabled:Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--qa-isolated") && ProcessInfo.processInfo.arguments.contains("--xcode-local-storekit-qa")
        #else
        return false
        #endif
    }
    var sceneFurniture:Set<String>{var value=state.placedFurnitureIDs;if localStoreKitQAEnabled && state.localStoreKitQAOwnedProductIDs.contains("local.witch.test.furniture"){value.insert("FURN_DESK_BOTANICAL")};return value}
    func startLocalStoreKitQA() async throws {
        guard localStoreKitQAEnabled,let engine else{return}
        let sink=GameStoreKitQASink(saves:engine.saves){[weak self] in await self?.qaDidPersistTransactionUpdate()}
        qaPurchaseSink=sink
        let bridge=StoreKitLocalQABridge(gate:StoreKitLocalQAGate(xcodeLocalConfigurationIsActive:true),sink:sink)
        qaPurchaseBridge=bridge;try await bridge.startObserving()
        let products=try await bridge.products(for:["local.witch.test.furniture","local.witch.test.ticket"])
        purchaseStatus="Xcode商品: \(products.count)件"
    }
    func qaDidPersistTransactionUpdate() async {
        await refresh();purchaseStatus="取引更新を保存しました（記録: \(state.localStoreKitQARecords.count)）"
        writeReceipt("purchase_update",purchaseStatus)
    }
    func qaSetWriteFailure(_ enabled:Bool){guard localStoreKitQAEnabled,!busy,let sink=qaPurchaseSink else{return};busy=true;Task{await sink.setFailureInjection(enabled);qaFailPurchaseWrites=enabled;busy=false}}
    func qaRetryUnfinished(){guard localStoreKitQAEnabled,!busy,let bridge=qaPurchaseBridge else{return};busy=true;Task{do{await bridge.stopObserving();try await bridge.startObserving();purchaseStatus="未完了取引の再読込を開始"}catch{purchaseStatus=String(reflecting:error)};busy=false}}
    func qaPurchase(_ id:String){guard let bridge=qaPurchaseBridge,!busy else{return};busy=true;Task{do{let result=try await bridge.purchase(productID:id);purchaseStatus=String(describing:result);await refresh()}catch{purchaseStatus=String(reflecting:error)};writeReceipt("purchase",purchaseStatus);busy=false}}
    func qaRestore(){guard let bridge=qaPurchaseBridge,!busy else{return};busy=true;Task{do{try await bridge.restoreEntitlementsExcludingConsumables();purchaseStatus="ローカル復元完了";await refresh()}catch{purchaseStatus=String(reflecting:error)};busy=false}}
}

struct GameStoreKitQAPanel:View {
    @ObservedObject var model:GameModel
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            Text("Xcode購入検証").font(.title);Text("独立したQAセーブを使用。実販売商品ではありません。").font(.caption)
            Text(model.purchaseStatus).accessibilityIdentifier("qa_purchase_status")
            Text("検証机: "+(model.state.localStoreKitQAOwnedProductIDs.contains("local.witch.test.furniture") ? "所有":"未所有")).accessibilityIdentifier("qa_furniture_owned")
            Text("検証券: \(model.state.currency["storekit_qa_ticket",default:0]) / 記録: \(model.state.localStoreKitQARecords.count)").accessibilityIdentifier("qa_purchase_records")
            Button("検証机を購入"){model.qaPurchase("local.witch.test.furniture")}.accessibilityIdentifier("qa_buy_furniture")
            Button("検証券を購入"){model.qaPurchase("local.witch.test.ticket")}.accessibilityIdentifier("qa_buy_ticket")
            Button("検証購入を復元"){model.qaRestore()}.accessibilityIdentifier("qa_restore")
            Button("存在しない商品で取得失敗を検証"){model.qaPurchase("local.witch.test.missing")}.accessibilityIdentifier("qa_missing_product")
            Toggle("保存失敗を注入（QA）",isOn:Binding(get:{model.qaFailPurchaseWrites},set:model.qaSetWriteFailure)).accessibilityIdentifier("qa_fail_writes")
            Button("未完了取引を再読み込み"){model.qaRetryUnfinished()}.accessibilityIdentifier("qa_retry_unfinished")
            Text("検証券は抽選に使用できません。有料抽選とサーバー権威は未統合です。").font(.caption)
        }.buttonStyle(.bordered).disabled(model.busy)
    }
}
