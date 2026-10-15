import SwiftUI
import SpriteKit

/// Room-context preview using the production LivingScene renderer. It owns a separate,
/// short-lived scene and never attaches the live GameModel.scene to a second SpriteView.
@MainActor
struct FurnitureRoomPreviewR275: View {
    @ObservedObject var model: GameModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var previewScene: LivingScene?
    @State private var previewOwnerID = UUID()

    private let sceneSize = CGSize(width: 402, height: 600)
    private var deskPlaced: Bool { model.sceneFurniture.contains("FURN_DESK_BOTANICAL") }

    var body: some View {
        VStack(spacing: 8) {
            Text(deskPlaced ? "机を置いた家" : "机をしまった家")
                .font(.headline)
                .accessibilityIdentifier("furniture_room_preview_state_r275")
            Group {
                if let previewScene {
                    GeometryReader { proxy in
                        let width = min(proxy.size.width, 241.2)
                        SpriteView(scene: previewScene)
                            .frame(width: width, height: width * 600 / 402)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 360)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(deskPlaced ? "植物研究の机と、机で本を読むルナがいる家の見本" : "植物研究の机をしまった家の見本")
                    .accessibilityIdentifier("furniture_room_preview_scene_r275")
                } else {
                    Color.clear.frame(height: 360)
                        .accessibilityLabel("家の見本を準備しています")
                }
            }
            Text(deskPlaced
                 ? "机を置くと、ルナがこの場所で本を読みます。"
                 : "机をしまった状態の部屋です。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("furniture_room_preview_description_r275")
        }
        .frame(maxWidth: .infinity)
        .onAppear { configurePreview() }
        .onChange(of: model.sceneFurniture) { _, _ in configurePreview() }
        .onChange(of: model.sceneAppearance) { _, _ in configurePreview() }
        .onChange(of: model.wardrobeCandidateDevelopmentR169Enabled) { _, _ in configurePreview() }
        .onChange(of: scenePhase) { _, phase in
            previewScene?.isPaused = phase != .active
        }
        .onDisappear { tearDownPreview() }
    }

    private func configurePreview() {
        let scene: LivingScene
        if let existing = previewScene {
            scene = existing
        } else {
            model.setFurniturePreviewActiveR275(true, owner: previewOwnerID)
            scene = LivingScene(size: sceneSize)
            scene.scaleMode = .aspectFit
            scene.suppressSharedDiagnosticsR275 = true
            previewScene = scene
        }
        scene.isPaused = scenePhase != .active
        scene.configure(place: .home, cosmetics: model.sceneAppearance,
                        furniture: model.sceneFurniture,
                        wardrobeCandidateDevelopmentEnabled: model.wardrobeCandidateDevelopmentR169Enabled)
    }

    private func tearDownPreview() {
        previewScene?.releaseFurnitureRoomPreviewR275()
        previewScene = nil
        model.setFurniturePreviewActiveR275(false, owner: previewOwnerID)
    }
}
