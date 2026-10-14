import CryptoKit
import Foundation
import Vision
import UIKit

/// Detects injected advertisement/recruitment pages — QR-code images appended to the
/// tail of a gallery by scanlation groups — from a page's *thumbnail* bytes.
///
/// The pipeline mirrors the reader/download consumers' needs: a monochrome page is
/// manga content (short-circuit), and only a colour page carrying a QR code whose
/// payload is outside the creator-support allowlist is an ad. Detection is meant to
/// run exclusively within `tailWindowIndices`, since ad pages cluster at the end and
/// scanning every page would waste work and widen the false-positive surface.
public enum AdPageDetector: Sendable {
    public static let tailWindowSize = 10

    /// QR payloads pointing at creator-support platforms are legitimate author content,
    /// not injected advertising. Matched as case-insensitive regular expressions.
    static let allowlistPatterns = [
        #"\.fanbox\.cc"#,
        #"twitter\.com"#,
        #"(^|\.)x\.com"#,
        #"www\.pixiv\.net"#,
        #"www\.dmm\.co\.jp"#,
        #"fantia\.jp"#,
        #"marshmallow-qa\.com"#,
        #"www\.dlsite\.com"#,
        #"hitomi\.la"#
    ]

    public static func isAdPage(imageData: Data) -> Bool {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return false }
        return isAdPage(cgImage: cgImage)
    }

    public static func isAdPage(image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        return isAdPage(cgImage: cgImage)
    }

    public static func isAdPage(cgImage: CGImage) -> Bool {
        guard !isMonochrome(cgImage) else { return false }
        let payloads = qrPayloads(in: cgImage)
        guard !payloads.isEmpty else { return false }
        return payloads.contains { !isAllowlisted($0) }
    }

    /// The 1-based page indices worth scanning: the last `tailWindowSize` pages.
    public static func tailWindowIndices(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let start = max(1, pageCount - tailWindowSize + 1)
        return Array(start...pageCount)
    }

    /// A format-stable fingerprint of the page's pixels (RGBA8 render + SHA-1), used by
    /// `AdPageVerdictCache` to recognise an ad image across galleries without re-running
    /// QR detection. Rendering normalises colour space and bit depth, so the same source
    /// image hashes identically regardless of its on-disk encoding. Returns an empty
    /// string when the bitmap context can't be created — callers treat that as "no hash".
    public static func imageHash(for cgImage: CGImage) -> String {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return "" }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "" }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let digest = pixels.withUnsafeBytes { Insecure.SHA1.hash(data: $0) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Widens a detected ad set with pages that evidently belong to the same ad block:
    /// pages sandwiched between two ads, and pages following a run of two or more
    /// consecutive ads. This catches ad pages that carry no decodable QR code.
    public static func backfilled(_ detected: Set<Int>, pageCount: Int) -> Set<Int> {
        guard let first = detected.min() else { return detected }
        var result = detected
        var consecutiveAds = 0
        for index in first...pageCount {
            if result.contains(index) {
                consecutiveAds += 1
            } else if result.contains(index - 1) && result.contains(index + 1) || consecutiveAds >= 2 {
                result.insert(index)
                consecutiveAds += 1
            } else {
                consecutiveAds = 0
            }
        }
        return result
    }

    static func isAllowlisted(_ payload: String) -> Bool {
        allowlistPatterns.contains { pattern in
            payload.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// A page whose sampled pixels never leave the grayscale band is a B/W manga page;
    /// ad and recruitment images are almost always coloured. The tolerance absorbs
    /// resampling chroma noise on thumbnails.
    static func isMonochrome(_ cgImage: CGImage) -> Bool {
        let sampleEdge = 64
        var pixels = [UInt8](repeating: 0, count: sampleEdge * sampleEdge * 4)
        guard let context = CGContext(
            data: &pixels,
            width: sampleEdge,
            height: sampleEdge,
            bitsPerComponent: 8,
            bytesPerRow: sampleEdge * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleEdge, height: sampleEdge))
        let tolerance = 16
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if max(red, green, blue) - min(red, green, blue) > tolerance { return false }
        }
        return true
    }

    /// Vision's barcode detector is resolution-tolerant, so thumbnails are scanned
    /// as-is; quadrant crops recover codes that fail to decode at full-page scale.
    static func qrPayloads(in cgImage: CGImage) -> [String] {
        var payloads = detectPayloads(in: cgImage)
        let halfWidth = cgImage.width / 2
        let halfHeight = cgImage.height / 2
        let quadrantRects = [
            CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
            CGRect(x: halfWidth, y: 0, width: cgImage.width - halfWidth, height: halfHeight),
            CGRect(x: 0, y: halfHeight, width: halfWidth, height: cgImage.height - halfHeight),
            CGRect(
                x: halfWidth, y: halfHeight,
                width: cgImage.width - halfWidth, height: cgImage.height - halfHeight
            )
        ]
        for rect in quadrantRects {
            guard let cropped = cgImage.cropping(to: rect) else { continue }
            payloads.append(contentsOf: detectPayloads(in: cropped))
        }
        return payloads
    }

    private static func detectPayloads(in cgImage: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
