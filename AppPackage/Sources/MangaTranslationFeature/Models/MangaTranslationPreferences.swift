import Foundation
import AppModels

public struct MangaTranslationPreferences: Codable, Equatable, Sendable, SchemaVersioned {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    enum SchemaV1: VersionedSchema {
        static let version = 1
        static func migrate(_ object: inout [String: JSONValue]) throws {}
    }

    public var schemaVersion: SchemaVersion<MangaTranslationPreferences> = 1

    public var selectedProviderID = ""
    public var sourceLanguage = MangaTranslationLanguage.defaultSource
    public var targetLanguage = ""
    public var includeMetadata = false
    public var showTranslation = true
    public var textDirection: MangaTranslationTextDirection = .auto

    public init() {}
}
