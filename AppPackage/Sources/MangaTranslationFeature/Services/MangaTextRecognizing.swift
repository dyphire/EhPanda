import CoreGraphics
import Foundation

public protocol MangaTextRecognizing: Sendable {
    func recognize(crops regions: [MangaTextRegion], image: CGImage) throws -> [MangaTextRegion]
}
