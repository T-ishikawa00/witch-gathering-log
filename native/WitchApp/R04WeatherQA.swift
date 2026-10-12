import SpriteKit

/// Isolated policy and SpriteKit-node QA. It does not dispatch combat or access saves.
@MainActor enum R04WeatherQA {
    static func run() -> [String: Any] {
        let ids = BattleEffects.environmentIDs(region: "R04")
        var checks: [String: Bool] = ["twoEmitterCap": ids.count >= 3]
        var seenIDs = Set<String>()
        var sceneResults: [[String: Any]] = []
        var maximumEmitterCount = 0

        for sceneSize in [CGSize(width: 402, height: 844), CGSize(width: 402, height: 320)] {
            for cycle in 0..<max(1, ids.count) {
                let selected = R04TelegraphEnvironmentPolicy.selectedIDs(ids, cycle: cycle)
                let scene = SKScene(size: sceneSize)
                let policy = R04TelegraphEnvironmentPolicy()
                var nodes: [SKSpriteNode] = []
                for (slot, id) in selected.enumerated() {
                    seenIDs.insert(id)
                    guard let node = BattleEffects.makeNode(id: id, environment: true) else {
                        checks["assetLoaded_\(id)"] = false
                        continue
                    }
                    checks["assetLoaded_\(id)"] = true
                    BattleEffects.playEnvironment(id: id, on: node)
                    policy.place(node, id: id, slot: slot, sceneSize: sceneSize)
                    scene.addChild(node)
                    nodes.append(node)
                }
                maximumEmitterCount = max(maximumEmitterCount, nodes.count)
                checks["rotationCap_\(cycle)_\(Int(sceneSize.height))"] = selected.count <= 2 && nodes.count == selected.count

                let foreignEnvironment = SKSpriteNode(color: .magenta, size: CGSize(width: 12, height: 12))
                foreignEnvironment.name = "environment_effect:ENV_R05_01"
                foreignEnvironment.userData = NSMutableDictionary()
                foreignEnvironment.userData?["environmentOwner"] = "R05"
                foreignEnvironment.run(.repeatForever(.wait(forDuration: 1)), withKey: "foreign_environment_loop")
                scene.addChild(foreignEnvironment)
                let combat = SKSpriteNode(color: .yellow, size: CGSize(width: 12, height: 12))
                combat.name = "combat_effect:QA_SENTINEL"
                combat.run(.repeatForever(.wait(forDuration: 1)), withKey: "foreign_combat_loop")
                scene.addChild(combat)
                let foreignUnchanged: () -> Bool = {
                    !foreignEnvironment.isHidden && foreignEnvironment.action(forKey: "foreign_environment_loop") != nil
                        && !combat.isHidden && combat.action(forKey: "foreign_combat_loop") != nil
                }
                func reconcile(_ region: String, _ cueCount: Int) -> Bool {
                    policy.reconcile(region: region, cueNodeCount: cueCount, nodes: scene.children)
                }
                func allVisible() -> Bool { nodes.allSatisfy { !$0.isHidden } }
                func allHidden() -> Bool { nodes.allSatisfy(\.isHidden) }
                func allActionsPresent() -> Bool { nodes.allSatisfy { $0.action(forKey: "effect_frames") != nil } }
                func laneClear() -> Bool {
                    nodes.allSatisfy { node in
                        let halfW = node.size.width * abs(node.xScale) / 2
                        let halfH = node.size.height * abs(node.yScale) / 2
                        let bounds = CGRect(x: (node.position.x - halfW) / sceneSize.width,
                                            y: 1 - (node.position.y + halfH) / sceneSize.height,
                                            width: 2 * halfW / sceneSize.width,
                                            height: 2 * halfH / sceneSize.height)
                        return !bounds.intersects(R04TelegraphEnvironmentPolicy.protectedLaneTopLeft)
                    }
                }

                let idle = !reconcile("R04", 0) && allVisible() && allActionsPresent() && foreignUnchanged()
                let held = reconcile("R04", 1) && allHidden() && allActionsPresent() && foreignUnchanged()
                let impact = !reconcile("R04", 0) && allVisible() && allActionsPresent() && foreignUnchanged()
                let cancelled = reconcile("R04", 1) && !reconcile("R04", 0) && allVisible() && allActionsPresent() && foreignUnchanged()
                let ended = reconcile("R04", 1) && !reconcile("R05", 0) && allVisible() && allActionsPresent() && foreignUnchanged()
                let clear = laneClear()
                let suffix = "_\(cycle)_\(Int(sceneSize.height))"
                checks["idle" + suffix] = idle
                checks["held" + suffix] = held
                checks["impact" + suffix] = impact
                checks["cancel" + suffix] = cancelled
                checks["endAndLeaveR04" + suffix] = ended
                checks["foreignNodesUntouched" + suffix] = foreignUnchanged()
                checks["protectedLaneClear" + suffix] = clear
                sceneResults.append([
                    "sceneSize": [sceneSize.width, sceneSize.height],
                    "cycle": cycle,
                    "selectedIDs": selected,
                    "idleVisible": idle,
                    "heldHidden": held,
                    "impactRestored": impact,
                    "cancelRestored": cancelled,
                    "endAndLeaveR04Restored": ended,
                    "foreignEnvironmentAndCombatUntouched": foreignUnchanged(),
                    "protectedLaneClear": clear,
                    "emitterCount": nodes.count,
                    "emitterBounds": policy.snapshot(currentOwnedEmitterCount: nodes.count,
                                                       currentHiddenEmitterCount: nodes.filter(\.isHidden).count)["latestPlacementByEffectID"] ?? [:]
                ])
            }
        }
        checks["rotationCoversAllThreeIDs"] = ids.count == 3 && seenIDs == Set(ids)
        checks["maximumEmitterCountAtMostTwo"] = maximumEmitterCount <= 2
        return [
            "status": checks.values.allSatisfy { $0 } ? "PASS_ISOLATED_POLICY_AND_NODE_STATE_ONLY" : "FAIL",
            "checks": checks,
            "runtimeIDs": ids,
            "maximumEmitterCount": maximumEmitterCount,
            "sceneResults": sceneResults,
            "scope": "Policy and SpriteKit node/action state only. No combat dispatch, reward, or save API is called. This does not test elapsed animation, real cue-event bridging, or visual Simulator acceptance."
        ]
    }
}
