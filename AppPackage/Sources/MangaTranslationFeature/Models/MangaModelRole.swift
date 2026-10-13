import Foundation

public enum MangaModelRole: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case detector
    case recognizer

    public var id: String { rawValue }

    public var componentName: String { rawValue }

    public var selectionStorageKey: String {
        "\(ModelPurpose.mangaOCR.rawValue).\(rawValue)"
    }

    public static func supported(by archive: ModelArchive) -> [MangaModelRole] {
        allCases.filter { archive.components[$0.componentName] != nil }
    }
}
