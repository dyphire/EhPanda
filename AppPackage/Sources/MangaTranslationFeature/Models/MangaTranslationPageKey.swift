import Foundation

/// Identity of one cached page translation. Everything the output depends on
/// — the source bytes, the model set, the provider — folds into the
/// signatures, so any change invalidates the row without a schema bump.
public struct MangaTranslationPageKey: Hashable, Codable, Sendable {
    public let galleryID: String
    public let pageNumber: Int
    public let sourceSignature: String
    public let providerSignature: String
    public let modelSignature: String

    public init(
        galleryID: String,
        pageNumber: Int,
        sourceSignature: String,
        providerSignature: String,
        modelSignature: String
    ) {
        self.galleryID = galleryID
        self.pageNumber = pageNumber
        self.sourceSignature = sourceSignature
        self.providerSignature = providerSignature
        self.modelSignature = modelSignature
    }

    // Signatures are "<detector sha256>:<recognizer sha256>:<inference cache
    // version>"; cache pruning uses the detector prefix to find retired
    // same-page rows (same detector family, older inference version).
    public var modelArchivePrefix: String {
        modelSignature.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    }

    public var cacheKey: String {
        MangaSignature.make([
            "galleryID": galleryID,
            "pageNumber": String(pageNumber),
            "sourceSignature": sourceSignature,
            "providerSignature": providerSignature,
            "modelSignature": modelSignature
        ])
    }
}
