import SpriteKit
import UIKit

/// Presentation-only bindings from candidate art to observed R6 event kinds.
/// This table is deliberately not catalog/gameplay authority.
@MainActor enum BattleEffects {
    struct Binding {
        let id: String
        let eventKinds: Set<String>
        let telegraphKinds: Set<String>
    }

    struct FrameSet {
        let textures: [SKTexture]
        let frameDuration: TimeInterval
        let cueFrame: Int
        let impactFrame: Int
        let recoverFrame: Int
    }

    private static func dictionary(_ file: String, _ field: String) -> [String: [String: Any]] {
        guard let data = try? Data(contentsOf: ArtLibrary.root.appendingPathComponent(file)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json[field] as? [String: [String: Any]] ?? [:]
    }

    static let entries = dictionary("runtime_index.json", "effects")
    static let contracts = dictionary("effect_contract_candidate_r001.json", "entries")
    private static var textures: [String: SKTexture] = [:]

    /// Explicit actor/event bindings. Unsupported visual/event pairs intentionally have no binding.
    /// Names are candidate semantics only; no R6 gameplay values or event generation are changed.
    private static let bindings: [String: Binding] = {
        let tells: Set<String> = ["enemy_telegraph", "telegraph_heavy", "telegraph_aoe", "enemy_cast_start"]
        func attack(_ id: String) -> Binding { Binding(id: id, eventKinds: ["enemy_hit"], telegraphKinds: tells) }
        func direct(_ id: String, _ events: Set<String>) -> Binding { Binding(id: id, eventKinds: events, telegraphKinds: []) }
        return [
            "ACT_E_R01_01": attack("ACT_E_R01_01_charge"),
            "ACT_E_R01_02": attack("ACT_E_R01_02_silk"),
            // Candidate overlay emits three enemy_hit events from one telegraph/root; coordinator dedupes art per root.
            "ACT_E_R01_03": attack("ACT_E_R01_03_double_leaf"),
            // Candidate shell effect is attached to the armored enemy when its real damage-prevention event fires.
            "ACT_E_R01_04": direct("ACT_E_R01_04_shell", ["enemy_armor"]),
            "ACT_B_R01_A": attack("ACT_B_R01_A_heavy_charge"),
            "ACT_B_R01_B": attack("ACT_B_R01_B_branch"), // telegraph_aoe selects root_floor below.
            "ACT_E_R02_01": attack("ACT_E_R02_01_spore"),
            "ACT_E_R02_02": direct("ACT_E_R02_02_mist_guard", ["enemy_armor"]),
            // The return mote is the delayed reflected projectile only, not ordinary attack damage.
            "ACT_E_R02_03": direct("ACT_E_R02_03_return_mote", ["enemy_reflect_projectile"]),
            // Candidate overlay support transfer has its own event and no enemy_hit; render at actual recipient.
            "ACT_E_R02_04": Binding(id: "ACT_E_R02_04_support_arc", eventKinds: ["enemy_magic_support"], telegraphKinds: ["enemy_telegraph"]),
            "ACT_B_R02_A": Binding(id: "ACT_B_R02_A_drowse_spore", eventKinds: ["enemy_hit", "party_drowse", "enemy_rest"], telegraphKinds: tells),
            "ACT_B_R02_B": Binding(id: "ACT_B_R02_B_mirror_bolt", eventKinds: ["enemy_hit", "enemy_armor", "enemy_reflect_stance", "enemy_reflect_projectile", "enemy_scale_opening"], telegraphKinds: tells),
            // Candidate pincer art covers its push and the real shell-prevention pulse.
            // Armor events target the attacker in Core; the renderer anchors the pulse on this enemy.
            "ACT_E_R03_01": Binding(id: "ACT_E_R03_01_pincer_guard", eventKinds: ["enemy_hit", "enemy_armor"], telegraphKinds: tells),
            // Resonance rings represent an actual cast interruption, not poison/DOT.
            "ACT_E_R03_02": Binding(id: "ACT_E_R03_02_resonance", eventKinds: ["cast_interrupt"], telegraphKinds: tells),
            "ACT_E_R03_03": attack("ACT_E_R03_03_tool_combo"),
            // R014 provisional mark/strike emits a real locked-target event.
            // Generic legacy heavy tells alone cannot fabricate a magnet mark.
            "ACT_E_R03_04": Binding(id: "ACT_E_R03_04_magnet_pullcue", eventKinds: ["enemy_hit"], telegraphKinds: ["enemy_magnet_mark", "telegraph_heavy"]),
            "ACT_B_R03_A": Binding(id: "ACT_B_R03_A_three_hammer", eventKinds: ["enemy_hit", "enemy_rest"], telegraphKinds: tells),
            "ACT_B_R03_B": Binding(id: "ACT_B_R03_B_heat_floor", eventKinds: ["enemy_hit", "enemy_vent", "enemy_heat_store", "enemy_heat_release"], telegraphKinds: tells),
            // The candidate low pursuit streak covers ordinary wolf strikes as well
            // as followups. enemy_followup marks the tell, not an immediate impact;
            // its later same-root enemy_hit advances the existing cue.
            "ACT_E_R04_01": attack("ACT_E_R04_01_pursuit"),
            // Gust is the cast-slow status cue; ordinary enemy_hit remains represented by its normal motion.
            "ACT_E_R04_02": Binding(id: "ACT_E_R04_02_wing_gust", eventKinds: ["party_cast_slow"], telegraphKinds: tells),
            // White guard plates belong to shell closure/prevented damage, not its delayed strike.
            "ACT_E_R04_03": direct("ACT_E_R04_03_hex_guard", ["enemy_shell_close", "enemy_armor"]),
            "ACT_E_R04_04": attack("ACT_E_R04_04_tool_arcs"),
            "ACT_B_R04_A": attack("ACT_B_R04_A_snow_charge"),
            "ACT_B_R04_B": Binding(id: "ACT_B_R04_B_breath_fan", eventKinds: ["enemy_hit", "enemy_cold_wave", "party_frost_slow", "enemy_breath_inhale", "enemy_breath_release"], telegraphKinds: tells),
            // Status changes share the same enemy action root as the hit; one cue/impact is deduped per root.
            "ACT_E_R05_01": Binding(id: "ACT_E_R05_01_unbind", eventKinds: ["enemy_hit", "support_duration_reduced"], telegraphKinds: tells),
            // Guard stance and actual prevented damage are distinct candidate events.
            "ACT_E_R05_02": direct("ACT_E_R05_02_guard_attack", ["enemy_guard_stance", "enemy_guard_absorb"]),
            // Candidate overlay transfer event is not damage-over-time and must not be shown as an attack.
            "ACT_E_R05_03": Binding(id: "ACT_E_R05_03_light_transfer", eventKinds: ["enemy_light_transfer"], telegraphKinds: ["enemy_telegraph"]),
            // Poison status and effective self-heal use the combined poison/heal effect; neither invents damage.
            "ACT_E_R05_04": Binding(id: "ACT_E_R05_04_heal_toxin", eventKinds: ["enemy_hit", "dot_applied", "enemy_regen"], telegraphKinds: tells),
            "ACT_B_R05_A": Binding(id: "ACT_B_R05_A_pruning_ring", eventKinds: ["enemy_hit", "enemy_ring_opening", "enemy_ring_sweep"], telegraphKinds: tells),
            "ACT_B_R05_B": Binding(id: "ACT_B_R05_B_seed_wave", eventKinds: ["enemy_hit", "enemy_seed_pressure", "dot_applied", "enemy_guard_stance", "enemy_guard_absorb", "enemy_ultimate_release"], telegraphKinds: tells)
        ]
    }()

    static var allIDs: [String] { entries.keys.sorted() }
    static func environmentIDs(region: String) -> [String] { allIDs.filter { $0.hasPrefix("ENV_\(region)_") } }
    static var unsupportedCombatActors: [String] {
        let actorIDs = Set(allIDs.filter { $0.hasPrefix("ACT_") }.map { id in
            let parts = id.split(separator: "_")
            return parts.count >= 4 ? parts.prefix(4).joined(separator: "_") : id
        })
        return actorIDs.subtracting(Set(bindings.keys)).sorted()
    }

    static func binding(actor: String) -> Binding? { bindings[actor] }
    static func combatID(actor: String, event: String, telegraph: String?) -> String? {
        guard let binding = bindings[actor], binding.eventKinds.contains(event) else { return nil }
        if actor == "ACT_B_R01_B" {
            let variant = telegraph == "telegraph_aoe" ? "_root_floor" : "_branch"
            let id = "ACT_B_R01_B\(variant)"
            return entries[id] == nil ? nil : id
        }
        return entries[binding.id] == nil ? nil : binding.id
    }

    static func frameSet(id: String) -> FrameSet? {
        guard let frames = entries[id]?["frames"] as? [[String: Any]], !frames.isEmpty,
              let contract = contracts[id] else { return nil }
        var loaded: [SKTexture] = []
        for frame in frames {
            guard let path = frame["path"] as? String else { return nil }
            let texture: SKTexture
            if let cached = textures[path] { texture = cached }
            else {
                guard let image = UIImage(contentsOfFile: ArtLibrary.root.appendingPathComponent(path).path) else { return nil }
                texture = SKTexture(image: image); texture.filteringMode = .linear; textures[path] = texture
            }
            loaded.append(texture)
        }
        guard !loaded.isEmpty else { return nil }
        let duration = max(0.02, (contract["animation_duration_ms"] as? Double ?? Double(frames.count * 90)) / 1000 / Double(frames.count))
        let sequence = contract["event_contract"] as? [String: Any] ?? [:]
        func bounded(_ key: String, fallback: Int) -> Int { min(loaded.count - 1, max(0, sequence[key] as? Int ?? fallback)) }
        return FrameSet(textures: loaded, frameDuration: duration,
                        cueFrame: bounded("cue_peak_frame", fallback: 2),
                        impactFrame: bounded("impact_present_frame", fallback: 4),
                        recoverFrame: bounded("recover_end_frame", fallback: loaded.count - 1))
    }

    static func makeNode(id: String, environment: Bool = false) -> SKSpriteNode? {
        guard let frames = frameSet(id: id), let contract = contracts[id] else { return nil }
        let node = SKSpriteNode(texture: frames.textures[0])
        node.name = (environment ? "environment_effect:" : "combat_effect:") + id
        let opacity = (contract["opacity"] as? Double) ?? (environment ? 0.30 : 0.62)
        // Candidate line art is faint in phone-sized battle composition; renderer adjustment only.
        node.alpha = CGFloat(min(environment ? 0.72 : 0.94, opacity * (environment ? 1.35 : 1.45)))
        node.blendMode = (contract["blend_mode"] as? String) == "additive" ? .add : .alpha
        node.size = CGSize(width: environment ? 150 : 136, height: environment ? 150 : 136)
        node.zPosition = environment ? 8 : 24
        return node
    }

    static func playCue(id: String, on node: SKSpriteNode) {
        guard let frames = frameSet(id: id) else { return }
        let steps = (0...frames.cueFrame).flatMap { index -> [SKAction] in
            [.run { node.texture = frames.textures[index] }, .wait(forDuration: frames.frameDuration)]
        }
        node.run(.sequence(steps), withKey: "effect_frames") // Holds at cue_peak until the impact event.
    }

    static func playImpact(id: String, on node: SKSpriteNode) {
        MagnetMarkIndicator.remove(from: node)
        guard let frames = frameSet(id: id) else { node.removeFromParent(); return }
        let lower = min(frames.impactFrame, frames.recoverFrame)
        let clipDuration=Double(frames.recoverFrame-lower+1)*frames.frameDuration
        let duration=TransferPathGeometry.presentationDuration(id:id,on:node,clipDuration:clipDuration)
        TransferPathGeometry.showArrival(on:node,id:id,duration:duration)
        let steps = (lower...frames.recoverFrame).flatMap { index -> [SKAction] in
            [.run { node.texture = frames.textures[index] }, .wait(forDuration: frames.frameDuration)]
        }
        node.removeAction(forKey: "effect_frames")
        node.run(.sequence(steps + [.wait(forDuration:max(0,duration-clipDuration)),.removeFromParent()]), withKey: "effect_frames")
    }

    static func playAll(id: String, on node: SKSpriteNode) {
        guard let frames = frameSet(id: id) else { node.removeFromParent(); return }
        let clipDuration=Double(frames.textures.count)*frames.frameDuration
        let duration=TransferPathGeometry.presentationDuration(id:id,on:node,clipDuration:clipDuration)
        TransferPathGeometry.showArrival(on:node,id:id,duration:duration)
        let steps = frames.textures.enumerated().flatMap { index, texture -> [SKAction] in
            [.run { node.texture = texture }, .wait(forDuration: frames.frameDuration)]
        }
        node.run(.sequence(steps + [.wait(forDuration:max(0,duration-clipDuration)),.removeFromParent()]), withKey: "effect_frames")
    }

    static func playEnvironment(id: String, on node: SKSpriteNode) {
        guard let frames = frameSet(id: id) else { return }
        let steps = frames.textures.enumerated().flatMap { index, texture -> [SKAction] in
            [.run { node.texture = texture }, .wait(forDuration: frames.frameDuration)]
        }
        node.run(.repeatForever(.sequence(steps)), withKey: "effect_frames")
    }

    static func anchors(id: String) -> [String: String] { contracts[id]?["anchors"] as? [String: String] ?? [:] }
    static func symbolicAnchorPoint(_ symbol: String, actorID: String) -> CGPoint {
        // Normalized actor-local coordinates, origin at bottom-left; per-art anchor candidates.
        let actorSpecific: [String: CGPoint] = [
            "ACT_B_R01_B.root_anchor": .init(x: 0.52, y: 0.15),
            "ACT_B_R01_B.branch_anchor": .init(x: 0.68, y: 0.73),
            "ACT_B_R02_B.mirror_surface": .init(x: 0.55, y: 0.66),
            "ACT_B_R04_B.mouth_anchor": .init(x: 0.78, y: 0.72),
            "ACT_B_R05_B.antler_anchor": .init(x: 0.54, y: 0.86),
            "ACT_E_R03_03.tool_anchor": .init(x: 0.66, y: 0.47),
            "ACT_E_R04_04.tool_anchor": .init(x: 0.65, y: 0.49),
            "ACT_E_R05_01.vine_tip": .init(x: 0.62, y: 0.72),
            "ACT_B_R03_A.three_hammer_anchors": .init(x: 0.50, y: 0.51),
            "ACT_B_R05_A.ring_center": .init(x: 0.50, y: 0.62)
        ]
        if let point = actorSpecific[actorID + "." + symbol] { return point }
        switch symbol {
        case "ground", "ground_path", "ground_target_area": return .init(x: 0.5, y: 0.08)
        case "head_anchor", "mouth_anchor", "antler_anchor", "flower_center", "vine_tip": return .init(x: 0.55, y: 0.78)
        case "wing_anchor", "branch_anchor", "tool_anchor": return .init(x: 0.68, y: 0.56)
        case "root_anchor": return .init(x: 0.50, y: 0.17)
        default: return .init(x: 0.5, y: 0.5)
        }
    }
}
