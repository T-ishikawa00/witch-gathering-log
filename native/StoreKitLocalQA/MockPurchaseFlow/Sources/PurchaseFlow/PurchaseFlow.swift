import Foundation

public enum StoreItemKind: Sendable, Equatable { case consumable, nonConsumable }

public struct StoreItem: Sendable, Equatable {
    public let id: String
    public let kind: StoreItemKind
    public init(id: String, kind: StoreItemKind) { self.id = id; self.kind = kind }
}

public struct StoreTransaction: Sendable, Equatable {
    public let id: UInt64
    public let productID: String
    public init(id: UInt64, productID: String) { self.id = id; self.productID = productID }
}

public enum StorePurchaseResult: Sendable, Equatable {
    case success(StoreTransaction)
    case pending
    case cancelled
}

public protocol PurchaseStore: Sendable {
    func products(for ids: [String]) async throws -> [StoreItem]
    func purchase(_ item: StoreItem) async throws -> StorePurchaseResult
    func restore() async throws -> [StoreTransaction]
}

public enum PurchaseFlowResult: Equatable, Sendable {
    case productsLoaded(Int)
    case productUnavailable(String)
    case productLoadFailed(String)
    case purchaseGranted(String)
    case purchasePending
    case purchaseCancelled
    case purchaseFailed(String)
    case restored(Int)
    case restoreFailed(String)
    case duplicateTransaction(UInt64)
}

@MainActor
public final class PurchaseFlow {
    private let store: any PurchaseStore
    private var catalog: [String: StoreItem] = [:]
    private var processedTransactionIDs = Set<UInt64>()
    public private(set) var ownedProductIDs = Set<String>()
    public private(set) var consumableGrantCount = 0

    public init(store: any PurchaseStore) { self.store = store }

    @discardableResult
    public func loadProducts(_ ids: [String]) async -> PurchaseFlowResult {
        do {
            let items = try await store.products(for: ids)
            catalog = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return .productsLoaded(items.count)
        } catch { return .productLoadFailed(String(describing: error)) }
    }

    @discardableResult
    public func buy(_ id: String) async -> PurchaseFlowResult {
        let item: StoreItem
        if let cached = catalog[id] { item = cached }
        else {
            do {
                let refreshed = try await store.products(for: [id])
                guard let loaded = refreshed.first(where: { $0.id == id }) else { return .productUnavailable(id) }
                catalog[id] = loaded
                item = loaded
            } catch { return .productLoadFailed(String(describing: error)) }
        }
        do {
            switch try await store.purchase(item) {
            case .pending: return .purchasePending
            case .cancelled: return .purchaseCancelled
            case .success(let transaction):
                guard transaction.productID == item.id else { return .purchaseFailed("transaction_product_mismatch") }
                guard processedTransactionIDs.insert(transaction.id).inserted else { return .duplicateTransaction(transaction.id) }
                grant(item)
                return .purchaseGranted(item.id)
            }
        } catch { return .purchaseFailed(String(describing: error)) }
    }

    @discardableResult
    public func restore() async -> PurchaseFlowResult {
        do {
            let transactions = try await store.restore()
            var newEntitlements = 0
            for transaction in transactions where processedTransactionIDs.insert(transaction.id).inserted {
                guard let item = catalog[transaction.productID], item.kind == .nonConsumable else { continue }
                if ownedProductIDs.insert(item.id).inserted { newEntitlements += 1 }
            }
            return .restored(newEntitlements)
        } catch { return .restoreFailed(String(describing: error)) }
    }

    private func grant(_ item: StoreItem) {
        switch item.kind {
        case .consumable: consumableGrantCount += 1
        case .nonConsumable: ownedProductIDs.insert(item.id)
        }
    }
}
