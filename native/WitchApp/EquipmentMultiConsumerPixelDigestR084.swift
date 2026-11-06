import CoreGraphics
import CryptoKit
import Foundation

/// Normalizes a decoded image to deterministic device-RGB, 8-bit premultiplied
/// RGBA bytes before hashing. This binds the sampled SKTexture pixels, rather
/// than trusting a same-sized texture or a claimed resource path.
enum EquipmentMultiConsumerPixelDigestR084 {
    static func sha256(_ image: CGImage) -> String? {
        guard image.width > 0, image.height > 0,
              image.width <= Int.max / 4,
              image.height <= Int.max / (image.width * 4) else { return nil }
        let rowBytes = image.width * 4
        let byteCount = rowBytes * image.height
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = CFDataCreateMutable(kCFAllocatorDefault, byteCount) else { return nil }
        CFDataSetLength(data, byteCount)
        guard let bytes = CFDataGetMutableBytePtr(data),
              let context = CGContext(data: bytes, width: image.width,
                                      height: image.height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                  CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let normalized = Data(bytes: bytes, count: byteCount)
        return SHA256.hash(data: normalized).map { String(format: "%02x", $0) }.joined()
    }
}
