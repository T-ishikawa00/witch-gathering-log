import Foundation
import Combine

/// App-facing purchase flow. A shipping configuration must explicitly inject the
/// real StoreKit adapter and approved content-to-product mapping. The local
/// candidate constructs this with no adapter, so neither StoreKit nor Keychain
/// nor an authority endpoint is contacted during ordinary play.
@MainActor
final class ProductCommerceModelR1: ObservableObject {
    @Published private(set) var busy=false
    @Published private(set) var status="正式な商品・価格・購入確認先は未接続です。現在は購入できません。"
    @Published private(set) var lastPurchase: CommercePurchasePresentationR465?
    private let adapter: CommerceStoreKit2R465?
    private let productByContentID: [String:String]
    private var observation: AnyCancellable?
    private var transactionObservation: AnyCancellable?

    init(adapter: CommerceStoreKit2R465? = nil, approvedProductByContentID: [String:String] = [:]) {
        self.adapter=adapter
        productByContentID=approvedProductByContentID
        observation=adapter?.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        transactionObservation=adapter?.$lastTransactionPresentation.sink { [weak self] result in
            guard let result else {return}
            Task { @MainActor in self?.present(result) }
        }
    }

    var connected: Bool { adapter?.isConfigured == true && !productByContentID.isEmpty }
    var shopStatus: String {
        connected ? (adapter?.lastStatusMessage ?? status)
            : "販売準備中です。価格・商品数・購入権利は未設定で、現在は購入できません。"
    }

    func price(contentID: String?) -> String {
        guard let id=contentID,let productID=productByContentID[id],let adapter else {return "価格未設定／購入未接続"}
        switch adapter.availability[productID] {
        case .available(let price,_): return price
        case .unavailable: return "現在は購入できません"
        default: return "商品情報を確認中"
        }
    }

    func canPurchase(contentID: String?) -> Bool {
        guard connected,!busy,let id=contentID,let productID=productByContentID[id],let adapter else {return false}
        if case .available = adapter.availability[productID] {return true}
        return false
    }

    func refreshCatalogAndRecover() async {
        guard connected,let adapter else {return}
        await adapter.refreshCatalog()
        adapter.startObservingTransactions()
    }

    func purchase(contentID: String?) async {
        guard connected,!busy,let id=contentID,let productID=productByContentID[id],let adapter else {return}
        busy=true
        defer {busy=false}
        status="App Storeで購入内容を確認しています。"
        let result=await adapter.purchase(productID:productID)
        present(result)
    }

    private func present(_ result: CommercePurchasePresentationR465) {
        lastPurchase=result
        switch result {
        case .blocked(let reasons): status=reasons.joined(separator:"・")
        case .pending: status="購入は保留中です。承認後に結果を確認します。再購入は不要です。"
        case .cancelled: status="購入を取り消しました。"
        case .delivered: status="購入内容を確認し、権利を保存しました。"
        case .awaitingApprovedAuthority: status="購入確認先の接続待ちです。取引の確認が終わるまで再購入しないでください。"
        case .retryable(let reason): status="購入結果を再確認します。再購入は不要です。\(reason)"
        case .revoked: status="返金または失効した購入権利を更新しました。"
        case .failed(let reason): status=reason
        }
    }

    func restore() async {
        guard !busy else {return}
        guard let adapter else {
            status="購入の復元は未接続です。ゲームの進行状況はこの端末のセーブに保存されており、購入の復元とは別です。"
            return
        }
        busy=true
        defer {busy=false}
        switch await adapter.restoreNonConsumables() {
        case .blocked(let reasons): status=reasons.joined(separator:"・")
        case .completed(let count,let note): status="購入権利を\(count)件確認しました。\(note)"
        case .retryable(let reason): status="復元を完了できませんでした。\(reason)"
        }
    }
}
