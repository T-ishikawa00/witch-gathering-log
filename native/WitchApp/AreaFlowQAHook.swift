import Foundation

/// QA-only route/fallback control. It is configured only when --qa-isolated is present.
@MainActor enum AreaFlowQAHook {
    enum ProbeKind: String, Equatable { case missing, decodeLayer = "decode-layer", decodeFullFrame = "decode-fullframe" }
    struct Probe { let variantID: String; let kind: ProbeKind }

    private(set) static var isolated = false
    private(set) static var probe: Probe?
    private(set) static var observedBranch: String?
    private(set) static var observedVariantID: String?

    static var availabilityOverrideVariantID: String? {
        guard isolated, probe?.kind == .missing else { return nil }
        return probe?.variantID
    }

    static var injectionReceipt: [String: Any]? {
        guard isolated, let probe else { return nil }
        let branch: String
        switch probe.kind {
        case .missing: branch = "availability_override"
        case .decodeLayer: branch = "layer_decode_branch"
        case .decodeFullFrame: branch = "fullframe_decode_branch"
        }
        return ["variantID": probe.variantID,
                "mode": probe.kind.rawValue,
                "branch": observedBranch ?? (probe.kind == .missing ? branch : "not_observed"),
                "observedVariantID": observedVariantID ?? NSNull()]
    }

    static func configure(arguments: [String], isolated: Bool) {
        self.isolated = isolated
        probe = nil
        observedBranch = nil
        observedVariantID = nil
        guard isolated,
              let raw = arguments.first(where: { $0.hasPrefix("--qa-area-availability-probe=") }) else { return }
        let payload = String(raw.dropFirst("--qa-area-availability-probe=".count))
        let parts = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let kind = ProbeKind(rawValue: String(parts[1])) else { return }
        probe = Probe(variantID: String(parts[0]), kind: kind)
    }

    static func shouldFailFullFrameDecode(id: String) -> Bool {
        isolated && probe?.kind == .decodeFullFrame && probe?.variantID == id
    }

    static func shouldFailLayerDecode(variantID: String) -> Bool {
        isolated && probe?.kind == .decodeLayer && probe?.variantID == variantID
    }

    static func recordDecodeFailureBranch(_ branch: String, variantID: String) {
        guard isolated, probe?.variantID == variantID else { return }
        observedBranch = branch
        observedVariantID = variantID
    }

    static func checkpointToken(runID: String, stepIndex: Int, phase: String) -> String {
        "\(runID)__\(stepIndex)__\(phase)"
    }
}

private struct AreaFlowDocument: Decodable {
    let version: Int
    let runID: String
    let fixture: String
    let regionID: String
    let sequence: [Step]

    struct Step: Decodable {
        let id: String
        let kind: String
        let regionID: String
        let materialID: String?
        let enemyID: String?
        let expectedSceneID: String
        let expectedAreaID: String
        let expectedRegionID: String
        let selectionBasis: String
    }
}

@MainActor extension GameModel {
    func runAreaFlowQAHookIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated") else { return }
        do {
            if let raw = arguments.first(where: { $0.hasPrefix("--qa-area-flow-b64=") }) {
                let encoded = String(raw.dropFirst("--qa-area-flow-b64=".count))
                guard let data = Data(base64Encoded: encoded) else { throw AreaFlowHookError.invalid("bad base64") }
                let flow = try JSONDecoder().decode(AreaFlowDocument.self, from: data)
                try await executeAreaFlow(flow)
            } else if let raw = arguments.first(where: { $0.hasPrefix("--qa-area-availability-probe=") }) {
                try await executeAreaFallbackProbe(argument: String(raw.dropFirst("--qa-area-availability-probe=".count)))
            }
        } catch {
            writeAreaRouteError(String(reflecting: error))
        }
    }

    private func executeAreaFlow(_ flow: AreaFlowDocument) async throws {
        guard flow.version == 1, flow.fixture == "area-routing",
              ["R01", "R04"].contains(flow.regionID),
              flow.runID.range(of: #"^[A-Za-z0-9-]{1,40}$"#, options: .regularExpression) != nil,
              !flow.sequence.isEmpty, let engine, let catalog else {
            throw AreaFlowHookError.invalid("unsupported flow header")
        }
        for (index, step) in flow.sequence.enumerated() {
            guard step.regionID == flow.regionID, step.expectedRegionID == flow.regionID else {
                throw AreaFlowHookError.invalid("step region mismatch: \(step.id)")
            }
            switch step.kind {
            case "gather":
                guard let materialID = step.materialID,
                      let route = R015AreaSceneRouting.routes.first(where: { $0.regionID == flow.regionID && $0.gatherableMaterialIDs.contains(materialID) }),
                      route.sceneID == step.expectedSceneID, route.areaID == step.expectedAreaID,
                      step.selectionBasis == "selectedGatherMaterial",
                      catalog.regions.first(where: { $0.id == flow.regionID })?.gatherMaterialIDs.contains(materialID) == true else {
                    throw AreaFlowHookError.invalid("unknown gather target: \(step.id)")
                }
                try await dispatchArea(.startExpeditionAt(regionID: flow.regionID, now: Date()), engine: engine)
                try await dispatchArea(.setGatherTargetAt(resourceID: materialID, now: Date()), engine: engine)
                activeAreaFightEnemyID = nil
                chosenRegion = flow.regionID
                tab = "探索"
                syncScene()
                let ready = await waitForAreaSceneFrame(after: scene.frames)
                try await writeAreaRouteCheckpoint(runID: flow.runID, stepIndex: index, stepID: step.id,
                                                   phase: "gather_selected", screenReady: ready, fixture: flow.fixture)
            case "fight":
                guard let enemyID = step.enemyID,
                      let route = R015AreaSceneRouting.routes.first(where: { $0.regionID == flow.regionID && $0.enemyIDs.contains(enemyID) }),
                      route.sceneID == step.expectedSceneID, route.areaID == step.expectedAreaID,
                      step.selectionBasis == "activeFightEnemy",
                      let enemy = catalog.enemies.first(where: { $0.id == enemyID && $0.regionID == flow.regionID }) else {
                    throw AreaFlowHookError.invalid("unknown encounter: \(step.id)")
                }
                // Actual expedition/encounter command path; QA fixture only supplies gate markers.
                try await dispatchArea(.startExpeditionAt(regionID: flow.regionID, now: Date()), engine: engine)
                chosenRegion = flow.regionID
                tab = "探索"
                activeAreaFightEnemyID = enemy.id
                syncScene()
                scene.setEnemy(enemy.id)
                let ready = await waitForAreaSceneFrame(after: scene.frames)
                try await writeAreaRouteCheckpoint(runID: flow.runID, stepIndex: index, stepID: step.id,
                                                   phase: "fight_started", screenReady: ready, fixture: flow.fixture)
                fight(enemy)
                let deadline = Date().addingTimeInterval(360)
                while busy && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
                guard !busy, state.lastEncounterID == enemy.id, state.lastCombatResult != nil else {
                    throw AreaFlowHookError.invalid("encounter did not reach a terminal result: \(enemy.id)")
                }
                writeQASaveReadbackIfRequested()
                let returnedReady = await waitForAreaSceneFrame(after: scene.frames)
                try await writeAreaRouteCheckpoint(runID: flow.runID, stepIndex: index, stepID: step.id,
                                                   phase: "fight_returned", screenReady: returnedReady, fixture: flow.fixture)
            default: throw AreaFlowHookError.invalid("unknown step kind: \(step.kind)")
            }
        }
    }

    private func executeAreaFallbackProbe(argument: String) async throws {
        guard let catalog, let engine else { throw AreaFlowHookError.invalid("catalog or engine unavailable") }
        guard let probe = AreaFlowQAHook.probe,
              let route = R015AreaSceneRouting.routes.first(where: { $0.variantID == probe.variantID }),
              ["R01", "R04"].contains(route.regionID),
              let enemyID = route.enemyIDs.first else { throw AreaFlowHookError.invalid("unsupported variant probe: \(argument)") }
        guard catalog.enemies.contains(where: { $0.id == enemyID }) else { throw AreaFlowHookError.invalid("probe encounter missing from catalog") }
        let parts = argument.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, String(parts[0]) == probe.variantID else { throw AreaFlowHookError.invalid("probe argument mismatch") }
        let isLayered = route.variantID.map { R015AreaSceneRouting.variantAvailability(index: ArtLibrary.index, artRoot: ArtLibrary.root).layeredIDs.contains($0) } ?? false
        if probe.kind == .decodeLayer && !isLayered { throw AreaFlowHookError.invalid("decode-layer probe does not match route mode") }
        if probe.kind == .decodeFullFrame && isLayered { throw AreaFlowHookError.invalid("decode-fullframe probe does not match route mode") }
        chosenRegion = route.regionID
        tab = "探索"
        try await dispatchArea(.startExpeditionAt(regionID: route.regionID, now: Date()), engine: engine)
        activeAreaFightEnemyID = enemyID
        syncScene()
        scene.setEnemy(enemyID)
        let ready = await waitForAreaSceneFrame(after: scene.frames)
        let runID = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--qa-save-key=") })
            .map { String($0.dropFirst("--qa-save-key=".count)) } ?? "area-flow-fallback"
        try await writeAreaRouteCheckpoint(runID: runID, stepIndex: 0, stepID: probe.variantID,
                                           phase: "fallback_rendered", screenReady: ready, fixture: "area-routing")
    }

    private func dispatchArea(_ command: GameCommand, engine: GameEngine) async throws {
        _ = try await engine.dispatch(command, operationID: UUID(), expectedRevision: state.revision)
        await refresh()
        writeQASaveReadbackIfRequested()
    }

    private func waitForAreaSceneFrame(after start: Int) async -> Bool {
        for _ in 0..<240 {
            if scene.view != nil && scene.frames > start { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    private func writeAreaRouteCheckpoint(runID: String, stepIndex: Int, stepID: String,
                                          phase: String, screenReady: Bool, fixture: String) async throws {
        let auditData = scene.artAuditJSON().data(using: .utf8) ?? Data()
        let audit = (try? JSONSerialization.jsonObject(with: auditData)) as? [String: Any] ?? [:]
        let area = audit["areaBackground"] as? [String: Any] ?? [:]
        let renderedID = area["renderedBackgroundID"] as? String ?? ""
        let states = audit["states"] as? [String: Any] ?? [:]
        let material = state.gatherTargetMaterialID
        let result: [String: Any] = [
            "runID": runID, "stepIndex": stepIndex, "stepID": stepID, "phase": phase,
            "fixture": fixture, "activeRegionID": state.activeRegionID ?? "",
            "gatherTargetMaterialID": material as Any? ?? NSNull(),
            "activeFightEnemyID": activeAreaFightEnemyID as Any? ?? NSNull(),
            "revision": state.revision, "areaBackground": area,
            "backgroundLoaded": states["background_\(renderedID)"] as? Bool ?? false,
            "screenReady": screenReady,
            "lastEncounterID": state.lastEncounterID as Any? ?? NSNull(),
            "combatWon": state.lastCombatResult?.won as Any? ?? NSNull(),
            "fallbackInjection": AreaFlowQAHook.injectionReceipt as Any? ?? NSNull()
        ]
        guard let saveURL else { throw AreaFlowHookError.invalid("isolated save path unavailable") }
        let support = saveURL.deletingLastPathComponent()
        let token = AreaFlowQAHook.checkpointToken(runID: runID, stepIndex: stepIndex, phase: phase)
        let checkpoints = support.appendingPathComponent("area_route_checkpoints", isDirectory: true)
        let acknowledgements = support.appendingPathComponent("area_route_acks", isDirectory: true)
        try FileManager.default.createDirectory(at: checkpoints, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: acknowledgements, withIntermediateDirectories: true)
        let bytes = try routeReceiptBytes(result)
        let checkpointURL = checkpoints.appendingPathComponent(token + ".json")
        guard !FileManager.default.fileExists(atPath: checkpointURL.path) else {
            throw AreaFlowHookError.invalid("checkpoint already exists: \(token)")
        }
        try bytes.write(to: checkpointURL, options: .atomic)
        try bytes.write(to: support.appendingPathComponent("last_area_route.json"), options: .atomic)

        // The host runner captures this exact frame and current persisted snapshot,
        // then writes an atomic token-matched ACK. No time-delay guess advances flow.
        let ackURL = acknowledgements.appendingPathComponent(token + ".json")
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: ackURL.path),
               let ackData = try? Data(contentsOf: ackURL),
               let ack = try? JSONSerialization.jsonObject(with: ackData) as? [String: Any],
               ack["token"] as? String == token,
               let accepted = ack["accepted"] as? Bool {
                guard accepted else {
                    let reason = ack["error"] as? String ?? "host runner rejected checkpoint"
                    try writeAreaRouteValue(["runID": runID, "stepIndex": stepIndex, "stepID": stepID,
                                             "phase": "ack_rejected", "token": token, "reason": reason,
                                             "revision": state.revision])
                    throw AreaFlowHookError.invalid("host runner rejected checkpoint \(token): \(reason)")
                }
                guard let screenshotSHA = ack["screenshotSHA256"] as? String,
                      isSHA256(screenshotSHA),
                      let readbackSHA = ack["saveReadbackSHA256"] as? String,
                      isSHA256(readbackSHA) else {
                    throw AreaFlowHookError.invalid("host runner ACK has invalid evidence hashes: \(token)")
                }
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try writeAreaRouteValue(["runID": runID, "stepIndex": stepIndex, "stepID": stepID,
                                 "phase": "ack_timeout", "token": token, "revision": state.revision])
        throw AreaFlowHookError.invalid("host runner ACK timeout after 30 seconds: \(token)")
    }

    private func writeAreaRouteError(_ message: String) {
        try? writeAreaRouteValue(["phase": "error", "message": message, "revision": state.revision])
    }

    private func writeAreaRouteValue(_ value: [String: Any]) throws {
        guard let saveURL else { throw AreaFlowHookError.invalid("isolated save path unavailable") }
        let bytes = try routeReceiptBytes(value)
        let destination = saveURL.deletingLastPathComponent().appendingPathComponent("last_area_route.json")
        try bytes.write(to: destination, options: .atomic)
    }

    private func routeReceiptBytes(_ value: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw AreaFlowHookError.invalid("receipt encoding failed") }
        let wrapper: [String: Any] = ["kind": "area_route", "value": json, "revision": state.revision,
                                      "date": ISO8601DateFormatter().string(from: Date())]
        return try JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys])
    }

    private func isSHA256(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }
}

private enum AreaFlowHookError: Error { case invalid(String) }
