import SwiftUI
import UIKit

/// Crops only transparent margins for the three R128/R130 wardrobe candidate thumbnails.
/// The original texture and in-scene registration are not changed.
struct WardrobeCandidateThumbnailR130: View {
    let id: String
    let fallbackAssetID: String
    let size: CGFloat

    private struct Crop { let asset: String; let rect: CGRect; let canvas: CGSize }
    private var crop: Crop? {
        switch id {
        case WardrobeCandidateResolverR128.lunaID:
            return Crop(asset: "LUNA_MANTLE_BODY_LAYER_R001", rect: CGRect(x: 111, y: 144, width: 34, height: 23), canvas: CGSize(width: 256, height: 256))
        case WardrobeCandidateResolverR128.noirID:
            return Crop(asset: "NOIR_NECKWEAR_MOSS_R001", rect: CGRect(x: 440, y: 672, width: 376, height: 154), canvas: CGSize(width: 1254, height: 1254))
        case WardrobeCandidateCatalogR130.appearanceID:
            return Crop(asset: "AIRA_HARVEST_APRON_R130", rect: CGRect(x: 363, y: 485, width: 529, height: 399), canvas: CGSize(width: 1254, height: 1254))
        default: return nil
        }
    }
    var body: some View {
        Group {
            if let image = candidateImage() { Image(uiImage: image).resizable().scaledToFit() }
            else { AssetIcon(id: fallbackAssetID, size: size) }
        }.frame(width: size, height: size)
    }
    private func candidateImage() -> UIImage? {
        guard let crop else { return nil }
        let source: UIImage?
        if id == WardrobeCandidateCatalogR130.appearanceID,
           let url = Bundle.main.url(forResource: crop.asset, withExtension: "png", subdirectory: "CandidateAppearance/R130") {
            source = UIImage(contentsOfFile: url.path)
        } else { source = ArtLibrary.image(crop.asset) }
        guard let image = source, let cg = image.cgImage,
              cg.width == Int(crop.canvas.width), cg.height == Int(crop.canvas.height),
              let cropped = cg.cropping(to: crop.rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
