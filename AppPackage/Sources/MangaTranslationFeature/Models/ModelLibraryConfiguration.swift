import Foundation
import AppModels

public struct ModelLibraryConfiguration: Codable, Equatable, Sendable, SchemaVersioned {
    public static let defaultCatalogURL = "https://models.kmworks.date/v1/catalog.json"

    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    enum SchemaV1: VersionedSchema {
        static let version = 1
        static func migrate(_ object: inout [String: JSONValue]) throws {}
    }

    public var schemaVersion: SchemaVersion<ModelLibraryConfiguration> = 1

    public var catalogURL: String = ModelLibraryConfiguration.defaultCatalogURL
    public var catalog: ModelCatalog?
    public var downloadedArchives: [ModelArchive] = []
    public var selectedStorageKeys: [String: String] = [:]

    public init() {}
}
