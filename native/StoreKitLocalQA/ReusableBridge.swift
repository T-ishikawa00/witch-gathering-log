import Foundation
import StoreKit

/// A deliberately local-only StoreKit 2 bridge for the QA harness.
///
/// Do not wire this into the shipping purchase UI. The caller must set
/// `xcodeLocalConfigurationIsActive` only for a Run scheme that has the local
/// `.storekit` file selected. The compile-time gate additionally makes every
/// operation unavailable outside DEBUG Simulator builds. Each returned
/// transaction is checked again for `Environment.xcode` before it reaches the
/// durable sink, so Sandbox/App Store transactions are never granted here.
@available(iOS 17.0, macOS 14.0, *)
public struct StoreKitLocalQAGate: Sendable {
    fileprivate let isOpen: Bool

    public init(xcodeLocalConfigurationIsActive: Bool) {
        #if DEBUG && targetEnvironment(simulator)
        self.isOpen = xcodeLocalConfigurationIsActive
            && ProcessInfo.processInfo.arguments.contains("--xcode-local-storekit-qa")
        #else
        self.isOpen = false
        #endif
    }
}

@available(iOS 17.0, macOS 14.0, *)
public enum StoreKitLocalQAEventKind: String, Sendable, Equatable {
    case purchase
    case restore
    case revocation
}

@available(iOS 17.0, macOS 14.0, *)
public enum StoreKitLocalQAProductKind: String, Sendable, Equatable {
    case consumable
    case nonConsumable
    case autoRenewable
    case nonRenewable
    case unknown
}

/// The immutable payload delivered to the game's durable ownership callback.
/// `idempotencyKey` remains stable when StoreKit redelivers an unfinished or
/// updated transaction. The sink must persist the delivery and deduplicate by
/// this key before returning successfully.
@available(iOS 17.0, macOS 14.0, *)
public struct StoreKitLocalQAEvent: Sendable, Equatable {
    public let kind: StoreKitLocalQAEventKind
    public let transactionID: UInt64
    public let originalTransactionID: UInt64?
    public let quantity: Int?
    public let appAccountToken: UUID?
    public let transactionBundleID: String?
    public let idempotencyKey: String
    public let productID: String
    public let productKind: StoreKitLocalQAProductKind
    public let environment: String
    public let purchaseDate: Date
    public let revocationDate: Date?

    public init(
        kind: StoreKitLocalQAEventKind,
        transactionID: UInt64,
        productID: String,
        productKind: StoreKitLocalQAProductKind,
        environment: String,
        purchaseDate: Date,
        revocationDate: Date?,
        originalTransactionID: UInt64? = nil,
        quantity: Int? = nil,
        appAccountToken: UUID? = nil,
        transactionBundleID: String? = nil
    ) {
        self.kind = kind
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.quantity = quantity
        self.appAccountToken = appAccountToken
        self.transactionBundleID = transactionBundleID
        let deliveryKind = kind == .revocation ? "revocation" : "entitlement"
        self.idempotencyKey = "storekit-xcode:\(transactionID):\(deliveryKind)"
        self.productID = productID
        self.productKind = productKind
        self.environment = environment
        self.purchaseDate = purchaseDate
        self.revocationDate = revocationDate
    }
}

/// Implement this with a durable, idempotent game-save transaction. Throwing
/// leaves the StoreKit transaction unfinished so StoreKit can redeliver it.
@available(iOS 17.0, macOS 14.0, *)
public protocol StoreKitLocalQADurableSink: Sendable {
    func apply(_ event: StoreKitLocalQAEvent) async throws
}

@available(iOS 17.0, macOS 14.0, *)
public enum StoreKitLocalQAPurchaseResult: Sendable, Equatable {
    case delivered(transactionID: UInt64)
    case pending
    case cancelled
}

@available(iOS 17.0, macOS 14.0, *)
public enum StoreKitLocalQAError: Error, Sendable, Equatable {
    case localRunDisabled
    case productUnavailable(String)
    case unverifiedTransaction
    case nonXcodeEnvironment(String)
    case transactionNotFound(UInt64)
    case transactionRevoked(UInt64)
    case transactionIdentityMismatch(UInt64)
}

/// StoreKit 2 adapter intended only for the dedicated Xcode local StoreKit
/// configuration. Integrators provide the durable callback; this type never
/// mutates game state directly.
@available(iOS 17.0, macOS 14.0, *)
public actor StoreKitLocalQABridge {
    private let gate: StoreKitLocalQAGate
    private let sink: any StoreKitLocalQADurableSink
    private var updatesTask: Task<Void, Never>?
    private var unfinishedTask: Task<Void, Never>?

    public init(gate: StoreKitLocalQAGate, sink: any StoreKitLocalQADurableSink) {
        self.gate = gate
        self.sink = sink
    }

    deinit {
        updatesTask?.cancel()
        unfinishedTask?.cancel()
    }

    /// Begins both StoreKit update and unfinished-transaction observation.
    /// Repeated calls are harmless; the durable sink must still be idempotent
    /// because StoreKit can redeliver after a crash or callback retry.
    public func startObserving() throws {
        try requireLocalRun()
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.consume(result, eventKind: .purchase)
            }
        }
        unfinishedTask = Task { [weak self] in
            for await result in Transaction.unfinished {
                guard !Task.isCancelled else { return }
                await self?.consume(result, eventKind: .purchase)
            }
        }
    }

    public func assertLocalRunEnabled() throws {
        try requireLocalRun()
    }

    /// Re-reads StoreKit's verified transaction history for a local QA import.
    /// The caller must still revalidate the host authority separately.
    public func currentVerifiedXcodeTransaction(matching expected: StoreKitLocalQAEvent) async throws -> StoreKitLocalQAEvent {
        try requireLocalRun()
        for await result in Transaction.all {
            switch result {
            case .verified(let transaction) where transaction.id == expected.transactionID:
                try requireXcodeEnvironment(transaction)
                guard transaction.revocationDate == nil else {
                    throw StoreKitLocalQAError.transactionRevoked(transaction.id)
                }
                let actual = makeEvent(transaction, eventKind: .purchase)
                guard actual == expected,
                      actual.transactionBundleID == Bundle.main.bundleIdentifier else {
                    throw StoreKitLocalQAError.transactionIdentityMismatch(transaction.id)
                }
                return actual
            case .unverified(let transaction, _) where transaction.id == expected.transactionID:
                throw StoreKitLocalQAError.unverifiedTransaction
            default:
                continue
            }
        }
        throw StoreKitLocalQAError.transactionNotFound(expected.transactionID)
    }

    /// Looks up StoreKit's current verified transaction without constructing an
    /// expected event from saved data. The caller must still revalidate the
    /// host authority separately.
    public func currentVerifiedXcodeTransaction(
        transactionID: UInt64,
        expectedAppAccountToken: UUID
    ) async throws -> StoreKitLocalQAEvent {
        try requireLocalRun()
        for await result in Transaction.all {
            switch result {
            case .verified(let transaction) where transaction.id == transactionID:
                try requireXcodeEnvironment(transaction)
                guard transaction.revocationDate == nil else {
                    throw StoreKitLocalQAError.transactionRevoked(transaction.id)
                }
                guard transaction.appBundleID == Bundle.main.bundleIdentifier,
                      transaction.appAccountToken == expectedAppAccountToken else {
                    throw StoreKitLocalQAError.transactionIdentityMismatch(transaction.id)
                }
                return makeEvent(transaction, eventKind: .purchase)
            case .unverified(let transaction, _) where transaction.id == transactionID:
                throw StoreKitLocalQAError.unverifiedTransaction
            default:
                continue
            }
        }
        throw StoreKitLocalQAError.transactionNotFound(transactionID)
    }

    public func stopObserving() {
        updatesTask?.cancel()
        unfinishedTask?.cancel()
        updatesTask = nil
        unfinishedTask = nil
    }

    public func products(for ids: [String]) async throws -> [Product] {
        try requireLocalRun()
        return try await Product.products(for: ids)
    }

    @discardableResult
    public func purchase(productID: String, appAccountToken: UUID? = nil) async throws -> StoreKitLocalQAPurchaseResult {
        try requireLocalRun()
        let products = try await Product.products(for: [productID])
        guard let product = products.first(where: { $0.id == productID }) else {
            throw StoreKitLocalQAError.productUnavailable(productID)
        }

        let purchaseResult: Product.PurchaseResult
        if let appAccountToken {
            purchaseResult = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        } else {
            purchaseResult = try await product.purchase()
        }
        switch purchaseResult {
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        case .success(let verification):
            let transaction = try verified(verification)
            try requireXcodeEnvironment(transaction)
            let event = makeEvent(transaction, eventKind: transaction.revocationDate == nil ? .purchase : .revocation)
            try await sink.apply(event)
            await transaction.finish()
            return .delivered(transactionID: transaction.id)
        @unknown default:
            throw StoreKitLocalQAError.unverifiedTransaction
        }
    }

    /// Re-syncs the local transaction history, then redelivers current durable
    /// entitlements. Consumables are excluded. `AppStore.sync()` may show the
    /// Xcode StoreKit simulated-account confirmation; this adapter does not
    /// collect credentials and is compiled out as an enabled path off Simulator.
    public func restoreEntitlementsExcludingConsumables() async throws {
        try requireLocalRun()
        try await AppStore.sync()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            try requireXcodeEnvironment(transaction)
            let kind = productKind(transaction.productType)
            guard kind != .consumable, kind != .unknown else { continue }
            let event = makeEvent(transaction, eventKind: .restore)
            try await sink.apply(event)
            await transaction.finish()
        }
    }

    private func consume(
        _ result: VerificationResult<Transaction>,
        eventKind: StoreKitLocalQAEventKind
    ) async {
        guard case .verified(let transaction) = result else { return }
        guard (try? requireXcodeEnvironment(transaction)) != nil else { return }
        let kind = transaction.revocationDate == nil ? eventKind : .revocation
        do {
            try await sink.apply(makeEvent(transaction, eventKind: kind))
            await transaction.finish()
        } catch {
            // Keep the transaction unfinished; StoreKit will redeliver it.
        }
    }

    private func requireLocalRun() throws {
        guard gate.isOpen else { throw StoreKitLocalQAError.localRunDisabled }
    }

    private func verified(
        _ result: VerificationResult<Transaction>
    ) throws -> Transaction {
        guard case .verified(let transaction) = result else {
            throw StoreKitLocalQAError.unverifiedTransaction
        }
        return transaction
    }

    private func requireXcodeEnvironment(_ transaction: Transaction) throws {
        guard transaction.environment == .xcode else {
            throw StoreKitLocalQAError.nonXcodeEnvironment(transaction.environment.rawValue)
        }
    }

    private func makeEvent(
        _ transaction: Transaction,
        eventKind: StoreKitLocalQAEventKind
    ) -> StoreKitLocalQAEvent {
        StoreKitLocalQAEvent(
            kind: eventKind,
            transactionID: transaction.id,
            productID: transaction.productID,
            productKind: productKind(transaction.productType),
            environment: transaction.environment.rawValue,
            purchaseDate: transaction.purchaseDate,
            revocationDate: transaction.revocationDate,
            originalTransactionID: transaction.originalID,
            quantity: transaction.purchasedQuantity,
            appAccountToken: transaction.appAccountToken,
            transactionBundleID: transaction.appBundleID
        )
    }

    private func productKind(_ type: Product.ProductType) -> StoreKitLocalQAProductKind {
        switch type {
        case .consumable: return .consumable
        case .nonConsumable: return .nonConsumable
        case .autoRenewable: return .autoRenewable
        case .nonRenewable: return .nonRenewable
        default: return .unknown
        }
    }
}
