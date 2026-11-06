import Foundation
import SpriteKit

/// Read-only index of one committed CombatResult's cue/impact relationships.
/// The coordinator only consumes events; it cannot dispatch commands or change combat state.
@MainActor final class EffectCueCoordinator {
    struct Plan {
        let key: String
        let rootActionID: String
        let sourceID: String
        let sourceArtID: String
        let effectID: String
        let telegraphKind: String
        let impactKinds: Set<String>
        let targetIDs: [String]
        let cueTargetIDs: [String]
    }

    struct Recipients {
        let targetIDs: [String]
        let eventKinds: Set<String>
    }
    private var recipientsByAction: [String: Recipients] = [:]
    private(set) var plans: [String: Plan] = [:]
    private(set) var emitted = Set<String>()
    private(set) var pendingNodes: [String: SKSpriteNode] = [:]
    private(set) var audit: [[String: String]] = []

    func record(_ step: String, root: String = "", source: String = "", effect: String = "", targets: [String]? = nil, placement: [String:Any]? = nil) {
        var row = ["step":step,"rootActionID":root,"sourceID":source,"effectID":effect]
        if let targets { row["targetIDs"] = targets.joined(separator: ",") }
        if let placement { for (key,value) in placement { row["placement."+key]=String(describing:value) } }
        audit.append(row)
    }

    static func key(rootActionID: String, sourceID: String) -> String { rootActionID + "|" + sourceID }

    func prepare(events: [CombatEvent], sourceArtID: (String) -> String) {
        recipientsByAction.removeAll(keepingCapacity: true)
        // A combat root can include victim delivery and a source-only state change
        // (for example mirror-scale opening or recovery). Only actual recipients
        // determine the attack centroid. Self-only defense/support still targets self.
        let groups = Dictionary(grouping: events.filter { event in
            guard let binding = BattleEffects.binding(actor: sourceArtID(event.sourceID)),
                  binding.eventKinds.contains(event.kind), event.rootActionID != nil else { return false }
            return !["enemy_armor", "enemy_guard_absorb"].contains(event.kind) || event.amount > 0
        }) { Self.key(rootActionID: $0.rootActionID ?? "", sourceID: $0.sourceID) }
        for (key, group) in groups {
            func recipient(_ event: CombatEvent) -> String {
                ["enemy_armor", "enemy_guard_absorb"].contains(event.kind) ? event.sourceID : event.targetID
            }
            let concrete = group.filter {
                let target = recipient($0)
                return !target.isEmpty && target != "party" && target != $0.rootActionID
            }
            let external = concrete.filter { recipient($0) != $0.sourceID }
            let deliveries = external.isEmpty ? concrete : external
            // A hit-bound action is anchored and advanced by actual hits. Status
            // recipients can be a subset (for example survivors after an AoE),
            // but cannot move that attack or advance it before damage arrives.
            let hits = deliveries.filter { $0.kind == "enemy_hit" }
            let selected = hits.isEmpty ? deliveries : hits
            var targets: [String] = []
            for event in selected where !targets.contains(recipient(event)) { targets.append(recipient(event)) }
            if !selected.isEmpty {
                recipientsByAction[key] = Recipients(targetIDs: targets, eventKinds: Set(selected.map(\.kind)))
            }
        }
        plans.removeAll(keepingCapacity: true)
        emitted.removeAll(keepingCapacity: true)
        pendingNodes.removeAll(keepingCapacity: true)
        audit.removeAll(keepingCapacity: true)
        let tells = events.filter { event in
            guard let binding = BattleEffects.binding(actor: sourceArtID(event.sourceID)) else { return false }
            return binding.telegraphKinds.contains(event.kind) && event.rootActionID != nil
        }
        for tell in tells {
            guard let root = tell.rootActionID else { continue }
            let actor = sourceArtID(tell.sourceID)
            guard let binding = BattleEffects.binding(actor: actor), !binding.eventKinds.isEmpty else { continue }
            let impacts = events.filter {
                $0.rootActionID == root && $0.sourceID == tell.sourceID && binding.eventKinds.contains($0.kind)
            }
            // The tool-combo tell is authored before its strike. A player interrupt
            // must cancel that visible tell, not make it disappear retrospectively.
            let isInterruptedToolCast = actor == "ACT_E_R03_03" && events.contains {
                $0.kind == "cast_interrupt" && $0.rootActionID == root && $0.targetID == tell.sourceID
            }
            let selectedRecipients = recipientsByAction[Self.key(rootActionID: root, sourceID: tell.sourceID)]
            let deliveryImpacts = impacts.filter { selectedRecipients?.eventKinds.contains($0.kind) ?? true }
            // A committed magnet mark is visible even if its target dies or the
            // battle ends before impact. Keep the original marked actor distinct
            // from a later Smith cover recipient; other actions retain R012 rules.
            let magnetMark = actor == "ACT_E_R03_04" ? events.first {
                $0.kind == "enemy_magnet_mark" && $0.rootActionID == root && $0.sourceID == tell.sourceID
            } : nil
            if actor == "ACT_E_R03_04", magnetMark == nil {
                record("unmatched_magnet_tell:" + tell.kind,root:root,source:tell.sourceID)
                continue
            }
            let impactKind = deliveryImpacts.first?.kind ?? ((isInterruptedToolCast || magnetMark != nil) ? "enemy_hit" : nil)
            guard let impactKind,
                  let effectID = BattleEffects.combatID(actor: actor, event: impactKind, telegraph: tell.kind) else {
                record("unmatched_tell:" + tell.kind,root:tell.rootActionID ?? "",source:tell.sourceID)
                continue
            }
            let key = Self.key(rootActionID: root, sourceID: tell.sourceID)
            // enemy_cast_start carries the root in targetID. Preserve the earlier
            // telegraph's actual victim when an interrupted cast has no hit event.
            var targets = (selectedRecipients?.targetIDs ?? (impacts.isEmpty ? [tell.targetID] : impacts.map(\.targetID))).filter { !$0.isEmpty && $0 != "party" && $0 != root }
            if targets.isEmpty, impacts.isEmpty { targets = plans[key]?.targetIDs ?? [] }
            var uniqueTargets: [String] = []
            for target in targets where !uniqueTargets.contains(target) { uniqueTargets.append(target) }
            plans[key] = Plan(key: key, rootActionID: root, sourceID: tell.sourceID, sourceArtID: actor,
                              effectID: effectID, telegraphKind: magnetMark?.kind ?? tell.kind,
                              impactKinds: selectedRecipients?.eventKinds ?? binding.eventKinds, targetIDs: uniqueTargets,
                              cueTargetIDs: magnetMark.map { [$0.targetID] } ?? uniqueTargets)
            record((impacts.isEmpty ? "plan_cancellable:" : "plan:") + tell.kind,root:root,source:tell.sourceID,effect:effectID)
        }
    }

    func recipients(rootActionID: String?, sourceID: String) -> Recipients? {
        guard let rootActionID else { return nil }
        return recipientsByAction[Self.key(rootActionID: rootActionID, sourceID: sourceID)]
    }

    func plan(rootActionID: String?, sourceID: String) -> Plan? {
        guard let rootActionID else { return nil }
        return plans[Self.key(rootActionID: rootActionID, sourceID: sourceID)]
    }

    func pendingNode(for key: String) -> SKSpriteNode? { pendingNodes[key] }
    func hold(_ node: SKSpriteNode, for plan: Plan) { pendingNodes[plan.key] = node;record("cue_hold:" + plan.telegraphKind,root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID) }
    func clearPending(_ key: String) { if let plan=plans[key] { record("impact_advance",root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID) };pendingNodes.removeValue(forKey: key) }
    func cancel(rootActionID: String?, sourceID: String, reason: String) {
        guard let rootActionID else { return }
        let key=Self.key(rootActionID:rootActionID,sourceID:sourceID)
        guard let plan=plans[key] else { return }
        guard let node=pendingNodes.removeValue(forKey:key) else {
            record("cancel_without_held_cue:"+reason,root:rootActionID,source:sourceID,effect:plan.effectID);return
        }
        node.removeAllActions()
        // Local presentation candidate: fade the interrupted tell without advancing
        // into impact frames. This duration is not a gameplay or R4 timing value.
        node.run(.sequence([.fadeOut(withDuration:0.12),.removeFromParent()]),withKey:"effect_cancel")
        record("cue_cancel:"+reason,root:rootActionID,source:sourceID,effect:plan.effectID)
    }
    func markEmitted(actionIdentity: String, effectID: String, sourceID: String) -> Bool {
        // One visual action per committed root, even if an AoE emits one hit event per ally.
        // In particular, never fall back from an already-presented root-floor variant to branch art.
        let token = actionIdentity + "|" + sourceID
        let inserted=emitted.insert(token).inserted
        record(inserted ? "emit":"dedupe",root:actionIdentity,source:sourceID,effect:effectID)
        return inserted
    }
    func finish() {
        for node in pendingNodes.values { node.removeAllActions(); node.removeFromParent() }
        pendingNodes.removeAll()
    }
}
