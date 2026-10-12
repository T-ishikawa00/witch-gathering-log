import Foundation
import CryptoKit

/// No-reward, read-only presentation probe for candidate mechanics that require multiple enemies.
extension GameModel {
    func runEffectMechanicPreviewIfRequested() {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let requested = arguments.first(where: { $0.hasPrefix("--qa-effect-mechanic-preview=") })?
            .replacingOccurrences(of: "--qa-effect-mechanic-preview=", with: "")
        guard arguments.contains("--qa-isolated"),
              let requested,
              ["E03_MAGNET", "E03_MAGNET_INTERRUPT", "E01_ARMOR", "E05_TRANSFER", "E05_GUARD", "E05_DURATION", "E05_POISON", "B02_DREAM", "B02_MIRROR", "B03_HAMMER", "B03_HEAT", "B04_BREATH", "B05_PRUNING", "B05_DEER"].contains(requested),
              let saveURL, saveURL.lastPathComponent.hasPrefix("qa-") else { return }

        Task { @MainActor in
            let began = ISO8601DateFormatter().string(from: Date())
            let savedBefore = try? Data(contentsOf: saveURL)
            let saveSHA256Before = savedBefore.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
            let revisionBefore = state.revision
            do {
                let battle: CombatResult
                var armorBaselineOutgoing: [CombatEvent] = []
                let fixtureEnemyIDs: [String]
                let fixtureFunction: String
                switch requested {
                case "E03_MAGNET":
                    battle = try EnemyActionPreviewFixture.magnetMarkStrike(); fixtureEnemyIDs = ["E_R03_04"]; fixtureFunction = "magnetMarkStrike"
                case "E03_MAGNET_INTERRUPT":
                    battle = try EnemyActionPreviewFixture.magnetMarkStrikeInterrupted(); fixtureEnemyIDs = ["E_R03_04"]; fixtureFunction = "magnetMarkStrikeInterrupted"
                case "E01_ARMOR":
                    battle = try EnemyActionPreviewFixture.armorDefense(); fixtureEnemyIDs = ["E_R01_04"]; fixtureFunction = "armorDefense"
                    let baselineParty = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
                        Combatant(id: $0, maxHP: 20_000, attack: 100, defense: 0)
                    }
                    let plainEnemy = Combatant(id: "E_R01_04", maxHP: 10_000, attack: 50, defense: 0,
                                               firstTelegraphMs: 0)
                    let baseline = try R6TimelineSimulator.run(party: baselineParty, enemies: [plainEnemy],
                                                               seed: 1_202, maxDurationMs: 4_000)
                    armorBaselineOutgoing = baseline.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R01_04" }
                case "E05_TRANSFER":
                    battle = try EnemyActionPreviewFixture.lightTransfer()
                    fixtureEnemyIDs = ["E_R05_03", "E_R05_02"]
                    fixtureFunction = "lightTransfer"
                case "E05_GUARD":
                    battle = try EnemyActionPreviewFixture.guardPosture()
                    fixtureEnemyIDs = ["E_R05_02"]
                    fixtureFunction = "guardPosture"
                case "E05_DURATION":
                    battle = try EnemyActionPreviewFixture.supportDurationReduction()
                    fixtureEnemyIDs = ["E_R05_01"]
                    fixtureFunction = "supportDurationReduction"
                case "E05_POISON":
                    battle = try EnemyActionPreviewFixture.poisonRegeneration()
                    fixtureEnemyIDs = ["E_R05_04"]
                    fixtureFunction = "poisonRegeneration"
                case "B02_DREAM":
                    battle = try EnemyActionPreviewFixture.dreamMushroomBoss(); fixtureEnemyIDs = ["B_R02_A"]; fixtureFunction = "dreamMushroomBoss"
                case "B02_MIRROR":
                    battle = try EnemyActionPreviewFixture.mirrorLizardBoss(); fixtureEnemyIDs = ["B_R02_B"]; fixtureFunction = "mirrorLizardBoss"
                case "B03_HAMMER":
                    battle = try EnemyActionPreviewFixture.hammerTrooperBoss(); fixtureEnemyIDs = ["B_R03_A"]; fixtureFunction = "hammerTrooperBoss"
                case "B03_HEAT":
                    battle = try EnemyActionPreviewFixture.forgeGuardianBoss(); fixtureEnemyIDs = ["B_R03_B"]; fixtureFunction = "forgeGuardianBoss"
                case "B04_BREATH":
                    battle = try EnemyActionPreviewFixture.mountainDragonBoss(); fixtureEnemyIDs = ["B_R04_B"]; fixtureFunction = "mountainDragonBoss"
                case "B05_PRUNING":
                    battle = try EnemyActionPreviewFixture.pruningMachineBoss(); fixtureEnemyIDs = ["B_R05_A"]; fixtureFunction = "pruningMachineBoss"
                default:
                    battle = try EnemyActionPreviewFixture.moonDeerBoss(); fixtureEnemyIDs = ["B_R05_B"]; fixtureFunction = "moonDeerBoss"
                }
                let watchedEvents = battle.events.filter {
                    $0.sourceID.hasPrefix("E_R01_") || $0.sourceID.hasPrefix("E_R05_") || $0.sourceID.hasPrefix("B_R0") || $0.sourceID == "E_R03_04" || $0.kind == "cast_interrupt" || $0.kind == "cover_redirect"
                }.map { event -> [String: Any] in
                    var item: [String: Any] = ["kind": event.kind, "sourceID": event.sourceID,
                                                "targetID": event.targetID, "amount": event.amount,
                                                "tick": event.tick]
                    item["rootActionID"] = (event.rootActionID as Any?) ?? NSNull()
                    item["timestampMs"] = (event.timestampMs as Any?) ?? NSNull()
                    item["diagnostics"] = (event.diagnostics as Any?) ?? NSNull()
                    return item
                }
                guard let catalog else { throw CoreError.invalidCatalog("catalog unavailable") }
                let fixtureRegions = fixtureEnemyIDs.compactMap { id in
                    catalog.enemies.first(where: { $0.id == id })?.regionID
                }
                let uniqueFixtureRegions = Set(fixtureRegions)
                guard fixtureRegions.count == fixtureEnemyIDs.count,
                      uniqueFixtureRegions.count == 1,
                      let fixtureRegion = uniqueFixtureRegions.first else {
                    throw CoreError.invalidCommand("preview fixture has missing or mixed region IDs")
                }
                chosenRegion = fixtureRegion
                tab = "探索"
                fighting = true
                notice = "候補戦闘演出の読み取り専用プレビュー"
                syncScene()
                scene.setEnemies(fixtureEnemyIDs)
                await play(battle)

                let savedAfter = try? Data(contentsOf: saveURL)
                let saveSHA256After = savedAfter.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
                let transfers = battle.events.filter { $0.kind == "enemy_light_transfer" && $0.sourceID == "E_R05_03" }
                let matchedCue = battle.events.contains { $0.kind == "enemy_telegraph" && $0.sourceID == "E_R05_03" }
                let relevantEvents: [CombatEvent]
                let contractMatches: Bool
                switch requested {
                case "E01_ARMOR":
                    relevantEvents = battle.events.filter { $0.kind == "enemy_armor" && $0.sourceID == "E_R01_04" }
                    let allyRoots = Set(battle.events.filter { ["direct", "smith_hammer", "poison_seed"].contains($0.kind) && $0.sourceID.hasPrefix("C_") }.compactMap(\.rootActionID))
                    let outgoing = battle.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R01_04" }
                    let outgoingSignature = outgoing.map { "\($0.timestampMs ?? -1)|\($0.targetID)|\($0.amount)" }
                    let baselineSignature = armorBaselineOutgoing.map { "\($0.timestampMs ?? -1)|\($0.targetID)|\($0.amount)" }
                    contractMatches = !relevantEvents.isEmpty
                        && relevantEvents.allSatisfy { $0.amount > 0 && $0.targetID.hasPrefix("C_") && allyRoots.contains($0.rootActionID ?? "") && !($0.rootActionID ?? "").hasPrefix("enemy:") }
                        && battle.events.filter { $0.kind == "enemy_armor" && $0.rootActionID?.hasPrefix("enemy:") == true }.isEmpty
                        && !outgoing.isEmpty && outgoingSignature == baselineSignature
                case "E03_MAGNET", "E03_MAGNET_INTERRUPT":
                    let marks=battle.events.filter{$0.kind=="enemy_magnet_mark" && $0.sourceID=="E_R03_04"}
                    let hits=battle.events.filter{$0.kind=="enemy_hit" && $0.sourceID=="E_R03_04"}
                    let interrupts=battle.events.filter{$0.kind=="cast_interrupt" && $0.targetID=="E_R03_04"}
                    relevantEvents=battle.events.filter{$0.sourceID=="E_R03_04" || $0.kind=="cast_interrupt" || $0.kind=="cover_redirect"}
                    let hitRootsValid=hits.allSatisfy{hit in marks.contains{$0.rootActionID==hit.rootActionID} && hit.diagnostics?["candidateMagnetCoefficientBP"]==12_500}
                    let interruptRootsValid=interrupts.allSatisfy{interrupt in marks.contains{$0.rootActionID==interrupt.rootActionID} && !hits.contains{$0.rootActionID==interrupt.rootActionID}}
                    contractMatches = !marks.isEmpty && hitRootsValid && interruptRootsValid
                        && (requested=="E03_MAGNET" ? !hits.isEmpty && interrupts.isEmpty : !interrupts.isEmpty)
                case "E05_TRANSFER":
                    relevantEvents = transfers
                    contractMatches = matchedCue && transfers.count == 2
                        && transfers.allSatisfy { $0.targetID == "E_R05_02" && $0.amount == 1500 }
                case "E05_GUARD":
                    relevantEvents = battle.events.filter { $0.kind == "enemy_guard_stance" || $0.kind == "enemy_guard_absorb" }
                    contractMatches = relevantEvents.contains { $0.kind == "enemy_guard_stance" && $0.sourceID == "E_R05_02" && $0.targetID == "E_R05_02" && $0.amount == 2_500 }
                        && relevantEvents.contains { $0.kind == "enemy_guard_absorb" && $0.sourceID == "E_R05_02" && $0.targetID.hasPrefix("C_") && $0.amount > 0 }
                case "E05_DURATION":
                    relevantEvents = battle.events.filter { $0.kind == "support_duration_reduced" }
                    contractMatches = relevantEvents.contains { $0.sourceID == "E_R05_01" && $0.amount == 1_000 }
                        && battle.events.contains { $0.kind == "enemy_hit" && $0.rootActionID == relevantEvents.first?.rootActionID }
                case "E05_POISON":
                    relevantEvents = battle.events.filter { $0.kind == "dot_applied" || $0.kind == "enemy_regen" }
                    contractMatches = relevantEvents.contains { $0.kind == "dot_applied" && $0.sourceID == "E_R05_04" && $0.amount == 3 }
                        && relevantEvents.contains { $0.kind == "enemy_regen" && $0.sourceID == "E_R05_04" && $0.targetID == "E_R05_04" && $0.amount > 0 }
                default:
                    let requiredKinds: Set<String>
                    switch requested {
                    case "B02_DREAM": requiredKinds = ["enemy_hit", "party_drowse", "enemy_rest"]
                    case "B02_MIRROR": requiredKinds = ["enemy_reflect_stance", "enemy_reflect_projectile", "enemy_scale_opening", "enemy_hit"]
                    case "B03_HAMMER": requiredKinds = ["enemy_hit", "enemy_rest"]
                    case "B03_HEAT": requiredKinds = ["enemy_hit", "enemy_vent", "enemy_heat_store", "enemy_heat_release"]
                    case "B04_BREATH": requiredKinds = ["enemy_hit", "enemy_cold_wave", "party_frost_slow", "enemy_breath_inhale", "enemy_breath_release"]
                    case "B05_PRUNING": requiredKinds = ["enemy_hit", "enemy_ring_opening", "enemy_ring_sweep"]
                    default: requiredKinds = ["enemy_hit", "enemy_seed_pressure", "dot_applied", "enemy_guard_stance", "enemy_ultimate_release"]
                    }
                    relevantEvents = battle.events.filter { requiredKinds.contains($0.kind) }
                    contractMatches = requiredKinds.allSatisfy { kind in relevantEvents.contains { $0.kind == kind } }
                        && (requested != "B03_HAMMER" || battle.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "B_R03_A" }.count >= 4)
                }
                let recipient = relevantEvents.first?.targetID
                let artText = scene.artAuditJSON()
                let expectedEffectID: String
                switch requested {
                case "E03_MAGNET", "E03_MAGNET_INTERRUPT": expectedEffectID = "ACT_E_R03_04_magnet_pullcue"
                case "E01_ARMOR": expectedEffectID = "ACT_E_R01_04_shell"
                case "E05_TRANSFER": expectedEffectID = "ACT_E_R05_03_light_transfer"
                case "E05_GUARD": expectedEffectID = "ACT_E_R05_02_guard_attack"
                case "E05_DURATION": expectedEffectID = "ACT_E_R05_01_unbind"
                case "E05_POISON": expectedEffectID = "ACT_E_R05_04_heal_toxin"
                case "B02_DREAM": expectedEffectID = "ACT_B_R02_A_drowse_spore"
                case "B02_MIRROR": expectedEffectID = "ACT_B_R02_B_mirror_bolt"
                case "B03_HAMMER": expectedEffectID = "ACT_B_R03_A_three_hammer"
                case "B03_HEAT": expectedEffectID = "ACT_B_R03_B_heat_floor"
                case "B04_BREATH": expectedEffectID = "ACT_B_R04_B_breath_fan"
                case "B05_PRUNING": expectedEffectID = "ACT_B_R05_A_pruning_ring"
                default: expectedEffectID = "ACT_B_R05_B_seed_wave"
                }
                let artObject = (try? JSONSerialization.jsonObject(with: Data(artText.utf8))) as? [String: Any] ?? [:]
                let effectStats = artObject["effects"] as? [String: Any] ?? [:]
                let trace = effectStats["cueTrace"] as? [[String: String]] ?? []
                let traceHasExpectedEffect = trace.contains {
                    guard $0["effectID"] == expectedEffectID, let step = $0["step"] else { return false }
                    return step == "impact_advance" || step.hasPrefix("direct_full:")
                        || (requested == "E03_MAGNET_INTERRUPT" && step == "cue_cancel:cast_interrupt")
                }
                let effectCounts = effectStats["counts"] as? [String: Int] ?? [:]
                let renderedExpectedEffect = (effectCounts[expectedEffectID] ?? 0) > 0 && traceHasExpectedEffect
                let lastEffect = effectStats["last"] as? [String: Any] ?? [:]
                let armorVisualTargetIDs = lastEffect["targetIDs"] as? [String] ?? []
                let armorVisualCorrect = requested != "E01_ARMOR" || (
                    lastEffect["id"] as? String == expectedEffectID
                    && lastEffect["event"] as? String == "enemy_armor"
                    && armorVisualTargetIDs == ["ACT_E_R01_04"]
                )
                let hpMismatches = scene.hpMismatches(party: battle.remainingPartyHP, enemies: battle.remainingEnemyHP)
                let hpURL = saveURL.deletingLastPathComponent().appendingPathComponent("last_presentation_hp.json")
                let hpReceipt = (try? Data(contentsOf: hpURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
                // A missing hit is only horizon-censored when its actual scheduled
                // deadline lies beyond this fixture and both source and target live.
                let terminalCensoredRoots: [String] = requested.hasPrefix("E03_MAGNET") ? battle.events.compactMap { mark in
                    guard mark.kind == "enemy_magnet_mark", mark.sourceID == "E_R03_04",
                          let root=mark.rootActionID, let at=mark.timestampMs,
                          at + 2_000 > 12_000, battle.ticks * 1_000 >= 12_000,
                          (battle.remainingEnemyHP[mark.sourceID] ?? 0) > 0,
                          (battle.remainingPartyHP[mark.targetID] ?? 0) > 0,
                          !battle.events.contains(where: { event in
                              event.rootActionID == root && ((["enemy_hit","enemy_magnet_target_lost"].contains(event.kind) && event.sourceID == mark.sourceID)
                                  || (event.kind == "cast_interrupt" && event.targetID == mark.sourceID))
                          }) else { return nil }
                    return root
                } : []
                let report: [String: Any] = [
                    "fixtureMaxDurationMs": requested.hasPrefix("E03_MAGNET") ? 12_000 as Any : NSNull(),
                    "elapsedWholeSeconds": battle.ticks,
                    "remainingPartyHP": battle.remainingPartyHP,
                    "remainingEnemyHP": battle.remainingEnemyHP,
                    "terminalCensoredRoots": terminalCensoredRoots,
                    "status": contractMatches && renderedExpectedEffect && armorVisualCorrect && hpMismatches.isEmpty && savedBefore != nil && savedAfter != nil && saveSHA256Before == saveSHA256After && state.revision == revisionBefore ? "NO_REWARD_SIMULATION_PREVIEW_PASS" : "NO_REWARD_SIMULATION_PREVIEW_INCOMPLETE",
                    "scope": "NO_REWARD_SIMULATION_PREVIEW",
                    "authority": "UNAPPROVED_TEST_OVERLAY; not a committed battle or game-design approval",
                    "candidateMagnetParameters": requested.hasPrefix("E03_MAGNET") ? ["markWindowMs":800,"strikeWindupMs":1200,"strikeCoefficientBP":12500] as Any : NSNull(),
                    "campaignInterruptImplemented": false,
                    "fixture": "EnemyActionPreviewFixture.\(fixtureFunction)",
                    "mechanicCase": requested,
                    "began": began,
                    "revisionBefore": revisionBefore,
                    "revisionAfter": state.revision,
                    "snapshotFileSHA256Before": saveSHA256Before as Any? ?? NSNull(),
                    "snapshotFileSHA256After": saveSHA256After as Any? ?? NSNull(),
                    "snapshotFileBytesUnchanged": savedBefore == savedAfter,
                    "contractMatches": contractMatches,
                    "expectedEffectID": expectedEffectID,
                    "renderedExpectedEffect": renderedExpectedEffect,
                    "armorVisualTargetIDs": requested == "E01_ARMOR" ? armorVisualTargetIDs : [],
                    "armorVisualCorrect": armorVisualCorrect,
                    "enemyOutgoingHitAmounts": requested == "E01_ARMOR" ? battle.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R01_04" }.map(\.amount) : [],
                    "baselineEnemyOutgoingHitAmounts": requested == "E01_ARMOR" ? armorBaselineOutgoing.map(\.amount) : [],
                    "armorOutgoingMatchesUnarmoredBaseline": requested == "E01_ARMOR" ? (battle.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R01_04" }.map { "\($0.timestampMs ?? -1)|\($0.targetID)|\($0.amount)" } == armorBaselineOutgoing.map { "\($0.timestampMs ?? -1)|\($0.targetID)|\($0.amount)" }) : false,
                    "relevantEventCount": relevantEvents.count,
                    "relevantEvents": relevantEvents.map { ["kind":$0.kind,"sourceID":$0.sourceID,"targetID":$0.targetID,"amount":$0.amount,"rootActionID":$0.rootActionID ?? "","timestampMs":$0.timestampMs ?? -1] as [String:Any] },
                    "transferTargetID": requested == "E05_TRANSFER" ? recipient as Any? ?? NSNull() : NSNull(),
                    "transferBuffAmount": requested == "E05_TRANSFER" ? relevantEvents.first?.amount as Any? ?? NSNull() : NSNull(),
                    "presentationHPReceiptAfterPlayback": hpReceipt as Any? ?? NSNull(),
                    "transferContractMatches": requested == "E05_TRANSFER" ? contractMatches : NSNull(),
                    "hpPresentationMismatchesAfterFinish": hpMismatches,
                    "events": watchedEvents,
                    "battleArtReceipt": artText
                ]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                writeReceipt("effect_mechanic_preview", String(data: data, encoding: .utf8) ?? "ENCODING_FAILED")
                fighting = false
            } catch {
                let report: [String: Any] = ["status": "NO_REWARD_SIMULATION_PREVIEW_FAILED",
                                             "scope": "NO_REWARD_SIMULATION_PREVIEW",
                                             "revision": state.revision,
                                             "snapshotFileSHA256Before": saveSHA256Before as Any? ?? NSNull(),
                                             "error": String(reflecting: error)]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    writeReceipt("effect_mechanic_preview", String(data: data, encoding: .utf8) ?? "ENCODING_FAILED")
                }
                self.error = "候補戦闘演出プレビューに失敗しました。"
                fighting = false
            }
        }
        #endif
    }
}
