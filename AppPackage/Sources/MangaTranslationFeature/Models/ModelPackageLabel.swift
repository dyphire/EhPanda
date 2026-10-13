import Foundation

public struct ModelPackageLabel: Codable, Hashable, Sendable {
    public let name: String
    public let recognize: Bool
    public let orientation: String?

    public init(name: String, recognize: Bool, orientation: String? = nil) {
        self.name = name
        self.recognize = recognize
        self.orientation = orientation
    }

    public var isValid: Bool {
        guard !name.isEmpty else { return false }
        guard let orientation else { return true }
        return ["unknown", "horizontal", "vertical"].contains(orientation)
    }
}
