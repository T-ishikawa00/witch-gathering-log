import Foundation

/// Isolated visual-QA scenario only. This never mutates a catalog, save, or
/// production encounter; it raises only the cloned target HP and caps runtime.
public enum SyntheticPartyDash2PreviewR043 {
    public static let encounterID = "E_R01_01"
    public static let enemyHPMultiplier = 6
    public static let maxDurationMs = 12_000
    public static let deterministicSeed: UInt64 = 1_018
    public static let minimumTailAfterDash2Ms = 1_000

    public static func run(engine: GameEngine, seed: UInt64, snapshot: GameSnapshot? = nil) async throws -> CombatResult {
        let state: GameSnapshot
        if let snapshot { state = snapshot } else { state = await engine.snapshot() }
        guard let enemy = engine.catalog.enemies.first(where: { $0.id == encounterID }),
              let regionIndex = engine.catalog.regions.firstIndex(where: { $0.id == enemy.regionID }) else {
            throw CoreError.invalidCommand("R043 synthetic dash fixture enemy is missing")
        }
        let party = try R6CampaignQAAdapter.party(from: state, catalog: engine.catalog)
        var target = try R6CampaignQAAdapter.enemy(enemy, regionIndex: regionIndex)
        let (testHP, overflow) = target.maxHP.multipliedReportingOverflow(by: enemyHPMultiplier)
        guard !overflow, testHP > target.maxHP else {
            throw CoreError.invalidCommand("R043 synthetic target HP cannot be represented")
        }
        target.maxHP = testHP
        let mapping = [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy", catalogID: enemy.id,
                                                            label: enemy.name, assetKey: enemy.id)]
        return try R6TimelineSimulator.run(party: party, enemies: [target], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: mapping,
                                           sourceProfileSeed: String(seed))
    }
}
