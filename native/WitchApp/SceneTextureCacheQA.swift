import Foundation
import CryptoKit
import SpriteKit

/// Simulator-only presentation probe. No commands, rewards or save writes.
@MainActor extension GameModel {
    func runSceneTextureCacheQAIfRequested() {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-scene-texture-cache"),
              let rawKey = args.first(where: { $0.hasPrefix("--qa-save-key=") }),
              let saveURL, saveURL.lastPathComponent.hasPrefix("qa-") else { return }
        let key = String(rawKey.dropFirst("--qa-save-key=".count)).filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let folder = saveURL.deletingLastPathComponent()
        let output = folder.appendingPathComponent("scene_texture_cache_\(key).json")
        guard !key.isEmpty, !FileManager.default.fileExists(atPath: output.path) else { return }
        let conflicts = args.filter { argument in
            argument.hasPrefix("--") && argument != "--qa-isolated" && argument != "--qa-scene-texture-cache"
                && !argument.hasPrefix("--qa-save-key=") && !argument.hasPrefix("--qa-scene-cache-ids-b64=")
        }
        guard conflicts.isEmpty else {
            let rejection: [String: Any] = ["saveKey": key, "status": "REJECTED_CONFLICTING_LAUNCH_ARGUMENTS",
                                            "arguments": conflicts]
            if let data = try? JSONSerialization.data(withJSONObject: rejection, options: .sortedKeys) {
                try? data.write(to: output, options: .atomic)
            }
            return
        }
        guard let idsArgument = args.first(where: { $0.hasPrefix("--qa-scene-cache-ids-b64=") }),
              let idsData = Data(base64Encoded: String(idsArgument.dropFirst("--qa-scene-cache-ids-b64=".count))),
              let pressureIDs = try? JSONDecoder().decode([String].self, from: idsData),
              !pressureIDs.isEmpty, pressureIDs.count <= 200,
              Set(pressureIDs).count == pressureIDs.count,
              pressureIDs.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } })
        else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let initialState = try? encoder.encode(state)
            let initialSave = try? Data(contentsOf: saveURL)
            let oldTab = tab, oldRegion = chosenRegion, oldEnemy = activeAreaFightEnemyID
            var rows: [[String: Any]] = []
            let started = ISO8601DateFormatter().string(from: Date())
            let held = scene.texture("HOME_BASE")
            // Observe the already-rendered home background, not a proxy node.
            let holder = scene.children.compactMap { $0 as? SKSpriteNode }.first { $0.texture === held }
            let beforeClear = scene.textureRetentionSnapshot()
            scene.clearRetainedTexturesForQA()
            let afterClear = scene.textureRetentionSnapshot()
            let heldSurvivesClear = held != nil && holder?.parent === scene && holder?.texture === held
            let availability = R015AreaSceneRouting.variantAvailability(index: ArtLibrary.index, artRoot: ArtLibrary.root)
            for pass in 1...2 {
                for route in R015AreaSceneRouting.routes {
                    tab = "探索"; chosenRegion = route.regionID
                    activeAreaFightEnemyID = route.enemyIDs.first
                    syncScene()
                    let startFrame = scene.frames
                    for _ in 0..<200 {
                        if scene.frames > startFrame { break }
                        try? await Task.sleep(for: .milliseconds(25))
                    }
                    let audit = (try? JSONSerialization.jsonObject(with: Data(scene.artAuditJSON().utf8))) as? [String: Any] ?? [:]
                    let area = audit["areaBackground"] as? [String: String] ?? [:]
                    let states = audit["states"] as? [String: Bool] ?? [:]
                    let expected = R015AreaSceneRouting.resolve(regionID: route.regionID,
                        activeFightEnemyID: route.enemyIDs.first,
                        availableVariantIDs: availability.fullFrameIDs.union(availability.layeredIDs),
                        layeredVariantIDs: availability.layeredIDs)
                    let row: [String: Any] = ["pass": pass, "sceneID": route.sceneID,
                        "expectedBackgroundID": expected.renderedBackgroundID,
                        "actualBackgroundID": area["renderedBackgroundID"] ?? "",
                        "backgroundLoaded": states["background_" + expected.renderedBackgroundID] == true,
                        "sceneMatches": area["sceneID"] == route.sceneID,
                        "renderedAfterConfigure": scene.frames > startFrame,
                        "cache": scene.textureRetentionSnapshot(), "art": audit]
                    rows.append(row)
                    let stepURL = folder.appendingPathComponent("scene_texture_cache_\(key)_p\(pass)_\(route.areaID).json")
                    if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .prettyPrinted]) {
                        try? data.write(to: stepURL, options: .atomic)
                    }
                    try? await Task.sleep(for: .milliseconds(160))
                }
            }
            // Deliberate cache pressure through the production texture loader.
            // This is separate from the forty rendered routes above and does
            // not claim that normal play requests all these assets at once.
            let beforePressure = scene.textureRetentionSnapshot()
            var pressureRows: [[String: Any]] = []
            for id in pressureIDs {
                let texture = scene.texture(id)
                pressureRows.append(["id": id, "loaded": texture != nil,
                    "cache": scene.textureRetentionSnapshot()])
                try? await Task.sleep(for: .milliseconds(10))
            }
            tab = oldTab; chosenRegion = oldRegion; activeAreaFightEnemyID = oldEnemy; syncScene()
            try? await Task.sleep(for: .milliseconds(350))
            let finalState = try? encoder.encode(state)
            let finalSave = try? Data(contentsOf: saveURL)
            let saveUnchanged = initialSave != nil && initialSave == finalSave
            let report: [String: Any] = ["scope": "SIMULATOR_PRESENTATION_ROUTES_NOT_GAMEPLAY_OR_DEVICE_MEMORY",
                "saveKey": key, "startedAt": started,
                "finishedAt": ISO8601DateFormatter().string(from: Date()),
                "beforeClear": beforeClear, "afterClear": afterClear,
                "heldTextureSurvivesCacheClear": heldSurvivesClear,
                "heldTextureSurvivesRouteSweep": held != nil && holder != nil && holder?.texture === held,
                "heldNodeScope": "Actual home background node at clear; retained by QA after route rebuild detaches it",
                "rows": rows, "beforePressure": beforePressure, "pressureRows": pressureRows,
                "finalCache": scene.textureRetentionSnapshot(),
                "stateUnchanged": initialState != nil && initialState == finalState,
                "saveUnchanged": saveUnchanged,
                "initialSaveSHA256": initialSave.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "MISSING",
                "finalSaveSHA256": finalSave.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "MISSING",
                "initialContext": ["tab": oldTab, "region": oldRegion, "activeEnemy": oldEnemy as Any? ?? NSNull()],
                "restoredContext": ["tab": tab, "region": chosenRegion, "activeEnemy": activeAreaFightEnemyID as Any? ?? NSNull()],
                "restoredTab": tab, "restoredRegion": chosenRegion,
                "finalArt": scene.artAuditJSON(),
                "status": "CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
                try? data.write(to: output, options: .atomic)
            }
        }
        #endif
    }
}
