import Foundation

/// Page translation results persist as one JSON file per cache key in a
/// purgeable cache directory — the data is recomputable and never authored,
/// so it stays out of app storage.
public struct MangaTranslationStore: Sendable {
    public init() {}

    private static var rootDirectory: URL {
        URL.cachesDirectory.appendingPathComponent("MangaTranslations", isDirectory: true)
    }

    private static func fileURL(for cacheKey: String) -> URL {
        rootDirectory.appendingPathComponent("\(cacheKey).json")
    }

    public static func save(_ translation: MangaPageTranslation) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(translation)
        let url = fileURL(for: translation.key.cacheKey)
        // Retired inference versions can never match again; prune them for
        // this page. Rows from other model archives and same-signature
        // language/provider variants stay.
        let archivePrefix = translation.key.modelArchivePrefix
        if let entries = try? fileManager.contentsOfDirectory(atPath: rootDirectory.path) {
            for entry in entries where entry.hasSuffix(".json") && entry != "\(translation.key.cacheKey).json" {
                let entryURL = rootDirectory.appendingPathComponent(entry)
                guard let entryData = try? Data(contentsOf: entryURL),
                    let existing = try? JSONDecoder().decode(MangaPageTranslation.self, from: entryData),
                    existing.key.galleryID == translation.key.galleryID,
                    existing.key.pageNumber == translation.key.pageNumber
                else { continue }
                let signature = existing.key.modelSignature
                if signature.isEmpty || signature.hasPrefix("\(archivePrefix):") {
                    try? fileManager.removeItem(at: entryURL)
                }
            }
        }
        try data.write(to: url, options: .atomic)
    }

    public static func fetch(key: MangaTranslationPageKey) throws -> MangaPageTranslation? {
        let url = fileURL(for: key.cacheKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MangaPageTranslation.self, from: data)
    }

    public static func clear() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.removeItem(at: rootDirectory)
        }
    }
}
