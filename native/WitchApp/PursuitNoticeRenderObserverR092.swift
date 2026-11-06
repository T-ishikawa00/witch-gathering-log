import SpriteKit
import UIKit

/// Opt-in diagnostic only. It records SpriteKit state after scene actions and
/// notice reflow, immediately before render. It does not claim pixel visibility.
@MainActor final class PursuitNoticeRenderObserverR092 {
    static let argument = "--qa-pursuit-notice-render-r092"
    static let keyPrefix = "--qa-save-key="
    static let rowLimit = 1_024

    private(set) var rows: [[String: Any]] = []
    private(set) var cues: [[String: Any]] = []
    private(set) var removals: [[String: Any]] = []
    private(set) var status = "TRACE_ONLY_PENDING_VISUAL_REVIEW"
    private(set) var overflowCount = 0
    let saveKey: String

    private var cueByRoot: [String: [String: Any]] = [:]
    private var captureWindow = PursuitNoticeCaptureWindowR092()
    private weak var marker: SKNode?
    private var markerSequence = 0

    init?(arguments: [String]) {
        guard Self.isRequested(arguments: arguments),
              let keyArg = arguments.first(where: { $0.hasPrefix(Self.keyPrefix) }) else { return nil }
        let key = String(keyArg.dropFirst(Self.keyPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        saveKey = key
    }

    static func isRequested(arguments: [String]) -> Bool {
        guard arguments.contains("--qa-isolated"), arguments.contains(argument),
              let keyArg = arguments.first(where: { $0.hasPrefix(keyPrefix) }) else { return false }
        return !String(keyArg.dropFirst(keyPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func recordInstall(rootID: String, sourceID: String, targetID: String,
                       effectID: String, sceneFrame: Int, sceneTime: TimeInterval,
                       spriteKitTime: TimeInterval, sceneGeneration: Int) {
        let row: [String: Any] = [
            "rootActionID": rootID, "sourceID": sourceID, "targetID": targetID,
            "effectID": effectID, "sceneFrame": sceneFrame,
            "sceneTime": sceneTime, "spriteKitTime": spriteKitTime,
            "systemUptime": ProcessInfo.processInfo.systemUptime,
            "sceneGeneration": sceneGeneration,
            "phase": "cue_handler_after_install_before_render"
        ]
        cues.append(row)
        cueByRoot[rootID] = row
        captureWindow.recordInstall(rootID: rootID, generation: sceneGeneration)
    }

    func recordRemoval(rootID: String, reason: String, sceneFrame: Int,
                       sceneTime: TimeInterval, spriteKitTime: TimeInterval,
                       sceneGeneration: Int) {
        captureWindow.recordRemoval(rootID: rootID, sceneFrame: sceneFrame)
        removals.append([
            "rootActionID": rootID, "sourceID": cueByRoot[rootID]?["sourceID"] as? String ?? "",
            "targetID": cueByRoot[rootID]?["targetID"] as? String ?? "",
            "effectID": cueByRoot[rootID]?["effectID"] as? String ?? "",
            "reason": reason,
            "sceneFrame": sceneFrame, "sceneTime": sceneTime,
            "spriteKitTime": spriteKitTime,
            "systemUptime": ProcessInfo.processInfo.systemUptime,
            "sceneGeneration": sceneGeneration,
            "phase": "removal_handler_before_node_removal"
        ])
    }

    func recordLifecycleRemoval(groups: [SKNode], reason: String, sceneFrame: Int,
                                sceneTime: TimeInterval, spriteKitTime: TimeInterval,
                                sceneGeneration: Int) {
        for group in groups {
            guard group.name == PursuitSuppressionNotice.nodeName,
                  let root = group.userData?["pursuitRootID"] as? String else { continue }
            recordRemoval(rootID: root, reason: reason, sceneFrame: sceneFrame,
                          sceneTime: sceneTime, spriteKitTime: spriteKitTime,
                          sceneGeneration: sceneGeneration)
        }
    }

    func sample(scene: LivingScene, groups: [SKNode], recipients: [String: SKSpriteNode],
                sceneFrame: Int, sceneTime: TimeInterval, spriteKitTime: TimeInterval,
                sceneGeneration: Int) {
        guard status == "TRACE_ONLY_PENDING_VISUAL_REVIEW",
              !captureWindow.status.hasPrefix("CAPTURED_"),
              !captureWindow.status.hasPrefix("INCOMPLETE_"),
              captureWindow.status != "NO_NOTICE_CUE_CAPTURED" else { return }
        let activeRootIDs = Set(groups.compactMap { group -> String? in
            guard group.name == PursuitSuppressionNotice.nodeName else { return nil }
            return group.userData?["pursuitRootID"] as? String
        })
        captureWindow.observe(sceneFrame: sceneFrame, generation: sceneGeneration,
                              activeRootIDs: activeRootIDs)
        if captureWindow.status.hasPrefix("INCOMPLETE_") {
            status = captureWindow.status
            return
        }
        // Startup/home/encounter scene rebuilds before the first cue are setup,
        // not a failed notice capture. Begin the video marker on the first cue.
        guard !cues.isEmpty else { return }
        ensureMarker(in: scene)
        if marker?.parent === scene {
            markerSequence += 1
            (marker?.childNode(withName: "r092_marker_label") as? SKLabelNode)?.text = String(format: "R92 %04d", markerSequence)
        }
        for group in groups where group.name == PursuitSuppressionNotice.nodeName {
            if rows.count >= Self.rowLimit {
                overflowCount += 1
                status = "INCOMPLETE_ROW_CAP"
                return
            }
            let root = group.userData?["pursuitRootID"] as? String ?? ""
            let source = group.userData?["pursuitSourceID"] as? String ?? ""
            let target = group.userData?["pursuitTargetID"] as? String ?? ""
            let cue = cueByRoot[root] ?? [:]
            let title = group.childNode(withName: PursuitSuppressionNotice.titleName) as? SKLabelNode
            let recipientName = group.childNode(withName: PursuitSuppressionNotice.recipientNameNode) as? SKLabelNode
            let backing = group.children.first { $0 is SKShapeNode && $0.name == nil }
            let viewport = Self.viewportInScene(scene)
            let titleBounds = title.flatMap { Self.rectInScene($0, scene: scene) }
            let nameBounds = recipientName.flatMap { Self.rectInScene($0, scene: scene) }
            let panelBounds = backing.flatMap { Self.rectInScene($0, scene: scene) }
            let chain = Self.ancestorChain(group, through: scene)
            let titleChain = title.map { Self.ancestorChain($0, through: scene) } ?? []
            let recipientNameChain = recipientName.map { Self.ancestorChain($0, through: scene) } ?? []
            let targetNode = recipients[target]
            let exactParent = targetNode.map { group.parent === $0 } ?? false
            let layout = targetNode.map {
                PursuitNoticeRenderedBoundsQA_R059.inspect(
                    group: group, recipient: $0, scene: scene,
                    obstacles: scene.pursuitNoticeObstacleNodes(excluding: target))
            }
            rows.append([
                "sequence": rows.count + 1,
                "sceneFrame": sceneFrame, "sceneTime": sceneTime,
                "spriteKitTime": spriteKitTime,
                "systemUptime": ProcessInfo.processInfo.systemUptime,
                "sceneGeneration": sceneGeneration,
                "videoMarkerVisible": marker?.parent === scene,
                "videoMarkerText": (marker?.childNode(withName: "r092_marker_label") as? SKLabelNode)?.text ?? "",
                "videoMarkerSequence": marker?.parent === scene ? markerSequence : -1,
                "videoMarkerPosition": marker.map { [Double($0.position.x), Double($0.position.y)] } ?? [],
                "videoMarkerSize": [112.0, 26.0],
                "samplePhase": "didFinishUpdate_postActions_postNoticeReflow_preRender",
                "renderedPixelsEvaluated": false,
                "saveKey": saveKey,
                "rootActionID": root, "sourceID": source, "targetID": target,
                "effectID": cue["effectID"] as? String ?? "",
                "cueSceneFrame": cue["sceneFrame"] as? Int ?? -1,
                "cueSceneTime": cue["sceneTime"] as? TimeInterval ?? -1,
                "cueSpriteKitTime": cue["spriteKitTime"] as? TimeInterval ?? -1,
                "cuePhase": cue["phase"] as? String ?? "MISSING_CUE_RECORD",
                "groupName": group.name ?? "",
                "groupParentName": group.parent?.name ?? "",
                "groupParentMatchesTarget": exactParent,
                "groupPosition": [Double(group.position.x), Double(group.position.y)],
                "groupZPosition": Double(group.zPosition),
                "groupBoundsScene": Self.rectArray(Self.rectInScene(group, scene: scene)),
                "titleText": title?.text ?? "MISSING_LABEL",
                "titleFont": title?.fontName ?? "",
                "titleFontSize": Double(title?.fontSize ?? 0),
                "titleFontColorRGBA": Self.colorRGBA(title?.fontColor),
                "titleIsHidden": title?.isHidden ?? true,
                "titleAlpha": Double(title?.alpha ?? 0),
                "titleAncestorChain": titleChain,
                "titleEffectiveAlpha": titleChain.reduce(1.0) { $0 * (($1["alpha"] as? Double) ?? 0) },
                "titlePosition": title.map { [Double($0.position.x), Double($0.position.y)] } ?? [],
                "titleZPosition": Double(title?.zPosition ?? 0),
                "titleBoundsScene": Self.rectArray(titleBounds),
                "titleInsideViewport": Self.contains(viewport, titleBounds),
                "titleInsidePanel": Self.contains(panelBounds, titleBounds),
                "recipientText": recipientName?.text ?? "MISSING_LABEL",
                "recipientIsHidden": recipientName?.isHidden ?? true,
                "recipientAlpha": Double(recipientName?.alpha ?? 0),
                "recipientAncestorChain": recipientNameChain,
                "recipientEffectiveAlpha": recipientNameChain.reduce(1.0) { $0 * (($1["alpha"] as? Double) ?? 0) },
                "recipientBoundsScene": Self.rectArray(nameBounds),
                "recipientInsideViewport": Self.contains(viewport, nameBounds),
                "panelBoundsScene": Self.rectArray(panelBounds),
                "panelInsideViewport": Self.contains(viewport, panelBounds),
                "viewportScene": Self.rectArray(viewport),
                "sceneFrameBounds": Self.rectArray(scene.frame),
                "viewBounds": scene.view.map { Self.rectArray($0.bounds) } ?? [],
                "ancestorChain": chain,
                "effectiveAlpha": chain.reduce(1.0) { $0 * (($1["alpha"] as? Double) ?? 0) },
                "hasHiddenAncestor": chain.contains { ($0["isHidden"] as? Bool) == true },
                "cropAncestors": chain.filter { ($0["type"] as? String)?.contains("SKCropNode") == true },
                "potentialZOccludersTitle": Self.potentialZOccluders(
                    node: title, bounds: titleBounds, scene: scene),
                "potentialZOccludersPanel": Self.potentialZOccluders(
                    node: backing, bounds: panelBounds, scene: scene),
                "layoutReadback": Self.layoutDictionary(layout),
                "reflowDisposition": group.userData?["r008LastDisposition"] as? String ?? "",
                "actualCollisionIDs": group.userData?["r008LastActualCollisionIDs"] as? [String] ?? [],
                "candidatePlacement": group.userData?["placementCandidate"] as? String ?? ""
            ])
        }
    }

    func requestBattleEnd(sceneFrame: Int, sceneGeneration: Int, activeGroups: [SKNode]) {
        let activeRootIDs = Set(activeGroups.compactMap { group -> String? in
            guard group.name == PursuitSuppressionNotice.nodeName else { return nil }
            return group.userData?["pursuitRootID"] as? String
        })
        captureWindow.requestBattleEnd(sceneFrame: sceneFrame, generation: sceneGeneration,
                                       activeRootIDs: activeRootIDs)
        if captureWindow.status == "NO_NOTICE_CUE_CAPTURED" || captureWindow.status.hasPrefix("INCOMPLETE_") {
            status = captureWindow.status
        }
        if captureWindow.status.hasPrefix("CAPTURED_") || captureWindow.status.hasPrefix("INCOMPLETE_") ||
            captureWindow.status == "NO_NOTICE_CUE_CAPTURED" {
            marker?.removeFromParent()
            marker = nil
        }
    }

    func receipt() -> [String: Any] {
        [
            "schema": "PURSUIT_NOTICE_RENDER_R092",
            "status": status,
            "captureWindow": captureWindow.receipt,
            "saveKey": saveKey,
            "rowCount": rows.count,
            "rowLimit": Self.rowLimit,
            "overflowCount": overflowCount,
            "cueCount": cues.count,
            "removalCount": removals.count,
            "cues": cues,
            "removals": removals,
            "rows": rows,
            "visualPixelsEvaluated": false,
            "visualStatus": "PENDING_ORIGINAL_PTS_VIDEO_REVIEW"
        ]
    }

    private func ensureMarker(in scene: SKScene) {
        guard marker?.parent !== scene else { return }
        let node = SKShapeNode(rectOf: CGSize(width: 112, height: 26), cornerRadius: 3)
        node.name = "r092_video_sync_marker"
        node.fillColor = .black
        node.strokeColor = .white
        node.lineWidth = 0.7
        node.zPosition = 30_000
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = "r092_marker_label"
        label.text = "R92 0000"
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        node.addChild(label)
        node.position = CGPoint(x: 68, y: scene.size.height - 76)
        scene.addChild(node)
        marker = node
    }

    private static func rectInScene(_ node: SKNode, scene: SKScene) -> CGRect? {
        guard let parent = node.parent else { return nil }
        let rect = node.frame
        let points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY),
                      CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)]
            .map { scene.convert($0, from: parent) }
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private static func viewportInScene(_ scene: SKScene) -> CGRect? {
        guard let view = scene.view else { return nil }
        let b = view.bounds
        let points = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.minX, y: b.maxY),
                      CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY)]
            .map { scene.convertPoint(fromView: $0) }
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private static func ancestorChain(_ node: SKNode, through scene: SKScene) -> [[String: Any]] {
        var chain: [[String: Any]] = []
        var current: SKNode? = node
        while let item = current {
            chain.append([
                "name": item.name ?? "",
                "type": String(describing: type(of: item)),
                "isHidden": item.isHidden,
                "alpha": Double(item.alpha),
                "zPosition": Double(item.zPosition),
                "position": [Double(item.position.x), Double(item.position.y)],
                "xScale": Double(item.xScale), "yScale": Double(item.yScale),
                "zRotation": Double(item.zRotation)
            ])
            if item === scene { break }
            current = item.parent
        }
        return chain
    }

    private static func potentialZOccluders(node: SKNode?, bounds: CGRect?, scene: SKScene) -> [[String: Any]] {
        guard let node, let bounds else { return [] }
        var result: [[String: Any]] = []
        var current: SKNode? = node
        while let item = current, item !== scene, let parent = item.parent {
            for sibling in parent.children where sibling !== item && sibling.zPosition > item.zPosition &&
                !sibling.isHidden && sibling.alpha > 0 &&
                rectInScene(sibling, scene: scene).map({ $0.intersects(bounds) }) == true {
                result.append(["name": sibling.name ?? String(describing: type(of: sibling)),
                               "parentName": parent.name ?? String(describing: type(of: parent)),
                               "siblingZ": Double(sibling.zPosition), "currentZ": Double(item.zPosition),
                               "boundsScene": rectArray(rectInScene(sibling, scene: scene))])
            }
            current = parent
        }
        return result
    }

    private static func colorRGBA(_ color: UIColor?) -> [Double] {
        guard let color else { return [] }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return [] }
        return [Double(r), Double(g), Double(b), Double(a)]
    }

    private static func contains(_ outer: CGRect?, _ inner: CGRect?) -> Bool {
        guard let outer, let inner else { return false }
        return outer.contains(inner)
    }

    private static func rectArray(_ rect: CGRect?) -> [Double] {
        guard let rect else { return [] }
        return [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
    }

    private static func layoutDictionary(_ result: PursuitNoticeRenderedBoundsQA_R059.Result?) -> [String: Any] {
        guard let result else { return ["available": false] }
        return [
            "available": true, "candidateInstalled": result.candidateInstalled,
            "actualLayoutSafe": result.actualLayoutSafe, "actualBoundsInsideScene": result.actualBoundsInsideScene,
            "recipientBodyClear": result.recipientBodyClear, "attachmentWithinRecipient": result.attachmentWithinRecipient,
            "actualCollisionIDs": result.actualCollisionIDs,
            "connectorRequired": result.connectorRequired, "requiredLeaderPresent": result.requiredLeaderPresent
        ]
    }
}
