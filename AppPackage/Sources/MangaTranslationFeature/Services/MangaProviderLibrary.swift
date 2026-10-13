import Foundation
import Sharing

public enum MangaProviderLibrary {
    public static func current() async throws -> MangaProviderConfig? {
        @Shared(.mangaTranslationPreferences) var preferences
        @Shared(.mangaTranslationProviders) var providers
        let selectedID = preferences.selectedProviderID
        guard !selectedID.isEmpty else { return nil }
        return providers.first { $0.id == selectedID }
    }

    public static func all() async throws -> [MangaProviderConfig] {
        @Shared(.mangaTranslationProviders) var providers
        return providers.sorted {
            $0.resolvedDisplayName.localizedStandardCompare($1.resolvedDisplayName) == .orderedAscending
        }
    }

    public static func save(_ provider: MangaProviderConfig, select: Bool = false) {
        guard !provider.id.isEmpty else { return }
        var normalized = provider
        normalized.baseURL = MangaProviderConfig.normalizedBaseURL(provider.baseURL)
        normalized.model = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.displayName = provider.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.apiKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        @Shared(.mangaTranslationProviders) var providers
        $providers.withLock {
            $0.removeAll { $0.id == normalized.id }
            $0.append(normalized)
        }
        if select {
            @Shared(.mangaTranslationPreferences) var preferences
            $preferences.withLock { $0.selectedProviderID = provider.id }
        }
    }

    public static func delete(_ provider: MangaProviderConfig) {
        @Shared(.mangaTranslationProviders) var providers
        $providers.withLock { $0.removeAll { $0.id == provider.id } }
        @Shared(.mangaTranslationPreferences) var preferences
        if preferences.selectedProviderID == provider.id {
            $preferences.withLock { $0.selectedProviderID = "" }
        }
    }
}
