import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import WitchGameCore

/// R355 reuses the R199 daily engine policy with the R230 candidate factory and R144.
/// Only three test-only cohorts and 30 virtual days are accepted by this test.
final class EconomyCohortProgressionR355Tests: XCTestCase {
    private struct Action: Encodable {
        let sequence: Int
        let day: Int
        let epoch: Int64
        let operationID: String
        let command: String
        let outcome: String
        let revisionBefore: Int64
        let revisionAfter: Int64?
        let resourceDelta: [String: Int]
        let campaignClears: [String]
        let selectedWorkTarget: String?
        let combatWon: Bool?
    }
    private struct Day: Encodable {
        let day: Int
        let startEpoch: Int64
        let endEpoch: Int64
        let revision: Int64
        let campaignClears: [String]
        let unlockedRegions: [String]
        let materials: [String: Int]
        let currency: [String: Int]
        let gear: [GearRow]
        let workTarget: String?
        let completedResearchIDs: [String]
        let challengeClearIDs: [String]
        let lastClaimEpoch: Int64?
        let remainderSeconds: Double
        let saveSHA256: String
        let saveSHA256AfterReopen: String
        let reopenedSnapshotSHA256: String
        let recoveryStatus: SaveRecoveryStatus
        let didDailyClaim: Bool
        let freeSummonDraws: Int
        let paidSummonDraws: Int
        let adOpportunitiesCreated: Int
        let adCallbacksCompleted: Int
        let syntheticGrantProductIDs: [String]
        let gearTrialsPerformed: Int
        let gearInspectionEligibleCount: Int
        let gearInspectionSelectedCount: Int
        let pendingGearTrialCount: Int
        let pendingGearTrialInstanceIDs: [String]
        let naturalGearRollIndex: Int
        let naturalGearWorkUnitsIntoDrop: Int
        let naturalGearAcquisitionRecords: [NaturalGearAcquisitionRecordR350]
        let refinementRanksByUUID: [String: Int]
    }
    private struct GearRow: Encodable {
        let id: String
        let templateID: String
        let ownerID: String?
        let slot: String?
        let qualityID: String
        let enhancement: Int
        let refinement: Int
        let refinementRankR352: Int
        let latentEffectID: String?
        let candidateLatentSlots: CandidateLatentSlotsR003?
        let affixIDs: [String]
        let investmentDust: Int
    }
    private struct GearTrial: Encodable {
        let day: Int
        let selectionPriorityDay: Int
        let selectionPrioritySequence: Int
        let actorID: String
        let enemyID: String
        let seed: UInt64
        let currentGearID: String?
        let candidateGearID: String
        let baselineKind: String
        let baseline: GearSwapCombatSummaryR131?
        let candidate: GearSwapCombatSummaryR131
        let decision: String
        let snapshotUnchanged: Bool
    }
    private struct AdEvent: Encodable {
        let opportunityID: String
        let sessionID: String
        let virtualDay: Int
        let mode: String
        let callbackResult: String
        let engineOutcome: String
        let engineRecordedAtEpoch: TimeInterval
        let claimedByAdSkip: Bool
        let rewardXPByActor: [String: Int]
        let rewardDust: Int
        let engineReceipt: String
        let source: String
    }
    private struct AppRuntimeIdentity: Decodable {
        let value: String
        let runtimeProfileID: String
        let runtimeConfigurationFingerprint: String
        let baseRuntimeProfileID: String
        let baseRuntimeConfigurationFingerprint: String
        let enhancementProjectionPolicy: String
        let enhancementPolicySHA256: String
        let partyWorkPolicyID: String
        let partyWorkPolicyFingerprint: String
        let purchaseEnabled: Bool
        let adRewardsEnabled: Bool
        let humanApproval: Bool
        let firstCraftAidEnabled: Bool
        let firstCraftAidPolicyID: String
        let firstCraftAidPolicyFingerprint: String
    }
    private struct ChallengeOutcome: Encodable {
        let challengeID: String
        let combatSeed: UInt64
        let loadoutID: String
        let gear: [GearRow]
        let won: Bool
        let ticks: Int
        let initialPartyHP: [String: Int]
        let remainingPartyHP: [String: Int]
        let downedPartyActorIDs: [String]
        let initialEnemyHP: [String: Int]
        let remainingEnemyHP: [String: Int]
        let eventKindCounts: [String: Int]
    }
    private struct UnavailableOutcome: Encodable {
        let challengeID: String
        let combatSeed: UInt64
        let loadoutID: String
        let reason: String
    }
    private struct Report: Encodable {
        let schema: String
        let status: String
        let policyApprovalStatus: String
        let caseID: String
        let runID: String
        let cohortID: String
        let seed: UInt64
        let days: Int
        let simulatedClock: String
        let runtimeProfileID: String
        let runtimeProfileVersion: Int
        let runtimeConfigurationFingerprint: String
        let runtimeManifestSHA256: String
        let naturalGearDiscoveryPolicyFingerprint: String
        let naturalGearRefinementPolicyFingerprint: String
        let dismantleRefundPolicyFingerprint: String
        let naturalGearAcquisitionRecords: [NaturalGearAcquisitionRecordR350]
        let refinementRanksByUUID: [String: Int]
        let baseRuntimeProfileID: String
        let baseRuntimeConfigurationFingerprint: String
        let appRuntimeIdentitySHA256: String
        let partyWorkPolicyID: String
        let partyWorkPolicyFingerprint: String
        let operationIDPolicy: String
        let gearUUIDPolicy: String
        let gearInspectionPolicyID: String
        let initialSnapshotSHA256: String
        let sourceDigestsAtStart: [String: String]
        let sourceDigestsAtEnd: [String: String]
        let executablePath: String
        let executableSHA256: String
        let actions: [Action]
        let daily: [Day]
        let gearTrials: [GearTrial]
        let challengeOutcomes: [ChallengeOutcome]
        let unavailableChallengeOutcomes: [UnavailableOutcome]
        let firstCraftAidPolicyID: String
        let firstCraftAidPolicyFingerprint: String
        let freshFirstCraftAidEligible: Bool
        let recipeGoalByDay: [String]
        let campaignVictoryCount: Int
        let challengeVictoryCount: Int
        let challengeDefeatCount: Int
        let unresolvedCampaignEnemyIDs: [String]
        let unresolvedChallengeIDs: [String]
        let campaignDefeatCount: Int
        let clearedEnemyReplayAttempts: Int
        let firstClearDayByEnemy: [String: Int]
        let firstClearDayByChallenge: [String: Int]
        let completedResearchIDs: [String]
        let unresolvedResearchIDs: [String]
        let unresolvedRecipeIDs: [String]
        let enhancementActionCount: Int
        let refinementActionCount: Int
        let naturalDuplicateSalvageOutcome: String
        let craftedRecipeIDs: [String]
        let evolvedRecipeIDs: [String]
        let equippedGearInstanceIDs: [String]
        let dailyClaimPolicyStatus: [String]
        let syntheticGrantReceipts: [EconomyCohortTreatmentR195.GrantReceipt]
        let adEvents: [AdEvent]
        let adOpportunityCreatedCount: Int
        let freeSummonDrawCount: Int
        let paidSummonDrawCount: Int
        let gearInstancesAddedOrEvolvedDuringRun: [String]
        let gearInstancesPreviewed: [String]
        let gearInstancesPreviewedAfterLatestChange: [String]
        let pendingGearTrialInstanceIDs: [String]
        let actionJournalSHA256: String
        let finalSaveSHA256: String
        let finalSnapshotSHA256: String
        let limits: [String]
    }

    private let seeds: [UInt64] = [100_049, 100_069, 100_089]
    private let horizons: [Int] = [30]
    private let runnableCohorts: [EconomyCohortTreatmentR195.Cohort] = [.freeNoAd]

    private func preregisteredRunID(cohort: EconomyCohortTreatmentR195.Cohort,
                                    horizon: Int, seed: UInt64, attempt: Int) -> (caseID: String, runID: String)? {
        guard let c = runnableCohorts.firstIndex(of: cohort), let h = horizons.firstIndex(of: horizon),
              let s = seeds.firstIndex(of: seed), attempt == 1 else { return nil }
        let index = c * horizons.count * seeds.count + h * seeds.count + s + 1
        let runID = String(format: "44800000-%04llx-4001-8000-%012llx", UInt64(index), UInt64(attempt))
        return ("R448-\(cohort.rawValue)-\(horizon)-seed\(seed)", runID)
    }
    private let startEpoch: Int64 = 1_792_000_000

    func testR448FreeNoAdZeroSummonFirstCraftProgression() async throws {
        guard let cohortRaw = ProcessInfo.processInfo.environment["WITCH_R355_COHORT"],
              let cohort = EconomyCohortTreatmentR195.Cohort(rawValue: cohortRaw),
              let horizonDays = ProcessInfo.processInfo.environment["WITCH_R355_HORIZON"].flatMap(Int.init),
              let seed = ProcessInfo.processInfo.environment["WITCH_R355_SEED"].flatMap(UInt64.init),
              let runAttempt = ProcessInfo.processInfo.environment["WITCH_R355_ATTEMPT"].flatMap(Int.init),
              let expected = preregisteredRunID(cohort: cohort, horizon: horizonDays, seed: seed, attempt: runAttempt),
              ProcessInfo.processInfo.environment["WITCH_R355_CASE_ID"] == expected.caseID,
              ProcessInfo.processInfo.environment["WITCH_R355_RUN_ID"] == expected.runID,
              let productInputPath = ProcessInfo.processInfo.environment["WITCH_R355_PRODUCT_INPUTS"],
              productInputPath.hasPrefix("/"),
              let productInputSHA = ProcessInfo.processInfo.environment["WITCH_R355_PRODUCT_INPUTS_SHA256"] else {
            throw CoreError.invalidCommand("R355 cohort/horizon/seed/attempt/run identity is outside the exact single free_no_ad 30-day preregistration")
        }
        let caseID = expected.caseID
        let runID = expected.runID
        var treatment = try EconomyCohortTreatmentR195.load(
            inputsURL: URL(fileURLWithPath: productInputPath), expectedSHA256: productInputSHA)
        let rootPath = ProcessInfo.processInfo.environment["WITCH_SOURCE_ROOT"] ?? ""
        guard rootPath.hasPrefix("/") else { throw CoreError.invalidCommand("WITCH_SOURCE_ROOT must be absolute") }
        let sourceRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let sourcePaths = [
            "Sources/WitchGameCore/Domain.swift",
            "Sources/WitchGameCore/GameEngine.swift",
            "Sources/WitchGameCore/GameRuntimeConfigurationR098.swift",
            "Sources/WitchGameCore/GameRuntimeEnhancementProfileR230.swift",
            "Sources/WitchGameCore/GearEnhancementGrowthR230.swift",
            "Sources/WitchGameCore/CandidateCharacterGrowth.swift",
            "Sources/WitchGameCore/CandidateCombatOverlay.swift",
            "Sources/WitchGameCore/CandidateLatentSlotPolicyR003.swift",
            "Sources/WitchGameCore/CandidateLatentCombatModifiersR005.swift",
            "Sources/WitchGameCore/CombatSimulator.swift",
            "Sources/WitchGameCore/R6CampaignQA.swift",
            "Sources/WitchGameCore/R6CanonicalProfile.swift",
            "Sources/WitchGameCore/R6CombatPresentationSemantics.swift",
            "Sources/WitchGameCore/R6TimelineSimulator.swift",
            "Sources/WitchGameCore/GearSwapCampaignPreviewR136.swift",
            "Sources/WitchGameCore/GearSwapCombatPreviewR131.swift",
            "Sources/WitchGameCore/GearSwapCombatSummaryR131.swift",
            "Sources/WitchGameCore/PartyWorkPolicyR144.swift",
            "Sources/WitchGameCore/NaturalGearDiscoveryR350.swift",
            "Sources/WitchGameCore/NaturalGearRefinementR352.swift",
            "Sources/WitchGameCore/GearDismantleRefundR353.swift",
            "Sources/WitchGameCore/GameRuntimeIntegratedEquipmentProfileR355.swift",
            "Sources/WitchGameCore/OwnedPartyLoadoutPreviewR181.swift",
            "Sources/WitchGameCore/SaveRepository.swift",
            "Sources/WitchGameCore/Resources/catalog_overlay.json",
            "Sources/WitchGameCore/Resources/candidate_latent_policy_r004.json",
            "Tests/WitchGameCoreTests/GlobalRecipeGoalPlannerR159.swift",
            "Tests/WitchGameCoreTests/EconomyCohortProgressionR355Tests.swift",
            "Tests/WitchGameCoreTests/GearTrialPlannerR199.swift",
            "Tests/WitchGameCoreTests/EconomyCohortTreatmentR195.swift",
            "Tests/WitchGameCoreTests/EconomyCohortTreatmentR195Tests.swift"
        ]
        var digestsAtStart = try digestSources(sourceRoot, paths: sourcePaths)
        digestsAtStart["external/R355_PRODUCT_INPUTS.json"] = Self.sha256(try Data(contentsOf: URL(fileURLWithPath: productInputPath)))
        XCTAssertEqual(digestsAtStart["external/R355_PRODUCT_INPUTS.json"], productInputSHA)
        let runtime = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        guard let appIdentityPath = ProcessInfo.processInfo.environment["WITCH_R355_APP_IDENTITY_PATH"],
              appIdentityPath.hasPrefix("/"),
              let appIdentitySHA = ProcessInfo.processInfo.environment["WITCH_R355_APP_IDENTITY_SHA256"] else {
            throw CoreError.invalidCommand("R355 requires an exact current App runtime identity receipt")
        }
        let appIdentityData = try Data(contentsOf: URL(fileURLWithPath: appIdentityPath))
        XCTAssertEqual(Self.sha256(appIdentityData), appIdentitySHA)
        digestsAtStart["external/R355_APP_RUNTIME_IDENTITY.json"] = appIdentitySHA
        let appIdentity = try JSONDecoder().decode(AppRuntimeIdentity.self, from: appIdentityData)
        XCTAssertEqual(appIdentity.value, "UNAPPROVED_LOCAL_DEVELOPMENT_PROFILE")
        XCTAssertFalse(appIdentity.purchaseEnabled); XCTAssertFalse(appIdentity.adRewardsEnabled)
        XCTAssertFalse(appIdentity.humanApproval)
        let candidateRuntime = try GameRuntimeEnhancementProfileR230(base: runtime)
        let integratedRuntime = GameRuntimeIntegratedEquipmentProfileR355(base: candidateRuntime)
        XCTAssertEqual(integratedRuntime.discoveryPolicy.policyFingerprint,
                       "9888f5f0e7918ac0ea9de07e01ecb96d430cecb397b444d7f3863897f33c0f6a")
        XCTAssertEqual(integratedRuntime.refinementPolicy.policyFingerprint,
                       "5279e04574f7091c5b34b7aa8fec92a6b95d3464123bd4c67527c26d784b8d22")
        XCTAssertEqual(integratedRuntime.refundPolicy.policyFingerprint,
                       "33056eb7d447c06ddaf1e565b0b5d6646e53707500a86d9a14c318bb46a1a0d1")
        XCTAssertEqual(candidateRuntime.configurationFingerprint, appIdentity.runtimeConfigurationFingerprint,
                       "The tested policy stack must bind to the exact App R230 base configuration")
        XCTAssertEqual(candidateRuntime.base.profileID, appIdentity.baseRuntimeProfileID)
        XCTAssertEqual(candidateRuntime.base.configurationFingerprint, appIdentity.baseRuntimeConfigurationFingerprint)
        XCTAssertEqual(candidateRuntime.profileID, appIdentity.runtimeProfileID)
        XCTAssertEqual(candidateRuntime.configurationFingerprint, appIdentity.runtimeConfigurationFingerprint)
        XCTAssertEqual(appIdentity.enhancementProjectionPolicy, EnhancementProjectionPolicyR230.r2SlotBudgetCandidate.rawValue)
        XCTAssertEqual(appIdentity.enhancementPolicySHA256, GearEnhancementGrowthR230.policySHA256)
        let policy = try PartyWorkPolicyR144(baseProfileID: runtime.profileID,
                                             baseConfigurationFingerprint: runtime.configurationFingerprint)
        XCTAssertEqual(runtime.configurationFingerprint, PartyWorkPolicyR144.expectedBaseConfigurationFingerprint)
        XCTAssertEqual(appIdentity.partyWorkPolicyID, PartyWorkPolicyR144.policyID)
        XCTAssertEqual(appIdentity.partyWorkPolicyFingerprint, policy.policyFingerprint)
        XCTAssertEqual(runtime.catalog.gear.count, 33)

        guard let outputPath = ProcessInfo.processInfo.environment["WITCH_R355_OUTPUT"], outputPath.hasPrefix("/") else {
            throw CoreError.invalidCommand("WITCH_R355_OUTPUT must be an absolute path to report.json")
        }
        let reportURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        guard reportURL.lastPathComponent == "report.json" else {
            throw CoreError.invalidCommand("R355 output must end in report.json")
        }
        let runDirectory = reportURL.deletingLastPathComponent()
        guard runDirectory.lastPathComponent == "r448_\(runID)",
              FileManager.default.fileExists(atPath: runDirectory.deletingLastPathComponent().path),
              Darwin.mkdir(runDirectory.path, mode_t(0o700)) == 0 else {
            throw CoreError.invalidCommand("R355 output directory must be new, exclusive, and contain run UUID")
        }
        let saveURL = runDirectory.appendingPathComponent("save.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let firstCraftCapability = FirstCraftAidCapabilityR179.enabled
        guard appIdentity.firstCraftAidEnabled,
              appIdentity.firstCraftAidPolicyID == firstCraftCapability.policyID,
              appIdentity.firstCraftAidPolicyFingerprint == firstCraftCapability.policyFingerprint else {
            throw CoreError.invalidCommand("R355 requires the exact current R179 first-craft capability")
        }
        var initial = try runtime.makeNewSnapshot()
        initial.firstCraftAidEligibleR179 = true // Mirror App only for this genuinely new, exclusive save.
        XCTAssertNil(initial.partyWorkTargetR144)
        XCTAssertEqual(initial.gear.count, 4)
        let initialHash = Self.sha256(try encoder.encode(initial))
        let fileManager = FileManager.default
        let journalURL = runDirectory.appendingPathComponent("actions.jsonl")
        guard fileManager.createFile(atPath: journalURL.path, contents: Data()) else {
            throw CoreError.invalidCommand("could not create exclusive R355 action journal")
        }
        let startReceipt: [String: String] = [
            "schema": "r448-run-start-v1", "caseID": caseID, "runID": runID,
            "cohort": cohort.rawValue, "horizonDays": String(horizonDays),
            "caseIndex": String(runnableCohorts.firstIndex(of: cohort)! * horizons.count * seeds.count + horizons.firstIndex(of: horizonDays)! * seeds.count + seeds.firstIndex(of: seed)! + 1),
            "configurationFingerprint": candidateRuntime.configurationFingerprint,
            "baseConfigurationFingerprint": runtime.configurationFingerprint,
            "candidateProfileID": candidateRuntime.profileID,
            "appRuntimeIdentitySHA256": appIdentitySHA,
            "policyFingerprint": policy.policyFingerprint, "seed": String(seed),
            "attempt": String(runAttempt), "maxAttempts": "1", "aggregateRuntimeCapSeconds": "600", "maxBuildAllocatedBytes": "500000000", "maxEvidenceAllocatedBytes": "50000000",
            "budgetScope": "One Core compile plus one 90-second selected test; 500MB allocated build cap, separate 50MB evidence cap, 12GB free floor; no retry",
            "virtualStartEpoch": String(startEpoch), "initialSnapshotSHA256": initialHash,
            "executionStatus": "RUNNING_NOT_YET_VERIFIED"
        ]
        try encoder.encode(startReceipt).write(to: runDirectory.appendingPathComponent("RUN_STARTED.json"), options: .atomic)
        var store = try SaveRepository(initial: initial, fileURL: saveURL)
        var engine = try integratedRuntime.makeEngine(saves: store, candidatePartyWorkPolicyR144: policy, firstCraftAidCapabilityR179: firstCraftCapability)
        var sequence = 0
        var actions: [Action] = []
        var daily: [Day] = []
        var pendingGearTrialIDs: Set<UUID> = []
        var pendingGearMutationDay: [UUID: Int] = [:]
        var pendingGearMutationSequence: [UUID: Int] = [:]
        var gearInstancesAddedOrEvolved: Set<UUID> = []
        var gearInstancesPreviewedAfterLatestChange: Set<UUID> = []
        let initialGearInstanceIDs = Set(initial.gear.map(\.id))
        var craftedGearInstanceIDsObserved: Set<UUID> = []
        var naturalGearInstanceIDsObserved: Set<UUID> = []
        var unclassifiedGearInstanceIDsObserved: Set<UUID> = []
        let maxGearTrialsPerDay = 12
        var firstClearDay: [String: Int] = [:]
        var firstChallengeClearDay: [String: Int] = [:]
        var crafted: [String] = []
        var evolved: [String] = []
        var equipped: [String] = []
        var dailyClaims: [String] = []
        var syntheticGrantReceipts: [EconomyCohortTreatmentR195.GrantReceipt] = []
        var adEvents: [AdEvent] = []
        var totalFreeSummonDrawCount = 0
        var totalPaidSummonDrawCount = 0
        var gearTrials: [GearTrial] = []
        var recipeGoalByDay: [String] = []
        var wins = 0
        var challengeWins = 0
        var challengeDefeats = 0
        var defeats = 0
        var clearedEnemyReplayAttempts = 0

        func opID(_ sequence: Int) -> UUID {
            UUID(uuidString: String(format: "44810000-%04llx-4001-8000-%012llx", UInt64(runAttempt), UInt64(sequence)))!
        }
        func delta(_ before: GameSnapshot, _ after: GameSnapshot) -> [String: Int] {
            var result: [String: Int] = [:]
            for (kind, left, right) in [("material", before.materials, after.materials), ("currency", before.currency, after.currency)] {
                for key in Set(left.keys).union(right.keys).sorted() {
                    let value = right[key, default: 0] - left[key, default: 0]
                    if value != 0 { result["\(kind):\(key)"] = value }
                }
            }
            return result
        }
        func journal(_ action: Action) throws {
            var bytes = try encoder.encode(action)
            bytes.append(0x0A)
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
        }
        func recordRejected(_ label: String, _ error: Error, day: Int, epoch: Int64,
                            operationID: UUID, before: GameSnapshot) throws {
            actions.append(Action(sequence: sequence, day: day, epoch: epoch,
                                  operationID: operationID.uuidString.lowercased(), command: label,
                                  outcome: "REJECTED_OR_FAILED: \(String(describing: error))",
                                  revisionBefore: before.revision, revisionAfter: nil, resourceDelta: [:],
                                  campaignClears: before.completedEncounterIDs.sorted(),
                                  selectedWorkTarget: before.partyWorkTargetR144.map { "\($0.kind.rawValue):\($0.targetID)" },
                                  combatWon: nil))
            try journal(actions[actions.count - 1])
        }
        func record(_ label: String, _ command: GameCommand, day: Int, epoch: Int64) async throws -> String {
            sequence += 1
            let before = await store.snapshot()
            let receipt: CommandReceipt
            do {
                receipt = try await engine.dispatch(command, operationID: opID(sequence), expectedRevision: before.revision, transactionDate: Date(timeIntervalSince1970: TimeInterval(epoch)))
            } catch {
                try recordRejected(label, error, day: day, epoch: epoch, operationID: opID(sequence), before: before)
                throw error
            }
            let after = await store.snapshot()
            let addedGearIDs = Set(after.gear.map(\.id)).subtracting(Set(before.gear.map(\.id)))
            if !addedGearIDs.isEmpty {
                if case .craftRecipe = command {
                    craftedGearInstanceIDsObserved.formUnion(addedGearIDs)
                } else {
                    let ledgerIDs = Set(after.naturalGearDiscoveryR350?.acquisitionRecords.map(\.gearInstanceID) ?? [])
                    let naturalIDs = addedGearIDs.intersection(ledgerIDs)
                    naturalGearInstanceIDsObserved.formUnion(naturalIDs)
                    unclassifiedGearInstanceIDsObserved.formUnion(addedGearIDs.subtracting(naturalIDs))
                }
            }
            if case .mockSummon = command {
                let beforeIDs = Set(before.gear.map(\.id))
                let added = after.gear.map(\.id).filter { !beforeIDs.contains($0) }
                pendingGearTrialIDs.formUnion(added)
                for id in added {
                    pendingGearMutationDay[id] = day
                    pendingGearMutationSequence[id] = sequence
                }
                gearInstancesAddedOrEvolved.formUnion(added)
                gearInstancesPreviewedAfterLatestChange.subtract(added)
            } else if case .craftRecipe = command {
                let beforeIDs = Set(before.gear.map(\.id))
                let added = after.gear.map(\.id).filter { !beforeIDs.contains($0) }
                pendingGearTrialIDs.formUnion(added)
                for id in added {
                    pendingGearMutationDay[id] = day
                    pendingGearMutationSequence[id] = sequence
                }
                gearInstancesAddedOrEvolved.formUnion(added)
                gearInstancesPreviewedAfterLatestChange.subtract(added)
            } else if case .evolveGear(let gearID, _) = command {
                pendingGearTrialIDs.insert(gearID)
                pendingGearMutationDay[gearID] = day
                pendingGearMutationSequence[gearID] = sequence
                gearInstancesAddedOrEvolved.insert(gearID)
                gearInstancesPreviewedAfterLatestChange.remove(gearID)
            }
            let won: Bool? = {
                switch command {
                case .resolveEncounter(_, _), .resolveChallenge(_, _): return after.lastCombatResult?.won
                default: return nil
                }
            }()
            if case .resolveChallenge(let challengeID, _) = command, won == true {
                challengeWins += 1
                if !before.completedEncounterIDs.contains("CHALLENGE_CLEAR|\(challengeID)") {
                    firstChallengeClearDay[challengeID] = day
                }
            } else if case .resolveChallenge = command, won == false {
                challengeDefeats += 1
            }
            if case .resolveEncounter(let enemyID, _) = command {
                if before.completedEncounterIDs.contains(enemyID) { clearedEnemyReplayAttempts += 1 }
                if won == true { wins += 1; if !before.completedEncounterIDs.contains(enemyID) { firstClearDay[enemyID] = day } }
                else { defeats += 1 }
            }
            actions.append(Action(sequence: sequence, day: day, epoch: epoch, operationID: receipt.operationID.uuidString.lowercased(),
                                  command: label, outcome: receipt.result, revisionBefore: before.revision,
                                  revisionAfter: after.revision, resourceDelta: delta(before, after),
                                  campaignClears: after.completedEncounterIDs.sorted(),
                                  selectedWorkTarget: after.partyWorkTargetR144.map { "\($0.kind.rawValue):\($0.targetID)" },
                                  combatWon: won))
            try journal(actions[actions.count - 1])
            return receipt.result
        }
        func applyScheduledSyntheticGrant(_ productID: String, day: Int, epoch: Int64) async throws -> String {
            let before = await store.snapshot()
            var nextTreatment = treatment
            var expectedAfter = before
            let grant = try nextTreatment.applySyntheticTicketGrant(productID: productID, cohort: cohort,
                                                                      virtualDay: day, to: &expectedAfter)
            let grantDelta = grant.syntheticTicketDelta
            let expectedTicketAfter = expectedAfter.currency["ticket_paid_mock", default: 0]
            sequence += 1
            let operation = opID(sequence)
            let grantReceipt = try await store.transact(expectedRevision: before.revision,
                operationID: operation,
                requestFingerprint: "r195.syntheticGrant|\(cohort.rawValue)|\(productID)|day=\(day)|+\(grant.syntheticTicketDelta)") { state in
                    guard state.currency["ticket_paid_mock", default: 0] == before.currency["ticket_paid_mock", default: 0] else {
                        throw CoreError.invalidCommand("R195 synthetic grant currency changed before commit")
                    }
                    state.currency["ticket_paid_mock"] = expectedTicketAfter
                    return "UNAPPROVED_TEST_ONLY synthetic ticket input +\(grantDelta); no StoreKit transaction or entitlement"
                }
            treatment = nextTreatment
            let after = await store.snapshot()
            let action = Action(sequence: sequence, day: day, epoch: epoch,
                operationID: grantReceipt.operationID.uuidString.lowercased(),
                command: "synthetic_product_input_\(productID)", outcome: grantReceipt.result,
                revisionBefore: before.revision, revisionAfter: after.revision,
                resourceDelta: delta(before, after), campaignClears: after.completedEncounterIDs.sorted(),
                selectedWorkTarget: after.partyWorkTargetR144.map { "\($0.kind.rawValue):\($0.targetID)" }, combatWon: nil)
            actions.append(action)
            try journal(action)
            syntheticGrantReceipts.append(grant)
            let sidecar = runDirectory.appendingPathComponent(String(format: "SYNTHETIC_GRANT_%03d.json", syntheticGrantReceipts.count))
            try encoder.encode(grant).write(to: sidecar, options: .withoutOverwriting)
            return grantReceipt.result
        }
        // R448 omits all summon dispatches while retaining the real post-comparison gacha unlock.
        func summonAvailable(_ currencyID: String, day: Int, epoch: Int64) async throws -> Int {
            return 0
        }
        func settleAdOpportunities(day: Int, epoch: Int64) async throws -> (seen: Int, completed: Int) {
            guard cohort == .rewardedAd || cohort == .adSkip else { return (0, 0) }
            let state = await store.snapshot()
            let pending = state.localAdRewardOpportunities.values.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
            }
            var completed = 0
            for opportunity in pending {
                let current = await store.snapshot()
                guard current.localAdRewardOpportunities[opportunity.id] != nil else { continue }
                let session = cohort == .rewardedAd ? "R448-\(runID)-\(opportunity.id)" : "LOCAL_SKIP_\(opportunity.id)"
                let mode: String
                let result: String
                if cohort == .rewardedAd {
                    mode = "LOCAL_QA_SIMULATED_COMPLETED_VIEW"
                    result = try await record("local_qa_completed_ad_callback_\(opportunity.id)",
                        .recordMockRewardedAdAttempt(opportunityID: opportunity.id,
                            result: LocalRewardedAdQAResult.simulate(sessionID: session, outcome: .completed)),
                        day: day, epoch: epoch)
                } else {
                    mode = "LOCAL_QA_SKIP_SAME_STORED_REWARD"
                    result = try await record("local_qa_skip_claim_\(opportunity.id)",
                        .claimMockAdSkip(opportunityID: opportunity.id), day: day, epoch: epoch)
                }
                let committed = await store.snapshot()
                guard let actual = committed.localAdAttemptRecords[session], actual.opportunityID == opportunity.id,
                      actual.claimedByAdSkip == (cohort == .adSkip) else {
                    throw CoreError.invalidCommand("R195 ad callback did not persist the exact opportunity/session result")
                }
                completed += 1
                adEvents.append(AdEvent(opportunityID: opportunity.id, sessionID: actual.sessionID,
                    virtualDay: day, mode: mode, callbackResult: cohort == .rewardedAd ? "completed" : "skip_claimed",
                    engineOutcome: actual.outcome.rawValue, engineRecordedAtEpoch: actual.recordedAt.timeIntervalSince1970,
                    claimedByAdSkip: actual.claimedByAdSkip, rewardXPByActor: actual.rewardXPByActor,
                    rewardDust: actual.rewardDust, engineReceipt: result,
                    source: "ACTUAL_R098_R144_OPPORTUNITY_AND_GAMEENGINE_COMMAND_LOCAL_QA_ONLY"))
            }
            return (pending.count, completed)
        }

        if cohort == .adSkip {
            _ = try await record("enable_explicit_local_ad_skip_qa_flag", .setLocalAdSkipEntitlementForQA(enabled: true),
                                 day: 0, epoch: startEpoch)
        }

        for day in 1...horizonDays {
            let dayStart = startEpoch + Int64(day - 1) * 86_400
            let dayEnd = dayStart + 86_400
            var didDailyClaim = false
            var dayFreeSummonDraws = 0
            var dayPaidSummonDraws = 0
            var dayAdOpportunitiesCreated = 0
            var dayAdCallbacksCompleted = 0
            var dayGrantProductIDs: [String] = []
            var state = await store.snapshot()
            let gearIDsAtDayStart = Set(state.gear.map(\.id))
            if state.lastClaimAt == nil || state.activeRegionID == nil {
                let regionID = state.activeRegionID ?? runtime.catalog.regions.first?.id
                guard let regionID else { throw CoreError.invalidCatalog("R098 has no initial region") }
                _ = try await record("start_exp_verified_\(regionID)", .startExpeditionAt(regionID: regionID, now: Date(timeIntervalSince1970: TimeInterval(dayStart))), day: day, epoch: dayStart)
                state = await store.snapshot()
            }
            // Keep the campaign frontier independent from whichever old region the
            // previous day's global material target used. All switches are engine
            // commands at the same session timestamp, never direct snapshot writes.
            var combatActionsToday = 0
            for frontierIndex in 0..<3 {
                state = await store.snapshot()
                guard let frontier = GlobalRecipeGoalPlannerR159.nextFrontier(catalog: runtime.catalog, snapshot: state) else { break }
                if state.activeRegionID != frontier.regionID {
                    _ = try await record("switch_to_actual_frontier_\(frontier.regionID)",
                                         .startExpeditionAt(regionID: frontier.regionID,
                                                           now: Date(timeIntervalSince1970: TimeInterval(dayStart))),
                                         day: day, epoch: dayStart)
                    state = await store.snapshot()
                    guard state.activeRegionID == frontier.regionID else {
                        throw CoreError.invalidCommand("frontier region switch did not persist")
                    }
                }
                let battleSeed = seed &+ UInt64(day * 1_000 + frontierIndex + 1)
                _ = try await record("resolve_actual_frontier_\(frontier.enemyID)_seed_\(battleSeed)",
                                     .resolveEncounter(enemyID: frontier.enemyID, seed: battleSeed), day: day, epoch: dayStart)
                combatActionsToday += 1
                state = await store.snapshot()
                // A failed first-clear attempt ends today's campaign loop. Do not
                // retry the same uncleared enemy under another seed in this session.
                guard state.lastCombatResult?.won == true else { break }
            }
            state = await store.snapshot()
            let availableChallenges = runtime.catalog.challenges.sorted(by: { $0.id < $1.id }).filter { item in
                let clearKey = "CHALLENGE_CLEAR|\(item.id)"
                let parts = item.unlockGate.split(separator: "_")
                guard parts.count == 3, parts[0] == "G" else { return false }
                return !state.completedEncounterIDs.contains(clearKey) &&
                    state.completedEncounterIDs.contains("B_\(parts[1])_\(parts[2])")
            }
            for (challengeIndex, challenge) in availableChallenges.prefix(max(0, 3 - combatActionsToday)).enumerated() {
                _ = try await record("resolve_first_gate_open_challenge_\(challenge.id)",
                    .resolveChallenge(challengeID: challenge.id,
                                      seed: seed &+ UInt64(day * 7_000 + challengeIndex + 5_501)),
                    day: day, epoch: dayStart)
                state = await store.snapshot()
            }

            let researchGoals = try GlobalRecipeGoalPlannerR159.researchGoals(catalog: runtime.catalog, snapshot: state)
            let researchGoal = researchGoals.first
            let onboardingCraftPending = state.firstCraftAidEligibleR179 == true && !state.craftedGearOnce
            let researchReserve = onboardingCraftPending ? [:] : (researchGoal?.gateOpen == true ? researchGoal!.costs : [:])
            let (recipePlan, rejectedRecipePlans) = try firstReachableRecipePlan(
                runtime: runtime, snapshot: state, researchReserve: researchReserve,
                completedRecipeIDs: Set(crafted + evolved),
                firstCraftTutorialPending: state.firstCraftAidEligibleR179 == true && !state.craftedGearOnce)
            let targetRecipe = recipePlan.flatMap { plan in runtime.catalog.recipes.first(where: { $0.id == plan.recipeID }) }
            let chosenSource: GlobalRecipeGoalPlannerR159.Work? = {
                // The R179 first-craft tutorial is the top onboarding goal until the
                // actual craft transaction succeeds; collect its projected recipe inputs first.
                if state.firstCraftAidEligibleR179 == true, !state.craftedGearOnce,
                   let material = recipePlan?.workByMaterial.keys.sorted().first {
                    return recipePlan?.workByMaterial[material]
                }
                if let researchGoal, researchGoal.gateOpen,
                   let material = researchGoal.workByMaterial.keys.sorted().first {
                    return researchGoal.workByMaterial[material]
                }
                if let material = recipePlan?.workByMaterial.keys.sorted().first {
                    return recipePlan?.workByMaterial[material]
                }
                return nil
            }()
            var workRegionID: String?
            let target: PartyWorkTargetR144
            switch chosenSource {
            case .gather(let regionID, let materialID):
                target = .gather(materialID); workRegionID = regionID
            case .investigate(let regionID, let enemyID):
                target = .investigate(enemyID); workRegionID = regionID
            case nil:
                target = try selectedTarget(snapshot: state, runtime: runtime, goalRecipe: targetRecipe)
                workRegionID = state.activeRegionID
            }
            if let workRegionID, state.activeRegionID != workRegionID {
                _ = try await record("switch_to_global_goal_source_\(workRegionID)",
                                     .startExpeditionAt(regionID: workRegionID,
                                                       now: Date(timeIntervalSince1970: TimeInterval(dayStart))),
                                     day: day, epoch: dayStart)
                state = await store.snapshot()
                XCTAssertEqual(state.activeRegionID, workRegionID, "global material work region must be an actual persisted expedition switch")
            }
            let projectedRecipeCosts = try targetRecipe.map { recipe in
                try FirstCraftCostProjectionR179.validateCatalog(recipeID: recipe.id, declaredCosts: recipe.costs,
                    snapshot: state, capability: firstCraftCapability).costs
            } ?? [:]
            let goalDeficits = projectedRecipeCosts.keys.sorted().compactMap { materialID -> String? in
                let missing = max(0, (projectedRecipeCosts[materialID] ?? 0) - state.materials[materialID, default: 0])
                return missing > 0 ? "\(materialID):\(missing)" : nil
            }.joined(separator: ",")
            let dustDeficit = max(0, (targetRecipe?.dustCost ?? 0) - state.materials["refine_dust", default: 0])
            let researchTrace = researchGoals.map { goal in
                "\(goal.researchID){gate=\(goal.gateID ?? "none");open=\(goal.gateOpen);cost=\(goal.costs.sorted { $0.key < $1.key });deficit=\(goal.materialDeficits.sorted { $0.key < $1.key });unavailable=\(goal.unavailableMaterials)}"
            }.joined(separator: ";")
            recipeGoalByDay.append("day\(day):research=[\(researchTrace)]:recipe=\(targetRecipe?.id ?? "NO_REACHABLE_RECIPE"):rejectedRecipePlans=\(rejectedRecipePlans):parent=\(recipePlan?.parentGearUUID?.uuidString.lowercased() ?? "none"):work=\(target.kind.rawValue):\(target.targetID)@\(workRegionID ?? "none"):missing=\(goalDeficits):refine_dust=\(dustDeficit)")
            if target.kind == .investigate {
                XCTAssertTrue(state.completedEncounterIDs.contains(target.targetID),
                              "investigation target must be unlocked by a real prior clear")
                XCTAssertNotNil(firstClearDay[target.targetID],
                                "investigation target must have a first-clear battle receipt in this run")
            }
            if state.partyWorkTargetR144 != target {
                sequence += 1
                let selectionID = opID(sequence)
                do {
                    _ = try await engine.setPartyWorkTargetR144(target, now: Date(timeIntervalSince1970: TimeInterval(dayStart)),
                                                                operationID: selectionID, expectedRevision: state.revision)
                } catch {
                    try recordRejected("select_single_target", error, day: day, epoch: dayStart,
                                       operationID: selectionID, before: state)
                    throw error
                }
                state = await store.snapshot()
                actions.append(Action(sequence: sequence, day: day, epoch: dayStart,
                                      operationID: opID(sequence).uuidString.lowercased(), command: "select_single_target",
                                      outcome: "selected \(target.kind.rawValue):\(target.targetID)", revisionBefore: state.revision - 1,
                                      revisionAfter: state.revision, resourceDelta: [:],
                                      campaignClears: state.completedEncounterIDs.sorted(),
                                      selectedWorkTarget: "\(target.kind.rawValue):\(target.targetID)", combatWon: nil))
                try journal(actions[actions.count - 1])
            }
            // One UTC-calendar daily claim follows the actual onboarding comparison gate.
            // The one-day virtual clock is an explicit scripted cadence, not real playtime.
            let preClaim = await store.snapshot()
            let adSequenceBeforeClaim = preClaim.localAdNextOpportunitySequence
            sequence += 1
            let claimID = opID(sequence)
            let claim: CommandReceipt
            do {
                claim = try await engine.claimOffline(now: Date(timeIntervalSince1970: TimeInterval(dayEnd)),
                                                      operationID: claimID, expectedRevision: preClaim.revision)
            } catch {
                try recordRejected("settle_one_R144_target_24h_virtual", error, day: day, epoch: dayEnd,
                                   operationID: claimID, before: preClaim)
                throw error
            }
            state = await store.snapshot()
            dayAdOpportunitiesCreated = max(0, state.localAdNextOpportunitySequence - adSequenceBeforeClaim)
            actions.append(Action(sequence: sequence, day: day, epoch: dayEnd,
                                  operationID: claim.operationID.uuidString.lowercased(), command: "settle_one_R144_target_24h_virtual",
                                  outcome: claim.result, revisionBefore: preClaim.revision, revisionAfter: state.revision,
                                  resourceDelta: delta(preClaim, state), campaignClears: state.completedEncounterIDs.sorted(),
                                  selectedWorkTarget: state.partyWorkTargetR144.map { "\($0.kind.rawValue):\($0.targetID)" }, combatWon: nil))
            try journal(actions[actions.count - 1])
            let adSettlement = try await settleAdOpportunities(day: day, epoch: dayEnd)
            dayAdCallbacksCompleted = adSettlement.completed

            // Execute only the recipe goal chosen before this day's accrual. Successful
            // recipes are never repeated unless a later policy explicitly declares an
            // instance goal; this candidate retains the R191 policy for both horizons.
            var changedGearID: UUID?
            if let recipe = targetRecipe, recipeGateIsOpen(recipe, snapshot: state),
               projectedRecipeCosts.allSatisfy({ state.materials[$0.key, default: 0] - researchReserve[$0.key, default: 0] >= $0.value }),
               state.materials["refine_dust", default: 0] - researchReserve["refine_dust", default: 0] >= recipe.dustCost {
                switch recipe.kind {
                case "craft_new":
                    guard recipe.outputGearID != nil else { throw CoreError.invalidCatalog("goal craft has no output") }
                    _ = try await record("craft_once_for_goal_\(recipe.id)", .craftRecipe(recipe.id), day: day, epoch: dayEnd)
                    crafted.append(recipe.id)
                    state = await store.snapshot()
                    changedGearID = recipe.outputGearID.flatMap { outputID in
                        state.gear.last(where: { $0.definitionID == outputID && $0.ownerID == nil })?.id
                    }
                case "evolve_in_place":
                    guard recipe.parentTemplateID != nil,
                          let parentID = recipePlan?.parentGearUUID,
                          state.gear.contains(where: { $0.id == parentID && $0.definitionID == recipe.parentTemplateID }) else {
                        throw CoreError.invalidCommand("goal evolution parent instance is absent")
                    }
                    _ = try await record("evolve_owned_parent_once_\(parentID.uuidString.lowercased())_\(recipe.id)",
                                         .evolveGear(gearID: parentID, recipeID: recipe.id), day: day, epoch: dayEnd)
                    evolved.append(recipe.id)
                    changedGearID = parentID
                default:
                    throw CoreError.invalidCatalog("unsupported goal recipe kind \(recipe.kind)")
                }
            }

            // Complete one research only when its actual persisted catalog cost and
            // any associated campaign gate are satisfied after higher-priority recipe work.
            state = await store.snapshot()
            if let research = try GlobalRecipeGoalPlannerR159.nextResearchGoal(catalog: runtime.catalog, snapshot: state),
               research.gateOpen,
               research.costs.allSatisfy({ state.materials[$0.key, default: 0] >= $0.value }) {
                _ = try await record("complete_affordable_catalog_research_\(research.researchID)",
                    .completeResearch(research.researchID), day: day, epoch: dayEnd)
                state = await store.snapshot()
            }

            // Apply at most one real investment action per virtual day. Refinement
            // follows the persisted R352 UUID-rank ledger, boss gate, dust and
            // material transition; legacy GearInstance.refinement is not a rank.
            let completedRecipes = Set(crafted + evolved)
            let outstandingRecipeReserve: [String: Int] = {
                guard let recipe = targetRecipe, !completedRecipes.contains(recipe.id) else { return [:] }
                return projectedRecipeCosts
            }()
            let remainingResearch = try GlobalRecipeGoalPlannerR159.nextResearchGoal(catalog: runtime.catalog, snapshot: state)
            let outstandingResearchReserve = remainingResearch?.gateOpen == true ? (remainingResearch?.costs ?? [:]) : [:]
            func canSpend(_ amount: Int, materialID: String) -> Bool {
                state.materials[materialID, default: 0] - outstandingRecipeReserve[materialID, default: 0]
                    - outstandingResearchReserve[materialID, default: 0] >= amount
            }
            let equippedItems = state.gear.filter { state.equippedGearIDs.values.contains($0.id) }
            var investmentApplied = false
            for gear in equippedItems.sorted(by: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }) {
                let rank = state.naturalGearRefinementR352?.rank(for: gear.id) ?? 1
                guard (1...5).contains(rank) else { throw CoreError.invalidCommand("persisted R352 rank is outside I–V") }
                guard let step = integratedRuntime.refinementPolicy.transition(from: rank),
                      gateIsOpen(step.gateID, snapshot: state),
                      canSpend(step.dustCost, materialID: "refine_dust"),
                      step.materialCosts.allSatisfy({ canSpend($0.value, materialID: $0.key) }) else { continue }
                let beforeInvestment = state
                _ = try await record("refine_r352_equipped_\(gear.id.uuidString.lowercased())_\(rank)_to_\(step.toRank)",
                                     .refine(gearID: gear.id), day: day, epoch: dayEnd)
                state = await store.snapshot()
                XCTAssertEqual(state.naturalGearRefinementR352?.rank(for: gear.id), step.toRank,
                               "ordinary earned refine dispatch must advance the actual persisted UUID rank")
                XCTAssertEqual(beforeInvestment.materials["refine_dust", default: 0] - state.materials["refine_dust", default: 0], step.dustCost)
                for (materialID, amount) in step.materialCosts {
                    XCTAssertEqual(beforeInvestment.materials[materialID, default: 0] - state.materials[materialID, default: 0], amount)
                }
                XCTAssertEqual(state.gear.first(where: { $0.id == gear.id })?.investmentDust,
                               (beforeInvestment.gear.first(where: { $0.id == gear.id })?.investmentDust ?? 0) + step.dustCost)
                investmentApplied = true
                break
            }
            if !investmentApplied {
                for gear in equippedItems.sorted(by: {
                    $0.enhancement < $1.enhancement ||
                    ($0.enhancement == $1.enhancement && $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased())
                }) {
                    let rank = state.naturalGearRefinementR352?.rank(for: gear.id) ?? 1
                    guard let rankCap = integratedRuntime.refinementPolicy.maximumEnhancement(forRank: rank),
                          gear.enhancement < rankCap,
                          let recipe = runtime.catalog.recipes.first(where: { $0.id == "ENHANCE_\(gear.enhancement + 1)" }),
                          recipe.kind == "enhance", recipeGateIsOpen(recipe, snapshot: state),
                          canSpend(recipe.dustCost, materialID: "refine_dust") else { continue }
                    let beforeInvestment = state
                    _ = try await record("enhance_r352_rank\(rank)_equipped_\(gear.id.uuidString.lowercased())",
                                         .enhance(gearID: gear.id), day: day, epoch: dayEnd)
                    state = await store.snapshot()
                    XCTAssertEqual(state.gear.first(where: { $0.id == gear.id })?.enhancement, gear.enhancement + 1)
                    XCTAssertEqual(state.naturalGearRefinementR352?.rank(for: gear.id) ?? 1, rank,
                                   "enhancement must preserve this instance's R352 rank")
                    XCTAssertEqual(beforeInvestment.materials["refine_dust", default: 0] - state.materials["refine_dust", default: 0], recipe.dustCost)
                    investmentApplied = true
                    break
                }
            }

            // Inspect newly acquired, crafted, or evolved real instances with paired
            // read-only campaign trials. Each pair uses one snapshot, enemy and seed.
            // Any instance skipped by the daily cap or because it is already equipped
            // remains in the UUID backlog; it is never counted as inspected.
            state = await store.snapshot()
            var gearIDsToInspect = Array(pendingGearTrialIDs)
            gearIDsToInspect.append(contentsOf: state.gear.map(\.id).filter { !gearIDsAtDayStart.contains($0) })
            if let changedGearID, !gearIDsToInspect.contains(changedGearID) { gearIDsToInspect.append(changedGearID) }
            for id in gearIDsToInspect {
                if pendingGearMutationDay[id] == nil { pendingGearMutationDay[id] = day }
                if pendingGearMutationSequence[id] == nil { pendingGearMutationSequence[id] = sequence }
            }
            let trialEnemyID = engine.availableCampaignGearTrialEnemiesR136(snapshot: state).first?.id
            let planningItems = Array(Set(gearIDsToInspect)).map { id -> GearTrialQueueItemR199 in
                let isEligible: Bool
                if let candidate = state.gear.first(where: { $0.id == id }),
                   !state.equippedGearIDs.values.contains(id),
                   let definition = runtime.catalog.gear.first(where: { $0.id == candidate.definitionID }),
                   state.partyActorIDs.contains(where: {
                       (definition.actorIDs.isEmpty || definition.actorIDs.contains($0)) &&
                       (candidate.ownerID == nil || candidate.ownerID == $0)
                   }), trialEnemyID != nil {
                    isEligible = true
                } else {
                    isEligible = false
                }
                return GearTrialQueueItemR199(id: id,
                    lastMutationDay: pendingGearMutationDay[id] ?? day,
                    lastMutationSequence: pendingGearMutationSequence[id] ?? sequence,
                    isEligible: isEligible)
            }
            let selectedGearIDs = GearTrialPlannerR199.select(planningItems, limit: maxGearTrialsPerDay)
            let gearInspectionEligibleCount = planningItems.filter(\.isEligible).count
            let gearInspectionSelectedCount = selectedGearIDs.count
            var gearEquipsToday = 0
            let gearTrialsBeforeDay = gearTrials.count
            for (trialIndex, candidateID) in selectedGearIDs.enumerated() {
                state = await store.snapshot()
                guard let candidate = state.gear.first(where: { $0.id == candidateID }),
                      !state.equippedGearIDs.values.contains(candidateID),
                      let definition = runtime.catalog.gear.first(where: { $0.id == candidate.definitionID }),
                      let actor = state.partyActorIDs.first(where: {
                          (definition.actorIDs.isEmpty || definition.actorIDs.contains($0)) &&
                          (candidate.ownerID == nil || candidate.ownerID == $0)
                      }),
                      let enemy = engine.availableCampaignGearTrialEnemiesR136(snapshot: state).first else { continue }
                let currentID = state.equippedGearIDs["\(actor)|\(definition.slot)"]
                guard currentID != candidateID else { continue }
                let beforePreview = state
                let previewSeed = seed &+ UInt64(day * 10_000 + 9_151 + trialIndex)
                let proposed = try engine.previewCampaignGearSwapR136(enemyID: enemy.id, actorID: actor,
                    selectedGearID: candidateID, seed: previewSeed, snapshot: state)
                let candidateSummary = GearSwapCombatSummaryR131.make(from: proposed)
                let currentCombat = try await engine.previewCampaignEncounterDefaultQA(
                    enemyID: enemy.id, seed: previewSeed, snapshot: state)
                let baselineSummary: GearSwapCombatSummaryR131? = Self.currentLoadoutSummary(
                    result: currentCombat, actorID: actor)
                if let currentID {
                    let noOp = try engine.previewCampaignGearSwapR136(enemyID: enemy.id, actorID: actor,
                        selectedGearID: currentID, seed: previewSeed, snapshot: state)
                    XCTAssertEqual(noOp.result, currentCombat,
                                   "unchanged default path must equal same-slot no-op preview")
                }
                let afterPreview = await store.snapshot()
                XCTAssertEqual(afterPreview, beforePreview, "campaign previews must not mutate or persist state")
                var decision: String
                if let baselineSummary {
                    let baselineHP = baselineSummary.remainingPartyHP.values.reduce(0, +)
                    let candidateHP = candidateSummary.remainingPartyHP.values.reduce(0, +)
                    if candidateSummary.won && !baselineSummary.won && candidateHP >= baselineHP {
                        decision = "EQUIP: preview win improved without lower remaining party HP"
                    } else if candidateSummary.won && baselineSummary.won && candidateSummary.ticks < baselineSummary.ticks && candidateHP >= baselineHP {
                        decision = "EQUIP: fewer ticks and no lower remaining party HP"
                    } else if candidateSummary.won && baselineSummary.won && candidateSummary.ticks == baselineSummary.ticks && candidateHP > baselineHP {
                        decision = "EQUIP: same ticks with higher remaining party HP"
                    } else {
                        decision = "NO_ACTION: no preregistered Pareto improvement; retain current gear"
                    }
                } else {
                    decision = "NO_ACTION: no equipped same-slot baseline; candidate trial is descriptive only"
                }
                if decision.hasPrefix("EQUIP:"), gearEquipsToday >= 1 {
                    decision = "NO_ACTION: daily equip cap reached; measured " + decision
                }
                gearTrials.append(GearTrial(day: day,
                    selectionPriorityDay: pendingGearMutationDay[candidateID] ?? day,
                    selectionPrioritySequence: pendingGearMutationSequence[candidateID] ?? sequence,
                    actorID: actor, enemyID: enemy.id, seed: previewSeed,
                    currentGearID: currentID?.uuidString.lowercased(), candidateGearID: candidateID.uuidString.lowercased(),
                    baselineKind: "ACTUAL_UNCHANGED_CURRENT_SNAPSHOT_DEFAULT_CAMPAIGN",
                    baseline: baselineSummary, candidate: candidateSummary, decision: decision, snapshotUnchanged: afterPreview == beforePreview))
                pendingGearTrialIDs.remove(candidateID)
                pendingGearMutationDay.removeValue(forKey: candidateID)
                pendingGearMutationSequence.removeValue(forKey: candidateID)
                gearInstancesPreviewedAfterLatestChange.insert(candidateID)
                sequence += 1
                actions.append(Action(sequence: sequence, day: day, epoch: dayEnd,
                    operationID: "OBSERVATION_ONLY:gear-preview:\(candidateID.uuidString.lowercased()):\(previewSeed)",
                    command: "read_only_campaign_gear_preview", outcome: decision,
                    revisionBefore: state.revision, revisionAfter: state.revision, resourceDelta: [:],
                    campaignClears: state.completedEncounterIDs.sorted(),
                    selectedWorkTarget: state.partyWorkTargetR144.map { "\($0.kind.rawValue):\($0.targetID)" }, combatWon: candidateSummary.won))
                try journal(actions[actions.count - 1])
                if decision.hasPrefix("EQUIP:"), gearEquipsToday == 0 {
                    _ = try await record("equip_after_measured_preview_\(candidateID.uuidString.lowercased())",
                                         .equip(gearID: candidateID, actorID: actor), day: day, epoch: dayEnd)
                    equipped.append(candidateID.uuidString.lowercased())
                    gearEquipsToday += 1
                }
            }
            XCTAssertEqual(gearTrials.count - gearTrialsBeforeDay, gearInspectionSelectedCount,
                           "every selected eligible item must receive its preview; no filtered item may consume the quota")

            // The tutorial command follows a real same-slot preview. The factory's
            // initial five free tickets remain a baseline; later daily tickets come
            // from the actual Core dailyClaim command after this gate.
            state = await store.snapshot()
            if !state.gearComparisonSeen, let recipe = targetRecipe,
               let outputID = recipe.outputGearID,
               let output = state.gear.last(where: { $0.definitionID == outputID }),
               let outputDefinition = runtime.catalog.gear.first(where: { $0.id == outputID }),
               let comparable = initial.gear.first(where: { starter in
                   runtime.catalog.gear.first(where: { $0.id == starter.definitionID })?.slot == outputDefinition.slot
               }), gearTrials.contains(where: { $0.candidateGearID == output.id.uuidString.lowercased() && $0.baseline != nil }) {
                XCTAssertEqual(state.currency["ticket_free", default: 0], 5,
                               "fresh snapshot's five baseline tickets must remain untouched until the real comparison gate")
                _ = try await record("mark_real_same_slot_comparison_before_gacha_gate", .markGearComparisonSeen(
                    firstGearID: comparable.id, secondGearID: output.id), day: day, epoch: dayEnd)
                state = await store.snapshot()
                XCTAssertTrue(state.gearComparisonSeen)
                XCTAssertTrue(state.gachaUnlocked)
                XCTAssertEqual(state.currency["ticket_free", default: 0], 5,
                               "comparison unlocks gacha but does not fabricate or spend tickets")
            }

            state = await store.snapshot()
            if state.gachaUnlocked {
                if state.gachaPity.targetTemplateID == nil {
                    guard let firstPoolID = runtime.summonPoolIDs.first else {
                        throw CoreError.invalidCatalog("R098 ordered summon pool is empty")
                    }
                    _ = try await record("shared_first_gacha_target_selection_and_odds_preview_\(firstPoolID)",
                        .setGachaTarget(templateID: firstPoolID), day: day, epoch: dayEnd)
                    state = await store.snapshot()
                }
                _ = try await record("actual_engine_daily_claim_utc_day", .dailyClaim(now: Date(timeIntervalSince1970: TimeInterval(dayEnd))),
                                     day: day, epoch: dayEnd)
                didDailyClaim = true
                dailyClaims.append("day\(day):ENGINE_DAILY_CLAIM_UTC_CALENDAR")
                state = await store.snapshot()
                for productID in try treatment.dueProductIDs(cohort: cohort, day: day, gachaUnlocked: true) {
                    _ = try await applyScheduledSyntheticGrant(productID, day: day, epoch: dayEnd)
                    dayGrantProductIDs.append(productID)
                }
                dayFreeSummonDraws = try await summonAvailable("ticket_free", day: day, epoch: dayEnd)
                dayPaidSummonDraws = try await summonAvailable("ticket_paid_mock", day: day, epoch: dayEnd)
                totalFreeSummonDrawCount += dayFreeSummonDraws
                totalPaidSummonDrawCount += dayPaidSummonDraws
            } else {
                dailyClaims.append("day\(day):LOCKED_UNTIL_REAL_GEAR_COMPARISON_TUTORIAL")
            }

            let persistedBytes = try Data(contentsOf: saveURL)
            let persistedHash = Self.sha256(persistedBytes)
            let expectedSnapshot = await store.snapshot()
            store = try SaveRepository(fileURL: saveURL)
            engine = try integratedRuntime.makeEngine(saves: store, candidatePartyWorkPolicyR144: policy, firstCraftAidCapabilityR179: firstCraftCapability)
            let reopened = await store.snapshot()
            XCTAssertEqual(reopened, expectedSnapshot, "file-backed save must reopen to the exact pre-close state")
            XCTAssertNotNil(reopened.lastClaimAt, "each completed virtual day must have a settled work clock")
            XCTAssertNotNil(reopened.partyWorkTargetR144, "candidate work target must remain explicit in persisted save")
            let reopenedSaveBytes = try Data(contentsOf: saveURL)
            let reopenedSaveHash = Self.sha256(reopenedSaveBytes)
            XCTAssertEqual(reopenedSaveHash, persistedHash, "read-only reopen must preserve exact save bytes")
            let recoveryStatus = await store.recoveryStatus()
            XCTAssertFalse(recoveryStatus.recoveredPreviousGeneration,
                           "pilot checkpoints must not silently use a previous-generation rollback")
            let reopenedHash = Self.sha256(try encoder.encode(reopened))
            daily.append(Day(day: day, startEpoch: dayStart, endEpoch: dayEnd, revision: reopened.revision,
                             campaignClears: reopened.completedEncounterIDs.sorted(), unlockedRegions: reopened.unlockedRegionIDs.sorted(),
                             materials: reopened.materials, currency: reopened.currency,
                             gear: reopened.gear.map { item in
                                 GearRow(id: item.id.uuidString.lowercased(), templateID: item.definitionID,
                                         ownerID: item.ownerID,
                                         slot: runtime.catalog.gear.first(where: { $0.id == item.definitionID })?.slot,
                                         qualityID: item.qualityID, enhancement: item.enhancement, refinement: item.refinement,
                                         refinementRankR352: reopened.naturalGearRefinementR352?.rank(for: item.id) ?? 1,
                                         latentEffectID: item.latentEffectID, candidateLatentSlots: item.candidateLatentSlots,
                                         affixIDs: item.affixIDs, investmentDust: item.investmentDust)
                             },
                             workTarget: reopened.partyWorkTargetR144.map { "\($0.kind.rawValue):\($0.targetID)" },
                             completedResearchIDs: reopened.completedResearchIDs.sorted(),
                             challengeClearIDs: reopened.completedEncounterIDs.filter { $0.hasPrefix("CHALLENGE_CLEAR|") }.sorted(),
                             lastClaimEpoch: reopened.lastClaimAt.map { Int64($0.timeIntervalSince1970) },
                             remainderSeconds: reopened.offlineRemainderSeconds,
                             saveSHA256: persistedHash, saveSHA256AfterReopen: reopenedSaveHash,
                             reopenedSnapshotSHA256: reopenedHash, recoveryStatus: recoveryStatus,
                             didDailyClaim: didDailyClaim, freeSummonDraws: dayFreeSummonDraws,
                             paidSummonDraws: dayPaidSummonDraws, adOpportunitiesCreated: dayAdOpportunitiesCreated,
                             adCallbacksCompleted: dayAdCallbacksCompleted,
                             syntheticGrantProductIDs: dayGrantProductIDs,
                             gearTrialsPerformed: gearTrials.count - gearTrialsBeforeDay,
                             gearInspectionEligibleCount: gearInspectionEligibleCount,
                             gearInspectionSelectedCount: gearInspectionSelectedCount,
                             pendingGearTrialCount: pendingGearTrialIDs.count,
                             pendingGearTrialInstanceIDs: pendingGearTrialIDs.map { $0.uuidString.lowercased() }.sorted(),
                             naturalGearRollIndex: reopened.naturalGearDiscoveryR350?.naturalRollIndex ?? 0,
                             naturalGearWorkUnitsIntoDrop: reopened.naturalGearDiscoveryR350?.workUnitsIntoDrop ?? 0,
                             naturalGearAcquisitionRecords: reopened.naturalGearDiscoveryR350?.acquisitionRecords ?? [],
                             refinementRanksByUUID: (reopened.naturalGearRefinementR352?.ranksByUUID ?? [:]).mapKeys { $0.uuidString.lowercased() }))
            let dayReceipt = try encoder.encode(daily[daily.count - 1])
            try dayReceipt.write(to: runDirectory.appendingPathComponent(String(format: "DAY_%02d.json", day)), options: .atomic)
        }

        // Exercise R353 only when an actually acquired R350 instance is a legal
        // nonstarter duplicate. Otherwise preserve the cohort and report why no
        // dismantle transaction was available; never fabricate a duplicate.
        var naturalDuplicateSalvageOutcome = "UNAVAILABLE_NO_ELIGIBLE_NATURAL_DUPLICATE"
        let beforeSalvage = await store.snapshot()
        let acquiredIDs = Set((beforeSalvage.naturalGearDiscoveryR350?.acquisitionRecords ?? []).map(\.gearInstanceID))
        let starterIDs = Set(GearDismantleRefundPolicyR353.starterGearUUIDs.compactMap(UUID.init(uuidString:)))
        let eligibleSalvage = beforeSalvage.gear
            .filter { acquiredIDs.contains($0.id) && !starterIDs.contains($0.id) && !$0.protected && !beforeSalvage.equippedGearIDs.values.contains($0.id) }
            .filter { candidate in beforeSalvage.gear.filter { $0.definitionID == candidate.definitionID }.count > 1 }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
            .first
        if let salvage = eligibleSalvage {
            let expectedRefund = try integratedRuntime.refundPolicy.refundBreakdown(
                gearID: salvage.id, qualityID: salvage.qualityID, investmentDust: salvage.investmentDust)
            sequence += 1
            let dustBeforeSalvage = beforeSalvage.materials["refine_dust", default: 0]
            _ = try await record("dismantle_actual_natural_duplicate_\(salvage.id.uuidString.lowercased())",
                                 .dismantle(gearID: salvage.id), day: horizonDays,
                                 epoch: startEpoch + Int64(horizonDays) * 86_400)
            let afterSalvage = await store.snapshot()
            XCTAssertFalse(afterSalvage.gear.contains(where: { $0.id == salvage.id }))
            XCTAssertEqual(afterSalvage.materials["refine_dust", default: 0] - dustBeforeSalvage,
                           expectedRefund.totalDust, "real R353 transaction must match the policy and recorded dust delta")
            naturalDuplicateSalvageOutcome = "DISMANTLED_ACTUAL_NATURAL_DUPLICATE id=\(salvage.id.uuidString.lowercased()) template=\(salvage.definitionID) quality=\(salvage.qualityID) base=\(expectedRefund.baseSalvageDust) investment=\(expectedRefund.investmentRefundDust) total=\(expectedRefund.totalDust)"
        }
        let final = await store.snapshot()
        XCTAssertEqual(daily.count, horizonDays)
        XCTAssertEqual(clearedEnemyReplayAttempts, 0, "the pilot never replays cleared enemies for immediate farming")
        XCTAssertEqual(crafted.count, Set(crafted).count, "goal policy must not repeat a completed craft recipe")
        XCTAssertTrue(crafted.contains(FirstCraftCostProjectionR179.recipeID), "the real first-craft tutorial recipe must be completed")
        XCTAssertTrue(final.craftedGearOnce)
        XCTAssertTrue(final.gearComparisonSeen)
        XCTAssertTrue(final.gachaUnlocked)
        XCTAssertEqual(wins, 30, "all 30 campaign encounters must be cleared by actual engine commands")
        XCTAssertEqual(challengeWins, 15, "all 15 challenge encounters must be cleared by actual engine commands")
        XCTAssertEqual(final.unlockedRegionIDs.count, 5, "all five regions must be unlocked in the candidate snapshot")
        XCTAssertGreaterThan(evolved.count, 0, "ordinary recipe progression must evolve at least one owned item")
        XCTAssertGreaterThan(actions.filter { $0.command.hasPrefix("enhance_r352_rank") && $0.revisionAfter != nil }.count, 0, "ordinary progression must execute an enhancement")
        XCTAssertGreaterThan(actions.filter { $0.command.hasPrefix("refine_r352_equipped_") && $0.revisionAfter != nil }.count, 0, "ordinary progression must execute a refinement")
        XCTAssertGreaterThan(naturalGearInstanceIDsObserved.count, 0, "new natural items must be attributable to R350 acquisition records")
        XCTAssertEqual(totalFreeSummonDrawCount, 0, "R448 must not dispatch free mock summons")
        XCTAssertEqual(totalPaidSummonDrawCount, 0, "R448 must not dispatch paid mock summons")
        XCTAssertTrue(syntheticGrantReceipts.isEmpty, "R448 admits no synthetic product grants")
        XCTAssertEqual(actions.filter { $0.command.hasPrefix("actual_engine_summon_") }.count, 0, "no summon command may be dispatched")
        XCTAssertTrue(unclassifiedGearInstanceIDsObserved.isEmpty, "every added gear UUID must join to an actual craft receipt or natural acquisition record")
        let finalNewGearIDs = Set(final.gear.map(\.id)).subtracting(initialGearInstanceIDs)
        XCTAssertTrue(finalNewGearIDs.isSubset(of: craftedGearInstanceIDsObserved.union(naturalGearInstanceIDsObserved)), "all final non-starter gear must have a command or natural-ledger origin")
        XCTAssertEqual(evolved.count, Set(evolved).count, "goal policy must not repeat a completed evolution recipe")
        var endDigests = try digestSources(sourceRoot, paths: sourcePaths)
        endDigests["external/R355_PRODUCT_INPUTS.json"] = Self.sha256(try Data(contentsOf: URL(fileURLWithPath: productInputPath)))
        endDigests["external/R355_APP_RUNTIME_IDENTITY.json"] = Self.sha256(try Data(contentsOf: URL(fileURLWithPath: appIdentityPath)))
        XCTAssertEqual(digestsAtStart, endDigests, "pinned runtime and product inputs must not drift during pilot")

        XCTAssertEqual(horizonDays, 30, "R448 is one free_no_ad day-30 zero-summon pilot only")
        let challengeSeeds: [String: UInt64] = [
            "CH_R01_03": 34_601, "CH_R03_02": 34_602, "CH_R05_03": 34_603
        ]
        let currentWeaponKey = "C_WITCH|weapon"
        let equippedWeaponID = try XCTUnwrap(final.equippedGearIDs[currentWeaponKey])
        let equippedWeapon = try XCTUnwrap(final.gear.first(where: { $0.id == equippedWeaponID }))
        let equippedWeaponDefinition = try XCTUnwrap(runtime.catalog.gear.first(where: { $0.id == equippedWeapon.definitionID }))
        let occupiedGearIDs = Set(final.equippedGearIDs.values)
        let ownedAlternatives = final.gear.filter { item in
            guard item.id != equippedWeaponID, !occupiedGearIDs.contains(item.id),
                  item.ownerID == nil || item.ownerID == "C_WITCH",
                  let definition = runtime.catalog.gear.first(where: { $0.id == item.definitionID }) else { return false }
            return definition.slot == equippedWeaponDefinition.slot &&
                (definition.actorIDs.isEmpty || definition.actorIDs.contains("C_WITCH"))
        }.sorted {
            let leftRank = Self.r355InvestmentRank($0), rightRank = Self.r355InvestmentRank($1)
            if leftRank.quality != rightRank.quality { return leftRank.quality > rightRank.quality }
            if leftRank.enhancement != rightRank.enhancement { return leftRank.enhancement > rightRank.enhancement }
            if leftRank.refinement != rightRank.refinement { return leftRank.refinement > rightRank.refinement }
            if leftRank.investmentDust != rightRank.investmentDust { return leftRank.investmentDust > rightRank.investmentDust }
            return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
        }
        let alternativeWeapon = ownedAlternatives.first
        let loadoutIDs = ["actual_equipped", "first_highest_investment_compatible_owned_weapon"]
        var loadouts: [OwnedPartyLoadoutR181] = []
        if let alternativeWeapon {
            var alternativeGearMap = final.equippedGearIDs
            alternativeGearMap[currentWeaponKey] = alternativeWeapon.id
            loadouts = [
                OwnedPartyLoadoutR181(id: loadoutIDs[0], gearByActorSlot: final.equippedGearIDs),
                OwnedPartyLoadoutR181(id: loadoutIDs[1], gearByActorSlot: alternativeGearMap)
            ]
        }
        let saveBeforePreviews = try Data(contentsOf: saveURL)
        let snapshotBeforePreviews = await store.snapshot()
        var challengeOutcomes: [ChallengeOutcome] = []
        var unavailableChallengeOutcomes: [UnavailableOutcome] = []
        for challengeID in ["CH_R01_03", "CH_R03_02", "CH_R05_03"] {
            let combatSeed = try XCTUnwrap(challengeSeeds[challengeID])
            func unavailable(_ reason: String) {
                for id in loadoutIDs {
                    unavailableChallengeOutcomes.append(UnavailableOutcome(challengeID: challengeID,
                        combatSeed: combatSeed, loadoutID: id, reason: reason))
                }
            }
            guard alternativeWeapon != nil else {
                unavailable("PAIR_NOT_RUN_NO_COMPATIBLE_OWNED_ALTERNATIVE")
                continue
            }
            let previews: [OwnedPartyLoadoutPreviewR181]
            do {
                previews = try engine.previewChallengeOwnedPartyLoadoutsR181(
                    challengeID: challengeID, seed: combatSeed, snapshot: final, loadouts: loadouts)
            } catch OwnedPartyLoadoutPreviewErrorR181.challengeLocked {
                unavailable("CHALLENGE_GATE_NOT_REACHED_IN_THIS_COHORT")
                continue
            } catch OwnedPartyLoadoutPreviewErrorR181.unknownChallenge {
                unavailable("UNKNOWN_PREREGISTERED_CHALLENGE")
                continue
            }
            XCTAssertEqual(previews.map(\.loadoutID), ["actual_equipped", "first_highest_investment_compatible_owned_weapon"])
            for preview in previews {
                let gearRows = preview.gearByActorSlot.keys.sorted().compactMap { key -> GearRow? in
                    guard let id = preview.gearByActorSlot[key],
                          let item = final.gear.first(where: { $0.id == id }) else { return nil }
                    return GearRow(id: item.id.uuidString.lowercased(), templateID: item.definitionID,
                                   ownerID: item.ownerID,
                                   slot: runtime.catalog.gear.first(where: { $0.id == item.definitionID })?.slot,
                                   qualityID: item.qualityID, enhancement: item.enhancement,
                                   refinement: item.refinement,
                                   refinementRankR352: final.naturalGearRefinementR352?.rank(for: item.id) ?? 1,
                                   latentEffectID: item.latentEffectID,
                                   candidateLatentSlots: item.candidateLatentSlots,
                                   affixIDs: item.affixIDs, investmentDust: item.investmentDust)
                }
                XCTAssertEqual(gearRows.count, preview.gearByActorSlot.count)
                challengeOutcomes.append(ChallengeOutcome(
                    challengeID: challengeID, combatSeed: preview.seed, loadoutID: preview.loadoutID,
                    gear: gearRows, won: preview.result.won, ticks: preview.result.ticks,
                    initialPartyHP: preview.result.initialPartyHP,
                    remainingPartyHP: preview.result.remainingPartyHP,
                    downedPartyActorIDs: preview.result.remainingPartyHP.filter { $0.value <= 0 }.map(\.key).sorted(),
                    initialEnemyHP: preview.result.initialEnemyHP,
                    remainingEnemyHP: preview.result.remainingEnemyHP,
                    eventKindCounts: Dictionary(grouping: preview.result.events.map(\.kind), by: { $0 }).mapValues(\.count)))
            }
        }
        XCTAssertEqual(challengeOutcomes.count + unavailableChallengeOutcomes.count, 6)
        let snapshotAfterPreviews = await store.snapshot()
        XCTAssertEqual(snapshotAfterPreviews, snapshotBeforePreviews,
                       "R181 challenge previews must not mutate the persisted economy snapshot")
        XCTAssertEqual(try Data(contentsOf: saveURL), saveBeforePreviews,
                       "R355 no-reward previews must leave save bytes and receipts unchanged")
        let executable = Bundle(for: type(of: self)).executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let executableBytes = try Data(contentsOf: executable)
        let report = Report(schema: "economy-cohort-progress-r355-r002-v1", status: "RUNNER_FINISHED_XCTEST_RESULT_SEPARATE",
                            policyApprovalStatus: "UNAPPROVED_COMPARISON_ONLY",
                            caseID: caseID, runID: runID, cohortID: cohort.rawValue, seed: seed, days: horizonDays,
                            simulatedClock: "\(horizonDays) 24-hour virtual intervals; not real elapsed playtime; one persisted R144 target accrues per interval; engine 48-hour cap remains active",
                            runtimeProfileID: integratedRuntime.profileID, runtimeProfileVersion: candidateRuntime.base.profileVersion,
                            runtimeConfigurationFingerprint: integratedRuntime.configurationFingerprint,
                            runtimeManifestSHA256: Self.sha256(integratedRuntime.canonicalManifest),
                            naturalGearDiscoveryPolicyFingerprint: integratedRuntime.discoveryPolicy.policyFingerprint,
                            naturalGearRefinementPolicyFingerprint: integratedRuntime.refinementPolicy.policyFingerprint,
                            dismantleRefundPolicyFingerprint: integratedRuntime.refundPolicy.policyFingerprint,
                            naturalGearAcquisitionRecords: final.naturalGearDiscoveryR350?.acquisitionRecords ?? [],
                            refinementRanksByUUID: (final.naturalGearRefinementR352?.ranksByUUID ?? [:]).mapKeys { $0.uuidString.lowercased() },
                            baseRuntimeProfileID: runtime.profileID,
                            baseRuntimeConfigurationFingerprint: runtime.configurationFingerprint,
                            appRuntimeIdentitySHA256: appIdentitySHA,
                            partyWorkPolicyID: PartyWorkPolicyR144.policyID, partyWorkPolicyFingerprint: policy.policyFingerprint,
                            operationIDPolicy: "fixed per-case attempt namespace 44810000-<attempt>-4001-8000-<sequence>; case identity is separately preregistered",
                            gearUUIDPolicy: "ordinary GameRuntimeConfigurationR098.makeNewSnapshot plus engine-generated IDs; recorded per daily checkpoint",
                            gearInspectionPolicyID: GearTrialPlannerR199.policyID,
                            initialSnapshotSHA256: initialHash, sourceDigestsAtStart: digestsAtStart, sourceDigestsAtEnd: endDigests,
                            executablePath: executable.path, executableSHA256: Self.sha256(executableBytes),
                            actions: actions, daily: daily, gearTrials: gearTrials,
                            challengeOutcomes: challengeOutcomes, unavailableChallengeOutcomes: unavailableChallengeOutcomes,
                            firstCraftAidPolicyID: firstCraftCapability.policyID, firstCraftAidPolicyFingerprint: firstCraftCapability.policyFingerprint,
                            freshFirstCraftAidEligible: initial.firstCraftAidEligibleR179 == true, recipeGoalByDay: recipeGoalByDay,
                            campaignVictoryCount: wins, challengeVictoryCount: challengeWins,
                            challengeDefeatCount: challengeDefeats,
                            unresolvedCampaignEnemyIDs: runtime.catalog.enemies.filter { enemy in
                                runtime.catalog.regions.contains(where: { $0.enemyIDs.contains(enemy.id) }) &&
                                !final.completedEncounterIDs.contains(enemy.id)
                            }.map(\.id).sorted(),
                            unresolvedChallengeIDs: runtime.catalog.challenges.filter {
                                !final.completedEncounterIDs.contains("CHALLENGE_CLEAR|\($0.id)")
                            }.map(\.id).sorted(),
                            campaignDefeatCount: defeats,
                            clearedEnemyReplayAttempts: clearedEnemyReplayAttempts,
                            firstClearDayByEnemy: firstClearDay, firstClearDayByChallenge: firstChallengeClearDay,
                            completedResearchIDs: final.completedResearchIDs.sorted(),
                            unresolvedResearchIDs: runtime.catalog.research.filter {
                                !final.completedResearchIDs.contains($0.id)
                            }.map(\.id).sorted(),
                            unresolvedRecipeIDs: runtime.catalog.recipes.filter {
                                ($0.kind == "craft_new" && !crafted.contains($0.id)) ||
                                ($0.kind == "evolve_in_place" && !evolved.contains($0.id))
                            }.map(\.id).sorted(),
                            enhancementActionCount: actions.filter { $0.command.hasPrefix("enhance_r352_rank") && $0.revisionAfter != nil }.count,
                            refinementActionCount: actions.filter { $0.command.hasPrefix("refine_r352_equipped_") && $0.revisionAfter != nil }.count,
                            naturalDuplicateSalvageOutcome: naturalDuplicateSalvageOutcome,
                            craftedRecipeIDs: crafted, evolvedRecipeIDs: evolved,
                            equippedGearInstanceIDs: equipped, dailyClaimPolicyStatus: dailyClaims,
                            syntheticGrantReceipts: syntheticGrantReceipts, adEvents: adEvents,
                            adOpportunityCreatedCount: daily.reduce(0) { $0 + $1.adOpportunitiesCreated },
                            freeSummonDrawCount: totalFreeSummonDrawCount, paidSummonDrawCount: totalPaidSummonDrawCount,
                            gearInstancesAddedOrEvolvedDuringRun: gearInstancesAddedOrEvolved.map { $0.uuidString.lowercased() }.sorted(),
                            gearInstancesPreviewed: Array(Set(gearTrials.map(\.candidateGearID))).sorted(),
                            gearInstancesPreviewedAfterLatestChange: gearInstancesPreviewedAfterLatestChange.map { $0.uuidString.lowercased() }.sorted(),
                            pendingGearTrialInstanceIDs: pendingGearTrialIDs.map { $0.uuidString.lowercased() }.sorted(),
                            actionJournalSHA256: Self.sha256(try Data(contentsOf: journalURL)),
                            finalSaveSHA256: Self.sha256(try Data(contentsOf: saveURL)),
                            finalSnapshotSHA256: Self.sha256(try encoder.encode(final)),
                            limits: ["One scripted 30-day candidate pilot; not normal human play or retention evidence.",
                                     "R230/R144 App identity is verified as the base; R350/R352/R353 are a separate explicit unapproved test overlay with a distinct effective fingerprint.",
                                     "R350 acquisition, R352 UUID ranks/costed transitions, and R353 refund transactions are recorded separately; natural duplicate salvage is executed only for an actual eligible natural nonstarter duplicate, otherwise marked unavailable.",
                                     "R448 uses the free_no_ad treatment with zero synthetic ticket inputs and zero summons; this is a scripted Core pilot, not normal human-play evidence.",
                                     "Challenge outcomes use actual items in each final generated snapshot and R181 no-reward previews; no items are injected.",
                                     "Alternative ranking is deterministic within the archived generated inventory; engine-generated random UUIDs and UUID-based action tie breaks limit cross-run reproducibility. Paired economy seeds do not isolate a pure payment effect.",
                                     "Fresh first-craft eligibility, capability and projected recipe costs mirror the current R179 development App; no existing save is modified.",
                                     "Six preregistered outcome slots are each recorded as preview or explicit unavailability. Locked challenges are cohort observations, not fabricated losses.",
                                     "The paired equipment alternative is a high-investment compatible owned item, not an optimal build search.",
                                     "Event-kind counts are observations; this report does not infer item-level causality or sum healing/prevented damage.",
                                     "Battle seeds are fixed by preregistration and day/action sequence; no winning-seed search.",
                                     "No cleared encounter is replayed to farm first-clear rewards.",
                                     "Agent actions are policy decisions; engine receipts and persisted snapshots are game facts.",
                                     "Preview summaries are deterministic same-seed observations, not a universal gear score or proof of optimality.",
                                     "Current-loadout baseline includes empty slots unchanged; no fictitious gear instance.",
                                     "Distinct operation namespaces affect crafted latent rolls. Cross-run differences are not a pure policy-only causal estimate.",
                                     "R448 does not dispatch .mockSummon and asserts zero free/paid draws and zero synthetic grants; daily-claim behavior remains actual Core dispatch.",
                                     "The catalog recipe table is a candidate QA profile; this report does not adopt costs, cadence, or policy.",
                                     "The first deterministic summon target is selected after the real comparison tutorial for all arms; this is a common scripted odds/guarantee-preview proxy, not a recorded human screen view.",
                                     "Ad completions/skips use actual settled R144 opportunities and Core local-QA callback commands, not a provider or human ad view; callback wall timestamps come from the engine system clock.",
                                     "R144 single-target clock ties virtual daily gaps to work output; no per-login collection ceiling is invented."])
        let reportBytes = try encoder.encode(report)
        try reportBytes.write(to: reportURL, options: .atomic)
    }

    private func selectedTarget(snapshot: GameSnapshot, runtime: GameRuntimeConfigurationR098,
                                goalRecipe: RecipeDefinition?) throws -> PartyWorkTargetR144 {
        guard let regionID = snapshot.activeRegionID,
              let region = runtime.catalog.regions.first(where: { $0.id == regionID }) else {
            throw CoreError.invalidCommand("R355 requires a real active catalog region")
        }
        if let targetRecipe = goalRecipe {
            let missingInputs = targetRecipe.costs.keys.filter {
                snapshot.materials[$0, default: 0] < targetRecipe.costs[$0, default: 0]
            }.sorted()
            for missing in missingInputs {
                if runtime.catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: snapshot.unlockedRegionIDs,
                                                              completedEncounterIDs: snapshot.completedEncounterIDs).contains(missing) {
                    return .gather(missing)
                }
                if let cleared = region.enemyIDs.first(where: { enemyID in
                    snapshot.completedEncounterIDs.contains(enemyID) &&
                    runtime.catalog.enemies.first(where: { $0.id == enemyID })?.dropMaterialID == missing
                }) { return .investigate(cleared) }
            }
        }
        if let first = runtime.catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: snapshot.unlockedRegionIDs,
                                                                   completedEncounterIDs: snapshot.completedEncounterIDs).first {
            return .gather(first)
        }
        if let cleared = region.enemyIDs.first(where: { enemyID in
            snapshot.completedEncounterIDs.contains(enemyID) &&
            runtime.catalog.enemies.first(where: { $0.id == enemyID })?.dropMaterialID != nil
        }) {
            return .investigate(cleared)
        }
        throw CoreError.invalidCommand("no reachable gather or cleared-investigation target; pilot records a reachability stop")
    }

    /// Uses the R002 projection against this day's actual snapshot. Recipes whose
    /// output is already owned, gate is closed, parent is absent/incompatible, or
    /// deficits have no unlocked source are recorded and skipped; no inventory is
    /// inferred or fabricated. Catalog order and an explicit tracked recipe make the
    /// selection deterministic.
    private func firstReachableRecipePlan(runtime: GameRuntimeConfigurationR098,
                                          snapshot: GameSnapshot,
                                          researchReserve: [String: Int],
                                          completedRecipeIDs: Set<String>,
                                          firstCraftTutorialPending: Bool) throws
        -> (GlobalRecipeGoalPlannerR159.Plan?, [String]) {
        var ids: [String] = []
        if firstCraftTutorialPending { ids.append(FirstCraftCostProjectionR179.recipeID) }
        if let tracked = snapshot.trackedRecipeID, !ids.contains(tracked) { ids.append(tracked) }
        ids.append(contentsOf: runtime.catalog.recipes.map(\.id).sorted().filter { !ids.contains($0) })
        var rejected: [String] = []
        for id in ids where !completedRecipeIDs.contains(id) {
            do {
                if firstCraftTutorialPending, id == FirstCraftCostProjectionR179.recipeID {
                    // Planner-only candidate exception: fresh starters already own the
                    // tutorial output template. Keep live snapshot intact; let the same
                    // planner project legitimate input sources/costs for one distinct UUID.
                    guard let output = runtime.catalog.recipes.first(where: { $0.id == id })?.outputGearID else {
                        throw CoreError.invalidCatalog("R179 tutorial recipe has no output")
                    }
                    var plannerSnapshot = snapshot
                    plannerSnapshot.gear.removeAll(where: { $0.definitionID == output })
                    let plan = try GlobalRecipeGoalPlannerR159.makePlan(requestedRecipeID: id,
                        catalog: runtime.catalog, snapshot: plannerSnapshot, researchReserve: [:])
                    return (plan, rejected)
                }
                let plan = try GlobalRecipeGoalPlannerR159.makePlan(requestedRecipeID: id,
                    catalog: runtime.catalog, snapshot: snapshot, researchReserve: researchReserve)
                return (plan, rejected)
            } catch let failure as GlobalRecipeGoalPlannerR159.Failure {
                switch failure {
                case .unknownRecipe, .closedGate, .unavailableOutput, .noParent,
                     .missingMaterialSource, .outputAlreadyOwned:
                    rejected.append("\(id):\(failure)")
                case .unknownResearch(let researchID):
                    rejected.append("\(id):unknownResearch(\(researchID))")
                case .insufficientSourceForMaterial, .invalidMaterialAmount, .invalidReserve:
                    throw failure
                }
            }
        }
        return (nil, rejected)
    }

    private func recipeGateIsOpen(_ recipe: RecipeDefinition, snapshot: GameSnapshot) -> Bool {
        guard let gate = recipe.gateID else { return true }
        return gateIsOpen(gate, snapshot: snapshot)
    }

    private func gateIsOpen(_ gate: String, snapshot: GameSnapshot) -> Bool {
        guard gate != "G_START" else { return true }
        let parts = gate.split(separator: "_")
        guard parts.count == 3 else { return false }
        return snapshot.completedEncounterIDs.contains("B_\(parts[1])_\(parts[2])")
    }

    /// Aggregate the unchanged-loadout result without inventing a gear UUID.
    private static func currentLoadoutSummary(result: CombatResult, actorID: String) -> GearSwapCombatSummaryR131 {
        func counts(_ events: [CombatEvent]) -> [String: Int] {
            Dictionary(grouping: events.map(\.kind), by: { $0 }).mapValues(\.count)
        }
        return GearSwapCombatSummaryR131(won: result.won, ticks: result.ticks,
            initialPartyHP: result.initialPartyHP, remainingPartyHP: result.remainingPartyHP,
            downedPartyActorIDs: result.remainingPartyHP.filter { $0.value <= 0 }.map(\.key).sorted(),
            initialEnemyHP: result.initialEnemyHP, remainingEnemyHP: result.remainingEnemyHP,
            eventKindCounts: counts(result.events),
            selectedActorSourceEventKindCounts: counts(result.events.filter { $0.sourceID == actorID }),
            selectedActorTargetEventKindCounts: counts(result.events.filter { $0.targetID == actorID }),
            eventAttribution: "OBSERVED_EVENTS_ONLY_NO_GEAR_CAUSALITY")
    }

    private func digestSources(_ root: URL, paths: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for path in paths {
            let url = root.appendingPathComponent(path)
            result[path] = Self.sha256(try Data(contentsOf: url))
        }
        return result
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func r355InvestmentRank(_ item: GearInstance) -> (quality: Int, enhancement: Int, refinement: Int, investmentDust: Int) {
        let quality = ["Q0": 0, "Q1": 1, "Q2": 2, "Q3": 3, "Q4": 4][item.qualityID] ?? -1
        return (quality, item.enhancement, item.refinement, item.investmentDust)
    }
}

private extension Dictionary where Key == UUID {
    func mapKeys<T: Hashable>(_ transform: (UUID) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
