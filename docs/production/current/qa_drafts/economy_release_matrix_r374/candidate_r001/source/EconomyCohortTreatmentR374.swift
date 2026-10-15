import CryptoKit
import Foundation
@testable import WitchGameCore

/// Test-target-only cohort input adapter. It is intentionally not part of WitchGameCore
/// and never writes StoreKit/purchase entitlements. Ticket credits are synthetic inputs
/// applied only to a fresh isolated snapshot before/inside the QA run.
struct EconomyCohortTreatmentR374 {
    enum Cohort: String, CaseIterable {
        case freeNoAd = "free_no_ad"
        case rewardedAd = "rewarded_ad_simulated"
        case adSkip = "ad_skip_simulated"
        case starterTrial = "starter_ticket_candidate"
        case recurring30 = "value30_ticket_candidate"
        case highCollector = "ticket200_candidate"
        case cosmeticsOnly = "cosmetics_only_candidate"
        case smallBundle = "ticket10_candidate"
        case outfitOnly = "outfit_only_blocked"
        case furnitureOnly = "furniture_only_blocked"
        case starterChoiceVariant = "starter_plus_choice_blocked"
    }

    struct Product: Decodable {
        let id: String
        let priceJpy: Int
        let priceStatus: String
        let tickets: Int
        let statModifierBP: Int
        let cadenceDays: Int
        let phase: String
        let scope: String?
        enum CodingKeys: String, CodingKey { case id, tickets, phase, scope; case statModifierBP = "stat_modifier_bp"; case priceJpy = "price_jpy"; case priceStatus = "price_status"; case cadenceDays = "cadence_days" }
    }
    struct Inputs: Decodable {
        let schema: String
        let authorityStatus: String
        let products: [Product]
        let source: SourcePins
        struct SourcePins: Decodable { let path: String; let sha256: String; let matrixPath: String; let matrixSHA256: String }
    }
    struct GrantReceipt: Encodable, Sendable {
        let schema: String
        let origin: String
        let cohort: String
        let productID: String
        let draftPriceJPY: Int
        let priceStatus: String
        let virtualDay: Int
        let syntheticTicketDelta: Int
        let ticketPaidMockBefore: Int
        let ticketPaidMockAfter: Int
        let transactionStatus: String
        let storeKitInvoked: Bool
        let networkInvoked: Bool
    }
    struct CosmeticScenarioReceipt: Encodable, Sendable {
        let schema: String
        let origin: String
        let cohort: String
        let productID: String
        let draftPriceJPY: Int
        let priceStatus: String
        let virtualDay: Int
        let ticketDelta: Int
        let statModifierBP: Int
        let transactionStatus: String
        let gameSnapshotEntitlementApplied: Bool
        let appearanceMappingStatus: String
        let storeKitInvoked: Bool
        let networkInvoked: Bool
    }
    enum AdapterError: Error, Equatable {
        case invalidInputFile
        case inputDigestMismatch
        case productNotCandidate(String)
        case productNotYetEligible(String)
        case contentMappingUnavailable(String)
        case choiceVariantUnderspecified
        case duplicateScheduledGrant(String)
        case invalidDay(Int)
    }

    let inputs: Inputs
    private let productByID: [String: Product]
    private(set) var grantDaysByProduct: [String: [Int]] = [:]
    private(set) var firstEligibleDay: Int?
    private var pendingGrants: [String: Int] = [:]

    static func load(inputsURL: URL, expectedSHA256: String) throws -> Self {
        guard inputsURL.isFileURL, inputsURL.path.hasPrefix("/"), inputsURL.pathExtension == "json" else {
            throw AdapterError.invalidInputFile
        }
        let data = try Data(contentsOf: inputsURL)
        guard sha256(data) == expectedSHA256 else { throw AdapterError.inputDigestMismatch }
        let inputs = try JSONDecoder().decode(Inputs.self, from: data)
        guard inputs.schema == "r195-unapproved-product-inputs-v1",
              inputs.authorityStatus == "PROPOSED_CATALOG_NOT_APPROVED",
              inputs.source.sha256 == "11a4fa5a9984a32683f0770bd2cf228c51f3c28530abf01abecf8fe9b82e795e",
              inputs.source.matrixSHA256 == "86ac5189196a050461ef909e77e1bd36d54cea774b89b2298ecf73f2ddaf54f3",
              inputs.products.allSatisfy({ $0.priceStatus == "HYPOTHETICAL_NOT_APP_STORE_REGISTERED" }) else {
            throw AdapterError.invalidInputFile
        }
        let ids = inputs.products.map(\.id)
        guard Set(ids).count == ids.count else { throw AdapterError.invalidInputFile }
        let map = Dictionary(uniqueKeysWithValues: inputs.products.map { ($0.id, $0) })
        return Self(inputs: inputs, productByID: map)
    }

    /// The same post-onboarding eligibility gate is used for all ticket products.
    /// This only schedules candidate inputs; it does not claim a purchase occurred.
    mutating func dueProductIDs(cohort: Cohort, day: Int, gachaUnlocked: Bool) throws -> [String] {
        guard day >= 1 else { throw AdapterError.invalidDay(day) }
        guard gachaUnlocked else { return [] }
        if firstEligibleDay == nil { firstEligibleDay = day }
        switch cohort {
        case .freeNoAd, .rewardedAd, .adSkip, .outfitOnly, .furnitureOnly:
            return []
        case .starterTrial:
            return try scheduleOnce("STARTER", day: day, eligibleDay: firstEligibleDay!)
        case .cosmeticsOnly:
            return [] // Non-ticket metadata scenario is scheduled separately from the gacha gate.
        case .smallBundle:
            return try scheduleOnce("TICKET10", day: day, eligibleDay: firstEligibleDay!)
        case .recurring30:
            return try scheduleRepeating("VALUE30", interval: 30, day: day, eligibleDay: firstEligibleDay!)
        case .highCollector:
            return try scheduleOnce("TICKET200", day: day, eligibleDay: firstEligibleDay!)
        case .starterChoiceVariant:
            throw AdapterError.choiceVariantUnderspecified
        }
    }

    /// A strictly test-only grant seam. Call only against the cohort's isolated run
    /// snapshot. It changes only ticket_paid_mock; callers must append the returned
    /// receipt to a separate run artifact. It does not touch purchase/StoreKit fields.
    mutating func applySyntheticTicketGrant(productID: String, cohort: Cohort, virtualDay: Int,
                                            to snapshot: inout GameSnapshot) throws -> GrantReceipt {
        guard virtualDay >= 1 else { throw AdapterError.invalidDay(virtualDay) }
        guard pendingGrants[productID] == virtualDay else { throw AdapterError.productNotYetEligible(productID) }
        guard let product = productByID[productID],
              ["STARTER", "VALUE30", "TICKET10", "TICKET50", "TICKET200"].contains(productID),
              product.tickets > 0 else { throw AdapterError.productNotCandidate(productID) }
        let expectedID: String
        switch cohort {
        case .starterTrial: expectedID = "STARTER"
        case .smallBundle: expectedID = "TICKET10"
        case .recurring30: expectedID = "VALUE30"
        case .highCollector: expectedID = "TICKET200"
        default: throw AdapterError.productNotYetEligible(productID)
        }
        guard productID == expectedID else { throw AdapterError.productNotCandidate(productID) }
        let before = snapshot.currency["ticket_paid_mock", default: 0]
        let (after, overflow) = before.addingReportingOverflow(product.tickets)
        guard !overflow, before >= 0 else { throw AdapterError.productNotCandidate(productID) }
        snapshot.currency["ticket_paid_mock"] = after
        grantDaysByProduct[productID, default: []].append(virtualDay)
        pendingGrants.removeValue(forKey: productID)
        return GrantReceipt(schema: "r374-synthetic-grant-v1", origin: "UNAPPROVED_TEST_ONLY_SYNTHETIC_INPUT",
                            cohort: cohort.rawValue, productID: product.id, draftPriceJPY: product.priceJpy,
                            priceStatus: product.priceStatus, virtualDay: virtualDay,
                            syntheticTicketDelta: product.tickets, ticketPaidMockBefore: before,
                            ticketPaidMockAfter: after, transactionStatus: "NO_TRANSACTION_CREATED",
                            storeKitInvoked: false, networkInvoked: false)
    }

    /// Fail closed for product concepts that have no exact mapping to current R098 assets.
    func runtimeContentStatus(for cohort: Cohort, catalog: GameCatalog) -> String {
        switch cohort {
        case .cosmeticsOnly:
            return "CANDIDATE_QA_METADATA_ONLY_NO_R098_APPEARANCE_ENTITLEMENT"
        case .outfitOnly:
            let ids = inputs.products.filter { $0.id.hasPrefix("OUT_") }.map(\.id)
            return ids.contains(where: { sku in catalog.appearances.contains(where: { $0.id == sku }) })
                ? "PARTIAL_MAPPING_REQUIRES_PER_ACTOR_ASSET_PROOF" : "BLOCKED_NO_EXACT_R098_APPEARANCE_ID_MAPPING"
        case .furnitureOnly:
            let ids = inputs.products.filter { $0.id.hasPrefix("FUR_") }.map(\.id)
            return ids.contains(where: catalog.furnitureIDs.contains)
                ? "PARTIAL_MAPPING_REQUIRES_ASSET_AND_LAYOUT_PROOF" : "BLOCKED_NO_EXACT_R098_FURNITURE_ID_MAPPING"
        default:
            return "NOT_A_COSMETIC_OR_FURNITURE_COHORT"
        }
    }

    /// Schedule the cosmetic-only comparison independently of the ticket/gacha gate.
    /// This creates no game entitlement; its receipt is a test-side scenario record.
    mutating func dueCosmeticMetadataScenario(day: Int) throws -> String? {
        guard day >= 1 else { throw AdapterError.invalidDay(day) }
        guard let id = try scheduleOnce("OUT_C_WITCH_MOON_01", day: day, eligibleDay: 1).first else { return nil }
        return id
    }

    /// Records an unapproved cosmetics-only scenario without mutating GameSnapshot.
    /// R098 has no matching appearance ID, so this is not an entitlement/render test.
    mutating func applySyntheticCosmeticScenario(productID: String, cohort: Cohort, virtualDay: Int) throws -> CosmeticScenarioReceipt {
        guard cohort == .cosmeticsOnly, virtualDay >= 1, pendingGrants[productID] == virtualDay else {
            throw AdapterError.productNotYetEligible(productID)
        }
        guard let product = productByID[productID], productID == "OUT_C_WITCH_MOON_01",
              product.tickets == 0, product.statModifierBP == 0,
              product.priceStatus == "HYPOTHETICAL_NOT_APP_STORE_REGISTERED" else {
            throw AdapterError.productNotCandidate(productID)
        }
        guard (grantDaysByProduct[productID] ?? []).isEmpty else { throw AdapterError.duplicateScheduledGrant(productID) }
        grantDaysByProduct[productID, default: []].append(virtualDay)
        pendingGrants.removeValue(forKey: productID)
        return CosmeticScenarioReceipt(schema: "r374-cosmetic-scenario-v1", origin: "UNAPPROVED_QA_SCENARIO_ONLY",
            cohort: cohort.rawValue, productID: product.id, draftPriceJPY: product.priceJpy, priceStatus: product.priceStatus,
            virtualDay: virtualDay, ticketDelta: product.tickets, statModifierBP: product.statModifierBP,
            transactionStatus: "NO_TRANSACTION_CREATED", gameSnapshotEntitlementApplied: false,
            appearanceMappingStatus: "NO_R098_APPEARANCE_MAPPING", storeKitInvoked: false, networkInvoked: false)
    }

    private mutating func scheduleOnce(_ id: String, day: Int, eligibleDay: Int) throws -> [String] {
        guard day >= eligibleDay else { return [] }
        if !(grantDaysByProduct[id] ?? []).isEmpty { return [] }
        guard productByID[id] != nil else { throw AdapterError.productNotCandidate(id) }
        pendingGrants[id] = day
        return [id]
    }

    private mutating func scheduleRepeating(_ id: String, interval: Int, day: Int, eligibleDay: Int) throws -> [String] {
        guard let product = productByID[id], product.cadenceDays == interval else { throw AdapterError.productNotCandidate(id) }
        guard day >= eligibleDay, day - eligibleDay == ((day - eligibleDay) / interval) * interval else { return [] }
        let previous = grantDaysByProduct[id, default: []]
        guard !previous.contains(day), previous.last.map({ day - $0 >= interval }) ?? true else { return [] }
        pendingGrants[id] = day
        return [id]
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
