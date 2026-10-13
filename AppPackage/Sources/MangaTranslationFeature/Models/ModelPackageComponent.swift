import Foundation

public struct ModelPackageComponent: Codable, Hashable, Sendable {
    public let engine: ModelEngine
    public let engineVersion: Int
    public let files: [String: String]
    public let labels: [String: ModelPackageLabel]?

    public init(
        engine: ModelEngine,
        engineVersion: Int,
        files: [String: String],
        labels: [String: ModelPackageLabel]? = nil
    ) {
        self.engine = engine
        self.engineVersion = engineVersion
        self.files = files
        self.labels = labels
    }

    public var coreMLFileNames: [String] {
        files.filter { $0.value.hasSuffix(".mlpackage") }.map(\.key).sorted()
    }

    public var isValid: Bool {
        engine.isValid && engineVersion > 0 && !files.isEmpty && labelsAreValid
            && files.allSatisfy {
                ModelPackageManifest.isValidIdentifier($0.key)
                    && ModelPackageManifest.isValidRelativePath($0.value)
            }
    }

    private var labelsAreValid: Bool {
        guard let labels else { return true }
        return !labels.isEmpty
            && labels.allSatisfy {
                Int($0.key) != nil && $0.value.isValid
            }
    }

    enum CodingKeys: String, CodingKey {
        case engine
        case engineVersion = "engine_version"
        case files
        case labels
    }

    public static let currentMangaOCRComponents: [String: ModelPackageComponent] = [
        "detector": ModelPackageComponent(
            engine: .rtDetrV2,
            engineVersion: 1,
            files: ["model": "detector.mlpackage"],
            labels: [
                "0": ModelPackageLabel(name: "bubble", recognize: false),
                "1": ModelPackageLabel(name: "text_bubble", recognize: true),
                "2": ModelPackageLabel(name: "text_free", recognize: true)
            ]
        ),
        "recognizer": ModelPackageComponent(
            engine: .mangaOCRTransformer,
            engineVersion: 1,
            files: [
                "encoder": "ocr_encoder.mlpackage",
                "decoder": "ocr_decoder.mlpackage",
                "tokenizer": "vocab.txt"
            ]
        )
    ]
}
