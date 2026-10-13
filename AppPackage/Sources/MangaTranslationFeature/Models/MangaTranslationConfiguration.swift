import Foundation
import Sharing

public struct MangaTranslationConfiguration: Hashable, Sendable {
    private static let inferenceCacheVersion = "inference-6"

    public let detectorArchive: ModelArchive
    public let recognizerArchive: ModelArchive
    public let provider: MangaProviderConfig?
    public let isOffline: Bool
    public let sourceLanguage: String
    public let targetLanguage: String
    public let metadata: MangaTranslationMetadata?

    public init(
        detectorArchive: ModelArchive,
        recognizerArchive: ModelArchive,
        provider: MangaProviderConfig?,
        isOffline: Bool,
        sourceLanguage: String,
        targetLanguage: String,
        metadata: MangaTranslationMetadata?
    ) {
        self.detectorArchive = detectorArchive
        self.recognizerArchive = recognizerArchive
        self.provider = provider
        self.isOffline = isOffline
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.metadata = metadata
    }

    public var hasConfiguredProvider: Bool {
        provider?.isConfigured == true
    }

    public var usesSystemProvider: Bool {
        !hasConfiguredProvider && SystemTranslationProvider.isAvailable
    }

    public var canTranslate: Bool {
        (hasConfiguredProvider && !isOffline) || usesSystemProvider
    }

    public var providerSignature: String {
        guard let provider, hasConfiguredProvider else {
            return MangaSignature.make([
                "provider": usesSystemProvider ? "system" : "unconfigured",
                "sourceLanguage": sourceLanguage,
                "targetLanguage": targetLanguage
            ])
        }
        return provider.signature(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            metadata: metadata
        )
    }

    public var modelSignature: String {
        "\(detectorArchive.sha256):\(recognizerArchive.sha256):\(Self.inferenceCacheVersion)"
    }

    public static func current(
        metadata: MangaTranslationMetadata? = nil,
        isOffline: Bool
    ) async throws -> MangaTranslationConfiguration? {
        guard let detectorArchive = MangaModelLibrary.selectedArchive(for: .detector),
            let recognizerArchive = MangaModelLibrary.selectedArchive(for: .recognizer)
        else { return nil }
        @Shared(.mangaTranslationPreferences) var preferences
        let languages = resolvedLanguages(metadata: metadata, preferences: preferences)
        return MangaTranslationConfiguration(
            detectorArchive: detectorArchive,
            recognizerArchive: recognizerArchive,
            provider: try await MangaProviderLibrary.current(),
            isOffline: isOffline,
            sourceLanguage: languages.sourceLanguage,
            targetLanguage: languages.targetLanguage,
            metadata: preferences.includeMetadata ? metadata : nil
        )
    }

    public static func resolvedLanguages(
        metadata: MangaTranslationMetadata?,
        preferences: MangaTranslationPreferences
    ) -> (sourceLanguage: String, targetLanguage: String) {
        let sourceLanguage =
            MangaTranslationLanguage.normalized(metadata?.sourceLanguage)
            ?? MangaTranslationLanguage.normalized(preferences.sourceLanguage)
            ?? MangaTranslationLanguage.defaultSource
        let targetLanguage =
            MangaTranslationLanguage.normalized(preferences.targetLanguage)
            ?? MangaTranslationLanguage.systemTarget
        return (sourceLanguage, targetLanguage)
    }
}
