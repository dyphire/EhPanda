import CoreGraphics
import CoreML
import Foundation

public enum MangaOCRPreprocessing: Sendable {
    case stretch
    case letterbox

    public func pixelValues(_ image: CGImage) throws -> MLMultiArray {
        switch self {
        case .stretch:
            return try MangaInferenceUtilities.pixelValues(image, width: 224, height: 224, normalize: true)
        case .letterbox:
            return try MangaInferenceUtilities.pixelValuesLetterbox(image, size: 224)
        }
    }
}
