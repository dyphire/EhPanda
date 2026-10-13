import Foundation

public struct MangaTextSegment: Codable, Hashable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}
