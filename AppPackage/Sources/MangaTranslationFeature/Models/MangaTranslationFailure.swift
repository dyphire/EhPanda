import Foundation

public enum MangaTranslationFailure: String, Error, Codable, Sendable {
    case offline
    case notConfigured
    case modelPreparation
    case unsupportedModel
    case inference
    case noText
    case network
    case timeout
    case authentication
    case rateLimited
    case unavailable
    case languagePackRequired
    case unsupportedLanguagePair
    case invalidResponse

    public var notifiesDuringAutomaticTranslation: Bool {
        switch self {
        case .inference, .noText:
            return false
        default:
            return true
        }
    }

    public var description: String {
        switch self {
        case .offline:
            return String(localized: .mangaErrorOffline)
        case .notConfigured:
            return String(localized: .mangaErrorNotConfigured)
        case .modelPreparation:
            return String(localized: .mangaErrorModelPreparation)
        case .unsupportedModel:
            return String(localized: .mangaErrorUnsupportedModel)
        case .inference:
            return String(localized: .mangaErrorInference)
        case .noText:
            return String(localized: .mangaErrorNoText)
        case .network:
            return String(localized: .mangaErrorNetwork)
        case .timeout:
            return String(localized: .mangaErrorTimeout)
        case .authentication:
            return String(localized: .mangaErrorAuthentication)
        case .rateLimited:
            return String(localized: .mangaErrorRateLimited)
        case .unavailable:
            return String(localized: .mangaErrorUnavailable)
        case .languagePackRequired:
            return String(localized: .mangaErrorLanguagePackRequired)
        case .unsupportedLanguagePair:
            return String(localized: .mangaErrorUnsupportedLanguagePair)
        case .invalidResponse:
            return String(localized: .mangaErrorInvalidResponse)
        }
    }
}
