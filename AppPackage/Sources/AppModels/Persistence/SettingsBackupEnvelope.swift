import Foundation

/// The single Codable document written by "Export backup" and consumed by "Import backup".
///
/// Every member is optional so the envelope round-trips across app versions: a file exported before
/// a member existed decodes with that member `nil` (the import then keeps the current value rather
/// than overwriting with emptiness), and a member added after export is simply absent. Each whole-
/// struct member keeps its own self-validating `schemaVersion` (see `AppSharedKeys`), so a blob from
/// a newer model shape fails its decode and is skipped the same way. `formatVersion` gates the
/// envelope itself and is rejected by the importer when newer than `currentFormatVersion`.
public struct SettingsBackupEnvelope: Codable, Equatable, Sendable {
    /// Bump when the envelope layout changes incompatibly; the importer refuses files above it.
    public static let currentFormatVersion = 1

    public init(
        formatVersion: Int = SettingsBackupEnvelope.currentFormatVersion,
        exportDate: Date,
        setting: Setting? = nil,
        searchFilter: Filter? = nil,
        globalFilter: Filter? = nil,
        watchedFilter: Filter? = nil,
        quickSearchWords: [QuickSearchWord]? = nil,
        historyKeywords: [String]? = nil,
        galleryHistory: [GalleryHistoryEntry]? = nil,
        user: User? = nil,
        cookies: [ExportedCookie]? = nil,
        mangaTranslationPreferences: JSONValue? = nil,
        mangaTranslationProviders: JSONValue? = nil,
        mangaModelLibrary: JSONValue? = nil
    ) {
        self.formatVersion = formatVersion
        self.exportDate = exportDate
        self.setting = setting
        self.searchFilter = searchFilter
        self.globalFilter = globalFilter
        self.watchedFilter = watchedFilter
        self.quickSearchWords = quickSearchWords
        self.historyKeywords = historyKeywords
        self.galleryHistory = galleryHistory
        self.user = user
        self.cookies = cookies
        self.mangaTranslationPreferences = mangaTranslationPreferences
        self.mangaTranslationProviders = mangaTranslationProviders
        self.mangaModelLibrary = mangaModelLibrary
    }

    public var formatVersion: Int
    public var exportDate: Date

    // Local configuration
    public var setting: Setting?
    public var searchFilter: Filter?
    public var globalFilter: Filter?
    public var watchedFilter: Filter?
    public var quickSearchWords: [QuickSearchWord]?
    public var historyKeywords: [String]?

    // Browsing history (capped, disposable — see `AppSharedKeys`)
    public var galleryHistory: [GalleryHistoryEntry]?

    // Account identity. Login credentials travel as plaintext snapshots; the export description in
    // the UI warns the user to keep the file safe. They cannot be replayed across accounts, so
    // importing them on another device is exactly the intended migration path.
    public var user: User?
    public var cookies: [ExportedCookie]?

    // Manga-translation preferences. The concrete model types live in a feature module downstream
    // of `AppModels` (where this envelope must stay, since `FileClient` only depends on `AppModels`),
    // so these payloads travel as raw JSON trees and are decoded at the import site.
    public var mangaTranslationPreferences: JSONValue?
    public var mangaTranslationProviders: JSONValue?
    public var mangaModelLibrary: JSONValue?
}

/// A plaintext snapshot of a session cookie (`HTTPCookie` itself is not `Codable`). Only the
/// session-relevant cookies are snapshotted (see `CookieClient`); `domain` is recorded for
/// provenance — restore re-derives the target hosts from the cookie name.
public struct ExportedCookie: Codable, Equatable, Sendable {
    public init(name: String, value: String, domain: String) {
        self.name = name
        self.value = value
        self.domain = domain
    }

    public var name: String
    public var value: String
    public var domain: String
}

// MARK: Codable bridging
extension JSONValue {
    /// Round-trips any `Encodable` through the JSON tree. `nil` when the value cannot be encoded,
    /// in which case the export simply omits that payload (its member stays `nil`).
    public init?(encoding value: some Encodable) {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        self = json
    }

    /// Decodes this tree into a concrete model. `nil` when the tree doesn't match the model's
    /// shape — the import site then keeps the current value instead of overwriting with a default.
    public func decoded<T: Decodable>(as type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
