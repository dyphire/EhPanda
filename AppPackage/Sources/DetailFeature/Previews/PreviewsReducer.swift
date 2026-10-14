import Foundation
import AppModels
import Sharing
import ComposableArchitecture
import AppComponents
import AppTools
import HapticsClient
import NetworkingFeature
import DownloadClient
import ReadingFeature

@Reducer
public struct PreviewsReducer: Sendable {
    @Reducer
    public enum Destination {
        case reading(ReadingReducer)
    }

    private enum CancelID {
        case observeDownloads
        case loadLocalPreviewURLs
        case fetchPreviewURLs
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        @SharedReader(.setting) public var setting: Setting
        @Presents public var destination: Destination.State?

        // The gallery id this screen fetches; captured when pushed onto the host's gallery stack.
        public var gid: String
        public var gallery: Gallery
        // Threaded from the detail context (via the `pushPreviews` delegate) so a reader opened from
        // this screen keeps the correct page math (`previewConfig`) and Live Text `language` for
        // remote sessions — Previews itself never fetches a gallery detail to re-derive them.
        public var language: Language?
        public var loadingState: LoadingState = .idle

        public var previewURLs = [Int: URL]()
        public var localPreviewURLs = [Int: URL]()
        public var previewConfig: PreviewConfig = .normal(rows: 4)
        public var localPreviewRequestID = UUID()

        // Display-ready ad set (recorded positives + neighbour backfill), seeded from
        // `@Shared(.adPageVerdictCache)` on appear and refreshed as detections land.
        public var adPageIndices = Set<Int>()
        public var adDetectionInFlight = Set<Int>()

        public init(
            gallery: Gallery,
            previewConfig: PreviewConfig = .normal(rows: 4), language: Language? = nil
        ) {
            self.gid = gallery.id
            self.gallery = gallery
            self.previewConfig = previewConfig
            self.language = language
        }

        mutating func updatePreviewURLs(_ previewURLs: [Int: URL]) {
            self.previewURLs = self.previewURLs.merging(
                previewURLs, uniquingKeysWith: { stored, _ in stored }
            )
        }
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case destination(PresentationAction<Destination.Action>)

        case updateReadingProgress(Int)

        case onAppear(String)
        case observeDownloads(String)
        case observeDownloadsDone([DownloadedGallery])
        case loadLocalPreviewURLs(String)
        case loadLocalPreviewURLsDone(UUID, [Int: URL])
        case openReading(Int)
        case openReadingDone(Result<(DownloadedGallery, DownloadManifest), AppError>)
        case fetchPreviewURLs(Int)
        case fetchPreviewURLsDone(Result<[Int: URL], AppError>)

        // A `nil` verdict means the thumbnail couldn't be loaded — nothing is recorded,
        // so a later appearance retries instead of caching a false negative. The third
        // payload is the page's pixel hash, supplied when the page was judged an ad.
        case detectAdPage(Int)
        case adPageDetected(Int, Bool?, String?)
    }

    @Dependency(\.downloadClient) private var downloadClient
    @Dependency(\.hapticsClient) private var hapticsClient
    @Dependency(\.date) private var date

    public init() {}

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .destination(.presented(.reading(.onPerformDismiss))):
                return .send(.destination(.dismiss))

            case .destination:
                return .none

            case .updateReadingProgress(let progress):
                @Shared(.galleryHistory) var galleryHistory
                $galleryHistory.withLock {
                    $0.updateReadingProgress(
                        gid: state.gallery.id, token: state.gallery.token, progress: progress, date: date.now
                    )
                }
                return .none

            case .onAppear(let gid):
                if state.setting.detectsAdPagesEnabled {
                    @Shared(.adPageVerdictCache) var verdictCache
                    state.adPageIndices = verdictCache.displayAdIndices(
                        gid: gid,
                        pageCount: state.gallery.pageCount
                    )
                }
                // Gallery is seeded from the pushing context; preview URLs are fetched on demand.
                return .merge(
                    .send(.observeDownloads(gid)),
                    .send(.loadLocalPreviewURLs(gid))
                )

            case .detectAdPage(let index):
                let gid = state.gallery.id
                let pageCount = state.gallery.pageCount
                guard state.setting.detectsAdPagesEnabled,
                      gid.isValidGID,
                      AdPageDetector.tailWindowIndices(pageCount: pageCount).contains(index),
                      !state.adDetectionInFlight.contains(index)
                else { return .none }
                @Shared(.adPageVerdictCache) var verdictCache
                if let verdict = verdictCache.verdict(gid: gid, pageIndex: index) {
                    if verdict {
                        state.adPageIndices = verdictCache.displayAdIndices(
                            gid: gid, pageCount: pageCount
                        )
                    }
                    return .none
                }
                guard let previewURL = state.localPreviewURLs[index] ?? state.previewURLs[index]
                else { return .none }
                state.adDetectionInFlight.insert(index)
                let knownAdImageHashes = verdictCache.adImageHashSet
                return .run { send in
                    guard let image = await AdPageThumbnailLoader.load(previewURL: previewURL) else {
                        await send(.adPageDetected(index, nil, nil))
                        return
                    }
                    let imageHash = image.cgImage.map { AdPageDetector.imageHash(for: $0) } ?? ""
                    // A known ad image needs no QR re-detection — ad images repeat
                    // across galleries byte-identically.
                    if !imageHash.isEmpty, knownAdImageHashes.contains(imageHash) {
                        await send(.adPageDetected(index, true, imageHash))
                        return
                    }
                    let isAd = AdPageDetector.isAdPage(image: image)
                    await send(.adPageDetected(index, isAd, isAd ? imageHash : nil))
                }

            case .adPageDetected(let index, let isAd, let imageHash):
                state.adDetectionInFlight.remove(index)
                guard let isAd else { return .none }
                let gid = state.gallery.id
                @Shared(.adPageVerdictCache) var verdictCache
                $verdictCache.withLock {
                    $0.record(gid: gid, pageIndex: index, isAd: isAd)
                    if let imageHash, !imageHash.isEmpty {
                        $0.recordAdImageHash(imageHash)
                    }
                }
                state.adPageIndices = verdictCache.displayAdIndices(
                    gid: gid, pageCount: state.gallery.pageCount
                )
                return .none

            case .observeDownloads(let gid):
                guard gid.isValidGID else { return .none }
                return .run { send in
                    var previousRelevantDownloads = [DownloadedGallery]()
                    var hadRelevantDownloads = false
                    for await downloads in downloadClient.observeDownloads() {
                        let relevantDownloads = downloads.filter { $0.gid == gid }
                        let hasRelevantDownloads = !relevantDownloads.isEmpty
                        guard hasRelevantDownloads || hadRelevantDownloads else { continue }
                        if relevantDownloads == previousRelevantDownloads {
                            hadRelevantDownloads = hasRelevantDownloads
                            continue
                        }
                        previousRelevantDownloads = relevantDownloads
                        hadRelevantDownloads = hasRelevantDownloads
                        await send(.observeDownloadsDone(relevantDownloads))
                    }
                }
                .cancellable(id: CancelID.observeDownloads, cancelInFlight: true)

            case .observeDownloadsDone:
                return .send(.loadLocalPreviewURLs(state.gallery.id))

            case .loadLocalPreviewURLs(let gid):
                guard gid.isValidGID else {
                    state.localPreviewRequestID = UUID()
                    state.localPreviewURLs = .init()
                    return .none
                }
                let requestID = UUID()
                state.localPreviewRequestID = requestID
                return .run { send in
                    let localPreviewURLs = await downloadClient.loadLocalPageURLs(gid) ?? [:]
                    await send(.loadLocalPreviewURLsDone(requestID, localPreviewURLs))
                }
                .cancellable(id: CancelID.loadLocalPreviewURLs, cancelInFlight: true)

            case .loadLocalPreviewURLsDone(let requestID, let localPreviewURLs):
                guard state.localPreviewRequestID == requestID else { return .none }
                guard state.localPreviewURLs != localPreviewURLs else { return .none }
                state.localPreviewURLs = localPreviewURLs
                return .none

            case .openReading:
                return .run { [galleryID = state.gallery.id] send in
                    guard galleryID.isValidGID else {
                        await send(.openReadingDone(.failure(.notFound)))
                        return
                    }
                    await send(.openReadingDone(.success(try await downloadClient.loadManifest(galleryID))))
                } catch: { error, send in
                    await send(.openReadingDone(.failure(AppError(error))))
                }

            case .openReadingDone(let result):
                var readingState: ReadingReducer.State
                if case .success(let (download, manifest)) = result {
                    readingState = .init(
                        gallery: state.gallery, contentSource: .local(download, manifest),
                        previewConfig: state.previewConfig, language: state.language
                    )
                } else {
                    readingState = .init(
                        gallery: state.gallery, contentSource: .remote,
                        previewConfig: state.previewConfig, language: state.language
                    )
                    readingState.localPageURLs = state.localPreviewURLs
                }
                state.destination = .reading(readingState)
                return .none

            case .fetchPreviewURLs(let index):
                guard state.loadingState != .loading,
                      let galleryURL = state.gallery.galleryURL
                else { return .none }
                state.loadingState = .loading
                let pageNum = state.previewConfig.pageNumber(index: index)
                return .run { send in
                    let response = await GalleryPreviewURLsRequest(galleryURL: galleryURL, pageNum: pageNum).response()
                    await send(.fetchPreviewURLsDone(response))
                }
                .cancellable(id: CancelID.fetchPreviewURLs)

            case .fetchPreviewURLsDone(let result):
                state.loadingState = .idle

                switch result {
                case .success(let previewURLs):
                    guard !previewURLs.isEmpty else {
                        state.loadingState = .failed(.notFound)
                        return .none
                    }
                    state.updatePreviewURLs(previewURLs)
                    // A cell that appeared before its preview URL existed couldn't run
                    // ad detection; revisit the newly arrived batch (deduped downstream).
                    return .run { send in
                        for previewIndex in previewURLs.keys {
                            await send(.detectAdPage(previewIndex))
                        }
                    }
                case .failure(let error):
                    state.loadingState = .failed(error)
                }
                return .none
            }
        }
        .haptics(
            unwrapping: \.destination,
            case: \.reading,
            hapticsClient: hapticsClient
        )
        .ifLet(\.$destination, action: \.destination)
    }
}

extension PreviewsReducer.Destination.State: Equatable, Sendable {}
