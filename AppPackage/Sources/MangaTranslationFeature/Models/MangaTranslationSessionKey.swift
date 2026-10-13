import Foundation
import Sharing

/// Lookup key for a page translation held in memory for one reading session.
/// Unlike `MangaTranslationPageKey` it carries no source/provider/model
/// signatures; the configuration stamp substitutes for them so mid-session
/// configuration changes stop matching stale results.
public struct MangaTranslationSessionKey: Hashable, Sendable {
    public let galleryID: String
    public let pageNumber: Int
    public let configurationStamp: String

    public init(galleryID: String, pageNumber: Int, configurationStamp: String) {
        self.galleryID = galleryID
        self.pageNumber = pageNumber
        self.configurationStamp = configurationStamp
    }

    /// Snapshot of everything translation output depends on that is readable
    /// synchronously. Provider configuration edits are covered separately by
    /// the settings-dismiss session refresh.
    public static func currentConfigurationStamp() -> String {
        @Shared(.mangaTranslationPreferences) var preferences
        @Shared(.mangaModelLibrary) var modelLibrary
        var values: [String: String] = [
            "sourceLanguage": preferences.sourceLanguage,
            "targetLanguage": preferences.targetLanguage,
            "includeMetadata": String(preferences.includeMetadata),
            "provider": preferences.selectedProviderID
        ]
        for (key, value) in modelLibrary.selectedStorageKeys {
            values["model.\(key)"] = value
        }
        return MangaSignature.make(values)
    }
}
