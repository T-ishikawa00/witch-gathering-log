import Foundation
import CryptoKit

/// Product and endpoint facts are deliberately supplied by an approved build
/// configuration. There is no usable production default in this package.
public struct CommerceApprovalConfigurationR465: Sendable, Equatable {
    public let approvalID: String
    public let bundleID: String
    public let productIDs: Set<String>
    public let authorityURL: URL
    public let authorityContractVersion: Int
    public let accountBindingConfigured: Bool
    public let humanApproved: Bool
    public let pricePresentationApproved: Bool

    public init(approvalID: String, bundleID: String, productIDs: Set<String>, authorityURL: URL,
                authorityContractVersion: Int, accountBindingConfigured: Bool, humanApproved: Bool,
                pricePresentationApproved: Bool = false) {
        self.approvalID = approvalID
        self.bundleID = bundleID
        self.productIDs = productIDs
        self.authorityURL = authorityURL
        self.authorityContractVersion = authorityContractVersion
        self.accountBindingConfigured = accountBindingConfigured
        self.humanApproved = humanApproved
        self.pricePresentationApproved = pricePresentationApproved
    }

    public var validationReasons: [CommerceGateReasonR465] {
        var reasons: [CommerceGateReasonR465] = []
        if !humanApproved { reasons.append(.humanApprovalMissing) }
        if !pricePresentationApproved { reasons.append(.pricePresentationMissing) }
        if approvalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reasons.append(.approvalIdentityMissing) }
        if bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reasons.append(.bundleIdentityMissing) }
        if productIDs.isEmpty || productIDs.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            reasons.append(.productCatalogMissing)
        }
        let endpointIsApproved = URLComponents(url: authorityURL, resolvingAgainstBaseURL: false).map { components in
            components.scheme?.lowercased() == "https" &&
            components.host.map { !$0.isEmpty } == true &&
            components.path.hasPrefix("/") && components.path.count > 1 &&
            components.user == nil && components.password == nil &&
            components.query == nil && components.fragment == nil
        } ?? false
        if !endpointIsApproved {
            reasons.append(.authorityEndpointNotApproved)
        }
        if authorityContractVersion != 2 { reasons.append(.authorityContractNotApproved) }
        if !accountBindingConfigured { reasons.append(.accountBindingUnavailable) }
        return reasons
    }
}

public enum CommerceGateReasonR465: String, Codable, Sendable, Equatable, Hashable {
    case humanApprovalMissing
    case pricePresentationMissing
    case approvalIdentityMissing
    case bundleIdentityMissing
    case productCatalogMissing
    case authorityEndpointNotApproved
    case authorityContractNotApproved
    case accountBindingUnavailable

    public var userMessage: String {
        switch self {
        case .humanApprovalMissing: return "正式な販売承認がありません"
        case .pricePresentationMissing: return "価格表示条件が未承認です"
        case .approvalIdentityMissing: return "承認記録がありません"
        case .bundleIdentityMissing: return "アプリ識別情報が未設定です"
        case .productCatalogMissing: return "商品情報が未承認です"
        case .authorityEndpointNotApproved: return "購入確認先が未承認です"
        case .authorityContractNotApproved: return "購入確認契約が未承認です"
        case .accountBindingUnavailable: return "アカウント連携が未設定です"
        }
    }
}

public enum CommerceProductAvailabilityR465: Sendable, Equatable {
    case preparationOnly(reason: String)
    case unavailable
    case available(displayPrice: String, productID: String)
}

public enum CommerceOperationStatusR465: String, Codable, Sendable, Equatable {
    case awaitingStoreKit
    case userCancelled
    case storePending
    case verifiedAwaitingAuthority
    case authorityRetryRequired
    case deliveredAwaitingFinish
    case finished
    case revokedFinished
    case rejected
    case revoked
    case restoredNonConsumable
}

public enum CommerceOperationKindR465: String, Codable, Sendable, Equatable {
    case consumable
    case nonConsumable
    case subscription
}

public struct CommerceOperationRecordR465: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let environment: String
    public let bundleID: String
    public let transactionID: String
    public let originalTransactionID: String
    public let productID: String
    public let quantity: Int
    public let kind: CommerceOperationKindR465
    public var status: CommerceOperationStatusR465
    public let signedTransactionJWS: String
    public let transactionFingerprint: String
    public var lastFailureCode: String?

    public init(id: UUID, environment: String, bundleID: String, transactionID: String,
                originalTransactionID: String, productID: String, quantity: Int,
                kind: CommerceOperationKindR465, status: CommerceOperationStatusR465,
                signedTransactionJWS: String) throws {
        guard !environment.isEmpty, !bundleID.isEmpty, !transactionID.isEmpty,
              !originalTransactionID.isEmpty, !productID.isEmpty, quantity > 0,
              signedTransactionJWS.utf8.count <= 65_536, signedTransactionJWS.contains(".") else {
            throw CoreError.invalidCommand("invalid commerce transaction record")
        }
        self.id = id.uuidString.lowercased()
        self.environment = environment
        self.bundleID = bundleID
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.productID = productID
        self.quantity = quantity
        self.kind = kind
        self.status = status
        self.signedTransactionJWS = signedTransactionJWS
        self.transactionFingerprint = Self.sha256(Data(signedTransactionJWS.utf8))
    }

    public func validate() throws {
        guard let uuid = UUID(uuidString: id), id == uuid.uuidString.lowercased(),
              !environment.isEmpty, !bundleID.isEmpty, !transactionID.isEmpty,
              !originalTransactionID.isEmpty, !productID.isEmpty, quantity > 0,
              signedTransactionJWS.utf8.count <= 65_536,
              Self.sha256(Data(signedTransactionJWS.utf8)) == transactionFingerprint else {
            throw CoreError.invalidCommand("commerce journal record identity/fingerprint mismatch")
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func stableOperationID(environment: String, bundleID: String, transactionID: String) -> UUID {
        let digest = SHA256.hash(data: Data([environment, bundleID, transactionID].joined(separator: "/").utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

public enum CommerceLifecycleR465 {
    /// Strict state transitions prevent a cancelled/pending/refunded operation
    /// from becoming a local entitlement by UI interpretation.
    public static func permits(from: CommerceOperationStatusR465, to: CommerceOperationStatusR465) -> Bool {
        switch (from, to) {
        case (.awaitingStoreKit, .userCancelled), (.awaitingStoreKit, .storePending),
             (.awaitingStoreKit, .verifiedAwaitingAuthority),
             (.storePending, .verifiedAwaitingAuthority), (.storePending, .userCancelled),
             (.verifiedAwaitingAuthority, .authorityRetryRequired),
             (.verifiedAwaitingAuthority, .deliveredAwaitingFinish),
             (.authorityRetryRequired, .authorityRetryRequired),
             (.authorityRetryRequired, .deliveredAwaitingFinish),
             (.deliveredAwaitingFinish, .finished),
             (.verifiedAwaitingAuthority, .revoked), (.authorityRetryRequired, .revoked),
             (.deliveredAwaitingFinish, .revoked), (.finished, .revoked),
             (.revoked, .revokedFinished),
             (.awaitingStoreKit, .rejected), (.verifiedAwaitingAuthority, .rejected),
             (.authorityRetryRequired, .rejected), (.deliveredAwaitingFinish, .rejected): return true
        case (.awaitingStoreKit, .awaitingStoreKit), (.storePending, .storePending),
             (.verifiedAwaitingAuthority, .verifiedAwaitingAuthority),
             (.deliveredAwaitingFinish, .deliveredAwaitingFinish), (.finished, .finished),
             (.revoked, .revoked), (.revokedFinished, .revokedFinished),
             (.rejected, .rejected), (.userCancelled, .userCancelled): return true
        default: return false
        }
    }

    /// Restore must never replay a consumable purchase as a fresh grant.
    public static func canRestore(_ kind: CommerceOperationKindR465) -> Bool {
        kind == .nonConsumable || kind == .subscription
    }
}
