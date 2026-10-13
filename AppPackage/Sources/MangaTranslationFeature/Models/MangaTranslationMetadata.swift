import Foundation

public struct MangaTranslationMetadata: Hashable, Sendable {
    public let seriesTitle: String
    public let bookTitle: String
    public let authors: [String]
    public let genres: [String]
    public let sourceLanguage: String?

    public init(
        seriesTitle: String, bookTitle: String,
        authors: [String], genres: [String], sourceLanguage: String?
    ) {
        self.seriesTitle = seriesTitle
        self.bookTitle = bookTitle
        self.authors = authors
        self.genres = genres
        self.sourceLanguage = sourceLanguage
    }

    public var signature: String {
        MangaSignature.make([
            "seriesTitle": seriesTitle,
            "bookTitle": bookTitle,
            "authors": authors.joined(separator: "\u{1F}"),
            "genres": genres.joined(separator: "\u{1F}")
        ])
    }

    public var promptLines: [String] {
        var lines: [String] = []
        append("Series", value: seriesTitle, to: &lines)
        append("Chapter", value: bookTitle, to: &lines)
        append("Authors", value: authors.joined(separator: ", "), to: &lines)
        append("Genres", value: genres.joined(separator: ", "), to: &lines)
        return lines
    }

    private func append(_ label: String, value: String, to lines: inout [String]) {
        let cleaned =
            value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        lines.append("\(label): \(String(cleaned.prefix(300)))")
    }
}
