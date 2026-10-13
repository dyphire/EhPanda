import Foundation

public struct ModelPurpose: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var isValid: Bool {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !rawValue.isEmpty && rawValue.count <= 64 && rawValue != "." && rawValue != ".."
            && rawValue.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

    public static let mangaOCR = ModelPurpose(rawValue: "manga_ocr")
}
