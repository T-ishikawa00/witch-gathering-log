import Foundation

/// Copy-only presentation guidance. It reads the existing snapshot and catalog;
/// it does not mutate combat, progression, or save state.
enum DefeatGuidanceR229 {
    static func message(state: GameSnapshot, catalog: GameCatalog?) -> String {
        guard let catalog else {
            return "あと一歩。手持ちの装備を見直し、素材を集めて仲間を育てよう。"
        }

        let pendingResearch = catalog.research.filter {
            !state.completedResearchIDs.contains($0.id)
        }
        let unlockedResearch = pendingResearch.filter { research in
            guard let gateID = catalog.recipes.first(where: { $0.id == research.id })?.gateID,
                  gateID != "G_START" else { return true }
            guard let encounterID = encounterID(for: gateID) else { return false }
            return state.completedEncounterIDs.contains(encounterID)
        }

        if let available = unlockedResearch.first {
            let canAfford = available.cost.allSatisfy {
                state.materials[$0.key, default: 0] >= $0.value
            }
            if canAfford {
                return "あと一歩。手持ちの装備を見直し、素材を集めて仲間を育てよう。採集帳の「暮らしと冒険の研究」も確認できます。"
            }
            return "あと一歩。手持ちの装備を見直し、必要素材を集めて仲間を育てよう。研究は採集帳の「暮らしと冒険の研究」で確認できます。"
        }

        for research in pendingResearch {
            guard let gateID = catalog.recipes.first(where: { $0.id == research.id })?.gateID,
                  let encounterID = encounterID(for: gateID),
                  !state.completedEncounterIDs.contains(encounterID),
                  let enemy = catalog.enemies.first(where: { $0.id == encounterID }) else { continue }
            return "あと一歩。手持ちの装備を見直し、素材を集めて仲間を育てよう。研究は「\(enemy.name)」の討伐後に採集帳の「暮らしと冒険の研究」で確認できます。"
        }

        return "あと一歩。手持ちの装備を見直し、素材を集めて仲間を育てよう。"
    }

    private static func encounterID(for gateID: String) -> String? {
        let parts = gateID.split(separator: "_")
        guard parts.count == 3, parts[0] == "G" else { return nil }
        return "B_\(parts[1])_\(parts[2])"
    }
}
