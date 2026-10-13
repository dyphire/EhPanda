import Foundation

public struct ModelPackageManifest: Codable, Hashable, Sendable {
    public let formatVersion: Int
    public let capabilities: [String]
    public let components: [String: ModelPackageComponent]

    public init(formatVersion: Int, capabilities: [String], components: [String: ModelPackageComponent]) {
        self.formatVersion = formatVersion
        self.capabilities = capabilities
        self.components = components
    }

    public var isValid: Bool {
        formatVersion == 1 && !capabilities.isEmpty
            && Set(capabilities).count == capabilities.count
            && capabilities.allSatisfy(Self.isValidIdentifier)
            && !components.isEmpty
            && components.allSatisfy { Self.isValidIdentifier($0.key) && $0.value.isValid }
    }

    public func matches(_ archive: ModelArchive) -> Bool {
        Set(capabilities) == Set(archive.capabilities)
            && components == archive.components
    }

    public static func isValidIdentifier(_ value: String) -> Bool {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !value.isEmpty && value.count <= 64 && value != "." && value != ".."
            && value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

    public static func isValidRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(".") && !components.contains("..") && !components.contains("")
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case capabilities
        case components
    }
}
