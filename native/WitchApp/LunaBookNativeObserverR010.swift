import SpriteKit

/// Passive, bounded native trace. Sampling does not force texture/action updates.
@MainActor final class LunaBookNativeObserverR010 {
    let runID = UUID().uuidString
    let saveKey: String
    let scenario: String
    private(set) var rows: [[String: Any]] = []
    private(set) var overflowed = false
    private let rowLimit = 1_800
    private var marker: SKNode?
    private var markerReattachCount = 0

    init(arguments: [String]) {
        saveKey = arguments.first(where: {$0.hasPrefix("--qa-save-key=")})?.replacingOccurrences(of:"--qa-save-key=",with:"") ?? ""
        scenario = arguments.contains("--qa-luna-book-failure-after-success-r010") ? "failure_after_success" : "normal_control"
    }

    private func ensureMarker(in scene: SKScene) {
        if marker == nil {
            let group = SKNode()
            group.name = "luna_book_r010_video_marker"
            group.zPosition = 20_000
            let backing = SKShapeNode(rectOf: CGSize(width: 112, height: 26), cornerRadius: 3)
            backing.name = "luna_book_r010_video_marker_back"
            backing.fillColor = .black.withAlphaComponent(0.9)
            backing.strokeColor = .white.withAlphaComponent(0.95)
            backing.lineWidth = 1
            group.addChild(backing)
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.name = "luna_book_r010_video_marker_text"
            label.fontSize = 14
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            group.addChild(label)
            marker = group
            scene.addChild(group)
        } else if let marker, marker.parent !== scene {
            marker.removeFromParent()
            scene.addChild(marker)
            markerReattachCount += 1
        }
        marker?.position = CGPoint(x: 68, y: scene.size.height - 76)
    }

    func sample(scene: SKScene, sceneFrame: Int, sceneTime: TimeInterval, requestedState: String,
                body: SKSpriteNode?, hand: CGPoint?, fault: LunaBookFailureInjectionR010?) {
        guard rows.count < rowLimit else { overflowed = true; return }
        ensureMarker(in: scene)
        let markerText = String(format: "LUNA %04d", rows.count)
        (marker?.childNode(withName: "luna_book_r010_video_marker_text") as? SKLabelNode)?.text = markerText
        var row = LunaBookNativeSnapshotR010.capture(sceneFrame:sceneFrame,sceneTime:sceneTime,
                                                     requestedState:requestedState,body:body,hand:hand)
        row["sequence"] = rows.count
        row["videoMarker"] = markerText
        row["videoMarkerVisible"] = marker?.parent === scene
        row["videoMarkerPosition"] = marker.map { [Double($0.position.x), Double($0.position.y)] } ?? []
        row["videoMarkerReattachCount"] = markerReattachCount
        row["faultStatus"] = fault.map { ["successfulNonWalkPresentation":$0.successfulNonWalkPresentation,
                                           "injectedFailureCount":$0.injectedFailureCount] } ?? [:]
        rows.append(row)
    }

    func receipt(fault: LunaBookFailureInjectionR010?) -> [String: Any] {
        ["schema":"luna-book-native-r010", "status":overflowed ? "TRUNCATED_ROW_LIMIT" : "CAPTURED",
         "runID":runID, "saveKey":saveKey, "scenario":scenario,
         "r050MidpointRequested":ProcessInfo.processInfo.arguments.contains("--qa-isolated") &&
             ProcessInfo.processInfo.arguments.contains("--qa-luna-execute-recover-midpoint-r050"),
         "clock":"SKScene didFinishUpdate sceneTime; no ProcessInfo cross-clock inference",
         "samplePhase":"post-action didFinishUpdate", "rowLimit":rowLimit,
         "faultPlan":fault.map { $0.receipt() as Any } ?? NSNull(), "rows":rows]
    }
}
