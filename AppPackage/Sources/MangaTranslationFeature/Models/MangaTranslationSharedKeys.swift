import Foundation
import AppModels
import Sharing

// Manga translation preferences and provider configs are user-authored and small, so they
// persist whole in app storage like the rest of the account preferences (see AppSharedKeys).
// API keys follow the same plaintext-in-defaults posture as the EH credentials.

extension SharedKey where Self == AppStorageKey<MangaTranslationPreferences>.Default {
    public static var mangaTranslationPreferences: Self {
        Self[.appStorage("mangaTranslationPreferences"), default: MangaTranslationPreferences()]
    }
}

extension SharedKey where Self == AppStorageKey<[MangaProviderConfig]>.Default {
    public static var mangaTranslationProviders: Self {
        Self[.appStorage("mangaTranslationProviders"), default: []]
    }
}

extension SharedKey where Self == AppStorageKey<ModelLibraryConfiguration>.Default {
    public static var mangaModelLibrary: Self {
        Self[.appStorage("mangaModelLibrary"), default: ModelLibraryConfiguration()]
    }
}
