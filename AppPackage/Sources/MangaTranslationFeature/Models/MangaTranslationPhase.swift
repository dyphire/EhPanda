import Foundation

public enum MangaTranslationPhase: Equatable, Sendable {
    case idle
    case preparingModels
    case detecting
    case recognizing
    case translating
    case completed
    case noText
    case failed(MangaTranslationFailure)

    public var isBusy: Bool {
        switch self {
        case .preparingModels, .detecting, .recognizing, .translating:
            return true
        default:
            return false
        }
    }

    public var title: String {
        switch self {
        case .idle:
            return String(localized: .actionTranslatePage)
        case .preparingModels:
            return String(localized: .actionPreparingModels)
        case .detecting:
            return String(localized: .actionDetecting)
        case .recognizing:
            return String(localized: .actionRecognizing)
        case .translating:
            return String(localized: .actionTranslating)
        case .completed:
            return String(localized: .actionCompleted)
        case .noText:
            return MangaTranslationFailure.noText.description
        case .failed(let failure):
            return failure.description
        }
    }
}
