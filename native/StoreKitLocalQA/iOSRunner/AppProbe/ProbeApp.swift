import SwiftUI
import StoreKit

@main
struct StoreKitQAProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var status = "Ready"
    @Published var owned = "owned=[]"
    @Published var failWrites = false
    @Published var products: [Product] = []
    private let store = ProbeReceiptStore(failWrites: ProcessInfo.processInfo.arguments.contains("--qa-fail-save"))
    private lazy var bridge = StoreKitLocalQABridge(
        gate: StoreKitLocalQAGate(xcodeLocalConfigurationIsActive: true), sink: store
    )

    func start() async {
        do {
            try await bridge.startObserving()
            await loadProducts()
            await readSnapshot()
        } catch { status = "gateError=\(String(reflecting: error))" }
    }

    func loadProducts() async {
        do {
            products = try await bridge.products(for: ["local.witch.test.furniture", "local.witch.test.ticket"])
            status = "products=\(products.count) ids=\(products.map(\.id).sorted().joined(separator: ","))"
        } catch { status = "productError=\(String(reflecting: error))" }
    }

    func buy(_ id: String) async {
        do {
            let result = try await bridge.purchase(productID: id)
            status = "purchase=\(result)"
            await readSnapshot()
        } catch { status = "purchaseError=\(String(reflecting: error))" }
    }

    func restore() async {
        do {
            try await bridge.restoreEntitlementsExcludingConsumables()
            status = "restore=completed"
            await readSnapshot()
        } catch { status = "restoreError=\(String(reflecting: error))" }
    }

    func buyMissingProduct() async {
        do { _ = try await bridge.purchase(productID: "local.witch.test.missing") }
        catch { status = "missingProductError=\(String(reflecting: error))" }
    }

    func toggleFailure() async {
        failWrites.toggle()
        await store.setFailWrites(failWrites)
        status = "durableWriteFailure=\(failWrites)"
    }

    func readSnapshot() async {
        let snapshot = await store.currentSnapshot()
        let ids = snapshot.ownedProductIDs.sorted().joined(separator: ",")
        owned = "owned=[\(ids)] receipts=\(snapshot.receipts.count) persistedTransactions=\(snapshot.persistedTransactionIDs.count)"
        print("QA_RECEIPT_SNAPSHOT \(owned) file=\(await store.storageURL().path)")
    }
}

struct ProbeView: View {
    @StateObject private var model = ProbeModel()
    var body: some View {
        VStack(spacing: 12) {
            Text("StoreKit Local QA").font(.title2)
            Text(model.status).accessibilityIdentifier("status")
            Text(model.owned).accessibilityIdentifier("owned")
            Button("Load products") { Task { await model.loadProducts() } }.accessibilityIdentifier("load")
            Button("Buy furniture") { Task { await model.buy("local.witch.test.furniture") } }.accessibilityIdentifier("buyFurniture")
            Button("Buy ticket") { Task { await model.buy("local.witch.test.ticket") } }.accessibilityIdentifier("buyTicket")
            Button("Restore") { Task { await model.restore() } }.accessibilityIdentifier("restore")
            Button("Buy missing product") { Task { await model.buyMissingProduct() } }.accessibilityIdentifier("buyMissing")
            Button(model.failWrites ? "Allow durable writes" : "Fail durable writes") {
                Task { await model.toggleFailure() }
            }.accessibilityIdentifier("toggleSaveFailure")
            Button("Read durable receipt") { Task { await model.readSnapshot() } }.accessibilityIdentifier("readReceipt")
        }
        .padding()
        .task { await model.start() }
    }
}
