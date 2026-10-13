import Foundation

public enum ModelCatalogError: String, Error, Sendable {
    case invalidResponse
}

extension ModelCatalogError: LocalizedError {
    public var errorDescription: String? { String(localized: .modelCatalogInvalid) }
}
