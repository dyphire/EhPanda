import Foundation

public struct MangaChatMessage: Decodable {
    public let content: String
}

public struct MangaChatChoice: Decodable {
    public let message: MangaChatMessage
}

public struct MangaChatCompletionEnvelope: Decodable {
    public let choices: [MangaChatChoice]
}

public struct MangaTranslationEnvelope: Decodable {
    public let translations: [MangaTextSegment]
}
