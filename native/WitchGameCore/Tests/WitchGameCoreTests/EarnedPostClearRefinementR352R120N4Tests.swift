import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import WitchGameCore

/// Supplemental candidate-only check that spends an existing R352 transition
/// from a preserved ordinary-play save after acquiring its missing cost material.
final class EarnedPostClearRefinementR352R120N4Tests: XCTestCase {
    private struct Action: Encodable {
        let sequence: Int
        let command: String
        let operationID: String
        let revisionBefore: Int64
        let revisionAfter: Int64
        let receipt: String
        let resourceDelta: [String: Int]
        let saveSHA256: String
    }

    func testEarnedPostClearR352RankTwoWithRealR144GatherAndColdReload() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let sourcePath = env["WITCH_POSTCLEAR_SOURCE_SAVE"],
              let outputPath = env["WITCH_POSTCLEAR_OUTPUT_DIR"],
              let expectedSourceSHA = env["WITCH_POSTCLEAR_SOURCE_SHA256"],
              let runID = env["WITCH_POSTCLEAR_RUN_ID"] else {
            throw XCTSkip("supplemental post-clear run requires explicit preregistered paths and identity")
        }
        XCTAssertTrue(["12000000-0000-4000-8000-000000000031",
                       "12000000-0000-4000-8000-000000000032",
                       "12000000-0000-4000-8000-000000000033"].contains(runID))

        let fm = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
        let outputParent = outputURL.deletingLastPathComponent()
        XCTAssertTrue(fm.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(fm.fileExists(atPath: outputParent.path))
        XCTAssertFalse(fm.fileExists(atPath: outputURL.path), "supplemental run output must be unique")
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: false)

        let sourceData = try Data(contentsOf: sourceURL)
        let sourceSHA = Self.sha256(sourceData)
        XCTAssertEqual(sourceSHA, expectedSourceSHA, "source-case snapshot changed after preregistration")
        let workingSaveURL = outputURL.appendingPathComponent("save.json")
        try sourceData.write(to: workingSaveURL, options: .atomic)

        let sourceRoot = URL(fileURLWithPath: env["WITCH_SOURCE_ROOT"] ?? "")
            .standardizedFileURL
        let sourceHashesBefore = try Self.sourceHashes(packageRoot: sourceRoot)
        let executableURL = Bundle(for: type(of: self)).executableURL!.standardizedFileURL
        let executableSHA = Self.sha256(try Data(contentsOf: executableURL))

        let base = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let profile = try StandardPlayRuntimeProfileR1(
            base: base, options: .r020CurrentAppCandidate)
        let repository = try SaveRepository(fileURL: workingSaveURL)
        let before = await repository.snapshot()
        let preservedSourceRepository = try SaveRepository(fileURL: sourceURL)
        let preservedSourceSnapshot = await preservedSourceRepository.snapshot()
        XCTAssertEqual(before, preservedSourceSnapshot,
                       "working copy must start exactly at the preserved source snapshot")
        XCTAssertTrue(before.completedEncounterIDs.contains("B_R01_B"),
                      "R352 rank-I transition gate must already be earned")

        let policy = try XCTUnwrap(profile.refinement?.policy)
        let step = try XCTUnwrap(policy.transition(from: 1))
        XCTAssertEqual(step.toRank, 2)
        let eligible = before.equippedGearIDs.keys.sorted().compactMap { slot -> GearInstance? in
            guard let id = before.equippedGearIDs[slot] else { return nil }
            return before.gear.first(where: { $0.id == id })
        }.first(where: { (before.naturalGearRefinementR352 ?? .init()).rank(for: $0.id) == 1 })
        let targetGear = try XCTUnwrap(eligible, "source save needs an actually equipped rank-I item")
        let costs = step.materialCosts
        for (materialID, amount) in costs where materialID != "M_R02_G2" {
            XCTAssertGreaterThanOrEqual(before.materials[materialID, default: 0], amount,
                                        "only the declared missing gather cost may be acquired")
        }
        XCTAssertGreaterThanOrEqual(before.materials["refine_dust", default: 0], step.dustCost)

        let gatherMaterial = "M_R02_G2"
        let region = try XCTUnwrap(base.catalog.regions.first(where: { $0.id == "R02" }))
        XCTAssertTrue(region.gatherMaterialIDs.contains(gatherMaterial))
        XCTAssertTrue(base.catalog.availableGatherMaterialIDs(
            in: "R02", unlockedRegionIDs: before.unlockedRegionIDs,
            completedEncounterIDs: before.completedEncounterIDs).contains(gatherMaterial),
                      "target material must be available through the current catalog")
        XCTAssertGreaterThanOrEqual(region.workSeconds, 1)

        let engine = try await profile.makeEngine(saves: repository)
        var sequence = 0
        var actions: [Action] = []
        func operationID(_ sequence: Int) -> UUID {
            UUID(uuidString: String(format: "57495443-0001-4000-8000-%012llx", UInt64(sequence)))!
        }
        func delta(_ lhs: GameSnapshot, _ rhs: GameSnapshot) -> [String: Int] {
            var output: [String: Int] = [:]
            for id in Set(lhs.materials.keys).union(rhs.materials.keys) {
                let amount = rhs.materials[id, default: 0] - lhs.materials[id, default: 0]
                if amount != 0 { output["material:\(id)"] = amount }
            }
            return output
        }
        func dispatch(_ command: GameCommand, label: String, date: Date) async throws -> CommandReceipt {
            sequence += 1
            let op = operationID(sequence)
            let prior = await repository.snapshot()
            let receipt = try await engine.dispatch(command, operationID: op,
                expectedRevision: prior.revision, transactionDate: date)
            let next = await repository.snapshot()
            XCTAssertEqual(receipt.revision, next.revision)
            let bytes = try Data(contentsOf: workingSaveURL)
            actions.append(Action(sequence: sequence, command: label,
                operationID: op.uuidString.lowercased(), revisionBefore: prior.revision,
                revisionAfter: next.revision, receipt: receipt.result,
                resourceDelta: delta(prior, next), saveSHA256: Self.sha256(bytes)))
            return receipt
        }

        let startEpoch = Int64((before.lastClaimAt?.timeIntervalSince1970 ?? 1_794_592_000).rounded(.down)) + 1
        let startDate = Date(timeIntervalSince1970: TimeInterval(startEpoch))
        _ = try await dispatch(.startExpeditionAt(regionID: "R02", now: startDate),
                               label: "start-expedition:R02", date: startDate)
        _ = try await dispatch(.setGatherTargetAt(resourceID: gatherMaterial, now: startDate),
                               label: "set-gather-target:\(gatherMaterial)", date: startDate)
        let workSeconds = Int64(max(1, region.workSeconds))
        let gatherDate = Date(timeIntervalSince1970: TimeInterval(startEpoch + workSeconds * 6))
        let gathered = try await dispatch(.gather(resourceID: gatherMaterial, now: gatherDate),
                                           label: "gather:\(gatherMaterial)", date: gatherDate)
        XCTAssertTrue(gathered.result.contains("R144 gathered \(gatherMaterial)"))
        let afterGather = await repository.snapshot()
        XCTAssertGreaterThanOrEqual(afterGather.materials[gatherMaterial, default: 0], costs[gatherMaterial, default: 0])

        let refineDate = Date(timeIntervalSince1970: TimeInterval(startEpoch + workSeconds * 6 + 1))
        let refine = try await dispatch(.refine(gearID: targetGear.id),
                                        label: "refine:\(targetGear.id.uuidString)", date: refineDate)
        XCTAssertTrue(refine.result.contains("R352 rank 1→2"))
        let after = await repository.snapshot()
        XCTAssertEqual((after.naturalGearRefinementR352 ?? .init()).rank(for: targetGear.id), 2)
        XCTAssertEqual(after.materials["refine_dust", default: 0],
                       afterGather.materials["refine_dust", default: 0] - step.dustCost)

        // Complete the remaining authored research projects using only their
        // exact catalog costs and actual R144 region/work-target/gather commands.
        var cursor = startEpoch + workSeconds * 6 + 2
        var completedResearch: [String] = []
        var researchCosts: [String: [String: Int]] = [:]
        let researchIDs = ["RS_THEORY_2", "RS_THEORY_3", "RS_THEORY_4", "RS_THEORY_5"]
        for researchID in researchIDs {
            let research = try XCTUnwrap(base.catalog.research.first(where: { $0.id == researchID }))
            researchCosts[researchID] = research.cost
            for (materialID, required) in research.cost.sorted(by: { $0.key < $1.key }) {
                let current = await repository.snapshot()
                let shortfall = max(0, required - current.materials[materialID, default: 0])
                guard shortfall > 0 else { continue }
                let region = try XCTUnwrap(base.catalog.regions.first(where: { $0.gatherMaterialIDs.contains(materialID) }),
                    "no catalog gather region for \(materialID)")
                XCTAssertTrue(current.unlockedRegionIDs.contains(region.id), "research material region is not unlocked: \(region.id)")
                XCTAssertTrue(base.catalog.availableGatherMaterialIDs(in: region.id,
                    unlockedRegionIDs: current.unlockedRegionIDs,
                    completedEncounterIDs: current.completedEncounterIDs).contains(materialID),
                    "research material is not a legitimate available target: \(materialID)")
                let selectionDate = Date(timeIntervalSince1970: TimeInterval(cursor))
                _ = try await dispatch(.startExpeditionAt(regionID: region.id, now: selectionDate),
                    label: "research-expedition:\(region.id)", date: selectionDate)
                _ = try await dispatch(.setGatherTargetAt(resourceID: materialID, now: selectionDate),
                    label: "research-target:\(materialID)", date: selectionDate)
                let units = Int64((shortfall + PartyWorkPolicyR144.materialPerCompletedUnit - 1)
                    / PartyWorkPolicyR144.materialPerCompletedUnit)
                let gatherDate = Date(timeIntervalSince1970: TimeInterval(cursor + Int64(region.workSeconds) * units))
                let gatherReceipt = try await dispatch(.gather(resourceID: materialID, now: gatherDate),
                    label: "research-gather:\(materialID)", date: gatherDate)
                XCTAssertTrue(gatherReceipt.result.contains("R144 gathered \(materialID)"))
                cursor = Int64(gatherDate.timeIntervalSince1970.rounded(.down)) + 1
            }
            let ready = await repository.snapshot()
            XCTAssertTrue(research.cost.allSatisfy { ready.materials[$0.key, default: 0] >= $0.value },
                          "real acquisition did not meet the current \(researchID) catalog cost")
            let researchDate = Date(timeIntervalSince1970: TimeInterval(cursor))
            let receipt = try await dispatch(.completeResearch(researchID),
                label: "research:\(researchID)", date: researchDate)
            XCTAssertTrue(receipt.result.contains("research completed: \(researchID)"))
            completedResearch.append(researchID)
            cursor += 1
        }

        let afterResearch = await repository.snapshot()
        XCTAssertTrue(Set(researchIDs).isSubset(of: afterResearch.completedResearchIDs))
        XCTAssertEqual((afterResearch.naturalGearRefinementR352 ?? .init()).rank(for: targetGear.id), 2)
        let cold = try SaveRepository(fileURL: workingSaveURL)
        let coldSnapshot = await cold.snapshot()
        XCTAssertEqual(coldSnapshot, afterResearch,
                       "cold reopen must preserve earned gathering, R352 refinement, and research")
        XCTAssertEqual((coldSnapshot.naturalGearRefinementR352 ?? .init()).rank(for: targetGear.id), 2)
        let sourceHashesAfter = try Self.sourceHashes(packageRoot: sourceRoot)
        XCTAssertEqual(sourceHashesAfter, sourceHashesBefore,
                       "source/test inputs changed while the supplementary case was running")

        let report: [String: Any] = [
            "schema": "earned-postclear-refinement-and-research-r120n4-v1",
            "status": "UNAPPROVED_TEST_OVERLAY",
            "runID": runID,
            "caseID": "R120N4-POSTCLEAR-R352-RANK2",
            "sourceCaseSavePath": sourceURL.path,
            "sourceCaseSaveSHA256": sourceSHA,
            "workingSavePath": workingSaveURL.path,
            "finalSaveSHA256": Self.sha256(try Data(contentsOf: workingSaveURL)),
            "sourceHashes": sourceHashesBefore,
            "testExecutablePath": executableURL.path,
            "testExecutableSHA256": executableSHA,
            "runtimeProfileID": profile.profileID,
            "configurationFingerprint": profile.configurationFingerprint,
            "runtimeOptions": ["STANDARD_PLAY_R169": true, "FIRST_CRAFT_AID_R179": true,
                "EQUIPMENT_LOADOUTS_R342": true, "R144_SHARED_PARTY_WORK": true,
                "R230_ENHANCEMENT": true, "NATURAL_GEAR_R350": true,
                "NATURAL_GEAR_REFINEMENT_R352": true, "GEAR_DISMANTLE_REFUND_R353": true],
            "targetGearUUID": targetGear.id.uuidString.lowercased(),
            "targetGearDefinitionID": targetGear.definitionID,
            "refinementTransition": ["fromRank": step.fromRank, "toRank": step.toRank,
                "gateID": step.gateID, "dustCost": step.dustCost,
                "materialCosts": step.materialCosts],
            "gatherMaterialID": gatherMaterial,
            "gatheredMaterialTotal": afterGather.materials[gatherMaterial, default: 0]
                - before.materials[gatherMaterial, default: 0],
            "researchCompletedIDs": completedResearch,
            "researchCatalogCosts": researchCosts,
            "researchAdditionalVirtualSeconds": Int(cursor - startEpoch),
            "virtualElapsedSeconds": Int(cursor - startEpoch),
            "gatherWorkSecondsPerUnit": PartyWorkPolicyR144.materialPerCompletedUnit == 1
                ? region.workSeconds : -1,
            "actionLogArtifact": outputURL.appendingPathComponent("actions.json").path,
            "coldReloadSnapshotEqualsAfter": coldSnapshot == afterResearch,
            "candidateOnlyResearchDisclosure": "Research outcomes use the existing unapproved catalog; no costs or policy values were changed."
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try reportData.write(to: outputURL.appendingPathComponent("report.json"), options: .atomic)
        let actionData = try JSONEncoder().encode(actions)
        try actionData.write(to: outputURL.appendingPathComponent("actions.json"), options: .atomic)
        try Data((Self.prettyHashList(sourceHashesBefore) + "aggregate "
                  + Self.sha256(Data(Self.prettyHashList(sourceHashesBefore).utf8)) + "\n").utf8)
            .write(to: outputURL.appendingPathComponent("source_sha256.txt"), options: .atomic)
    }

    private static func sourceHashes(packageRoot: URL) throws -> [String: String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageRoot.appendingPathComponent("Package.swift").path) else {
            throw NSError(domain: "PostClearR352", code: 1,
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

    private static func prettyHashList(_ hashes: [String: String]) -> String {
        hashes.keys.sorted().map { "\(hashes[$0]!)  \($0)" }.joined(separator: "\n") + "\n"
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
