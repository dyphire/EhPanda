import Foundation

public enum MangaTranslationStatus: Hashable, Codable, Sendable {
    case translated
    case recognitionOnly(MangaTranslationFailure)

    public var failure: MangaTranslationFailure? {
        if case .recognitionOnly(let failure) = self { return failure }
        return nil
    }
}
