import Foundation
import Sharing

public enum ModelCatalogService {
    public static func fetch() async throws -> ModelCatalog {
        @Shared(.mangaModelLibrary) var configuration
        guard let url = URL(string: configuration.catalogURL), url.scheme == "https" else {
            throw ModelCatalogError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
            data.count <= 1024 * 1024
        else {
            throw ModelCatalogError.invalidResponse
        }
        let catalog = try JSONDecoder().decode(ModelCatalog.self, from: data)
        guard catalog.isValid, catalog.models.allSatisfy({ $0.url.scheme == "https" }) else {
            throw ModelCatalogError.invalidResponse
        }
        $configuration.withLock { $0.catalog = catalog }
        return catalog
    }
}
