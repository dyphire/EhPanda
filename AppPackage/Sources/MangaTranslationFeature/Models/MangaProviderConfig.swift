import Foundation
import AppModels

public struct MangaProviderConfig: Hashable, Codable, Identifiable, Sendable, SchemaVersioned {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    enum SchemaV1: VersionedSchema {
        static let version = 1
        static func migrate(_ object: inout [String: JSONValue]) throws {}
    }

    public var schemaVersion: SchemaVersion<MangaProviderConfig> = 1

    public let id: String
    public var baseURL: String
    public var model: String
    public var displayName: String
    public var apiKey: String

    public init(
        id: String = UUID().uuidString,
        baseURL: String,
        model: String,
        displayName: String,
        apiKey: String = ""
    ) {
        self.id = id
        self.baseURL = baseURL
        self.model = model
        self.displayName = displayName
        self.apiKey = apiKey
    }

    public var isConfigured: Bool {
        endpoint("chat/completions") != nil
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var resolvedDisplayName: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let host = URLComponents(string: baseURL)?.host, !host.isEmpty {
            return host
        }
        return baseURL
    }

    public func endpoint(_ path: String) -> URL? {
        guard var components = URLComponents(string: Self.normalizedBaseURL(baseURL)),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            components.host?.isEmpty == false
        else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + (basePath.isEmpty ? "" : basePath + "/") + suffix
        components.query = nil
        components.fragment = nil
        return components.url
    }

    public func signature(
        sourceLanguage: String,
        targetLanguage: String,
        metadata: MangaTranslationMetadata?
    ) -> String {
        MangaSignature.make([
            "baseURL": Self.normalizedBaseURL(baseURL),
            "model": model,
            "sourceLanguage": sourceLanguage,
            "targetLanguage": targetLanguage,
            "metadata": metadata?.signature ?? "",
            "promptVersion": "2"
        ])
    }

    public static func normalizedBaseURL(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
