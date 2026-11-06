import XCTest
@testable import WitchGameCore

private struct R047SaveEnvelopeFixture: Codable {
    let snapshot: GameSnapshot
    let receipts: [UUID: CommandReceipt]
}

final class SyntheticDash2VisualTailR047Tests: XCTestCase {
    private func event(_ kind: String, _ source: String, _ target: String, _ root: String?, _ ms: Int) -> CombatEvent {
        CombatEvent(tick: ms / 1_000, kind: kind, sourceID: source, targetID: target,
                    amount: kind == "direct" ? 125 : 0, rootActionID: root, timestampMs: ms)
    }

    private func donor() -> CombatResult {
        let target = "C_FAMILIAR:SK_F_DASH:2"
        let events = [
            event("cast_start", "C_WITCH", "seed", "C_WITCH:SK_W_SEED:4", 6_400),
            event("cast_start", "C_FAMILIAR", "dash", target, 6_600),
            event("direct", "C_FAMILIAR", "E_R01_01", target, 6_800),
            event("cast_start", "C_FAMILIAR", "basic", "C_FAMILIAR:C_FAMILIAR_BASIC:5", 7_100),
            event("direct", "C_FAMILIAR", "E_R01_01", "C_FAMILIAR:C_FAMILIAR_BASIC:5", 7_350)
        ]
        return CombatResult(won: false, ticks: 8, events: events,
                            remainingPartyHP: ["C_FAMILIAR": 700],
                            initialPartyHP: ["C_FAMILIAR": 1_000],
                            initialEnemyHP: ["E_R01_01": 2_000],
                            remainingEnemyHP: ["E_R01_01": 1_500])
    }

    func testPrefixEndsAtExactTargetImpactAndDoesNotImportLaterCastOrFinalHP() throws {
        let full = donor()
        let savedFull = full
        let plan = try SyntheticDash2VisualTailR047.makePlan(from: full)
        XCTAssertEqual(full, savedFull)
        XCTAssertEqual(plan.fullDonorEventCount, 5)
        XCTAssertEqual(plan.targetCastStartIndex, 1)
        XCTAssertEqual(plan.targetImpactIndex, 2)
        XCTAssertEqual(plan.targetCastStartTimestampMs, 6_600)
        XCTAssertEqual(plan.targetImpactTimestampMs, 6_800)
        XCTAssertEqual(plan.tailMilliseconds, 1_200)
        XCTAssertEqual(plan.playback.events, Array(full.events[...2]))
        XCTAssertEqual(plan.playback.events.last?.rootActionID, SyntheticDash2VisualTailR047.rootActionID)
        XCTAssertEqual(plan.playback.events.last?.kind, "direct")
        XCTAssertFalse(plan.playback.events.contains { $0.kind == "cast_start" && $0.timestampMs ?? 0 > 6_800 })
        XCTAssertEqual(plan.playback.remainingPartyHP["C_FAMILIAR"], 1_000)
        XCTAssertEqual(plan.playback.remainingEnemyHP["E_R01_01"], 1_875)
        XCTAssertFalse(plan.playback.won)
        XCTAssertEqual(plan.schema, "synthetic-dash2-visual-tail-r047")
    }

    func testRejectsDuplicateTargetStart() {
        var full = donor()
        full = CombatResult(won: full.won, ticks: full.ticks,
                            events: [full.events[1]] + full.events,
                            remainingPartyHP: full.remainingPartyHP,
                            initialPartyHP: full.initialPartyHP,
                            initialEnemyHP: full.initialEnemyHP,
                            remainingEnemyHP: full.remainingEnemyHP)
        XCTAssertThrowsError(try SyntheticDash2VisualTailR047.makePlan(from: full)) { error in
            XCTAssertEqual(error as? SyntheticDash2VisualTailR047.PlanError, .missingOrDuplicateTargetStart)
        }
    }

    func testRejectsMissingOrMismatchedImpactAndTimeReversal() {
        let full = donor()
        let noImpact = CombatResult(won: false, ticks: full.ticks,
                                    events: Array(full.events.prefix(2)),
                                    remainingPartyHP: full.remainingPartyHP,
                                    initialPartyHP: full.initialPartyHP,
                                    initialEnemyHP: full.initialEnemyHP,
                                    remainingEnemyHP: full.remainingEnemyHP)
        XCTAssertThrowsError(try SyntheticDash2VisualTailR047.makePlan(from: noImpact))

        let wrongTarget = CombatResult(won: false, ticks: full.ticks,
                                       events: Array(full.events.prefix(2)) + [event("direct", "C_FAMILIAR", "E_OTHER", SyntheticDash2VisualTailR047.rootActionID, 6_800)],
                                       remainingPartyHP: full.remainingPartyHP,
                                       initialPartyHP: full.initialPartyHP,
                                       initialEnemyHP: full.initialEnemyHP,
                                       remainingEnemyHP: full.remainingEnemyHP)
        XCTAssertThrowsError(try SyntheticDash2VisualTailR047.makePlan(from: wrongTarget))

        let reversed = CombatResult(won: false, ticks: full.ticks,
                                    events: [event("cast_start", "C_FAMILIAR", "dash", SyntheticDash2VisualTailR047.rootActionID, 7_000),
                                             event("direct", "C_FAMILIAR", "E_R01_01", SyntheticDash2VisualTailR047.rootActionID, 6_800)],
                                    remainingPartyHP: full.remainingPartyHP,
                                    initialPartyHP: full.initialPartyHP,
                                    initialEnemyHP: full.initialEnemyHP,
                                    remainingEnemyHP: full.remainingEnemyHP)
        XCTAssertThrowsError(try SyntheticDash2VisualTailR047.makePlan(from: reversed))

        let prefixOnly = CombatResult(won: false, ticks: full.ticks,
                                      events: Array(full.events.prefix(3)),
                                      remainingPartyHP: full.remainingPartyHP,
                                      initialPartyHP: full.initialPartyHP,
                                      initialEnemyHP: full.initialEnemyHP,
                                      remainingEnemyHP: full.remainingEnemyHP)
        XCTAssertThrowsError(try SyntheticDash2VisualTailR047.makePlan(from: prefixOnly)) { error in
            XCTAssertEqual(error as? SyntheticDash2VisualTailR047.PlanError, .donorNotFullerThanPrefix)
        }
    }

    func testActualSyntheticR043DonorCanProduceIsolatedTargetPrefixWithoutSaveMutation() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let initial = GameSnapshot(revision: 27, activeRegionID: "R01")
        let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent("r047-\(UUID().uuidString).json")
        try JSONEncoder().encode(R047SaveEnvelopeFixture(snapshot: initial, receipts: [:])).write(to: saveURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: saveURL)
            let lockURL = saveURL.appendingPathExtension("lock")
            if FileManager.default.fileExists(atPath: lockURL.path) { try? FileManager.default.removeItem(at: lockURL) }
        }
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: initial, fileURL: saveURL))
        let before = await engine.snapshot()
        let bytesBefore = try Data(contentsOf: saveURL)
        let fullDonor = try await SyntheticPartyDash2PreviewR043.run(
            engine: engine, seed: SyntheticPartyDash2PreviewR043.deterministicSeed, snapshot: before)
        let plan = try SyntheticDash2VisualTailR047.makePlan(from: fullDonor)
        let after = await engine.snapshot()
        let bytesAfter = try Data(contentsOf: saveURL)

        XCTAssertEqual(before, after)
        XCTAssertEqual(bytesBefore, bytesAfter)
        XCTAssertFalse(fullDonor.won)
        XCTAssertGreaterThan(plan.fullDonorEventCount, plan.playback.events.count)
        XCTAssertEqual(plan.playback.events.last?.rootActionID, SyntheticDash2VisualTailR047.rootActionID)
        XCTAssertEqual(plan.playback.events.last?.kind, "direct")
        XCTAssertEqual(plan.playback.events.last?.timestampMs, plan.targetImpactTimestampMs)
        XCTAssertFalse(plan.playback.events.contains {
            $0.kind == "cast_start" && $0.sourceID == SyntheticDash2VisualTailR047.actorID
                && ($0.timestampMs ?? Int.min) > plan.targetImpactTimestampMs
        })
        XCTAssertNotEqual(plan.playback.remainingEnemyHP, fullDonor.remainingEnemyHP,
                          "the visual prefix must not inherit the donor's later full-result HP")
    }
}
