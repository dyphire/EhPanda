import CoreGraphics
import Foundation

public protocol MangaTextDetecting: Sendable {
    func detect(image: CGImage) throws -> [MangaTextRegion]
}
