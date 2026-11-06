import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Small paired outcome comparison using only earned gear from one preserved
/// R020-profile save. All catalog values and combat results remain candidates.
final class CurrentProfileEarnedMechanicOutcomesR120Tests: XCTestCase {
    private struct Row: Encodable {
        let planID: String
        let selectedGear: [String: String]
        let battleID: String
        let regionID: String
        let seed: UInt64
        let won: Bool
        let ticks: Int
        let elapsedMs: Int
        let remainingPartyHP: [String: Int]
        let remainingEnemyHP: [String: Int]
        let eventCounts: [String: Int]
    }

    func testPairedCombatOutcomesFromEarnedR020Save() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let inputPath = env["WITCH_MECHANIC_SOURCE_SAVE"],
              let expectedInputSHA = env["WITCH_MECHANIC_SOURCE_SHA256"],
              let outputPath = env["WITCH_MECHANIC_OUTPUT_DIR"],
              let runID = env["WITCH_MECHANIC_RUN_ID"] else {
            throw XCTSkip("outcome comparison requires a preregistered earned source save and exclusive output")
        }
        XCTAssertTrue(["12000000-0000-4000-8000-000000000034",
                       "12000000-0000-4000-8000-000000000035"].contains(runID))
        let fm = FileManager.default
        let sourceURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
        XCTAssertTrue(fm.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(fm.fileExists(atPath: outputURL.deletingLastPathComponent().path))
        XCTAssertFalse(fm.fileExists(atPath: outputURL.path), "comparison output must be unique")
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: false)
        let inputData = try Data(contentsOf: sourceURL)
        XCTAssertEqual(Self.sha256(inputData), expectedInputSHA)

        let sourceRoot = URL(fileURLWithPath: env["WITCH_SOURCE_ROOT"] ?? "").standardizedFileURL
        let sourceHashesBefore = try Self.sourceHashes(packageRoot: sourceRoot)
        let executableURL = Bundle(for: type(of: self)).executableURL!.standardizedFileURL
        let executableSHA = Self.sha256(try Data(contentsOf: executableURL))
        let base = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let profile = try StandardPlayRuntimeProfileR1(base: base, options: .r020CurrentAppCandidate)
        let inputRepository = try SaveRepository(fileURL: sourceURL)
        let originalEnvelope = await inputRepository.snapshot()
        XCTAssertTrue(originalEnvelope.unlockedRegionIDs.contains("R05"))
        XCTAssertTrue(originalEnvelope.completedEncounterIDs.contains("B_R05_B"))

        let actors = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
        let plans: [(String, [String])] = [
            ("earned_saved_loadout", []),
            ("earned_direct_control", ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"]),
            ("earned_poison_heal_chase", ["EQ_W_P2", "EQ_A_03", "EQ_S_02", "EQ_F_03"]),
            ("earned_ward_heal_counter", ["EQ_W_G2", "EQ_A_02", "EQ_S_03", "EQ_F_02"])
        ]
        let battles = [("B_R01_B", "R01"), ("E_R03_04", "R03")]
        let seeds: [UInt64] = [100_049, 100_069]
        var rows: [Row] = []
        var ordinal = 0

        for (planID, templates) in plans {
            for (battleID, regionID) in battles {
                for seed in seeds {
                    ordinal += 1
                    let repository = try SaveRepository(initial: originalEnvelope)
                    let engine = try await profile.makeEngine(saves: repository)
                    var operationSequence = 0
                    let baseEpoch = Int64((originalEnvelope.lastClaimAt?.timeIntervalSince1970 ?? 1_794_592_000).rounded(.down)) + 1
                    func nextOperationID() -> UUID {
                        operationSequence += 1
                        return UUID(uuidString: String(format: "57495443-0002-4000-8000-%012llx",
                            UInt64(ordinal * 100 + operationSequence)))!
                    }
                    var time = baseEpoch
                    var selected: [String: String] = [:]

                    if !templates.isEmpty {
                        XCTAssertEqual(templates.count, actors.count)
                        for (actorID, templateID) in zip(actors, templates) {
                            let catalogGear = try XCTUnwrap(base.catalog.gear.first(where: { $0.id == templateID }))
                            XCTAssertTrue(catalogGear.actorIDs.isEmpty || catalogGear.actorIDs.contains(actorID))
                            let current = await repository.snapshot()
                            let candidate = try XCTUnwrap(current.gear
                                .filter { $0.definitionID == templateID }
                                .sorted { $0.id.uuidString < $1.id.uuidString }
                                .first,
                                "comparison gear must exist in the earned source save: \(templateID)")
                            let receipt = try await engine.dispatch(.equip(gearID: candidate.id, actorID: actorID),
                                operationID: nextOperationID(), expectedRevision: current.revision,
                                transactionDate: Date(timeIntervalSince1970: TimeInterval(time)))
                            XCTAssertTrue(receipt.result.contains("equipped:"))
                            selected[actorID] = "\(templateID)|\(candidate.id.uuidString.lowercased())"
                            time += 1
                        }
                    } else {
                        let current = await repository.snapshot()
                        selected = Dictionary(uniqueKeysWithValues: actors.map { actor in
                            let definitionBySlot = current.equippedGearIDs.filter { $0.key.hasPrefix(actor + "|") }
                            let parts = definitionBySlot.sorted(by: { $0.key < $1.key }).compactMap { slot, id -> String? in
                                current.gear.first(where: { $0.id == id }).map { "\(slot.split(separator: "|").last ?? "")=\($0.definitionID):\(id.uuidString.lowercased())" }
                            }
                            return (actor, parts.joined(separator: ","))
                        })
                    }

                    let selectedState = await repository.snapshot()
                    let moveToRegion = Date(timeIntervalSince1970: TimeInterval(time))
                    _ = try await engine.dispatch(.startExpeditionAt(regionID: regionID, now: moveToRegion),
                        operationID: nextOperationID(), expectedRevision: selectedState.revision,
                        transactionDate: moveToRegion)
                    let beforeBattle = await repository.snapshot()
                    let battleDate = Date(timeIntervalSince1970: TimeInterval(time + 1))
                    let command: GameCommand = .resolveEncounter(enemyID: battleID, seed: seed)
                    _ = try await engine.dispatch(command, operationID: nextOperationID(),
                        expectedRevision: beforeBattle.revision, transactionDate: battleDate)
                    let afterBattle = await repository.snapshot()
                    let result = try XCTUnwrap(afterBattle.lastCombatResult)
                    let relevantKinds = Set(["poison_seed", "poison_stack", "poison_tick", "poison_burst",
                        "barrier", "barrier_ward", "barrier_absorb", "reflect", "heal", "heal_barrier",
                        "heal_followup", "counter", "mark", "chase", "dash"])
                    let counts = Dictionary(grouping: result.events.map(\.kind), by: { $0 })
                        .mapValues(\.count).filter { relevantKinds.contains($0.key) }
                    rows.append(Row(planID: planID, selectedGear: selected,
                        battleID: battleID, regionID: regionID, seed: seed, won: result.won,
                        ticks: result.ticks,
                        elapsedMs: result.events.compactMap(\.timestampMs).max() ?? 0,
                        remainingPartyHP: result.remainingPartyHP,
                        remainingEnemyHP: result.remainingEnemyHP,
                        eventCounts: counts))
                }
            }
        }
        XCTAssertEqual(rows.count, plans.count * battles.count * seeds.count)
        let sourceHashesAfter = try Self.sourceHashes(packageRoot: sourceRoot)
        XCTAssertEqual(sourceHashesAfter, sourceHashesBefore,
                       "source/test inputs changed during paired comparison")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let report: [String: Any] = [
            "schema": "current-profile-earned-mechanic-outcomes-r120-v1",
            "status": "UNAPPROVED_TEST_OVERLAY",
            "runID": runID,
            "sourceSavePath": sourceURL.path,
            "sourceSaveSHA256": expectedInputSHA,
            "sourceHashes": sourceHashesBefore,
            "testExecutablePath": executableURL.path,
            "testExecutableSHA256": executableSHA,
            "runtimeProfileID": profile.profileID,
            "configurationFingerprint": profile.configurationFingerprint,
            "runtimeOptions": ["STANDARD_PLAY_R169": true, "FIRST_CRAFT_AID_R179": true,
                "EQUIPMENT_LOADOUTS_R342": true, "R144_SHARED_PARTY_WORK": true,
                "R230_ENHANCEMENT": true, "NATURAL_GEAR_R350": true,
                "NATURAL_GEAR_REFINEMENT_R352": true, "GEAR_DISMANTLE_REFUND_R353": true],
            "comparisonDesign": "4 plans × 2 authored encounters × 2 paired seeds. Every non-default plan is assembled from gear UUIDs already present in the earned source save; each row starts from an identical in-memory clone.",
            "plans": plans.map { ["id": $0.0, "templates": $0.1] },
            "battles": battles.map { ["id": $0.0, "regionID": $0.1] },
            "seeds": seeds,
            "rows": try JSONSerialization.jsonObject(with: encoder.encode(rows)),
            "limitations": [
                "All catalog/combat effects remain unapproved candidate values.",
                "This is a deterministic local comparison, not Human playtest, balance approval, or a claim about typical player outcomes.",
                "No gear, currency, research, or material was added to the tested snapshots."
            ]
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try reportData.write(to: outputURL.appendingPathComponent("report.json"), options: .atomic)
    }

    private static func sourceHashes(packageRoot: URL) throws -> [String: String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageRoot.appendingPathComponent("Package.swift").path) else {
            throw NSError(domain: "MechanicOutcomeR120", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "WITCH_SOURCE_ROOT must be the Swift package root"])
        }
        var paths = Set(["Package.swift"])
        let enumerator = try XCTUnwrap(fm.enumerator(at: packageRoot,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]))
        for case let url as URL in enumerator {
            let relative = String(url.path.dropFirst(packageRoot.path.count + 1))
            guard relative.hasPrefix("Sources/WitchGameCore/") || relative.hasPrefix("Tests/WitchGameCoreTests/") else { continue }
            if ["swift", "json", "plist"].contains(url.pathExtension.lowercased()) { paths.insert(relative) }
        }
        return try Dictionary(uniqueKeysWithValues: paths.sorted().map { path in
            (path, sha256(try Data(contentsOf: packageRoot.appendingPathComponent(path))))
        })
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
