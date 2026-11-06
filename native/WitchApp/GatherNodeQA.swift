import Foundation
import CryptoKit
import SpriteKit
import UIKit
import CoreGraphics

/// Isolated runtime audit for the R016 gathering props. Node-only runs never call the
/// game engine. Optional claim runs use the real collect() path on a QA-prefixed save.
@MainActor extension GameModel {
    func runGatherNodeRuntimeQAIfRequested() {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"),
              args.contains("--qa-gather-node-audit"),
              let saveURL,
              saveURL.lastPathComponent.hasPrefix("qa-"),
              let saveKeyArg = args.first(where: { $0.hasPrefix("--qa-save-key=") }) else { return }
        let key = String(saveKeyArg.dropFirst("--qa-save-key=".count)).filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !key.isEmpty, saveURL.lastPathComponent == "qa-\(key)-save.json" else { return }
        let outputURL = saveURL.deletingLastPathComponent().appendingPathComponent("gather_node_qa_\(key).json")
        let selectedArg = args.first(where: { $0.hasPrefix("--qa-gather-node-id=") })
            .map { String($0.dropFirst("--qa-gather-node-id=".count)) }
        let claimMode = args.first(where: { $0.hasPrefix("--qa-gather-claim=") })
            .map { String($0.dropFirst("--qa-gather-claim=".count)) }
        let runTransitions = args.contains("--qa-gather-node-transitions")
        Task { @MainActor in
            await runGatherNodeRuntimeAudit(outputURL: outputURL, saveKey: key,
                                           selectedMaterialID: selectedArg,
                                           claimMode: claimMode,
                                           runTransitions: runTransitions)
        }
        #endif
    }

    private func runGatherNodeRuntimeAudit(outputURL: URL, saveKey: String,
                                          selectedMaterialID: String?, claimMode: String?,
                                          runTransitions: Bool) async {
        let began = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let saveURL, saveURL.lastPathComponent == "qa-\(saveKey)-save.json",
              let initialSave = try? Data(contentsOf: saveURL) else {
            Self.atomicWrite(["schema":"R016_GATHER_NODE_RUNTIME_QA_R001","status":"UNSAFE_OR_MISSING_QA_SAVE"],to:outputURL)
            return
        }
        let initialSnapshot = (try? encoder.encode(state)) ?? Data()
        let initialRevision = state.revision
        let indexURL = ArtLibrary.root.appendingPathComponent("runtime_index.json")
        let indexData = (try? Data(contentsOf: indexURL)) ?? Data()
        let availability = R015AreaSceneRouting.variantAvailability(index: ArtLibrary.index, artRoot: ArtLibrary.root)
        let materials = R015AreaSceneRouting.routes.flatMap { route in
            route.gatherableMaterialIDs.map { (route, $0) }
        }.sorted { $0.1 < $1.1 }
        let requested = selectedMaterialID.map { id in materials.filter { $0.1 == id } } ?? materials
        var rows: [[String: Any]] = []
        var previousNodeName: String?
        let started = Date()
        let originalTab = tab
        let originalRegion = chosenRegion
        let originalFighting = fighting

        do {
            guard !requested.isEmpty else { throw CoreError.invalidCommand("no matching R4 gather material IDs") }
            if let claimMode, !["positive", "no-gain", "error"].contains(claimMode) {
                throw CoreError.invalidCommand("claim mode must be positive, no-gain, or error")
            }
            tab = "探索"
            if let activeRegion = state.activeRegionID { chosenRegion = activeRegion }
            fighting = false
            syncScene()
            try await Task.sleep(for: .milliseconds(700))

            for (route, materialID) in requested {
                chosenRegion = route.regionID
                let resolution = R015AreaSceneRouting.resolve(
                    regionID: route.regionID,
                    selectedGatherMaterialID: materialID,
                    availableVariantIDs: availability.fullFrameIDs.union(availability.layeredIDs),
                    layeredVariantIDs: availability.layeredIDs)
                scene.configure(place: .field(route.regionID), areaResolution: resolution,
                                selectedGatherMaterialID: materialID,
                                cosmetics: sceneAppearance, furniture: sceneFurniture)
                try await Task.sleep(for: .milliseconds(100))

                let nodeID = R016GatherNodePresentation.nodeID(for: materialID) ?? ""
                let imageID = nodeID + "__present"
                let entry = ArtLibrary.index[nodeID] ?? [:]
                let selected = entry["selectedPNG"] as? [String: String] ?? [:]
                let relativePath = selected["present"] ?? ""
                let pngURL = ArtLibrary.root.appendingPathComponent(relativePath)
                let pngData = (try? Data(contentsOf: pngURL)) ?? Data()
                let decodedImage = ArtLibrary.image(imageID)
                let matchingNodes = scene.children.filter { $0.name == "gather_node:" + materialID }
                let node = matchingNodes.first as? SKSpriteNode
                let textureSize = node?.texture?.size() ?? .zero
                let imageSize = decodedImage?.size ?? .zero
                let sceneSize = scene.size
                let expectedHeight = sceneSize.width * R016GatherNodePresentation.displayHeightMultiplier
                let expectedWidth = imageSize.height > 0 ? expectedHeight * imageSize.width / imageSize.height : 0
                let auditString = scene.artAuditJSON()
                let auditObject = Self.gatherNodeAudit(from: auditString)
                let auditStates = Self.gatherNodeStates(from: auditString)
                let nodeFrame = node?.calculateAccumulatedFrame() ?? .zero
                let currentNodeNames = scene.children.compactMap { child -> String? in
                    guard let name = child.name, name.hasPrefix("gather_node:") else { return nil }
                    return name
                }
                let cleanupOK = previousNodeName.map { !currentNodeNames.contains($0) } ?? true
                let textureRatio = textureSize.height > 0 ? textureSize.width / textureSize.height : 0
                let imageRatio = imageSize.height > 0 ? imageSize.width / imageSize.height : 0
                let texturePixelSHA = Self.sha256(node?.texture?.cgImage())
                let imagePixelSHA = Self.sha256(decodedImage?.cgImage)
                let presentationBefore = node.map {
                    GatherNodePresentation.qaSnapshot(on: $0, materialID: materialID)
                } ?? [:]
                let stateMatches = auditObject["materialID"] as? String == materialID &&
                    auditObject["nodeID"] as? String == nodeID &&
                    auditObject["state"] as? String == "present" &&
                    auditObject["textureID"] as? String == imageID &&
                    auditObject["loaded"] as? Bool == true
                let positionMatches = node.map {
                    abs($0.position.x - sceneSize.width * R016GatherNodePresentation.normalizedGroundPoint.x) < 0.5 &&
                    abs($0.position.y - sceneSize.height * R016GatherNodePresentation.normalizedGroundPoint.y) < 0.5
                } ?? false
                let row: [String: Any] = [
                    "materialID": materialID, "nodeID": nodeID, "regionID": route.regionID,
                    "sceneID": route.sceneID, "areaID": route.areaID,
                    "resolution": resolution.qaReceipt(),
                    "sourcePNG": relativePath, "sourcePNGExists": !pngData.isEmpty,
                    "sourcePNG_SHA256": Self.sha256(pngData),
                    "sourcePNGDecoded": decodedImage != nil,
                    "sourceImageSize": [imageSize.width, imageSize.height],
                    "runtimeNodeCount": matchingNodes.count,
                    "runtimeTextureSize": [textureSize.width, textureSize.height],
                    "expectedRuntimeTextureID": imageID,
                    "runtimeTexturePixelSHA256": texturePixelSHA,
                    "sourceImagePixelSHA256": imagePixelSHA,
                    "runtimeNodeFrame": ["x": nodeFrame.origin.x, "y": nodeFrame.origin.y,
                                         "width": nodeFrame.width, "height": nodeFrame.height],
                    "r018PresentationBefore": presentationBefore,
                    "expectedNodeSize": ["width": expectedWidth, "height": expectedHeight],
                    "textureAspectMatchesSource": abs(textureRatio - imageRatio) < 0.01,
                    "groundPositionMatches": positionMatches,
                    "auditStateMatches": stateMatches,
                    "artAuditLoaded": auditStates["gather_node_" + nodeID] as? Bool == true,
                    "previousNodeRemoved": cleanupOK,
                    "sceneAttachedToView": scene.view != nil,
                    "individualScreenshotRequired": selectedMaterialID != nil,
                    "assertions": [
                        "validR4Projection": resolution.selectionBasis == .selectedGatherMaterial && resolution.route.sceneID == route.sceneID,
                        "sourcePNGExistsAndDecodes": !pngData.isEmpty && decodedImage != nil,
                        "exactlyOneRuntimeNode": matchingNodes.count == 1,
                        "nodeHasTexture": node?.texture != nil,
                        "runtimeTextureMatchesDecodedSource": !texturePixelSHA.isEmpty && texturePixelSHA == imagePixelSHA,
                        "aspectMatchesSource": abs(textureRatio - imageRatio) < 0.01,
                        "positionMatchesProjection": positionMatches,
                        "initialAuditMatchesTextureAndState": stateMatches,
                        "runtimeArtAuditLoaded": auditStates["gather_node_" + nodeID] as? Bool == true,
                        "routeSwitchRemovedPreviousNode": cleanupOK,
                        "sceneIsHosted": scene.view != nil,
                        "positiveFiniteGeometry": nodeFrame.width.isFinite && nodeFrame.height.isFinite && nodeFrame.width > 0 && nodeFrame.height > 0
                    ]
                ]
                rows.append(row)
                previousNodeName = "gather_node:" + materialID

                if runTransitions {
                    let cueStartedAt = ProcessInfo.processInfo.systemUptime
                    scene.playGatherCollection(materialID: materialID)
                    try await Task.sleep(for: .milliseconds(120))
                    let cueAt120Elapsed = ProcessInfo.processInfo.systemUptime - cueStartedAt
                    let cueAt120 = Self.gatherNodeSprite(scene, materialID: materialID).map {
                        GatherNodePresentation.qaSnapshot(on: $0, materialID: materialID)
                    } ?? [:]
                    let collectedProjection = R016GatherNodePresentation.projection(
                        materialID: materialID, regionID: route.regionID, resolution: resolution, state: .collected)
                    let collectedID = collectedProjection.map(R016GatherNodePresentation.imageID(for:)) ?? ""
                    let collectedPixelSHA = Self.sha256(Self.gatherNodeSprite(scene, materialID: materialID)?.texture?.cgImage())
                    let collectedAudit = Self.gatherNodeAudit(from: scene.artAuditJSON())
                    let waitTo450 = max(0, 0.45 - (ProcessInfo.processInfo.systemUptime - cueStartedAt))
                    if waitTo450 > 0 { try await Task.sleep(for: .seconds(waitTo450)) }
                    let cueAt450Elapsed = ProcessInfo.processInfo.systemUptime - cueStartedAt
                    let cueAt450 = Self.gatherNodeSprite(scene, materialID: materialID).map {
                        GatherNodePresentation.qaSnapshot(on: $0, materialID: materialID)
                    } ?? [:]
                    let waitToSettle = max(0, 1.87 - (ProcessInfo.processInfo.systemUptime - cueStartedAt))
                    if waitToSettle > 0 { try await Task.sleep(for: .seconds(waitToSettle)) }
                    let presentPixelSHA = Self.sha256(Self.gatherNodeSprite(scene, materialID: materialID)?.texture?.cgImage())
                    let endAudit = Self.gatherNodeAudit(from: scene.artAuditJSON())
                    let presentationAtEnd = Self.gatherNodeSprite(scene, materialID: materialID).map {
                        GatherNodePresentation.qaSnapshot(on: $0, materialID: materialID)
                    } ?? [:]
                    rows[rows.count - 1]["presentationTransition"] = endAudit
                    rows[rows.count - 1]["collectedTexturePixelSHA256"] = collectedPixelSHA
                    rows[rows.count - 1]["expectedCollectedTextureID"] = collectedID
                    rows[rows.count - 1]["collectedAudit"] = collectedAudit
                    rows[rows.count - 1]["presentTexturePixelSHA256AfterRespawn"] = presentPixelSHA
                    rows[rows.count - 1]["r018PresentationCueAt120ms"] = [
                        "sampleElapsedSeconds": cueAt120Elapsed,
                        "withinCueSampleWindow": cueAt120Elapsed >= 0.10 && cueAt120Elapsed <= 0.32,
                        "snapshot": cueAt120
                    ]
                    rows[rows.count - 1]["r018PresentationCueAt450ms"] = [
                        "sampleElapsedSeconds": cueAt450Elapsed,
                        "minimumElapsedMet": cueAt450Elapsed >= 0.45,
                        "snapshot": cueAt450
                    ]
                    rows[rows.count - 1]["r018PresentationAtEnd"] = presentationAtEnd
                    let expectedPresentSHA = rows[rows.count - 1]["sourceImagePixelSHA256"] as? String ?? ""
                    let expectedCue = GatherNodePresentation.qaExpectsCollectionCue(for: materialID)
                    let expectedShadowCount = GatherNodePresentation.qaExpectedContactShadowCount(for: materialID)
                    let expectedCueAt120Count = expectedCue ? 1 : 0
                    let cueAt120Count = cueAt120["cueCount"] as? Int ?? -1
                    let cueAt450Count = cueAt450["cueCount"] as? Int ?? -1
                    let cueInvocationsAt120 = cueAt120["cueInvocationCount"] as? Int ?? -1
                    let cueInvocationsAt450 = cueAt450["cueInvocationCount"] as? Int ?? -1
                    let shadowBeforeCount = presentationBefore["contactShadowCount"] as? Int ?? -1
                    let shadowAt120Count = cueAt120["contactShadowCount"] as? Int ?? -1
                    let shadowAt450Count = cueAt450["contactShadowCount"] as? Int ?? -1
                    let cueAlphaAt120 = cueAt120["cueAlpha"] as? Double ?? 0
                    let geometryUnchanged = Self.sameSpriteGeometry(presentationBefore, cueAt120) &&
                        Self.sameSpriteGeometry(presentationBefore, cueAt450) &&
                        Self.sameSpriteGeometry(presentationBefore, presentationAtEnd)
                    let expectedCueVisibleAt120 = !expectedCue || (
                        cueAt120Elapsed >= 0.10 && cueAt120Elapsed <= 0.32 &&
                        cueAt120Count == 1 && cueAlphaAt120 > 0 &&
                        cueAt120["cueActionActive"] as? Bool == true
                    )
                    let r018Pass = shadowBeforeCount == expectedShadowCount &&
                        shadowAt120Count == expectedShadowCount && shadowAt450Count == expectedShadowCount &&
                        cueAt120Count == expectedCueAt120Count && cueAt120Count <= 1 &&
                        cueInvocationsAt120 == expectedCueAt120Count &&
                        cueInvocationsAt450 == expectedCueAt120Count &&
                        cueAt450Count == 0 && cueAt450Elapsed >= 0.45 &&
                        expectedCueVisibleAt120 && geometryUnchanged
                    rows[rows.count - 1]["r018PresentationAssertions"] = [
                        "expectedShadowOwnership": shadowBeforeCount == expectedShadowCount &&
                            shadowAt120Count == expectedShadowCount && shadowAt450Count == expectedShadowCount,
                        "cueOwnershipAndNoDuplicate": cueAt120Count == expectedCueAt120Count && cueAt120Count <= 1,
                        "cueInvocationCountExact": cueInvocationsAt120 == expectedCueAt120Count &&
                            cueInvocationsAt450 == expectedCueAt120Count,
                        "cueVisibleAt120msWhenExpected": expectedCueVisibleAt120,
                        "noCueAtOrAfter450ms": cueAt450Count == 0 && cueAt450Elapsed >= 0.45,
                        "spriteGeometryUnchanged": geometryUnchanged,
                        "boundedPresentationPass": r018Pass
                    ]
                    rows[rows.count - 1]["presentationTransitionPassed"] =
                        collectedAudit["state"] as? String == "collected" &&
                        collectedAudit["textureID"] as? String == collectedID &&
                        !collectedPixelSHA.isEmpty && collectedPixelSHA != expectedPresentSHA &&
                        endAudit["state"] as? String == "present" && endAudit["textureID"] as? String == imageID &&
                        endAudit["transition"] as? String == "respawned" &&
                        presentPixelSHA == expectedPresentSHA && r018Pass
                    try await Task.sleep(for: .milliseconds(50))
                }
                if selectedMaterialID != nil { break } // Keep one selected material stable for an external screenshot/ACK.
            }

            let afterSweepSnapshot = (try? encoder.encode(state)) ?? Data()
            let afterSweepSave = (try? Data(contentsOf: saveURL)) ?? Data()
            let afterSweepRevision = state.revision
            let sweepInvariants: [String: Any] = [
                "snapshotUnchanged": initialSnapshot == afterSweepSnapshot,
                "revisionUnchanged": initialRevision == afterSweepRevision,
                "saveBytesUnchanged": Self.sha256(initialSave) == Self.sha256(afterSweepSave)
            ]
            var claimRow: [String: Any] = ["requested": claimMode != nil, "mode": claimMode ?? "none"]
            if let claimMode {
                tab = "探索"
                if let active = state.activeRegionID { chosenRegion = active }
                fighting = false
                syncScene()
                let before = state
                let beforeMaterials = before.materials
                collect()
                let deadline = Date().addingTimeInterval(10)
                while busy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
                let didTimeout = busy
                if !didTimeout && sheet == "採集の成果" { try await Task.sleep(for: .milliseconds(600)) }
                let summary = collectionSummary
                let errorValue = error
                let materialID = before.gatherTargetMaterialID
                let gained = materialID.map { max(0, (state.materials[$0] ?? 0) - (beforeMaterials[$0] ?? 0)) } ?? 0
                let cueBeforeDismiss = materialID.flatMap { id in
                    Self.gatherNodeSprite(scene, materialID: id).map {
                        GatherNodePresentation.qaSnapshot(on: $0, materialID: id)
                    }
                } ?? [:]
                let cueCountBeforeDismiss = cueBeforeDismiss["cueCount"] as? Int ?? -1
                let cueInvocationsBeforeDismiss = cueBeforeDismiss["cueInvocationCount"] as? Int ?? -1
                let claimSucceeded = !didTimeout && errorValue == nil && sheet == "採集の成果"
                let expectedModePass: Bool
                switch claimMode {
                case "positive": expectedModePass = claimSucceeded && gained > 0
                case "no-gain": expectedModePass = claimSucceeded && gained == 0
                default: expectedModePass = !didTimeout && errorValue != nil
                }
                let saveAfterClaim = (try? Data(contentsOf: saveURL)) ?? Data()
                let snapshotAfterClaim = (try? encoder.encode(state)) ?? Data()
                let errorInvariantsHold = claimMode != "error" || (
                    snapshotAfterClaim == (try? encoder.encode(before)) &&
                    state.revision == before.revision &&
                    Self.sha256(saveAfterClaim) == Self.sha256(afterSweepSave))
                claimRow = [
                    "requested": true, "mode": claimMode, "timedOut": didTimeout,
                    "claimSucceeded": claimSucceeded, "error": (errorValue as Any?) ?? NSNull(),
                    "materialID": (materialID as Any?) ?? NSNull(), "actualMaterialDelta": gained,
                    "actualSummaryEmpty": (summary?.isEmpty as Any?) ?? NSNull(),
                    "revisionBefore": before.revision, "revisionAfter": state.revision,
                    "saveBytesChanged": Self.sha256(saveAfterClaim) != Self.sha256(afterSweepSave),
                    "errorCaseStateAndSaveUnchanged": errorInvariantsHold,
                    "r018CueSnapshotBeforeDismiss": cueBeforeDismiss,
                    "r018CueInvocationsBeforeDismiss": cueInvocationsBeforeDismiss,
                    "r018CueExpectedForTarget": materialID.map(GatherNodePresentation.qaExpectsCollectionCue(for:)) ?? false,
                    "expectedModePassed": expectedModePass,
                    "noDirectGrantOrClockOverrideByHook": true,
                    "fixtureMayContainBackdatedElapsedTime": ProcessInfo.processInfo.arguments.contains("--qa-fixture=gathering")
                ]
                var claimCueMaxCount = cueCountBeforeDismiss
                var claimCueMaxInvocationCount = cueInvocationsBeforeDismiss
                var claimCueSampleCount = 0
                var claimCueNeverDuplicated = cueCountBeforeDismiss <= 1
                if claimSucceeded {
                    // Trigger normal SwiftUI dismissal; wait for its real onDismiss callback.
                    Self.atomicWrite(["stage":"claim_captured_before_sheet_dismissal","claim":claimRow],to:outputURL)
                    closeSheet()
                    let dismissDeadline = Date().addingTimeInterval(5)
                    var dismissAudit: [String: Any] = [:]
                    var observedCollected = false
                    var observedPresentAfterCollected = false
                    var noGainTextureStayedPresent = true
                    let expectedPresentPixelSHA = Self.sha256(
                        Self.gatherNodeSprite(scene, materialID: materialID ?? "")?.texture?.cgImage())
                    let expectedCollectedProjection: R016GatherNodePresentation.Projection? = {
                        guard let materialID else { return nil }
                        let currentResolution = R015AreaSceneRouting.resolve(
                            regionID: chosenRegion,
                            selectedGatherMaterialID: materialID,
                            availableVariantIDs: availability.fullFrameIDs.union(availability.layeredIDs),
                            layeredVariantIDs: availability.layeredIDs)
                        return R016GatherNodePresentation.projection(materialID: materialID,
                            regionID: chosenRegion, resolution: currentResolution, state: .collected)
                    }()
                    let expectedCollectedPixelSHA = expectedCollectedProjection.flatMap {
                        Self.sha256(ArtLibrary.image(R016GatherNodePresentation.imageID(for: $0))?.cgImage)
                    } ?? ""
                    repeat {
                        try await Task.sleep(for: .milliseconds(100))
                        dismissAudit = Self.gatherNodeAudit(from: scene.artAuditJSON())
                        let currentPixelSHA = Self.sha256(Self.gatherNodeSprite(scene, materialID: materialID ?? "")?.texture?.cgImage())
                        let cueSnapshot = materialID.flatMap { id in
                            Self.gatherNodeSprite(scene, materialID: id).map {
                                GatherNodePresentation.qaSnapshot(on: $0, materialID: id)
                            }
                        } ?? [:]
                        let cueCount = cueSnapshot["cueCount"] as? Int ?? -1
                        let cueInvocations = cueSnapshot["cueInvocationCount"] as? Int ?? -1
                        claimCueSampleCount += 1
                        claimCueMaxCount = max(claimCueMaxCount, cueCount)
                        claimCueMaxInvocationCount = max(claimCueMaxInvocationCount, cueInvocations)
                        claimCueNeverDuplicated = claimCueNeverDuplicated && cueCount <= 1
                        if dismissAudit["state"] as? String == "collected" && currentPixelSHA == expectedCollectedPixelSHA {
                            observedCollected = true
                        }
                        if observedCollected && dismissAudit["state"] as? String == "present" &&
                            dismissAudit["transition"] as? String == "respawned" &&
                            currentPixelSHA == expectedPresentPixelSHA {
                            observedPresentAfterCollected = true
                        }
                        if claimMode == "no-gain" && currentPixelSHA != expectedPresentPixelSHA {
                            noGainTextureStayedPresent = false
                        }
                        let reachedExpected = claimMode == "positive"
                            ? observedPresentAfterCollected
                            : dismissAudit["state"] as? String == "present"
                        if sheet == nil && reachedExpected { break }
                    } while Date() < dismissDeadline
                    if claimMode == "no-gain" {
                        // Observe the full visual claim window; a brief delayed animation must not pass.
                        let observationEnd = Date().addingTimeInterval(2.5)
                        while Date() < observationEnd {
                            try await Task.sleep(for: .milliseconds(100))
                            dismissAudit = Self.gatherNodeAudit(from: scene.artAuditJSON())
                            let currentPixelSHA = Self.sha256(Self.gatherNodeSprite(scene, materialID: materialID ?? "")?.texture?.cgImage())
                            let cueCount = materialID.flatMap { id -> Int? in
                                guard let node = Self.gatherNodeSprite(scene, materialID: id) else { return nil }
                                return GatherNodePresentation.qaSnapshot(on: node, materialID: id)["cueCount"] as? Int
                            } ?? 0
                            let cueInvocations = materialID.flatMap { id -> Int? in
                                guard let node = Self.gatherNodeSprite(scene, materialID: id) else { return nil }
                                return GatherNodePresentation.qaSnapshot(on: node, materialID: id)["cueInvocationCount"] as? Int
                            } ?? 0
                            claimCueSampleCount += 1
                            claimCueMaxCount = max(claimCueMaxCount, cueCount)
                            claimCueMaxInvocationCount = max(claimCueMaxInvocationCount, cueInvocations)
                            claimCueNeverDuplicated = claimCueNeverDuplicated && cueCount <= 1
                            if cueInvocations > cueInvocationsBeforeDismiss { claimCueMaxInvocationCount = max(claimCueMaxInvocationCount, cueInvocations) }
                            if currentPixelSHA != expectedPresentPixelSHA || dismissAudit["state"] as? String != "present" {
                                noGainTextureStayedPresent = false
                            }
                        }
                    }
                    claimRow["dismissedSheet"] = sheet == nil
                    claimRow["postDismissGatherNodeAudit"] = dismissAudit
                    let expectedCueForTarget = materialID.map(GatherNodePresentation.qaExpectsCollectionCue(for:)) ?? false
                    let cueInvocationDelta = cueInvocationsBeforeDismiss >= 0
                        ? claimCueMaxInvocationCount - cueInvocationsBeforeDismiss : -1
                    let cueCreationWasExpected = claimMode == "positive" && expectedCueForTarget
                    let claimCuePolicyPassed = claimCueNeverDuplicated &&
                        cueInvocationDelta == (cueCreationWasExpected ? 1 : 0) &&
                        (cueCreationWasExpected || claimCueMaxCount == cueCountBeforeDismiss)
                    claimRow["r018ClaimCueChecks"] = [
                        "materialID": (materialID as Any?) ?? NSNull(),
                        "actualMaterialDelta": gained,
                        "cueExpectedForSuccessfulTarget": expectedCueForTarget,
                        "maxCueChildCount": claimCueMaxCount,
                        "maxCueInvocationCount": claimCueMaxInvocationCount,
                        "cueInvocationDelta": cueInvocationDelta,
                        "samplesAfterDismiss": claimCueSampleCount,
                        "neverDuplicated": claimCueNeverDuplicated,
                        "positiveCueObservedWhenExpected": !cueCreationWasExpected || cueInvocationDelta == 1,
                        "positiveR01G1NoCueControl": materialID == "M_R01_G1" && cueInvocationDelta == 0,
                        "noCueWhenRewardWasZero": claimMode != "no-gain" || cueInvocationDelta == 0,
                        "claimCuePolicyPassed": claimCuePolicyPassed
                    ]
                    if claimMode == "positive" {
                        claimRow["observedCollectedTexture"] = observedCollected
                        claimRow["observedPresentAfterCollectedTexture"] = observedPresentAfterCollected
                        claimRow["returnedToPresentAfterClaim"] = observedCollected && observedPresentAfterCollected
                    } else {
                        claimRow["noGainDidNotAnimate"] = noGainTextureStayedPresent &&
                            dismissAudit["transition"] as? String != "collecting" && dismissAudit["state"] as? String == "present"
                        claimRow["r018NoGainCueStayedAbsent"] = cueInvocationDelta == 0
                    }
                } else if claimMode == "error" {
                    claimRow["errorStateAndSaveUnchanged"] = errorInvariantsHold
                    if let materialID = before.gatherTargetMaterialID {
                        let observationEnd = Date().addingTimeInterval(0.45)
                        while Date() < observationEnd {
                            try await Task.sleep(for: .milliseconds(100))
                            let cueCount = Self.gatherNodeSprite(scene, materialID: materialID).map {
                                GatherNodePresentation.qaSnapshot(on: $0, materialID: materialID)["cueCount"] as? Int ?? 0
                            } ?? 0
                            let cueInvocations = Self.gatherNodeSprite(scene, materialID: materialID).map {
                                GatherNodePresentation.qaSnapshot(on: $0, materialID: materialID)["cueInvocationCount"] as? Int ?? 0
                            } ?? 0
                            claimCueSampleCount += 1
                            claimCueMaxCount = max(claimCueMaxCount, cueCount)
                            claimCueMaxInvocationCount = max(claimCueMaxInvocationCount, cueInvocations)
                            claimCueNeverDuplicated = claimCueNeverDuplicated && cueCount <= 1
                        }
                    }
                    let errorCueInvocationDelta = cueInvocationsBeforeDismiss >= 0
                        ? claimCueMaxInvocationCount - cueInvocationsBeforeDismiss : -1
                    claimRow["r018ErrorCueStayedAbsent"] = errorCueInvocationDelta == 0
                    claimRow["r018ClaimCueChecks"] = [
                        "materialID": (before.gatherTargetMaterialID as Any?) ?? NSNull(),
                        "actualMaterialDelta": gained,
                        "maxCueChildCount": claimCueMaxCount,
                        "maxCueInvocationCount": claimCueMaxInvocationCount,
                        "cueInvocationDelta": errorCueInvocationDelta,
                        "samplesAfterAttempt": claimCueSampleCount,
                        "neverDuplicated": claimCueNeverDuplicated,
                        "errorCueStayedAbsent": errorCueInvocationDelta == 0,
                        "claimCuePolicyPassed": errorCueInvocationDelta == 0 && claimCueNeverDuplicated
                    ]
                }
            }

            if selectedMaterialID == nil {
                tab = originalTab
                chosenRegion = originalRegion
                fighting = originalFighting
                syncScene()
            }
            let finalSnapshot = (try? encoder.encode(state)) ?? Data()
            let finalSave = (try? Data(contentsOf: saveURL)) ?? Data()
            let claimExpectedPass = claimMode == nil || claimRow["expectedModePassed"] as? Bool == true
            let shadowOwnerIDs = rows.compactMap { row -> String? in
                guard let snapshot = row["r018PresentationBefore"] as? [String: Any],
                      (snapshot["contactShadowCount"] as? Int ?? 0) > 0 else { return nil }
                return row["materialID"] as? String
            }.sorted()
            let cueOwnerIDsObserved = rows.compactMap { row -> String? in
                guard let id = row["materialID"] as? String,
                      GatherNodePresentation.qaExpectsCollectionCue(for: id),
                      let sample = row["r018PresentationCueAt120ms"] as? [String: Any],
                      let snapshot = sample["snapshot"] as? [String: Any],
                      snapshot["cueCount"] as? Int == 1 else { return nil }
                return id
            }.sorted()
            let requestedIDs = Set(requested.map { $0.1 })
            let expectedShadowOwnerIDs = ["M_R04_G1", "M_R04_G3"].filter { requestedIDs.contains($0) }
            let expectedCueOwnerIDs = ["M_R01_G3", "M_R04_G1", "M_R04_G3"].filter { requestedIDs.contains($0) }
            let presentationOwnershipPassed = !runTransitions || (
                shadowOwnerIDs == expectedShadowOwnerIDs && cueOwnerIDsObserved == expectedCueOwnerIDs
            )
            let transitionChecks = rows.allSatisfy { $0["presentationTransitionPassed"] as? Bool ?? true } &&
                presentationOwnershipPassed
            let nodeChecks = rows.flatMap { ($0["assertions"] as? [String: Bool] ?? [:]).values }
            let allNodesPassed = rows.count == requested.count && nodeChecks.allSatisfy { $0 }
            let sweepPassed = sweepInvariants.values.allSatisfy { $0 as? Bool == true }
            let claimPresentationPassed: Bool
            let claimCueChecks = claimRow["r018ClaimCueChecks"] as? [String: Any] ?? [:]
            let claimCuePolicyPassed = claimCueChecks["claimCuePolicyPassed"] as? Bool == true
            if claimMode == "positive" {
                claimPresentationPassed = claimRow["returnedToPresentAfterClaim"] as? Bool == true && claimCuePolicyPassed
            }
            else if claimMode == "no-gain" {
                claimPresentationPassed = claimRow["noGainDidNotAnimate"] as? Bool == true && claimCuePolicyPassed
            }
            else if claimMode == "error" {
                claimPresentationPassed = claimRow["errorStateAndSaveUnchanged"] as? Bool == true && claimCuePolicyPassed
            }
            else { claimPresentationPassed = true }
            let status = allNodesPassed && transitionChecks && sweepPassed && claimExpectedPass && claimPresentationPassed
                ? "RUNTIME_NODES_PASS" : "RUNTIME_NODES_FAIL"
            let output: [String: Any] = [
                "schema": "R016_GATHER_NODE_RUNTIME_QA_R001",
                "status": status,
                "startedAt": began, "elapsedSeconds": Date().timeIntervalSince(started),
                "appBuildPath": Bundle.main.bundleURL.path,
                "runtimeIndexSHA256": Self.sha256(indexData),
                "saveFile": saveURL.lastPathComponent, "saveKey": saveKey,
                "saveBeforeSHA256": Self.sha256(initialSave),
                "snapshotBeforeSHA256": Self.sha256(initialSnapshot),
                "revisionBefore": initialRevision,
                "mode": selectedMaterialID == nil ? "sequential_all20_no_individual_screenshots" : "single_material_hold_for_external_capture",
                "requestedMaterialID": (selectedMaterialID as Any?) ?? NSNull(),
                "individualScreenshotInstruction": selectedMaterialID == nil ? "capture a separate single-ID launch for visual proof" : "capture this stable scene before relaunching",
                "nodeCount": rows.count, "allNodesPassed": allNodesPassed,
                "nodeSweepInvariants": sweepInvariants,
                "transitionChecksPassed": transitionChecks,
                "r018PresentationDiagnostics": [
                    "shadowOwnerIDs": shadowOwnerIDs,
                    "expectedShadowOwnerIDs": expectedShadowOwnerIDs,
                    "cueOwnerIDsObservedAt120ms": cueOwnerIDsObserved,
                    "expectedCueOwnerIDs": expectedCueOwnerIDs,
                    "exactOwnershipPassed": presentationOwnershipPassed
                ],
                "claim": claimRow, "claimAssertionsPassed": claimExpectedPass && claimPresentationPassed,
                "finalSnapshotSHA256": Self.sha256(finalSnapshot),
                "finalSaveSHA256": Self.sha256(finalSave),
                "rows": rows, "humanApproval": false,
                "nodeSweepIssuedNoGameCommands": true,
                "claimCaseUsesRealGameModelCollect": claimMode != nil,
                "fixtureMayContainBackdatedElapsedTime": ProcessInfo.processInfo.arguments.contains("--qa-fixture=gathering")
            ]
            Self.atomicWrite(output,to:outputURL)
        } catch {
            Self.atomicWrite(["schema":"R016_GATHER_NODE_RUNTIME_QA_R001","status":"HARNESS_ERROR",
                              "startedAt":began,"error":String(reflecting:error)],to:outputURL)
        }
    }

    private static func gatherNodeAudit(from json: String) -> [String: Any] {
        guard let data=json.data(using:.utf8),
              let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return root["gatherNode"] as? [String:Any] ?? [:]
    }

    private static func gatherNodeStates(from json: String) -> [String: Any] {
        guard let data=json.data(using:.utf8),
              let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return root["states"] as? [String:Any] ?? [:]
    }

    private static func gatherNodeSprite(_ scene: LivingScene, materialID: String) -> SKSpriteNode? {
        scene.children.first { $0.name == "gather_node:" + materialID } as? SKSpriteNode
    }

    private static func sameSpriteGeometry(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        ["spriteSize", "spritePosition", "spriteAnchor"].allSatisfy { key in
            (lhs[key] as? [Double]) == (rhs[key] as? [Double])
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ image: CGImage?) -> String {
        guard let image else { return "" }
        let width=image.width, height=image.height
        guard width>0,height>0 else{return ""}
        let bytesPerRow=width*4
        var pixels=[UInt8](repeating:0,count:height*bytesPerRow)
        let rendered=pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base=buffer.baseAddress,
                  let context=CGContext(data:base,width:width,height:height,bitsPerComponent:8,
                    bytesPerRow:bytesPerRow,space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else{return false}
            context.interpolationQuality = .none
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            return true
        }
        guard rendered else{return ""}
        var data=Data()
        var w=UInt32(width).bigEndian, h=UInt32(height).bigEndian
        withUnsafeBytes(of:&w){data.append(contentsOf:$0)}
        withUnsafeBytes(of:&h){data.append(contentsOf:$0)}
        data.append(contentsOf:pixels)
        return sha256(data)
    }

    private static func atomicWrite(_ object: [String: Any], to url: URL) {
        guard JSONSerialization.isValidJSONObject(object),
              let data=try? JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try? data.write(to:url,options:.atomic)
    }
}
