import Foundation
import CryptoKit

/// Simulator-only candidate QA, separate from committed campaign combat.
/// Every case calls R6TimelineSimulator directly and then exercises SpriteKit playback.
/// It never dispatches a GameEngine command, grants rewards, or changes campaign data.
extension GameModel {
    private struct MultiEnemyPreviewCase {
        let result: CombatResult
        let enemyIDs: [String]
        let expectedRegionID: String
        let caseID: String
        let compareResult: CombatResult?
        let legacyFixtureResult: CombatResult?
        let metadataCorrectionsApplied: [String]
    }

    func runMultiEnemyMechanicPreviewIfRequested() {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"),
              let option = args.first(where: { $0.hasPrefix("--qa-effect-multi-preview=") }),
              let saveURL, saveURL.lastPathComponent.hasPrefix("qa-"),
              let catalog else { return }
        let requested = String(option.dropFirst("--qa-effect-multi-preview=".count))
        guard ["E02_MAGIC_SUPPORT", "E04_FOLLOWUP", "E03_PINCER_FRONT", "E03_PINCER_BEHIND"].contains(requested),
              FileManager.default.fileExists(atPath: saveURL.path) else { return }

        Task { @MainActor in
            do {
                let previewStartedAt = Date()
                let before = try Data(contentsOf: saveURL)
                let revisionBefore = state.revision
                let fixture = try Self.makeMultiEnemyPreviewCase(requested)

                // Derive the scene region from the actual fixture entities. Refuse a
                // mixed-region fixture rather than silently choosing a hard-coded backdrop.
                let resolvedEnemyRegions = fixture.enemyIDs.compactMap { enemyID in
                    catalog.enemies.first(where: { $0.id == enemyID })?.regionID
                }
                let resolvedRegions = Set(resolvedEnemyRegions)
                guard resolvedEnemyRegions.count == fixture.enemyIDs.count,
                      resolvedRegions == [fixture.expectedRegionID] else {
                    throw CoreError.invalidCommand("Preview fixture has a missing or mixed region mapping")
                }

                let hpURL = saveURL.deletingLastPathComponent().appendingPathComponent("last_presentation_hp.json")
                let hpReceiptBefore = try? Data(contentsOf: hpURL)
                let hpModifiedBefore = (try? FileManager.default.attributesOfItem(atPath: hpURL.path)[.modificationDate]) as? Date
                chosenRegion = fixture.expectedRegionID
                tab = "探索"
                fighting = true
                notice = "候補戦闘演出の読み取り専用プレビュー"
                syncScene()
                scene.setEnemies(fixture.enemyIDs)
                await play(fixture.result)

                let after = try Data(contentsOf: saveURL)
                let beforeHash = Self.sha256(before)
                let afterHash = Self.sha256(after)
                let artwork = try JSONSerialization.jsonObject(with: Data(scene.artAuditJSON().utf8))
                let hpReceiptAfter = try? Data(contentsOf: hpURL)
                let hpReceipt = hpReceiptAfter.flatMap { try? JSONSerialization.jsonObject(with: $0) }
                let hpReceiptObject = hpReceipt as? [String: Any]
                let hpReceiptDate = (hpReceiptObject?["date"] as? String).flatMap(ISO8601DateFormatter().date(from:))
                let hpModifiedAfter = (try? FileManager.default.attributesOfItem(atPath: hpURL.path)[.modificationDate]) as? Date
                let previewStartSecond = Date(timeIntervalSince1970: floor(previewStartedAt.timeIntervalSince1970))
                let hpReceiptFresh = hpReceiptObject?["kind"] as? String == "presentation_hp" &&
                    (hpReceiptDate.map { $0 >= previewStartSecond } ?? false) &&
                    (hpModifiedAfter.map { $0 >= previewStartedAt } ?? false) &&
                    (hpModifiedBefore == nil || hpModifiedBefore != hpModifiedAfter)
                let events = fixture.result.events.map { event -> [String: Any] in
                    ["kind": event.kind, "sourceID": event.sourceID, "targetID": event.targetID,
                     "amount": event.amount, "timestampMs": event.timestampMs ?? -1,
                     "rootActionID": event.rootActionID ?? ""]
                }
                let contract = Self.contractAudit(fixture.result, fixture.compareResult, caseID: requested)
                let effectTrace = ((artwork as? [String: Any])?["effects"] as? [String: Any])?["cueTrace"] as? [[String: Any]] ?? []
                let effectID: String
                let expectedTraceRoots: Set<String>
                let expectedDisplayTargets: Set<String>
                let expectedRows: Set<String>
                switch requested {
                case "E02_MAGIC_SUPPORT":
                    let support = fixture.result.events.first { $0.kind == "enemy_magic_support" }
                    expectedTraceRoots = Set(support?.rootActionID.map { [$0] } ?? [])
                    expectedDisplayTargets = ["ACT_E_R02_03"]
                    expectedRows = ["cue_placement", "impact_placement"]
                    effectID = "ACT_E_R02_04_support_arc"
                case "E04_FOLLOWUP":
                    let rawTarget = fixture.result.events.first {
                        $0.kind == "enemy_hit" && $0.sourceID == "E_R04_01"
                    }?.targetID ?? ""
                    let followupRoot = fixture.result.events.first {
                        $0.kind == "enemy_hit" && $0.sourceID == "E_R04_01"
                    }?.rootActionID
                    expectedTraceRoots = Set(followupRoot.map { [$0] } ?? [])
                    expectedDisplayTargets = rawTarget.isEmpty ? [] : [GameModel.spriteIDs[rawTarget] ?? "ACT_" + rawTarget]
                    expectedRows = ["cue_placement", "impact_placement"]
                    effectID = "ACT_E_R04_01_pursuit"
                default:
                    let selectedFront = requested == "E03_PINCER_FRONT"
                    let matchingEvents = fixture.result.events.filter {
                        selectedFront ? $0.kind == "enemy_armor" && $0.sourceID == "E_R03_01"
                                      : $0.kind == "enemy_hit" && $0.sourceID == "E_R03_01"
                    }
                    expectedTraceRoots = Set(matchingEvents.compactMap(\.rootActionID))
                    expectedDisplayTargets = ["ACT_E_R03_01"]
                    expectedRows = selectedFront
                        ? ["direct_full:enemy_armor", "coalesced:enemy_armor"]
                        : ["cue_placement", "impact_placement"]
                    effectID = "ACT_E_R03_01_pincer_guard"
                }
                let renderedRows = effectTrace.filter {
                    $0["effectID"] as? String == effectID &&
                    expectedRows.contains($0["step"] as? String ?? "")
                }
                let tracedRoots = Set(renderedRows.compactMap { $0["rootActionID"] as? String })
                let exactTraceCoverage = tracedRoots == expectedTraceRoots && !expectedTraceRoots.isEmpty
                let exactTargetSet = renderedRows.allSatisfy {
                    let targets = Set(($0["targetIDs"] as? String ?? "").split(separator: ",").map(String.init))
                    if requested == "E03_PINCER_BEHIND" {
                        let root = $0["rootActionID"] as? String
                        let hitTargets = fixture.result.events.filter {
                            $0.kind == "enemy_hit" && $0.sourceID == "E_R03_01" && $0.rootActionID == root
                        }.map { GameModel.spriteIDs[$0.targetID] ?? "ACT_" + $0.targetID }
                        return !hitTargets.isEmpty && targets == Set(hitTargets)
                    }
                    return targets == expectedDisplayTargets
                }
                let finitePlacementForEveryRow = !renderedRows.isEmpty && renderedRows.allSatisfy { row in
                    ["placement.cueX", "placement.cueY", "placement.impactX", "placement.impactY",
                     "placement.rotation", "placement.scaleX"].allSatisfy { key in
                        guard let raw = row[key] as? String, let value = Double(raw) else { return false }
                        return value.isFinite
                    } && row["placement.sourceAnchor"] != nil && row["placement.targetAnchor"] != nil
                }
                let everyRootHasRequiredPhase = expectedTraceRoots.allSatisfy { root in
                    let steps = Set(renderedRows.filter { ($0["rootActionID"] as? String) == root }
                        .compactMap { $0["step"] as? String })
                    return requested == "E03_PINCER_FRONT"
                        ? !steps.intersection(expectedRows).isEmpty : expectedRows.isSubset(of: steps)
                }
                let artChecks = [
                    "everyRootHasRequiredPresentationPhase": everyRootHasRequiredPhase,
                    "allExpectedRootsHaveTraceRows": exactTraceCoverage,
                    "everyTraceRowHasExactDisplayTargetSet": exactTargetSet,
                    "everyTraceRowHasFinitePlacement": finitePlacementForEveryRow,
                    "behindHasNoArmorVisual": requested != "E03_PINCER_BEHIND" ||
                        !effectTrace.contains { ($0["effectID"] as? String) == effectID &&
                            ["direct_full:enemy_armor", "coalesced:enemy_armor"].contains($0["step"] as? String ?? "") }
                ]
                let artAudit = artwork as? [String: Any] ?? [:]
                let stateAudit = artAudit["states"] as? [String: Any] ?? [:]
                let actorIDs = Set(artAudit["actorIDs"] as? [String] ?? [])
                let geometry = artAudit["geometry"] as? [String: [String: Any]] ?? [:]
                // load_ACT_* is written only on failure, so absence is not a
                // success signal. Require independent actor listing, actual
                // battle-entry render state, and finite positive node geometry.
                let actorLoadChecks = fixture.enemyIDs.allSatisfy { enemyID in
                    let displayID = Self.spriteIDs[enemyID] ?? "ACT_" + enemyID
                    guard actorIDs.contains(displayID),
                          stateAudit[displayID + ":battle_entry_walk"] as? Bool == true,
                          stateAudit["load_" + displayID] as? Bool != false,
                          let node = geometry[displayID],
                          let width = node["width"] as? Double,
                          let height = node["height"] as? Double else { return false }
                    return width.isFinite && height.isFinite && width > 0 && height > 0
                }
                let hpValue = (hpReceipt as? [String: Any])?["value"] as? String
                let hpMismatchData = hpValue?.data(using: .utf8)
                let hpMismatches = hpMismatchData.flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: [Int]]
                }
                let saveUnchanged = before == after && revisionBefore == state.revision
                let legacyEventStreamUnchanged = fixture.legacyFixtureResult.map {
                    Self.eventSignature($0) == Self.eventSignature(fixture.result)
                } ?? true
                let previewPass = saveUnchanged && hpReceiptFresh &&
                    hpReceipt != nil && hpMismatches?.isEmpty == true &&
                    contract.values.allSatisfy { $0 } && artChecks.values.allSatisfy { $0 } &&
                    actorLoadChecks && legacyEventStreamUnchanged
                let report: [String: Any] = [
                    "status": previewPass ? "NO_REWARD_SIMULATION_PREVIEW_PASS" : "NO_REWARD_SIMULATION_PREVIEW_FAIL",
                    "scope": "R6_TIMELINE_AND_SPRITEKIT_PREVIEW_ONLY; NO_ENGINE_COMMAND_OR_REWARD",
                    "authority": "UNAPPROVED_TEST_OVERLAY; NOT CAMPAIGN INPUT OR DESIGN APPROVAL",
                    "caseID": fixture.caseID,
                    "fixtureEnemyIDs": fixture.enemyIDs,
                    "fixtureRegionIDs": Array(resolvedRegions).sorted(),
                    "campaignDirectionInputImplemented": false,
                    "metadataCorrectionsApplied": fixture.metadataCorrectionsApplied,
                    "legacyFixtureEventStreamUnchanged": legacyEventStreamUnchanged,
                    "legacyFixturePresentation": fixture.legacyFixtureResult.map {
                        $0.entityPresentation.mapValues { ["label": $0.label, "assetKey": $0.assetKey ?? ""] }
                    } as Any? ?? NSNull(),
                    "revisionBefore": revisionBefore,
                    "revisionAfter": state.revision,
                    "saveSHA256Before": beforeHash,
                    "saveSHA256After": afterHash,
                    "saveBytesUnchanged": saveUnchanged,
                    "saveReadbackAvailable": true,
                    "hpReceiptBytesChangedDuringPlayback": hpReceiptBefore != hpReceiptAfter,
                    "hpReceiptModificationTimeBefore": hpModifiedBefore.map { $0.timeIntervalSince1970 } as Any? ?? NSNull(),
                    "hpReceiptModificationTimeAfter": hpModifiedAfter.map { $0.timeIntervalSince1970 } as Any? ?? NSNull(),
                    "hpReceiptFreshAndCorrectKind": hpReceiptFresh,
                    "hpMismatchesEmpty": hpReceipt != nil && hpMismatches?.isEmpty == true,
                    "contractAssertions": contract,
                    "artAssertions": artChecks,
                    "allFixtureActorsLoaded": actorLoadChecks,
                    "hpPresentationReceipt": hpReceipt as Any? ?? NSNull(),
                    "result": ["won": fixture.result.won,
                               "remainingPartyHP": fixture.result.remainingPartyHP,
                               "remainingEnemyHP": fixture.result.remainingEnemyHP,
                               "events": events,
                               "entityPresentation": fixture.result.entityPresentation.mapValues {
                                   ["entityID": $0.entityID, "catalogID": $0.catalogID ?? "",
                                    "label": $0.label, "assetKey": $0.assetKey ?? ""]
                               }],
                    "artAudit": artwork,
                    "comparison": Self.pincerComparison(fixture.result, fixture.compareResult, side: requested)
                ]
                let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                writeReceipt("effect_multi_preview", String(data: bytes, encoding: .utf8) ?? "ENCODING_FAILED")
                fighting = false
            } catch {
                writeReceipt("effect_multi_preview_error", String(reflecting: error))
                self.error = "候補戦闘演出の検証に失敗しました。"
                fighting = false
            }
        }
        #endif
    }

    private static func makeMultiEnemyPreviewCase(_ requested: String) throws -> MultiEnemyPreviewCase {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 20_000, attack: 1, defense: 0)
        }
        switch requested {
        case "E02_MAGIC_SUPPORT":
            let enemies = [
                Combatant(id: "E_R02_04", maxHP: 100_000, attack: 80, defense: 0,
                          actionPattern: "magicSupport", firstTelegraphMs: 1_500),
                Combatant(id: "E_R02_03", maxHP: 100_000, attack: 80, defense: 0,
                          actionPattern: "standard", firstTelegraphMs: 12_000)
            ]
            let labels = ["E_R02_04": "月灯蛾", "E_R02_03": "水鏡くらげ"]
            let presentation = Dictionary(uniqueKeysWithValues: labels.map { id, label in
                (id, CombatEntityPresentation(entityID: id, kind: "enemy", catalogID: id,
                                              label: label, assetKey: "ACT_" + id))
            })
            let result = try R6TimelineSimulator.run(party: party, enemies: enemies, seed: 1_804,
                maxDurationMs: 5_000, entityPresentation: presentation)
            return .init(result: result, enemyIDs: ["E_R02_04", "E_R02_03"], expectedRegionID: "R02",
                         caseID: requested, compareResult: nil, legacyFixtureResult: nil, metadataCorrectionsApplied: [])

        case "E04_FOLLOWUP":
            let trigger = Combatant(id: "E_R04_04", maxHP: 100_000, attack: 80, defense: 0,
                                    actionPattern: "multiHit", firstTelegraphMs: 0)
            let follower = Combatant(id: "E_R04_01", maxHP: 100_000, attack: 80, defense: 0,
                                     actionPattern: "allyFollowup", firstTelegraphMs: 7_000)
            // Use canonical catalog labels and actor base IDs. The existing fixture's
            // follower assetKey is an effect ID; its trigger label incorrectly calls
            // E_R04_04 an owl. This draft fixes presentation metadata only.
            let presentation = [
                "E_R04_04": CombatEntityPresentation(entityID: "E_R04_04", kind: "enemy",
                    catalogID: "E_R04_04", label: "霜晶の削り偶", assetKey: "ACT_E_R04_04"),
                "E_R04_01": CombatEntityPresentation(entityID: "E_R04_01", kind: "enemy",
                    catalogID: "E_R04_01", label: "霜毛おおかみ", assetKey: "ACT_E_R04_01")
            ]
            let result = try R6TimelineSimulator.run(party: party, enemies: [trigger, follower], seed: 814,
                maxDurationMs: 4_000, entityPresentation: presentation)
            let legacy = try EnemyActionPreviewFixture.allyFollowup(seed: 814, maxDurationMs: 4_000)
            return .init(result: result, enemyIDs: ["E_R04_04", "E_R04_01"], expectedRegionID: "R04",
                         caseID: requested, compareResult: nil, legacyFixtureResult: legacy,
                         metadataCorrectionsApplied: ["E_R04_04 label corrected to catalog",
                                                      "E_R04_01 assetKey uses actor base ID"])

        case "E03_PINCER_FRONT", "E03_PINCER_BEHIND":
            let side: CandidateAttackSide = requested == "E03_PINCER_FRONT" ? .front : .flank
            let counterpart: CandidateAttackSide = side == .front ? .flank : .front
            func run(_ attackSide: CandidateAttackSide) throws -> CombatResult {
                let orientedParty = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
                    Combatant(id: $0, maxHP: 20_000, attack: 1_000, defense: 0,
                              candidateAttackSide: attackSide)
                }
                let enemy = Combatant(id: "E_R03_01", maxHP: 100_000, attack: 100, defense: 0,
                                      actionPattern: "armor", firstTelegraphMs: 0)
                let presentation = ["E_R03_01": CombatEntityPresentation(entityID: "E_R03_01", kind: "enemy",
                    catalogID: "E_R03_01", label: "銅殻やどかり", assetKey: "ACT_E_R03_01")]
                return try R6TimelineSimulator.run(party: orientedParty, enemies: [enemy], seed: 1_303,
                    maxDurationMs: 12_000, entityPresentation: presentation)
            }
            // `flank` is the Core enum value; in this QA caption it is the rear/behind
            // comparison. This is simulator fixture input, not a campaign formation option.
            let result = try run(side)
            let other = try run(counterpart)
            let legacy = try EnemyActionPreviewFixture.pincerOrientation(side: side, seed: 1_303, maxDurationMs: 12_000)
            return .init(result: result, enemyIDs: ["E_R03_01"], expectedRegionID: "R03",
                         caseID: requested, compareResult: other, legacyFixtureResult: legacy,
                         metadataCorrectionsApplied: ["E_R03_01 assetKey uses actor base ID",
                                                      "BEHIND is caption for Core .flank"])

        default:
            throw CoreError.invalidCommand("Unsupported multi-enemy preview case")
        }
    }

    private static func pincerComparison(_ primary: CombatResult, _ other: CombatResult?, side: String) -> [String: Any] {
        guard let other else { return ["applicable": false] }
        func direct(_ result: CombatResult) -> [[String: Any]] {
            result.events.filter { $0.kind == "direct" && $0.targetID == "E_R03_01" }.map {
                ["root": $0.rootActionID ?? "", "timestampMs": $0.timestampMs ?? -1,
                 "actor": $0.sourceID, "amount": $0.amount]
            }
        }
        func armor(_ result: CombatResult) -> [[String: Any]] {
            result.events.filter { $0.kind == "enemy_armor" }.map {
                ["root": $0.rootActionID ?? "", "timestampMs": $0.timestampMs ?? -1,
                 "source": $0.sourceID, "target": $0.targetID, "prevented": $0.amount]
            }
        }
        return ["applicable": true, "selectedSide": side,
                "campaignInputImplemented": false,
                "selectedDirectEvents": direct(primary), "counterpartDirectEvents": direct(other),
                "selectedArmorEvents": armor(primary), "counterpartArmorEvents": armor(other),
                "directRootScheduleMatches": direct(primary).map { $0["root"] as? String } == direct(other).map { $0["root"] as? String }]
    }

    private static func contractAudit(_ primary: CombatResult, _ other: CombatResult?, caseID: String) -> [String: Bool] {
        switch caseID {
        case "E02_MAGIC_SUPPORT":
            let tells = primary.events.filter { $0.kind == "enemy_telegraph" && $0.sourceID == "E_R02_04" }
            let supports = primary.events.filter { $0.kind == "enemy_magic_support" && $0.sourceID == "E_R02_04" }
            return [
                "oneSupportEvent": supports.count == 1,
                "supportRecipientIsAdjacentEnemy": supports.first?.targetID == "E_R02_03",
                "supportAmountMatchesCandidate": supports.first?.amount == 1_500,
                "oneSupportWithinFiveSecondHorizon": supports.count == 1 && supports.first?.timestampMs == 2_500,
                "supportSharesTellRoot": supports.first?.rootActionID != nil &&
                    supports.first?.rootActionID == tells.first?.rootActionID,
                "noDamageSubstitutedForSupport": !primary.events.contains {
                    $0.kind == "enemy_hit" && $0.sourceID == "E_R02_04"
                },
                "presentationUsesBaseAssetKeys": primary.entityPresentation["E_R02_04"]?.assetKey == "ACT_E_R02_04" &&
                    primary.entityPresentation["E_R02_03"]?.assetKey == "ACT_E_R02_03"
            ]
        case "E04_FOLLOWUP":
            let triggerHits = primary.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R04_04" }
            let followupMarks = primary.events.filter { $0.kind == "enemy_followup" && $0.sourceID == "E_R04_01" }
            let followupHits = primary.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R04_01" }
            let triggerRoot = triggerHits.first?.rootActionID
            let markRoot = followupMarks.first?.rootActionID
            let triggerTarget = triggerHits.first?.targetID
            return [
                "threeTriggerHitsOneRoot": triggerHits.count == 3 && triggerRoot != nil &&
                    Set(triggerHits.compactMap(\.rootActionID)).count == 1,
                "oneFollowupMark": followupMarks.count == 1 && markRoot != nil,
                "oneFollowupImpact": followupHits.count == 1,
                "followerImpactUsesFollowupRoot": followupHits.first?.rootActionID == markRoot &&
                    markRoot?.contains("followup") == true && markRoot != triggerRoot,
                "followerKeepsOriginalVictim": followupHits.first?.targetID == triggerTarget,
                "followupImpactIs350msAfterMark": {
                    guard let hitTime = followupHits.first?.timestampMs,
                          let markTime = followupMarks.first?.timestampMs else { return false }
                    return hitTime - markTime == 350
                }(),
                "noFollowupChain": !primary.events.contains {
                    $0.kind == "enemy_followup" && $0.sourceID == "E_R04_04"
                },
                "presentationMetadataCorrected": primary.entityPresentation["E_R04_04"]?.label == "霜晶の削り偶" &&
                    primary.entityPresentation["E_R04_04"]?.assetKey == "ACT_E_R04_04" &&
                    primary.entityPresentation["E_R04_01"]?.assetKey == "ACT_E_R04_01"
            ]
        case "E03_PINCER_FRONT", "E03_PINCER_BEHIND":
            guard let other else { return ["counterpartRunAvailable": false] }
            let selectedFront = caseID == "E03_PINCER_FRONT"
            let primaryArmor = primary.events.filter { $0.kind == "enemy_armor" && $0.sourceID == "E_R03_01" }
            let otherArmor = other.events.filter { $0.kind == "enemy_armor" && $0.sourceID == "E_R03_01" }
            let frontArmor = selectedFront ? primaryArmor : otherArmor
            let behindArmor = selectedFront ? otherArmor : primaryArmor
            let frontDirect = (selectedFront ? primary : other).events.filter { $0.kind == "direct" && $0.targetID == "E_R03_01" }
            let behindDirect = (selectedFront ? other : primary).events.filter { $0.kind == "direct" && $0.targetID == "E_R03_01" }
            let frontByActorAndRoot = Dictionary(uniqueKeysWithValues: frontDirect.compactMap { event in
                event.rootActionID.map { (event.sourceID + "|" + $0, event.amount) }
            })
            let behindByActorAndRoot = Dictionary(uniqueKeysWithValues: behindDirect.compactMap { event in
                event.rootActionID.map { (event.sourceID + "|" + $0, event.amount) }
            })
            let pairedRoots = Set(frontByActorAndRoot.keys).intersection(behindByActorAndRoot.keys)
            let armorRoots = Set(frontArmor.compactMap(\.rootActionID))
            let reducedRoots = pairedRoots.filter { key in
                guard let root = key.split(separator: "|", maxSplits: 1).last else { return false }
                return armorRoots.contains(String(root))
            }
            let unarmoredRoots = pairedRoots.subtracting(reducedRoots)
            return [
                "frontHasPositiveEnemyArmor": !frontArmor.isEmpty && frontArmor.allSatisfy { $0.amount > 0 && $0.targetID.hasPrefix("C_") },
                "behindHasNoArmor": behindArmor.isEmpty,
                "bothSidesHaveDirectAttacks": !frontDirect.isEmpty && !behindDirect.isEmpty,
                "frontDamageReducedOnlyOnArmoredRoots": !reducedRoots.isEmpty &&
                    reducedRoots.allSatisfy { (frontByActorAndRoot[$0] ?? Int.max) < (behindByActorAndRoot[$0] ?? Int.min) },
                "unarmoredWindowDamageUnchanged": !unarmoredRoots.isEmpty &&
                    unarmoredRoots.allSatisfy { frontByActorAndRoot[$0] == behindByActorAndRoot[$0] },
                "sameSeedActorAndRootSchedule": frontDirect.map { "\($0.sourceID)|\($0.rootActionID ?? "")|\($0.timestampMs ?? -1)" } ==
                    behindDirect.map { "\($0.sourceID)|\($0.rootActionID ?? "")|\($0.timestampMs ?? -1)" },
                "campaignDirectionStillUnsupported": true,
                "presentationUsesBaseAssetKey": primary.entityPresentation["E_R03_01"]?.assetKey == "ACT_E_R03_01"
            ]
        default:
            return ["knownCase": false]
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func eventSignature(_ result: CombatResult) -> [[String: String]] {
        result.events.map {
            ["kind": $0.kind, "source": $0.sourceID, "target": $0.targetID,
             "amount": String($0.amount), "time": String($0.timestampMs ?? -1),
             "root": $0.rootActionID ?? ""]
        }
    }
}
