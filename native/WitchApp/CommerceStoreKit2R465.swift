import Foundation
import Combine
import StoreKit
import Security
import CryptoKit

/// FIFO serialization for commerce delivery work. MainActor prevents data races,
/// but an async operation can still be interleaved whenever it suspends. The
/// lane keeps restore, update, and revocation commits in their enqueue order.
@MainActor
final class CommerceDeliverySerialLaneR1 {
    private var tail: Task<Void, Never>?

    func perform<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let predecessor = tail
        let task = Task { @MainActor in
            await predecessor?.value
            return try await operation()
        }
        tail = Task { @MainActor in
            _ = try? await task.value
        }
        return try await task.value
    }
}

/// Actual StoreKit 2 adapter. It has no singleton/default configuration and
/// cannot reach StoreKit's purchase call until an approved config is injected.
@MainActor
final class CommerceStoreKit2R465: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var availability: [String: CommerceProductAvailabilityR465] = [:]
    @Published private(set) var lastStatusMessage = "購入機能は準備中です"
    @Published private(set) var ownershipProjection = CommerceOwnershipReadModelCandidateV1.empty
    @Published private(set) var lastTransactionPresentation: CommercePurchasePresentationR465?

    var isConfigured: Bool { configurationGateReasons.isEmpty }
    var gateReasons: [String] { configurationGateReasons }
    private var configurationGateReasons: [String] {
        var reasons = configuration.validationReasons.map(\.userMessage)
        if Bundle.main.bundleIdentifier != configuration.bundleID {
            reasons.append("アプリ識別情報が実行中のアプリと一致しません")
        }
        return reasons
    }
    func productAvailability(_ productID: String) -> CommerceProductAvailabilityR465? { availability[productID] }
    func isPurchaseAvailable(_ productID: String) -> Bool {
        guard configurationGateReasons.isEmpty, let product = products[productID] else { return false }
        return authority.supports(productID: productID, productType: product.type)
    }

    private let configuration: CommerceApprovalConfigurationR465
    private let journal: KeychainCommerceJournalR465
    private let authority: CommerceCandidateAuthorityClientR465
    private let bindingProvider: any CommerceAccountBindingProviderR465
    private let deliveryLane = CommerceDeliverySerialLaneR1()
    private var updatesTask: Task<Void, Never>?

    init(configuration: CommerceApprovalConfigurationR465,
         journal: KeychainCommerceJournalR465,
         authority: CommerceCandidateAuthorityClientR465,
         bindingProvider: any CommerceAccountBindingProviderR465) {
        self.configuration = configuration
        self.journal = journal
        self.authority = authority
        self.bindingProvider = bindingProvider
    }

    deinit { updatesTask?.cancel() }

    func refreshCatalog() async {
        let reasons = configurationGateReasons
        guard reasons.isEmpty else {
            availability = Dictionary(uniqueKeysWithValues: configuration.productIDs.map {
                ($0, .preparationOnly(reason: reasons.joined(separator: "・")))
            })
            lastStatusMessage = reasons.joined(separator: "・")
            return
        }
        do {
            let fetched = try await Product.products(for: Array(configuration.productIDs).sorted())
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            availability = Dictionary(uniqueKeysWithValues: configuration.productIDs.map { id in
                if let product = products[id] {
                    guard authority.supports(productID: id, productType: product.type) else {
                        return (id, .preparationOnly(reason: "この商品種別の提供方法は準備中です"))
                    }
                    return (id, .available(displayPrice: product.displayPrice, productID: id))
                }
                return (id, .unavailable)
            })
        } catch {
            availability = Dictionary(uniqueKeysWithValues: configuration.productIDs.map { ($0, .unavailable) })
            lastStatusMessage = "商品情報を取得できません。時間をおいて再試行してください。"
        }
    }

    /// Read-only candidate rights projection for diagnostics/UI. The gameplay
    /// ownership sink is committed separately and must succeed before finish.
    func refreshOwnershipProjection(nowEpochSeconds: Int64 = Int64(Date().timeIntervalSince1970)) async {
        do { ownershipProjection = try await journal.ownershipProjection(nowEpochSeconds: nowEpochSeconds) }
        catch { ownershipProjection = .empty }
    }

    func startObservingTransactions() {
        guard configurationGateReasons.isEmpty, updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            guard let self else { return }
            let pendingFinish: Set<String>
            do {
                for revocation in try await self.journal.pendingStoreKitRevocations() {
                    try await self.deliveryLane.perform {
                        _ = try await self.authority.commitStoreKitRevocation(
                            transactionID: revocation.transactionID,
                            proofFingerprint: revocation.proofFingerprint, revision: 0)
                        try await self.journal.markGameDeliveryCompleted(
                            transactionID: revocation.transactionID,
                            receiptFingerprint: revocation.proofFingerprint)
                    }
                }
                pendingFinish = try await self.journal.pendingFinishTransactionIDs()
            } catch {
                // Never finish StoreKit transactions when the durable journal
                // cannot be read; leave them unfinished for a safe retry.
                self.lastStatusMessage = "購入状態を読み取れないため、取引の完了処理を保留しました"
                self.updatesTask = nil
                return
            }
            for await result in Transaction.all {
                guard case .verified(let transaction) = result,
                      pendingFinish.contains(String(transaction.id)) else { continue }
                // Re-run the complete verified consume path. The cached pending
                // set may be stale by the time this transaction is reached, so
                // never finish from that snapshot alone.
                _ = await self.consume(result)
            }
            for await result in Transaction.unfinished {
                _ = await self.consume(result)
            }
            for await result in Transaction.updates {
                await self.consume(result)
            }
        }
    }

    func purchase(productID: String) async -> CommercePurchasePresentationR465 {
        let reasons = configurationGateReasons
        guard reasons.isEmpty else {
            return .blocked(reasons)
        }
        guard configuration.productIDs.contains(productID), let product = products[productID] else {
            return .blocked(["この商品は承認済みカタログにありません"])
        }
        guard authority.supports(productID: productID, productType: product.type) else {
            return .blocked(["この商品種別のゲーム内提供条件が承認・接続されていません"])
        }
        do {
            let binding = try await bindingProvider.currentBinding()
            switch try await product.purchase(options: [.appAccountToken(binding.appAccountToken)]) {
            case .success(let verification):
                return await consume(verification)
            case .pending:
                lastStatusMessage = "購入確認は保留中です。確定後に自動で確認します。"
                return .pending
            case .userCancelled:
                lastStatusMessage = "購入をキャンセルしました"
                return .cancelled
            @unknown default:
                return .failed("StoreKitが未対応の状態を返しました")
            }
        } catch {
            return .failed("購入を開始できませんでした。時間をおいて再試行してください。")
        }
    }

    /// StoreKit restore only discovers current nonconsumable/subscription
    /// entitlements. Consumable draw history/game progression is not restored here.
    func restoreNonConsumables() async -> CommerceRestorePresentationR465 {
        let reasons = configurationGateReasons
        guard reasons.isEmpty else { return .blocked(reasons) }
        do {
            try await AppStore.sync()
            var restored = 0
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      configuration.productIDs.contains(transaction.productID),
                      transaction.productType != .consumable else { continue }
                let result = await consume(result)
                if case .delivered = result { restored += 1 }
            }
            return .completed(restoredNonConsumables: restored,
                              note: "消費型商品とゲーム進行はStoreKit復元の対象外です")
        } catch {
            return .retryable("購入情報を同期できませんでした")
        }
    }

    private func consume(_ result: VerificationResult<Transaction>) async -> CommercePurchasePresentationR465 {
        let presentation: CommercePurchasePresentationR465
        do {
            presentation = try await deliveryLane.perform {
                await self.consumeTransaction(result)
            }
        } catch {
            presentation = .retryable("購入状態の保存を確認できないため、取引を保留しました")
        }
        lastTransactionPresentation = presentation
        return presentation
    }

    private func consumeTransaction(_ result: VerificationResult<Transaction>) async -> CommercePurchasePresentationR465 {
        guard configurationGateReasons.isEmpty else {
            return .blocked(configurationGateReasons)
        }
        switch result {
        case .unverified:
            return .failed("Appleの取引検証に失敗しました")
        case .verified(let transaction):
            guard configuration.productIDs.contains(transaction.productID),
                  authority.supports(productID: transaction.productID, productType: transaction.productType),
                  transaction.environment == .production || transaction.environment == .sandbox else {
                return .failed("取引の商品種別または環境に対応した提供設定がありません")
            }
            let transactionJWS = result.jwsRepresentation
            let kind: CommerceOperationKindR465
            switch transaction.productType {
            case .consumable: kind = .consumable
            case .nonConsumable: kind = .nonConsumable
            default: kind = .subscription
            }
            do {
                let binding = try await bindingProvider.currentBinding()
                guard transaction.appAccountToken == binding.appAccountToken else {
                    return .failed("取引のアカウント連携が一致しません")
                }
                let environmentName = transaction.environment == .production ? "Production" : "Sandbox"
                let operationID = CommerceOperationRecordR465.stableOperationID(
                    environment: environmentName, bundleID: Bundle.main.bundleIdentifier ?? "",
                    transactionID: String(transaction.id))
                let proposedRecord = try CommerceOperationRecordR465(
                    id: operationID, environment: environmentName,
                    bundleID: Bundle.main.bundleIdentifier ?? "", transactionID: String(transaction.id),
                    originalTransactionID: String(transaction.originalID), productID: transaction.productID,
                    quantity: transaction.purchasedQuantity,
                    kind: kind, status: .verifiedAwaitingAuthority, signedTransactionJWS: transactionJWS)
                let record = try await journal.insertVerified(proposedRecord, isCryptographicallyVerified: true)
                if transaction.revocationDate != nil {
                    let revocation = try await journal.markRevoked(transactionID: String(transaction.id), verifiedJWS: transactionJWS)
                    _ = try await authority.commitStoreKitRevocation(transactionID: String(transaction.id),
                        proofFingerprint: revocation.proofFingerprint, revision: 0)
                    try await journal.markGameDeliveryCompleted(transactionID: String(transaction.id),
                                                               receiptFingerprint: revocation.proofFingerprint)
                    await transaction.finish()
                    try await journal.markFinished(transactionID: String(transaction.id))
                    await refreshOwnershipProjection()
                    return .revoked
                }
                let expectation = try LocalStoreKitPurchaseExpectationR461(
                    environment: environmentName,
                    bundleID: Bundle.main.bundleIdentifier ?? "", transactionID: String(transaction.id),
                    originalTransactionID: String(transaction.originalID), productID: transaction.productID,
                    quantity: transaction.purchasedQuantity, accountBindingSHA256: binding.accountBindingSHA256,
                    accountIDSHA256: binding.accountIDSHA256)
                switch record.status {
                case .finished:
                    // Keychain can outlive the game save (for example after an
                    // reinstall). A finished StoreKit transaction may still be
                    // a current entitlement, so replay its already-accepted
                    // signed receipt into the current save without another
                    // authority request or another finish transition.
                    if let accepted = try await journal.acceptedCandidateDelivery(transactionID: String(transaction.id)),
                       accepted.receipt.event == .grant {
                        try await authority.replayFinishedGrant(receipt: accepted.receipt,
                            pending: accepted.pending, expected: expectation, record: record)
                        await refreshOwnershipProjection()
                        return .delivered
                    }
                    await refreshOwnershipProjection()
                    return .retryable("購入記録を確認できないため、権利の再反映を保留しました")
                case .revokedFinished:
                    await refreshOwnershipProjection()
                    return .revoked
                case .revoked:
                    if let accepted = try await journal.acceptedCandidateDelivery(transactionID: String(transaction.id)),
                       accepted.receipt.event == .revoke {
                        try await authority.deliverAccepted(receipt: accepted.receipt, pending: accepted.pending,
                                                            expected: expectation, record: record, journal: journal,
                                                            finish: { await transaction.finish() })
                        await refreshOwnershipProjection()
                        return .revoked
                    }
                    return .retryable("失効処理の保存確認を待っています。取引は完了していません。")
                case .deliveredAwaitingFinish:
                    if let accepted = try await journal.acceptedCandidateDelivery(transactionID: String(transaction.id)) {
                        try await authority.deliverAccepted(receipt: accepted.receipt, pending: accepted.pending,
                                                            expected: expectation, record: record, journal: journal,
                                                            finish: { await transaction.finish() })
                        await refreshOwnershipProjection()
                        return .delivered
                    }
                    return .retryable("購入権利の保存確認を待っています。取引は完了していません。")
                default: break
                }
                let pending = try PendingCommerceOperationCandidateV1(
                    transactionOperationID: UUID(uuidString: record.id)!, signedTransactionJWS: transactionJWS)
                if let accepted = try await journal.acceptedCandidateReceipt(transactionID: String(transaction.id)),
                   accepted.requestSHA256 == pending.requestSHA256 {
                    try await authority.deliverAccepted(receipt: accepted, pending: pending, expected: expectation,
                                                        record: record, journal: journal,
                                                        finish: { await transaction.finish() })
                } else {
                    try await authority.submit(pending: pending, expected: expectation, record: record,
                                               journal: journal, transaction: transaction)
                }
                await refreshOwnershipProjection()
                return .delivered
            } catch {
                try? await journal.markAuthorityRetry(transactionID: String(transaction.id), reason: "authority-unavailable")
                return .retryable("取引は端末に保留しました。確認後に再試行します。")
            }
        }
    }
}

/// Candidate authority-v1 bridge: strict signed receipt, local journal, durable
/// game ownership commit, and only then StoreKit finish. R461 bytes are rejected.
final class CommerceCandidateAuthorityClientR465: Sendable {
    private let transport: any CommerceAuthorityByteTransportR465
    private let receiptPublicKey: Curve25519.Signing.PublicKey
    private let receiptKeyID: String
    private let clock: @Sendable () -> Int64
    private let contentByEntitlementID: [String: (cosmeticIDs: Set<String>, furnitureIDs: Set<String>)]
    private let supportedKindsByProductID: [String: Set<CommerceOperationKindR465>]
    private let ownershipCommit: @Sendable (VerifiedCommerceOwnershipMutationR1) async throws -> Void

    init(transport: any CommerceAuthorityByteTransportR465, receiptPublicKey: Curve25519.Signing.PublicKey,
         receiptKeyID: String,
         contentByEntitlementID: [String: (cosmeticIDs: Set<String>, furnitureIDs: Set<String>)],
         supportedKindsByProductID: [String: Set<CommerceOperationKindR465>],
         ownershipCommit: @escaping @Sendable (VerifiedCommerceOwnershipMutationR1) async throws -> Void,
         clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
        self.transport = transport
        self.receiptPublicKey = receiptPublicKey
        self.receiptKeyID = receiptKeyID
        self.contentByEntitlementID = contentByEntitlementID
        self.supportedKindsByProductID = supportedKindsByProductID
        self.ownershipCommit = ownershipCommit
        self.clock = clock
    }

    func supports(productID: String, productType: Product.ProductType) -> Bool {
        let kind: CommerceOperationKindR465
        switch productType {
        case .consumable: kind = .consumable
        case .nonConsumable: kind = .nonConsumable
        default: kind = .subscription
        }
        // No consumable fulfillment is implemented; do not charge and then
        // silently omit ticket/game-progression delivery.
        guard kind != .consumable else { return false }
        return supportedKindsByProductID[productID]?.contains(kind) == true
    }

    func submit(pending: PendingCommerceOperationCandidateV1, expected: LocalStoreKitPurchaseExpectationR461,
                record: CommerceOperationRecordR465, journal: KeychainCommerceJournalR465,
                transaction: Transaction) async throws {
        try pending.validate()
        try await journal.registerCandidateIfAbsent(pending)
        let response = try await transport.exchange(pending.request.canonicalData())
        let receipt = try CommerceAuthorityReceiptCandidateV1.decodeStrict(response)
        let identity = CommerceAuthorityReceiptCandidateV1.Identity(
            environment: record.environment, bundleID: record.bundleID, transactionID: record.transactionID,
            originalTransactionID: record.originalTransactionID, productID: record.productID,
            quantity: record.quantity)
        let journalBinding = await journal.boundAccountBindingSHA256()
        guard expected.transactionID == identity.transactionID, expected.bundleID == identity.bundleID,
              expected.productID == identity.productID,
              expected.accountBindingSHA256 == journalBinding else {
            throw URLError(.dataNotAllowed)
        }
        try await journal.applyCandidateReceipt(receipt, recordID: record.id,
                                                expectedOperationID: pending.request.operationID,
                                                requestSHA256: pending.requestSHA256,
                                                expectedAccountBindingSHA256: expected.accountBindingSHA256,
                                                expectedIdentity: identity, keyID: receiptKeyID,
                                                publicKey: receiptPublicKey, nowEpochSeconds: clock())
        try await deliverAccepted(receipt: receipt, pending: pending, expected: expected,
                                  record: record, journal: journal,
                                  finish: { await transaction.finish() })
    }

    func deliverAccepted(receipt: CommerceAuthorityReceiptCandidateV1,
                         pending: PendingCommerceOperationCandidateV1,
                         expected: LocalStoreKitPurchaseExpectationR461,
                         record: CommerceOperationRecordR465, journal: KeychainCommerceJournalR465,
                         finish: @Sendable () async -> Void) async throws {
        let identity = CommerceAuthorityReceiptCandidateV1.Identity(
            environment: record.environment, bundleID: record.bundleID, transactionID: record.transactionID,
            originalTransactionID: record.originalTransactionID, productID: record.productID,
            quantity: record.quantity)
        let mutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: receipt, expectedOperationID: UUID(uuidString: pending.request.operationID)!,
            expectedRequestSHA256: pending.requestSHA256,
            expectedAccountBindingSHA256: expected.accountBindingSHA256,
            expectedTransaction: identity, expectedKeyID: receiptKeyID,
            publicKey: receiptPublicKey, nowEpochSeconds: clock(),
            contentByEntitlementID: contentByEntitlementID)
        try await ownershipCommit(mutation)
        try await journal.markGameDeliveryCompleted(transactionID: identity.transactionID,
                                                     receiptFingerprint: receipt.receiptFingerprint)
        await finish()
        try await journal.markFinished(transactionID: identity.transactionID)
    }

    /// Replays a locally cached, already-verified grant into the current game
    /// save after StoreKit confirms the transaction remains entitled. This is
    /// intentionally network-free and does not alter the journal's finished
    /// state or call StoreKit finish again.
    func replayFinishedGrant(receipt: CommerceAuthorityReceiptCandidateV1,
                             pending: PendingCommerceOperationCandidateV1,
                             expected: LocalStoreKitPurchaseExpectationR461,
                             record: CommerceOperationRecordR465) async throws {
        guard record.status == .finished, receipt.event == .grant,
              record.transactionID == expected.transactionID,
              record.originalTransactionID == expected.originalTransactionID,
              record.productID == expected.productID,
              record.quantity == expected.quantity,
              record.bundleID == expected.bundleID,
              record.environment == expected.environment else {
            throw CoreError.invalidCommand("finished transaction is not an eligible cached grant")
        }
        let identity = CommerceAuthorityReceiptCandidateV1.Identity(
            environment: record.environment, bundleID: record.bundleID, transactionID: record.transactionID,
            originalTransactionID: record.originalTransactionID, productID: record.productID,
            quantity: record.quantity)
        let mutation = try VerifiedCommerceOwnershipMutationR1.validate(
            receipt: receipt, expectedOperationID: UUID(uuidString: pending.request.operationID)!,
            expectedRequestSHA256: pending.requestSHA256,
            expectedAccountBindingSHA256: expected.accountBindingSHA256,
            expectedTransaction: identity, expectedKeyID: receiptKeyID,
            publicKey: receiptPublicKey, nowEpochSeconds: clock(),
            contentByEntitlementID: contentByEntitlementID)
        try await ownershipCommit(mutation)
    }

    func commitStoreKitRevocation(transactionID: String, proofFingerprint: String,
                                  revision: Int64) async throws -> UUID {
        let operationID = CommerceOperationRecordR465.stableOperationID(
            environment: "StoreKitRevocation", bundleID: Bundle.main.bundleIdentifier ?? "",
            transactionID: transactionID + "/" + proofFingerprint)
        let mutation = try VerifiedCommerceOwnershipMutationR1.verifiedStoreKitRevocation(
            transactionID: transactionID, proofFingerprint: proofFingerprint,
            authorityRevision: revision, operationID: operationID)
        try await ownershipCommit(mutation)
        return operationID
    }
}

protocol CommerceAccountBindingProviderR465: Sendable {
    func currentBinding() async throws -> CommerceAccountBindingR465
}

struct CommerceAccountBindingR465: Sendable {
    let accountBindingSHA256: String
    let accountIDSHA256: String
    let appAccountToken: UUID
}

enum CommercePurchasePresentationR465: Sendable, Equatable {
    case blocked([String]), pending, cancelled, delivered, awaitingApprovedAuthority, retryable(String), revoked, failed(String)
}

enum CommerceRestorePresentationR465: Sendable, Equatable {
    case blocked([String]), completed(restoredNonConsumables: Int, note: String), retryable(String)
}

/// HTTPS-only, bounded POST transport with redirects disabled. Endpoint and
/// credential are injected; this file contains no URL, token, or account value.
final class URLSessionPurchaseTransportR465: PurchaseAuthorityTransportR461, CommerceAuthorityByteTransportR465, @unchecked Sendable {
    private let endpoint: URL
    private let credential: any CommerceCredentialProviderR465
    private let session: URLSession

    init(configuration: CommerceApprovalConfigurationR465, credential: any CommerceCredentialProviderR465,
         sessionConfiguration: URLSessionConfiguration = .ephemeral,
         actualBundleID: String? = Bundle.main.bundleIdentifier) throws {
        guard configuration.validationReasons.isEmpty,
              actualBundleID == configuration.bundleID,
              let scheme = URLComponents(url: configuration.authorityURL, resolvingAgainstBaseURL: false)?.scheme,
              scheme.lowercased() == "https",
              configuration.authorityURL.path.count > 1 else {
            throw URLError(.appTransportSecurityRequiresSecureConnection)
        }
        self.endpoint = configuration.authorityURL
        self.credential = credential
        let delegate = NoRedirectSessionDelegateR465()
        self.session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
    }

    func exchange(_ requestBytes: Data) async throws -> Data {
        guard (1...70_000).contains(requestBytes.count) else { throw URLError(.dataLengthExceedsMaximum) }
        let token = try await credential.bearerToken()
        guard Self.isValidBearerToken(token) else {
            throw URLError(.userAuthenticationRequired)
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.httpBody = requestBytes
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              http.url?.standardized == endpoint.standardized,
              http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        data.reserveCapacity(16_384)
        for try await byte in stream {
            guard data.count < 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        return data
    }

    /// Validate the RFC 6750 b64token alphabet at the byte level. Swift
    /// `Character` treats CRLF as one extended grapheme cluster, so String
    /// contains checks can miss a header-injection sequence such as bad CRLF value.
    private static func isValidBearerToken(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        guard !bytes.isEmpty, bytes.count <= 8192 else { return false }
        func isTokenByte(_ byte: UInt8) -> Bool {
            (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) ||
            (byte >= 0x30 && byte <= 0x39) || [0x2D, 0x2E, 0x5F, 0x7E, 0x2B, 0x2F].contains(byte)
        }
        var hasTokenByte = false
        var paddingStarted = false
        for byte in bytes {
            if isTokenByte(byte) {
                guard !paddingStarted else { return false }
                hasTokenByte = true
            } else if byte == 0x3D {
                guard hasTokenByte else { return false }
                paddingStarted = true
            } else {
                return false
            }
        }
        return hasTokenByte
    }
}

protocol CommerceCredentialProviderR465: Sendable { func bearerToken() async throws -> String }
protocol CommerceAuthorityByteTransportR465: Sendable { func exchange(_ requestBytes: Data) async throws -> Data }

private final class NoRedirectSessionDelegateR465: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Device-only Keychain journal for verified StoreKit facts and exact retry
/// requests. Separate from the gameplay save and scoped per account binding.
protocol CommerceJournalBlobStoreR465: Sendable {
    func read() throws -> Data?
    func writeAtomically(_ data: Data) throws
}

actor KeychainCommerceJournalR465: PendingPurchaseOperationStoreR461, AuthorityObservationStoreR461 {
    private struct Envelope: Codable {
        let schemaVersion: Int
        var pending: [PendingPurchaseOperationR461]
        var candidatePending: [PendingCommerceOperationCandidateV1]
        var records: [CommerceOperationRecordR465]
        var observations: [AuthorityObservationR461]
        var candidateLedger: CommerceEntitlementLedgerCandidateV1?
        // Optional for forward-compatible journal reads from the previous R465 shape.
        var acceptedCandidateReceipts: [String: CommerceAuthorityReceiptCandidateV1]?
        var gameDeliveredReceiptFingerprints: [String: String]?
        var gameDeliveryRequiredFingerprints: [String: String]?
    }

    private let service: String
    private let account: String
    private let accountBindingSHA256: String
    private let storage: any CommerceJournalBlobStoreR465

    init(accountBindingSHA256: String, storage: (any CommerceJournalBlobStoreR465)? = nil) throws {
        guard accountBindingSHA256.utf8.count == 64,
              accountBindingSHA256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw CoreError.invalidCommand("invalid commerce account binding")
        }
        self.service = "com.witch-gathering.commerce.r465.\(accountBindingSHA256)"
        self.account = "operation-journal-v1"
        self.accountBindingSHA256 = accountBindingSHA256
        self.storage = try storage ?? KeychainCommerceBlobStoreR465(
            service: "com.witch-gathering.commerce.r465.\(accountBindingSHA256)", account: "operation-journal-v1")
    }

    func registerIfAbsent(_ pending: PendingPurchaseOperationR461) async throws {
        try pending.validate()
        var envelope = try load()
        if let existing = envelope.pending.first(where: { $0.request.operationID == pending.request.operationID }) {
            guard existing == pending else { throw CoreError.invalidCommand("operation UUID reused with different signed transaction") }
            return
        }
        guard envelope.pending.count < 512 else { throw CoreError.invalidCommand("commerce retry journal is full") }
        envelope.pending.append(pending)
        try save(envelope)
    }

    func registerCandidateIfAbsent(_ pending: PendingCommerceOperationCandidateV1) throws {
        try pending.validate()
        var envelope = try load()
        if let existing = envelope.candidatePending.first(where: { $0.request.operationID == pending.request.operationID }) {
            guard existing == pending else {
                throw CoreError.invalidCommand("candidate operation UUID reused with different request")
            }
            return
        }
        guard envelope.candidatePending.count < 512 else {
            throw CoreError.invalidCommand("commerce retry journal is full")
        }
        envelope.candidatePending.append(pending)
        try save(envelope)
    }

    func insertVerified(_ record: CommerceOperationRecordR465,
                        isCryptographicallyVerified: Bool = false) throws -> CommerceOperationRecordR465 {
        try record.validate()
        var envelope = try load()
        if let existing = envelope.records.first(where: { $0.transactionID == record.transactionID }) {
            if existing == record || existing.transactionFingerprint == record.transactionFingerprint { return existing }
            let sameImmutableIdentity = existing.environment == record.environment &&
                existing.bundleID == record.bundleID && existing.transactionID == record.transactionID &&
                existing.originalTransactionID == record.originalTransactionID &&
                existing.productID == record.productID && existing.quantity == record.quantity &&
                existing.kind == record.kind
            guard isCryptographicallyVerified, sameImmutableIdentity else {
                throw CoreError.invalidCommand("StoreKit transaction identity collision")
            }
            return existing
        }
        guard envelope.records.count < 512 else { throw CoreError.invalidCommand("commerce journal is full") }
        envelope.records.append(record)
        try save(envelope)
        return record
    }

    func load(accountBindingSHA256: String) async throws -> AuthorityObservationR461? {
        guard let observation = try load().observations.first(where: { $0.accountBindingSHA256 == accountBindingSHA256 }) else { return nil }
        return observation
    }

    func compareAndSave(_ observation: AuthorityObservationR461, expectedPreviousRevision: Int64?) async throws -> Bool {
        var envelope = try load()
        let current = envelope.observations.firstIndex(where: { $0.accountBindingSHA256 == observation.accountBindingSHA256 })
        if let current {
            guard envelope.observations[current].revision == expectedPreviousRevision else { return false }
            envelope.observations[current] = observation
        } else {
            guard expectedPreviousRevision == nil else { return false }
            envelope.observations.append(observation)
        }
        try save(envelope)
        return true
    }

    func markAuthorityRetry(transactionID: String, reason: String) throws {
        try transition(transactionID: transactionID, to: .authorityRetryRequired, reason: reason)
    }

    func markRevoked(transactionID: String, verifiedJWS: String) throws -> (proofFingerprint: String, authorityRevision: Int64) {
        var envelope = try load()
        guard let index = envelope.records.firstIndex(where: { $0.transactionID == transactionID }) else {
            throw CoreError.invalidCommand("unknown StoreKit transaction revocation")
        }
        let current = envelope.records[index].status
        let proof = SHA256.hash(data: Data(verifiedJWS.utf8)).map { String(format: "%02x", $0) }.joined()
        if current != .revoked && current != .revokedFinished && !CommerceLifecycleR465.permits(from: current, to: .revoked) {
            throw CoreError.invalidCommand("revocation conflicts with transaction lifecycle")
        }
        var ledger = try envelope.candidateLedger ?? CommerceEntitlementLedgerCandidateV1(
            accountBindingSHA256: accountBindingSHA256)
        try ledger.applyingVerifiedStoreKitRevocation(transactionID: transactionID, proofFingerprint: proof)
        envelope.records[index].status = .revoked
        envelope.records[index].lastFailureCode = "storekit-revocation"
        envelope.candidateLedger = ledger
        var required = envelope.gameDeliveryRequiredFingerprints ?? [:]
        required[transactionID] = proof
        envelope.gameDeliveryRequiredFingerprints = required
        envelope.gameDeliveredReceiptFingerprints?.removeValue(forKey: transactionID)
        try save(envelope)
        return (proof, ledger.revision)
    }

    func applyCandidateReceipt(_ receipt: CommerceAuthorityReceiptCandidateV1, recordID: String,
                               expectedOperationID: String,
                               requestSHA256: String, expectedAccountBindingSHA256: String,
                               expectedIdentity: CommerceAuthorityReceiptCandidateV1.Identity,
                               keyID: String, publicKey: Curve25519.Signing.PublicKey,
                               nowEpochSeconds: Int64) throws {
        var envelope = try load()
        guard expectedAccountBindingSHA256 == accountBindingSHA256,
              receipt.accountBindingSHA256 == accountBindingSHA256,
              let index = envelope.records.firstIndex(where: { $0.id == recordID }),
              envelope.records[index].transactionID == expectedIdentity.transactionID,
              receipt.operationID == expectedOperationID,
              let pending = envelope.candidatePending.first(where: { $0.request.operationID == expectedOperationID }),
              pending.requestSHA256 == requestSHA256 else {
            throw CoreError.invalidCommand("receipt has no matching durable transaction request")
        }
        var ledger = try envelope.candidateLedger ?? CommerceEntitlementLedgerCandidateV1(
            accountBindingSHA256: receipt.accountBindingSHA256)
        let applied = try ledger.applying(receipt, expectedOperationID: UUID(uuidString: expectedOperationID)!,
                                          expectedRequestSHA256: requestSHA256,
                                          expectedTransaction: expectedIdentity, expectedKeyID: keyID,
                                          publicKey: publicKey, nowEpochSeconds: nowEpochSeconds)
        if applied {
            let next: CommerceOperationStatusR465 = receipt.event == .revoke ? .revoked : .deliveredAwaitingFinish
            guard CommerceLifecycleR465.permits(from: envelope.records[index].status, to: next) else {
                throw CoreError.invalidCommand("receipt conflicts with transaction lifecycle")
            }
            envelope.records[index].status = next
            envelope.records[index].lastFailureCode = nil
            envelope.candidateLedger = ledger
            var receipts = envelope.acceptedCandidateReceipts ?? [:]
            receipts[receipt.transaction.transactionID] = receipt
            envelope.acceptedCandidateReceipts = receipts
            var required = envelope.gameDeliveryRequiredFingerprints ?? [:]
            required[receipt.transaction.transactionID] = receipt.receiptFingerprint
            envelope.gameDeliveryRequiredFingerprints = required
            envelope.gameDeliveredReceiptFingerprints?.removeValue(forKey: receipt.transaction.transactionID)
            // A single Keychain item update atomically commits both the grant
            // and the transaction status that controls StoreKit finish.
            try save(envelope)
        } else {
            let required: CommerceOperationStatusR465 = receipt.event == .revoke ? .revoked : .deliveredAwaitingFinish
            guard envelope.records[index].status == required,
                  envelope.candidateLedger?.appliedOperationFingerprints[receipt.operationID + ":" + receipt.event.rawValue]
                    == receipt.receiptFingerprint else {
                throw CoreError.invalidCommand("idempotent replay lacks committed ledger state")
            }
            var receipts = envelope.acceptedCandidateReceipts ?? [:]
            if let prior = receipts[receipt.transaction.transactionID], prior != receipt {
                throw CoreError.invalidCommand("accepted receipt conflicts with replay")
            }
            if receipts[receipt.transaction.transactionID] == nil {
                receipts[receipt.transaction.transactionID] = receipt
                envelope.acceptedCandidateReceipts = receipts
                try save(envelope)
            }
        }
    }

    func acceptedCandidateReceipt(transactionID: String) throws -> CommerceAuthorityReceiptCandidateV1? {
        try load().acceptedCandidateReceipts?[transactionID]
    }

    func acceptedCandidateDelivery(transactionID: String) throws
        -> (receipt: CommerceAuthorityReceiptCandidateV1, pending: PendingCommerceOperationCandidateV1)? {
        let envelope = try load()
        guard let receipt = envelope.acceptedCandidateReceipts?[transactionID],
              let pending = envelope.candidatePending.first(where: { $0.request.operationID == receipt.operationID }),
              pending.requestSHA256 == receipt.requestSHA256 else { return nil }
        return (receipt, pending)
    }

    /// Persisted Apple proofs are replayed into the game save before startup
    /// considers any StoreKit finish operation. Server revocations already
    /// accepted by the candidate authority are handled through their receipt.
    func pendingStoreKitRevocations() throws -> [(transactionID: String, proofFingerprint: String)] {
        let envelope = try load()
        let required = envelope.gameDeliveryRequiredFingerprints ?? [:]
        return envelope.records.compactMap { record in
            guard record.status == .revoked,
                  let proof = required[record.transactionID] else { return nil }
            if let receipt = envelope.acceptedCandidateReceipts?[record.transactionID],
               receipt.event == .revoke, receipt.receiptFingerprint == proof { return nil }
            return (record.transactionID, proof)
        }
    }

    func markGameDeliveryCompleted(transactionID: String, receiptFingerprint: String) throws {
        var envelope = try load()
        var delivered = envelope.gameDeliveredReceiptFingerprints ?? [:]
        guard let record = envelope.records.first(where: { $0.transactionID == transactionID }) else {
            throw CoreError.invalidCommand("game delivery has no verified transaction")
        }
        let expectedFingerprint = envelope.gameDeliveryRequiredFingerprints?[transactionID]
            ?? ((record.status == .revoked || record.status == .revokedFinished)
                ? envelope.candidateLedger?.tombstones.first(where: { $0.transactionID == transactionID })?.receiptFingerprint
                : envelope.acceptedCandidateReceipts?[transactionID]?.receiptFingerprint)
        guard expectedFingerprint == receiptFingerprint else {
            throw CoreError.invalidCommand("game delivery receipt does not match accepted transaction state")
        }
        if delivered[transactionID] == receiptFingerprint { return }
        guard record.status == .deliveredAwaitingFinish || record.status == .revoked else {
            throw CoreError.invalidCommand("game delivery cannot complete before verified authority")
        }
        delivered[transactionID] = receiptFingerprint
        envelope.gameDeliveredReceiptFingerprints = delivered
        try save(envelope)
    }

    func boundAccountBindingSHA256() -> String { accountBindingSHA256 }

    func markFinished(transactionID: String) throws {
        let envelope = try load()
        guard let record = envelope.records.first(where: { $0.transactionID == transactionID }) else {
            throw CoreError.invalidCommand("unknown transaction finish acknowledgement")
        }
        if record.status == .finished || record.status == .revokedFinished { return }
        let target: CommerceOperationStatusR465 = record.status == .revoked ? .revokedFinished : .finished
        try transition(transactionID: transactionID, to: target, reason: nil)
    }

    func pendingFinishTransactionIDs() throws -> Set<String> {
        let envelope = try load()
        let delivered = envelope.gameDeliveredReceiptFingerprints ?? [:]
        return Set(envelope.records.filter { record in
            guard record.status == .deliveredAwaitingFinish || record.status == .revoked,
                  let deliveredFingerprint = delivered[record.transactionID] else { return false }
            let acceptedFingerprint = envelope.gameDeliveryRequiredFingerprints?[record.transactionID]
                ?? ((record.status == .revoked)
                    ? envelope.candidateLedger?.tombstones.first(where: { $0.transactionID == record.transactionID })?.receiptFingerprint
                    : envelope.acceptedCandidateReceipts?[record.transactionID]?.receiptFingerprint)
            return deliveredFingerprint == acceptedFingerprint
        }
            .map(\.transactionID))
    }

    func hasActiveEntitlement(_ entitlementID: String, nowEpochSeconds: Int64) throws -> Bool {
        guard let ledger = try load().candidateLedger else { return false }
        return ledger.entries.contains {
            $0.id.hasSuffix("/" + entitlementID) && ($0.expiresAtEpochSeconds.map { $0 > nowEpochSeconds } ?? true)
        }
    }

    func ownershipProjection(nowEpochSeconds: Int64) throws -> CommerceOwnershipReadModelCandidateV1 {
        CommerceOwnershipReadModelCandidateV1(ledger: try load().candidateLedger,
                                              nowEpochSeconds: nowEpochSeconds)
    }

    private func transition(transactionID: String, to next: CommerceOperationStatusR465, reason: String?) throws {
        var envelope = try load()
        guard let index = envelope.records.firstIndex(where: { $0.transactionID == transactionID }) else {
            throw CoreError.invalidCommand("unknown StoreKit transaction")
        }
        let current = envelope.records[index].status
        guard CommerceLifecycleR465.permits(from: current, to: next) else {
            if current == next { return }
            throw CoreError.invalidCommand("invalid commerce lifecycle transition")
        }
        envelope.records[index].status = next
        envelope.records[index].lastFailureCode = reason
        try save(envelope)
    }

    private func load() throws -> Envelope {
        guard let data = try storage.read() else {
            return Envelope(schemaVersion: 1, pending: [], candidatePending: [], records: [], observations: [],
                            candidateLedger: nil, acceptedCandidateReceipts: nil, gameDeliveredReceiptFingerprints: nil,
                            gameDeliveryRequiredFingerprints: nil)
        }
        guard data.count <= 16 * 1_048_576 else {
            throw CoreError.invalidCommand("commerce Keychain journal unavailable")
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw CoreError.invalidCommand("unsupported commerce journal schema") }
        for item in envelope.pending { try item.validate() }
        for item in envelope.candidatePending { try item.validate() }
        for item in envelope.records { try item.validate() }
        return envelope
    }

    private func save(_ envelope: Envelope) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= 16 * 1_048_576 else { throw CoreError.invalidCommand("commerce journal exceeds size limit") }
        try storage.writeAtomically(data)
    }
}

private struct KeychainCommerceBlobStoreR465: CommerceJournalBlobStoreR465 {
    private let service: String
    private let account: String

    init(service: String, account: String) { self.service = service; self.account = account }

    func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CoreError.invalidCommand("commerce Keychain read failed")
        }
        return data
    }

    func writeAtomically(_ data: Data) throws {
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
                throw CoreError.invalidCommand("commerce Keychain insert failed")
            }
        } else if status != errSecSuccess {
            throw CoreError.invalidCommand("commerce Keychain update failed")
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
