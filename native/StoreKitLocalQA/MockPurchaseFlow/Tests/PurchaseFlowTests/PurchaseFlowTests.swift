import XCTest
@testable import PurchaseFlow

private enum MockError: Error { case catalog, purchase, restore }

private actor MockStore: PurchaseStore {
    var items: [StoreItem]
    var purchaseResult: StorePurchaseResult = .cancelled
    var catalogFails = false
    var purchaseFails = false
    var restoreFails = false
    var restoreTransactions: [StoreTransaction] = []
    var purchaseCalls = 0

    init(items: [StoreItem] = []) { self.items = items }
    func products(for ids: [String]) async throws -> [StoreItem] {
        if catalogFails { throw MockError.catalog }
        return items.filter { ids.contains($0.id) }
    }
    func purchase(_ item: StoreItem) async throws -> StorePurchaseResult {
        purchaseCalls += 1
        if purchaseFails { throw MockError.purchase }
        return purchaseResult
    }
    func restore() async throws -> [StoreTransaction] {
        if restoreFails { throw MockError.restore }
        return restoreTransactions
    }
    func setPurchase(_ value: StorePurchaseResult) { purchaseResult = value }
    func setCatalogFailure(_ value: Bool) { catalogFails = value }
    func setPurchaseFailure(_ value: Bool) { purchaseFails = value }
    func setRestore(_ values: [StoreTransaction], fails: Bool = false) { restoreTransactions = values; restoreFails = fails }
    func calls() -> Int { purchaseCalls }
}

final class PurchaseFlowTests: XCTestCase {
    @MainActor
    func testVerifiedPurchaseGrantsNonConsumableExactlyOnce() async {
        let item = StoreItem(id: "furniture", kind: .nonConsumable)
        let store = MockStore(items: [item])
        await store.setPurchase(.success(StoreTransaction(id: 10, productID: item.id)))
        let flow = PurchaseFlow(store: store)
        let loadResult = await flow.loadProducts([item.id])
        XCTAssertEqual(loadResult, .productsLoaded(1))
        let firstPurchase = await flow.buy(item.id)
        XCTAssertEqual(firstPurchase, .purchaseGranted(item.id))
        XCTAssertTrue(flow.ownedProductIDs.contains(item.id))
        let replay = await flow.buy(item.id)
        XCTAssertEqual(replay, .duplicateTransaction(10))
        XCTAssertEqual(flow.ownedProductIDs.count, 1)
    }

    @MainActor
    func testCancellationAndPendingNeverGrant() async {
        let item = StoreItem(id: "furniture", kind: .nonConsumable)
        let store = MockStore(items: [item])
        let flow = PurchaseFlow(store: store)
        _ = await flow.loadProducts([item.id])
        await store.setPurchase(.cancelled)
        let cancelled = await flow.buy(item.id)
        XCTAssertEqual(cancelled, .purchaseCancelled)
        await store.setPurchase(.pending)
        let pending = await flow.buy(item.id)
        XCTAssertEqual(pending, .purchasePending)
        XCTAssertTrue(flow.ownedProductIDs.isEmpty)
    }

    @MainActor
    func testEmptyProductListDoesNotCallPurchase() async {
        let store = MockStore()
        let flow = PurchaseFlow(store: store)
        let result = await flow.buy("missing")
        XCTAssertEqual(result, .productUnavailable("missing"))
        let calls = await store.calls()
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testProductLoadingErrorDoesNotCallPurchase() async {
        let store = MockStore()
        await store.setCatalogFailure(true)
        let flow = PurchaseFlow(store: store)
        guard case .productLoadFailed = await flow.buy("furniture") else { return XCTFail("expected catalog failure") }
        let calls = await store.calls()
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testPurchaseErrorDoesNotGrant() async {
        let item = StoreItem(id: "ticket", kind: .consumable)
        let store = MockStore(items: [item])
        await store.setPurchaseFailure(true)
        let flow = PurchaseFlow(store: store)
        _ = await flow.loadProducts([item.id])
        guard case .purchaseFailed = await flow.buy(item.id) else { return XCTFail("expected purchase failure") }
        XCTAssertEqual(flow.consumableGrantCount, 0)
    }

    @MainActor
    func testRestoreGrantsOnlyNonConsumablesAndIsIdempotent() async {
        let furniture = StoreItem(id: "furniture", kind: .nonConsumable)
        let ticket = StoreItem(id: "ticket", kind: .consumable)
        let store = MockStore(items: [furniture, ticket])
        let transaction = StoreTransaction(id: 22, productID: furniture.id)
        await store.setRestore([transaction, transaction, StoreTransaction(id: 23, productID: ticket.id)])
        let flow = PurchaseFlow(store: store)
        _ = await flow.loadProducts([furniture.id, ticket.id])
        let firstRestore = await flow.restore()
        XCTAssertEqual(firstRestore, .restored(1))
        let secondRestore = await flow.restore()
        XCTAssertEqual(secondRestore, .restored(0))
        XCTAssertEqual(flow.ownedProductIDs, [furniture.id])
        XCTAssertEqual(flow.consumableGrantCount, 0)
    }

    @MainActor
    func testRestoreErrorDoesNotGrantEntitlements() async {
        let furniture = StoreItem(id: "furniture", kind: .nonConsumable)
        let store = MockStore(items: [furniture])
        await store.setRestore([], fails: true)
        let flow = PurchaseFlow(store: store)
        _ = await flow.loadProducts([furniture.id])
        guard case .restoreFailed = await flow.restore() else { return XCTFail("expected restore failure") }
        XCTAssertTrue(flow.ownedProductIDs.isEmpty)
    }
}
