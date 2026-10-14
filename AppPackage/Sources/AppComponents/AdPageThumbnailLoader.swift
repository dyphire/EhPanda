import SwiftUI
import AppTools
import AppModels
import Kingfisher
import ParserFeature

/// Loads the single-page thumbnail used as the ad-page detection sample.
///
/// Sprite-aware: the crop mirrors `PreviewResolver` / `RoundedOffsetModifier` (minus the
/// corner rounding), so detection runs on exactly the pixels the grid displays. Reads
/// through the shared Kingfisher cache first, so a page the user just looked at costs no
/// network; misses fetch the sprite sheet through the cookie-configured shared downloader.
/// Local file URLs (downloaded pages) are read straight from disk.
public enum AdPageThumbnailLoader {
    public static func load(previewURL: URL) async -> UIImage? {
        if previewURL.isFileURL {
            return UIImage(contentsOfFile: previewURL.path)
        }
        let info = Parser.parsePreviewConfigs(url: previewURL)
        let spriteURL = info?.plainURL ?? previewURL
        let cacheKey = spriteURL.stableImageCacheKey
            ?? previewURL.stableImageCacheKey
            ?? previewURL.absoluteString
        if let cached = try? await KingfisherManager.shared.cache.retrieveImage(forKey: cacheKey),
           let image = cached.image
        {
            return crop(image, info: info)
        }
        guard let downloaded = try? await KingfisherManager.shared.downloader.downloadImage(with: spriteURL)
        else { return nil }
        return crop(downloaded.image, info: info)
    }

    private static func crop(_ image: UIImage, info: Parser.PreviewConfigInfo?) -> UIImage {
        guard let info, let cropped = image.cropping(size: info.size, offset: info.offset)
        else { return image }
        return cropped
    }
}
