import CoreGraphics
import CoreImage
import Foundation
import UIKit

public enum MangaBubbleBackground {
    private static let ciContext = CIContext()

    // Sampled fills cluster near pure white/black, so a mid-gray luminance
    // threshold suffices to keep the text readable.
    public static func textColor(on background: CGColor) -> CGColor {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = background.converted(to: space, intent: .defaultIntent, options: nil)?
                .components,
              components.count >= 3
        else { return CGColor(gray: 0, alpha: 1) }
        let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        return luminance < 0.5 ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1)
    }

    public static func feather(forCoreSize size: CGSize) -> CGFloat {
        min(14, max(6, min(size.width, size.height) * 0.12))
    }

    public static func blobImage(size: CGSize, feather: CGFloat, cornerRadius: CGFloat, color: CGColor) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0, feather * 2 < size.width, feather * 2 < size.height else { return nil }
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        let coreRect = CGRect(
            x: feather,
            y: feather,
            width: size.width - feather * 2,
            height: size.height - feather * 2
        )
        context.setFillColor(color)
        context.addPath(
            CGPath(roundedRect: coreRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        )
        context.fillPath()
        guard let solid = context.makeImage() else { return nil }
        // sigma ≈ feather/2.2 keeps the fade inside the feather band (α < 2% at the edge)
        let blurred = CIImage(cgImage: solid).applyingGaussianBlur(sigma: feather * 0.45)
        return ciContext.createCGImage(blurred, from: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    private struct ColorBucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0
    }

    /// Estimates the bubble fill color behind a detected region. The dominant
    /// color of the band near the region's edges is the most robust guess: text
    /// and border strokes are the minority there, while the region center is
    /// covered by text.
    public static func backgroundColor(in image: CGImage, normalizedBox box: CGRect) -> CGColor? {
        let pixelRect = CGRect(
            x: box.minX * CGFloat(image.width),
            y: box.minY * CGFloat(image.height),
            width: box.width * CGFloat(image.width),
            height: box.height * CGFloat(image.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard pixelRect.width >= 8, pixelRect.height >= 8, let cropped = image.cropping(to: pixelRect)
        else { return nil }

        let scale = min(1, 64 / max(pixelRect.width, pixelRect.height))
        let sampleWidth = max(1, Int(pixelRect.width * scale))
        let sampleHeight = max(1, Int(pixelRect.height * scale))
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        guard
            let context = CGContext(
                data: &pixels,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: sampleWidth * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        let band = max(2, min(sampleWidth, sampleHeight) / 7)
        var buckets: [Int: ColorBucket] = [:]
        for row in 0..<sampleHeight {
            for column in 0..<sampleWidth {
                guard column < band || row < band
                    || column >= sampleWidth - band || row >= sampleHeight - band
                else { continue }
                let offset = (row * sampleWidth + column) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
                var bucket = buckets[key] ?? ColorBucket()
                bucket.count += 1
                bucket.red += red
                bucket.green += green
                bucket.blue += blue
                buckets[key] = bucket
            }
        }
        guard let winner = buckets.max(by: { $0.value.count < $1.value.count }), winner.value.count > 0
        else { return nil }
        return CGColor(
            srgbRed: CGFloat(winner.value.red) / CGFloat(winner.value.count) / 255,
            green: CGFloat(winner.value.green) / CGFloat(winner.value.count) / 255,
            blue: CGFloat(winner.value.blue) / CGFloat(winner.value.count) / 255,
            alpha: 1
        )
    }

    /// Region boxes are normalized onto the image as displayed; rendering the
    /// image upright keeps sampled pixels in the same coordinate space even when
    /// the source bitmap carries a non-default orientation.
    public static func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }.cgImage
    }
}
