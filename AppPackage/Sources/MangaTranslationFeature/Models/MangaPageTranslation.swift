import Foundation

public struct MangaPageTranslation: Codable, Hashable, Sendable {
    public let key: MangaTranslationPageKey
    public let regions: [MangaTextRegion]
    public let status: MangaTranslationStatus
    public let targetLanguage: String
    public let creationDate: Date

    public var isTranslated: Bool { status == .translated }

    /// Terminal for caching: a completed translation, or a page that provably
    /// has no text. Anything else (e.g. provider failures) must retry.
    public var isFinalized: Bool {
        (isTranslated && !regions.isEmpty) || status == .recognitionOnly(.noText)
    }

    public init(
        key: MangaTranslationPageKey,
        regions: [MangaTextRegion],
        status: MangaTranslationStatus,
        targetLanguage: String,
        creationDate: Date
    ) {
        self.key = key
        self.regions = regions
        self.status = status
        self.targetLanguage = targetLanguage
        self.creationDate = creationDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(MangaTranslationPageKey.self, forKey: .key)
        regions = try container.decode([MangaTextRegion].self, forKey: .regions)
        status = try container.decode(MangaTranslationStatus.self, forKey: .status)
        // Rows cached before the field existed fall back to an unknown
        // language, which keeps their rendering horizontal.
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? ""
        creationDate = try container.decode(Date.self, forKey: .creationDate)
    }

    enum CodingKeys: String, CodingKey {
        case key
        case regions
        case status
        case targetLanguage
        case creationDate
    }
}
