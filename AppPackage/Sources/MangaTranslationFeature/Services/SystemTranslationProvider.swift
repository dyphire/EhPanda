import Foundation
import Translation
import OSLogExt

public enum SystemTranslationProvider {
    public static var displayName: String {
        String(localized: .systemTranslation)
    }

    public static var isAvailable: Bool {
        true
    }

    public static func translate(
        segments: [MangaTextSegment],
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> [String] {
        guard !segments.isEmpty else { return [] }
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw MangaTranslationFailure.languagePackRequired
        case .unsupported:
            throw MangaTranslationFailure.unsupportedLanguagePair
        @unknown default:
            throw MangaTranslationFailure.unavailable
        }
        do {
            let session = TranslationSession(
                installedSource: source,
                target: target
            )
            let requests = segments.map {
                TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id))
            }
            let responses = try await session.translations(from: requests)
            var translationsByID: [String: String] = [:]
            for response in responses {
                if let identifier = response.clientIdentifier {
                    translationsByID[identifier] = response.targetText
                }
            }
            let translations = segments.map { translationsByID[String($0.id)] ?? "" }
            guard responses.count == segments.count,
                translations.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            else {
                throw MangaTranslationFailure.invalidResponse
            }
            return translations
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MangaTranslationFailure {
            throw error
        } catch {
            Logger(category: "MangaTranslation").error("System translation failed: \(error)")
            if TranslationError.notInstalled ~= error {
                throw MangaTranslationFailure.languagePackRequired
            }
            throw MangaTranslationFailure.unavailable
        }
    }
}
