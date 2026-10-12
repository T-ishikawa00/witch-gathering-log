import XCTest
import CryptoKit
@testable import WitchGameCore

private struct R043SaveEnvelopeFixture: Codable {
    let snapshot: GameSnapshot
    let receipts: [UUID: CommandReceipt]
}

final class SyntheticDash2ReachabilityTests: XCTestCase {
    func testSyntheticPreviewRetainsRealDash2AndPostImpactTailWithoutMutatingSave() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let smithGear = GearInstance(definitionID: "EQ_S_03", ownerID: "C_SMITH")
        let initial = GameSnapshot(revision: 17, gear: [smithGear],
                                   equippedGearIDs: ["C_SMITH|HAND": smithGear.id],
                                   activeRegionID: "R01")
        let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent("r043-\(UUID().uuidString).json")
        try JSONEncoder().encode(R043SaveEnvelopeFixture(snapshot: initial, receipts: [:])).write(to: saveURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: saveURL)
            let lockURL = saveURL.appendingPathExtension("lock")
            if FileManager.default.fileExists(atPath: lockURL.path) { try? FileManager.default.removeItem(at: lockURL) }
        }
        let saves = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try GameEngine(catalog: catalog, saves: saves)
        let before = await engine.snapshot()
        let diskBefore = try Data(contentsOf: saveURL)
        // Deterministic QA-only seed chosen because it emits NOIR dash2; this is
        // not a gameplay default and does not modify the snapshot or simulator.
        let seed = SyntheticPartyDash2PreviewR043.deterministicSeed

        let ordinary = try await engine.previewCampaignEncounterR6QA(enemyID: SyntheticPartyDash2PreviewR043.encounterID,
                                                                       seed: seed, snapshot: before)
        let synthetic = try await SyntheticPartyDash2PreviewR043.run(engine: engine, seed: seed, snapshot: before)
        let after = await engine.snapshot()
        let diskAfter = try Data(contentsOf: saveURL)

        XCTAssertEqual(before, after, "preview must not dispatch commands or mutate the save snapshot")
        XCTAssertEqual(diskBefore, diskAfter, "save bytes remain unchanged")
        XCTAssertEqual(before.revision, 17)
        let rootID = "C_FAMILIAR:SK_F_DASH:2"
        let ordinaryRoot = ordinary.events.filter { $0.rootActionID == rootID }
        let syntheticRoot = synthetic.events.filter { $0.rootActionID == rootID }
        let ordinaryStart = try XCTUnwrap(ordinaryRoot.first(where: { $0.kind == "cast_start" }))
        let ordinaryHit = try XCTUnwrap(ordinaryRoot.first(where: { $0.kind == "direct" }))
        let syntheticStart = try XCTUnwrap(syntheticRoot.first(where: { $0.kind == "cast_start" }))
        let syntheticHit = try XCTUnwrap(syntheticRoot.first(where: { $0.kind == "direct" }))
        XCTAssertLessThan(ordinaryStart.timestampMs ?? Int.max, ordinaryHit.timestampMs ?? 0)
        XCTAssertLessThan(syntheticStart.timestampMs ?? Int.max, syntheticHit.timestampMs ?? 0)
        XCTAssertEqual(ordinaryStart.timestampMs, syntheticStart.timestampMs,
                       "increasing only the cloned target HP must preserve the event prefix through dash2")
        XCTAssertEqual(ordinaryHit.timestampMs, syntheticHit.timestampMs)
        XCTAssertEqual(synthetic.entityPresentation[SyntheticPartyDash2PreviewR043.encounterID]?.catalogID,
                       SyntheticPartyDash2PreviewR043.encounterID)
        XCTAssertFalse(synthetic.won, "12-second bounded preview should terminate without a reward/kill")
        XCTAssertGreaterThanOrEqual((synthetic.ticks * 1_000) - (syntheticHit.timestampMs ?? 0),
                                    SyntheticPartyDash2PreviewR043.minimumTailAfterDash2Ms)
        XCTAssertEqual(synthetic.initialEnemyHP[SyntheticPartyDash2PreviewR043.encounterID],
                       (ordinary.initialEnemyHP[SyntheticPartyDash2PreviewR043.encounterID] ?? 0) * SyntheticPartyDash2PreviewR043.enemyHPMultiplier)
        let proof = [
            "schema": "party-motion-r043-synthetic-dash2-preview-r001",
            "claim": "Core R6 read-only synthetic reachability only; not native SpriteKit proof",
            "encounterID": SyntheticPartyDash2PreviewR043.encounterID,
            "seed": seed,
            "saveRevisionBefore": before.revision,
            "saveRevisionAfter": after.revision,
            "saveFileSHA256Before": SHA256.hash(data: diskBefore).map { String(format: "%02x", $0) }.joined(),
            "saveFileSHA256After": SHA256.hash(data: diskAfter).map { String(format: "%02x", $0) }.joined(),
            "enemyHPMultiplier": SyntheticPartyDash2PreviewR043.enemyHPMultiplier,
            "maxDurationMs": SyntheticPartyDash2PreviewR043.maxDurationMs,
            "ordinary": ["won": ordinary.won, "ticks": ordinary.ticks,
                         "dash2StartMs": ordinaryStart.timestampMs ?? -1,
                         "dash2DirectMs": ordinaryHit.timestampMs ?? -1,
                         "enemyInitialHP": ordinary.initialEnemyHP[SyntheticPartyDash2PreviewR043.encounterID] ?? -1],
            "synthetic": ["won": synthetic.won, "ticks": synthetic.ticks,
                          "dash2StartMs": syntheticStart.timestampMs ?? -1,
                          "dash2DirectMs": syntheticHit.timestampMs ?? -1,
                          "enemyInitialHP": synthetic.initialEnemyHP[SyntheticPartyDash2PreviewR043.encounterID] ?? -1,
                          "simulatedTailMs": synthetic.ticks * 1_000 - (syntheticHit.timestampMs ?? 0),
                          "dash2TimingMatchesOrdinary": ordinaryStart.timestampMs == syntheticStart.timestampMs && ordinaryHit.timestampMs == syntheticHit.timestampMs],
            "saveSnapshotUnchanged": before == after,
            "saveFileBytesUnchanged": diskBefore == diskAfter
        ] as [String : Any]
        if let path = ProcessInfo.processInfo.environment["R043_RESULT_PATH"] {
            let url = URL(fileURLWithPath: path)
            let data = try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        }
    }
}
