import Foundation
import AppModels
import Sharing
import MangaTranslationFeature

// Shared by the manual backup screen and the scheduled auto-backup: assembling the backup
// envelope from the current persisted values, plus the remote file naming and encoding both
// upload paths write. Local `@Shared` handles keep assembly free of any reducer state, so the
// manual and automatic paths produce byte-identical documents. (Applying an imported envelope
// lives on `BackupSettingReducer.State.restoreSharedMembers(from:)` — TestStore state replay
// requires the exact mutation sequence, so it stays a State method shared with the tests.)

enum SettingsBackup {
    static let latestFileName = "ehpanda-backup-latest.json"

    static func timestampedFileName(exportDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "ehpanda-backup-\(formatter.string(from: exportDate)).json"
    }

    static func encode(_ envelope: SettingsBackupEnvelope) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(envelope)
    }

    /// Snapshots every persisted model the backup covers. `nil` JSON payloads (a model that
    /// failed to encode) are simply omitted from the envelope.
    static func envelope(
        exportDate: Date,
        cookies: [ExportedCookie]
    ) -> SettingsBackupEnvelope {
        @Shared(.setting) var setting
        @Shared(.user) var user
        @Shared(.searchFilter) var searchFilter
        @Shared(.globalFilter) var globalFilter
        @Shared(.watchedFilter) var watchedFilter
        @Shared(.quickSearchWords) var quickSearchWords
        @Shared(.historyKeywords) var historyKeywords
        @Shared(.galleryHistory) var galleryHistory
        @Shared(.mangaTranslationPreferences) var mangaTranslationPreferences
        @Shared(.mangaTranslationProviders) var mangaTranslationProviders
        @Shared(.mangaModelLibrary) var mangaModelLibrary

        return SettingsBackupEnvelope(
            exportDate: exportDate,
            setting: setting,
            searchFilter: searchFilter,
            globalFilter: globalFilter,
            watchedFilter: watchedFilter,
            quickSearchWords: quickSearchWords,
            historyKeywords: historyKeywords,
            galleryHistory: galleryHistory,
            user: user,
            cookies: cookies,
            mangaTranslationPreferences: JSONValue(encoding: mangaTranslationPreferences),
            mangaTranslationProviders: JSONValue(encoding: mangaTranslationProviders),
            mangaModelLibrary: JSONValue(encoding: mangaModelLibrary)
        )
    }
}
