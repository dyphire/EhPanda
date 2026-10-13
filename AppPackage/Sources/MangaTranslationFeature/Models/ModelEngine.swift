import Foundation

public struct ModelEngine: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var isValid: Bool {
        ModelPackageManifest.isValidIdentifier(rawValue)
    }

    public static let rtDetrV2 = ModelEngine(rawValue: "rt_detr_v2")
    public static let mangaOCRTransformer = ModelEngine(rawValue: "manga_ocr_transformer")
    public static let yolo11nSeg = ModelEngine(rawValue: "yolo11n_seg")
    public static let mangaOCRMobile = ModelEngine(rawValue: "manga_ocr_mobile")
}
