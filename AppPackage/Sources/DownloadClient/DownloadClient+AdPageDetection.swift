import UIKit
import AppModels
import OSLogExt
import ParserFeature
import NetworkingFeature

private let logger = Logger(category: "AdPageDetection")

// MARK: - Ad Page Detection
extension DownloadCoordinator {
    /// Returns the pending tail pages that ad-page detection flags for skipping.
    ///
    /// Samples are *thumbnails*, matching the reader/previews surfaces: verdicts already
    /// in the shared cache cost nothing, and a page whose thumbnail can't be produced
    /// simply stays pending (no false skip, no poisoned cache). Positives are widened by
    /// `AdPageDetector.backfilled` before intersecting with the pending set.
    public func detectAdPagesToSkip(
        payload: DownloadRequestPayload,
        options: DownloadRequestOptions,
        pendingIndices: [Int]
    ) async -> Set<Int> {
        let gid = payload.gallery.gid
        let pageCount = payload.galleryDetail.pageCount
        let tailIndices = Set(AdPageDetector.tailWindowIndices(pageCount: pageCount))
        let candidates = pendingIndices.filter { tailIndices.contains($0) }
        guard !candidates.isEmpty else { return [] }

        let snapshot = await adPageVerdictsProvider(gid)
        var previewURLs = payload.previewURLs
        var verdicts = [Int: Bool]()
        for index in candidates {
            if let verdict = snapshot.verdicts[index] {
                verdicts[index] = verdict
                continue
            }
            guard let image = await adPageThumbnail(
                index: index, payload: payload, previewURLs: &previewURLs,
                allowsCellular: options.allowCellular
            ) else { continue }
            let imageHash = image.cgImage.map { AdPageDetector.imageHash(for: $0) } ?? ""
            // A known ad image needs no QR re-detection — ad images repeat across galleries.
            if snapshot.adImageHashes.contains(imageHash), !imageHash.isEmpty {
                verdicts[index] = true
                await adPageVerdictRecorder(gid, index, true, imageHash)
                continue
            }
            let isAd = AdPageDetector.isAdPage(image: image)
            verdicts[index] = isAd
            await adPageVerdictRecorder(gid, index, isAd, isAd ? imageHash : nil)
        }
        let detected = Set(verdicts.filter(\.value).keys)
        guard !detected.isEmpty else { return [] }
        return AdPageDetector.backfilled(detected, pageCount: pageCount).intersection(pendingIndices)
    }

    /// The payload only carries the detail page's first preview batch; tail pages usually
    /// need their preview batch fetched on demand (same request the grids use).
    private func adPageThumbnail(
        index: Int,
        payload: DownloadRequestPayload,
        previewURLs: inout [Int: URL],
        allowsCellular: Bool
    ) async -> UIImage? {
        if previewURLs[index] == nil,
           let galleryURL = payload.gallery.galleryURL
        {
            let pageNum = payload.previewConfig.pageNumber(index: index)
            if let fetched = try? await GalleryPreviewURLsRequest(
                galleryURL: galleryURL, pageNum: pageNum
            ).response().get() {
                previewURLs.merge(fetched, uniquingKeysWith: { stored, _ in stored })
            }
        }
        guard let previewURL = previewURLs[index] else { return nil }
        return await loadAdPageThumbnail(previewURL: previewURL, allowsCellular: allowsCellular)
    }

    /// Fetches the (sprite) thumbnail and crops the single page out of it, mirroring the
    /// grids' `RoundedOffsetModifier` geometry.
    private func loadAdPageThumbnail(previewURL: URL, allowsCellular: Bool) async -> UIImage? {
        let info = Parser.parsePreviewConfigs(url: previewURL)
        let spriteURL = info?.plainURL ?? previewURL
        var request = URLRequest(url: spriteURL)
        request.allowsCellularAccess = allowsCellular
        guard let (data, _) = try? await dataResponse(for: request),
              let image = UIImage(data: data), let cgImage = image.cgImage
        else { return nil }
        guard let info else { return image }
        let scale = image.scale
        let rect = CGRect(
            x: info.offset.width * scale, y: info.offset.height * scale,
            width: info.size.width * scale, height: info.size.height * scale
        )
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
    }

    /// Stamps the ad-skipped sentinel on the given pages so an interrupted run resumes
    /// with them still skipped. Pages that already hold a real hash are left untouched.
    public func markManifestAdSkippedPages(
        _ indices: Set<Int>,
        folderURL: URL
    ) throws {
        guard !indices.isEmpty else { return }
        var manifest = try storage.readManifest(folderURL: folderURL)
        var didUpdate = false
        for index in indices {
            let value = manifest.pages[index]
            guard value == nil || value?.isEmpty == true else { continue }
            manifest.pages[index] = DownloadManifest.adSkippedPageMarker
            didUpdate = true
        }
        guard didUpdate else { return }
        try storage.writeManifest(manifest, folderURL: folderURL)
        updateDownloadIndex(folderURL: folderURL, manifest: manifest)
        logger.notice("Marked \(indices.count) ad page(s) as skipped, gid: \(manifest.gid, privacy: .public)")
    }
}
