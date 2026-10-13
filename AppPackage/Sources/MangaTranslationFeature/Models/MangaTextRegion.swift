import CoreGraphics
import Foundation

public struct MangaTextRegion: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public let label: Int
    public let score: Float
    public let sourceBox: CGRect
    public let box: CGRect
    public let text: String
    public let translatedText: String?
    public let orientation: MangaTextOrientation

    public init(
        id: Int, label: Int, score: Float, sourceBox: CGRect, box: CGRect,
        text: String, translatedText: String?, orientation: MangaTextOrientation
    ) {
        self.id = id
        self.label = label
        self.score = score
        self.sourceBox = sourceBox
        self.box = box
        self.text = text
        self.translatedText = translatedText
        self.orientation = orientation
    }
}
