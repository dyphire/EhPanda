import CoreGraphics
import CoreImage
import CoreML
import Foundation
import OSLogExt

private let logger = Logger(category: "MangaTranslation")

public struct MangaOCRRecognizer: MangaTextRecognizing {
    private let preprocessing: MangaOCRPreprocessing
    private let decoder: MangaGreedyDecoder

    public init(models: MangaModelSet, preprocessing: MangaOCRPreprocessing) throws {
        self.preprocessing = preprocessing
        decoder = try MangaGreedyDecoder(models: models)
    }

    public func recognize(crops regions: [MangaTextRegion], image: CGImage) throws -> [MangaTextRegion] {
        var recognized: [MangaTextRegion] = []
        for region in regions {
            try Task.checkCancellation()
            let crop = try MangaInferenceUtilities.cropImage(image, normalizedRect: region.sourceBox)
            let pixels = try preprocessing.pixelValues(crop)
            guard let text = try decoder.recognize(crop: pixels) else { continue }
            recognized.append(
                MangaTextRegion(
                    id: recognized.count,
                    label: region.label,
                    score: region.score,
                    sourceBox: region.sourceBox,
                    box: region.box,
                    text: text,
                    translatedText: nil,
                    orientation: region.orientation
                )
            )
        }
        logger.info("Manga OCR: recognized \(recognized.count) of \(regions.count) regions")
        return recognized
    }
}
