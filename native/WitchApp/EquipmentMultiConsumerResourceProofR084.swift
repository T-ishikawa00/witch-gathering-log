import Foundation
import CryptoKit
import UIKit

/// Diagnostic only. Mirrors ArtLibrary.image's lookup order and reports the
/// actual first decodable bundle resource plus byte and normalized-pixel SHA.
@MainActor enum EquipmentMultiConsumerResourceProofR084 {
    private static var cache: [String: [String: Any]] = [:]
    static func proof(assetID: String) -> [String: Any] {
        if let cached = cache[assetID] { return cached }
        let root = Bundle.main.bundleURL
        var paths = ["Art/\(assetID).png", "GeneratedArt/\(assetID).png",
                     "GeneratedArt/PartyMotion/\(assetID).png", "GeneratedArt/WeaponLayers/\(assetID).png"]
        if assetID == "STAFF_MOON" || assetID == "STAFF_BRANCH" {
            paths.insert("GeneratedArt/WeaponLayers/\(assetID)_ALPHA_R002.png", at: 0)
        }
        if let entry = ArtLibrary.index[assetID] {
            if let path = entry["selectedPNG"] as? String { paths.append("Art/" + path) }
            else if let layers = entry["layers"] as? [String], let path = layers.first { paths.append("Art/" + path) }
            else if let clips = entry["clips"] as? [String: [String: Any]],
                    let frames = clips["idle"]?["frames"] as? [String], let path = frames.first { paths.append("Art/" + path) }
        }
        var seen = Set<String>()
        for relative in paths where seen.insert(relative).inserted {
            let url = root.appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data), let cg = image.cgImage else { continue }
            let result: [String: Any] = ["assetID": assetID, "resourcePath": relative,
                                         "resourceSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                                         "decoded": true, "decodedPixelSize": [cg.width, cg.height],
                                         "decodedPixelSHA256": EquipmentMultiConsumerPixelDigestR084.sha256(cg) ?? ""]
            cache[assetID] = result
            return result
        }
        let missing: [String: Any] = ["assetID": assetID, "resourcePath": "", "resourceSHA256": "",
                                      "decoded": false, "decodedPixelSize": [], "decodedPixelSHA256": ""]
        cache[assetID] = missing
        return missing
    }
}
