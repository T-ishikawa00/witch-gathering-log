import CryptoKit
import Foundation

/// Explicit projection switch. Default is the existing legacy formula; R230 never opts in implicitly.
public enum EnhancementProjectionPolicyR230: String, Sendable {
    case legacy = "legacy-current-projection"
    case r2SlotBudgetCandidate = "r2-slot-budget-growth-candidate-r230-v1"
}

/// UNAPPROVED candidate: R2 slot budgets supply enhancement growth only; level zero remains neutral.
public enum GearEnhancementGrowthR230 {
    public static let profileID = "gear-enhancement-r230-r2-slot-growth-v1"
    public static let profileVersion = 1
    public static let formulaID = "floor(slotBudget * (100 + 2*refinement) * 3*enhancement / 10000)"
    public static let canonicalManifest = "{\"formulaID\":\"floor(slotBudget*(100+2*refinement)*3*enhancement/10000)\",\"profileID\":\"gear-enhancement-r230-r2-slot-growth-v1\",\"profileVersion\":1,\"slotBudgets\":{\"amulet\":{\"attack\":5,\"defense\":0,\"hp\":25},\"body\":{\"attack\":0,\"defense\":10,\"hp\":80},\"feet\":{\"attack\":0,\"defense\":8,\"hp\":40},\"hands\":{\"attack\":4,\"defense\":5,\"hp\":0},\"ring\":{\"attack\":5,\"defense\":2,\"hp\":0},\"weapon\":{\"attack\":14,\"defense\":0,\"hp\":0}}}"
    public static let policySHA256 = SHA256.hash(data: Data(canonicalManifest.utf8)).map { String(format: "%02x", $0) }.joined()

    public struct Deltas: Equatable, Sendable {
        public let attack: Int
        public let hp: Int
        public let defense: Int
        public init(attack: Int, hp: Int, defense: Int) { self.attack = attack; self.hp = hp; self.defense = defense }
    }

    private static let budgets: [String: Deltas] = [
        "weapon": .init(attack: 14, hp: 0, defense: 0),
        "body": .init(attack: 0, hp: 80, defense: 10),
        "hands": .init(attack: 4, hp: 0, defense: 5),
        "feet": .init(attack: 0, hp: 40, defense: 8),
        "amulet": .init(attack: 5, hp: 25, defense: 0),
        "ring": .init(attack: 5, hp: 0, defense: 2)
    ]

    /// Reject invalid persisted enhancement data on the opt-in combat/UI projection paths.
    /// The legacy profile never calls this validator and remains unchanged.
    public static func validatePersistedEnhancement(_ item: GearInstance, in catalog: GameCatalog) throws {
        guard let definition = catalog.gear.first(where: { $0.id == item.definitionID }),
              delta(slot: definition.slot, enhancement: item.enhancement, refinement: item.refinement) != nil else {
            throw CoreError.invalidCommand("R230 candidate cannot project invalid gear definition/slot/enhancement/refinement")
        }
    }

    /// `hand` is a real catalog alias for the same familiar-hand budget as `hands`.
    public static func delta(slot: String, enhancement: Int, refinement: Int) -> Deltas? {
        guard (0...10).contains(enhancement), refinement >= 0 else { return nil }
        guard let budget = budgets[slot] ?? (slot == "hand" ? budgets["hands"] : nil) else { return nil }
        let (refineComponent, componentOverflow) = refinement.multipliedReportingOverflow(by: 2)
        guard !componentOverflow else { return nil }
        let (refineFactor, refineOverflow) = 100.addingReportingOverflow(refineComponent)
        guard !refineOverflow else { return nil }
        func scaled(_ amount: Int) -> Int? {
            let (factor, factorOverflow) = refineFactor.multipliedReportingOverflow(by: enhancement * 3)
            guard !factorOverflow else { return nil }
            let (product, productOverflow) = amount.multipliedReportingOverflow(by: factor)
            guard !productOverflow else { return nil }
            return product / 10_000
        }
        guard let attack = scaled(budget.attack), let hp = scaled(budget.hp), let defense = scaled(budget.defense) else { return nil }
        return Deltas(attack: attack, hp: hp, defense: defense)
    }
}

