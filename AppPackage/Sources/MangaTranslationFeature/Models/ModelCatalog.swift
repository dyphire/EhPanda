import Foundation

public struct ModelCatalog: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let models: [ModelArchive]

    public init(formatVersion: Int, models: [ModelArchive]) {
        self.formatVersion = formatVersion
        self.models = models
    }

    public var isValid: Bool {
        let ids = models.map(\.id)
        return formatVersion == 2 && !models.isEmpty && Set(ids).count == ids.count
            && models.allSatisfy(\.isValid)
    }

    public func models(for purpose: ModelPurpose) -> [ModelArchive] {
        models.filter { $0.purpose == purpose }
    }

    public func archive(id: String, purpose: ModelPurpose? = nil) -> ModelArchive? {
        models.first { $0.id == id && (purpose == nil || $0.purpose == purpose) }
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case models
    }
}
