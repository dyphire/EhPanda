import SwiftUI
import Sharing
import AppModels
import Observation
import SFSafeSymbols
import SwiftUIPager
import ComposableArchitecture
import AppTools
import AnimatedImageFeature
import MangaTranslationFeature
import SystemNotificationExt
import AppComponents
import ReadingSettingFeature

public struct ReadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var store: StoreOf<ReadingReducer>
    // Write handle for ControlPanel setting edits. The reading-setting sheet owns its own
    // `@Shared(.setting)`; this view derives an `effectiveSetting` that forces vertical mode
    // for webtoon galleries without mutating the global setting.
    @Shared(.setting) private var setting: Setting
    let gid: String
    let blurRadius: Double

    @State private var enablesLiveText = false
    @State private var mangaTranslationHandler = MangaTranslationHandler()
    @State private var showsMangaTranslationSettings = false
    @State private var autoPlayHandler = AutoPlayHandler()
    @State var gestureHandler = GestureHandler()
    @State private var pageHandler: PageHandler
    @StateObject var page: Page

    public init(
        store: StoreOf<ReadingReducer>,
        gid: String, blurRadius: Double
    ) {
        self.store = store
        self.gid = gid
        self.blurRadius = blurRadius
        // Seed the pager and slider from the resume page the reducer computed in `State.init`, so the
        // reader opens on the saved page. Seeding replaced a `.restoreSession` action that mutated
        // `readingProgress` after the view had subscribed; with no post-subscribe change event, the
        // pager must be positioned at construction or every session would open at page 1.
        let resumePage = max(store.state.readingProgress, 1)
        let handler = PageHandler()
        handler.sliderValue = Float(resumePage)
        let pagerIndex = handler.mapToPager(index: resumePage, setting: store.state.setting)
        _pageHandler = State(wrappedValue: handler)
        _page = StateObject(wrappedValue: .withIndex(pagerIndex))
    }

    private var backgroundColor: Color {
        colorScheme == .light ? Color(.systemGray4) : Color(.systemGray6)
    }

    private var displayPreviewURLs: [Int: URL] {
        store.localPageURLs.merging(store.previewURLs, uniquingKeysWith: { local, _ in local })
    }

    private var displayImageURLs: [Int: URL] {
        store.localPageURLs.merging(store.imageURLs, uniquingKeysWith: { local, _ in local })
    }

    private var displayOriginalImageURLs: [Int: URL] {
        if store.contentSource == .remote {
            return store.originalImageURLs
        }
        return store.localPageURLs.merging(store.originalImageURLs, uniquingKeysWith: { local, _ in local })
    }

    private var effectiveSetting: Setting {
        var copy = store.setting
        if store.gallery.hasWebtoonTag {
            copy.readingDirection = .vertical
        }
        return copy
    }

    private var effectiveSettingBinding: Binding<Setting> {
        Binding(
            get: { effectiveSetting },
            set: { newValue in
                var adjusted = newValue
                if store.gallery.hasWebtoonTag {
                    adjusted.readingDirection = store.setting.readingDirection
                }
                setting = adjusted
            }
        )
    }

    public var body: some View {
        @Bindable var bindablePageHandler = pageHandler

        return changeTriggers(content: { content })
            .sheet(
                item: $store.scope(state: \.destination?.readingSetting, action: \.destination.readingSetting)
            ) { readingSettingStore in
                NavigationStack {
                    ReadingSettingView(store: readingSettingStore)
                    .toolbar {
                        if !DeviceUtil.isPad && DeviceUtil.isLandscape {
                            CustomToolbarItem(placement: .cancellationAction) {
                                Button {
                                    store.send(.destination(.dismiss))
                                } label: {
                                    Image(systemSymbol: .chevronDown)
                                }
                            }
                        }
                    }
                }
                .accentColor(effectiveSetting.accentColor)
                .tint(effectiveSetting.accentColor)
                .autoBlur(radius: blurRadius)
            }
            .sheet(item: $store.destination.share, id: \.id) { shareItemBox in
                ActivityView(activityItems: [shareItemBox.wrappedValue.associatedValue])
                    .accentColor(effectiveSetting.accentColor)
                    .autoBlur(radius: blurRadius)
            }
            .sheet(isPresented: $showsMangaTranslationSettings) {
                mangaTranslationHandler.refreshConfiguration()
            } content: {
                NavigationStack {
                    MangaTranslationSettingsView()
                }
                .accentColor(effectiveSetting.accentColor)
                .autoBlur(radius: blurRadius)
            }
            .toast($store.scope(state: \.toast, action: \.toast))

            .animation(.linear(duration: 0.1), value: gestureHandler.offset)
            .animation(.default, value: enablesLiveText)
            .animation(.default, value: gestureHandler.scale)
            .animation(.default, value: store.showsPanel)
            .statusBar(hidden: !store.showsPanel)
            .onDisappear {
                mangaTranslationHandler.cancelAll()
                setAutoPlayPolocy(.off)
            }
            .onAppear {
                mangaTranslationHandler.setContext(
                    gid: gid,
                    pageCount: store.gallery.pageCount,
                    isOffline: store.state.isOffline,
                    metadata: Self.mangaTranslationMetadata(
                        gallery: store.gallery, language: store.state.language
                    )
                )
                mangaTranslationHandler.imageURLForIndex = { index in displayImageURLs[index] }
                mangaTranslationHandler.isAdPage = { index in store.adPageIndices.contains(index) }
                mangaTranslationHandler.onFailure = { failure in
                    store.send(.mangaTranslationFailed(failure.description))
                }
                store.send(.onAppear(gid))
            }
    }

    private var liveTextBinding: Binding<Bool> {
        Binding(
            get: { enablesLiveText },
            set: { newValue in
                enablesLiveText = newValue
                // Live Text and the translation overlay cannot analyze the same page.
                if newValue {
                    mangaTranslationHandler.setEnabled(false)
                }
            }
        )
    }

    private var mangaTranslationBinding: Binding<Bool> {
        Binding(
            get: { mangaTranslationHandler.isEnabled },
            set: { newValue in
                mangaTranslationHandler.setEnabled(newValue)
                if newValue {
                    enablesLiveText = false
                    _ = MangaModelMemoryWarningObserver.shared
                    configureDefaultMangaModelsIfNeeded()
                    mangaTranslationHandler.syncQueue(currentIndex: currentPageNumber)
                }
            }
        )
    }

    private var currentPageNumber: Int {
        pageHandler.mapFromPager(
            index: page.index, pageCount: store.gallery.pageCount, setting: effectiveSetting
        )
    }

    private func configureDefaultMangaModelsIfNeeded() {
        guard MangaModelLibrary.selectedArchive(for: .detector) == nil
            || MangaModelLibrary.selectedArchive(for: .recognizer) == nil
        else { return }
        Task {
            do {
                let catalog = try await ModelCatalogService.fetch()
                for role in MangaModelRole.allCases
                where MangaModelLibrary.selectedArchive(for: role) == nil {
                    if let archive = catalog.models(for: .mangaOCR)
                        .first(where: { MangaModelSet.supports($0, for: role) })
                    {
                        MangaModelLibrary.select(archive, for: role)
                    }
                }
            } catch {
                store.send(.mangaTranslationFailed(error.localizedDescription))
            }
        }
    }

    static func mangaTranslationMetadata(
        gallery: Gallery,
        language: Language?
    ) -> MangaTranslationMetadata {
        func tagTexts(namespaces: [String], excluding: Bool = false) -> [String] {
            gallery.tags
                .filter { namespaces.contains($0.rawNamespace) != excluding }
                .flatMap(\.contents)
                .map(\.text)
        }
        let artistNamespaces = ["artist", "group"]
        return MangaTranslationMetadata(
            seriesTitle: gallery.titleJpn ?? gallery.title,
            bookTitle: "",
            authors: tagTexts(namespaces: artistNamespaces),
            genres: tagTexts(namespaces: artistNamespaces, excluding: true),
            sourceLanguage: language.flatMap {
                $0.abbreviation == "N/A" ? nil : $0.abbreviation.lowercased()
            }
        )
    }

    var content: some View {
        @Bindable var bindablePageHandler = pageHandler

        return ZStack {
            backgroundColor.ignoresSafeArea()

            ZStack {
                if effectiveSetting.readingDirection == .vertical {
                    AdvancedList(
                        page: page,
                        data: store.state.containerDataSource(
                            setting: effectiveSetting,
                            isLandscape: DeviceUtil.isLandscape
                        ),
                        id: \.self,
                        spacing: effectiveSetting.contentDividerHeight,
                        gesture: SimultaneousGesture(magnificationGesture, tapGesture),
                        content: imageStack
                    )
                    .scrollDisabled(gestureHandler.scale != 1)
                } else {
                    Pager(
                        page: page,
                        data: store.state.containerDataSource(
                            setting: effectiveSetting,
                            isLandscape: DeviceUtil.isLandscape
                        ),
                        id: \.self,
                        content: imageStack
                    )
                    .horizontal(effectiveSetting.readingDirection == .rightToLeft ? .endToStart : .startToEnd)
                    .swipeInteractionArea(.allAvailable)
                    .allowsDragging(gestureHandler.scale == 1)
                }
            }
            .scaleEffect(gestureHandler.scale, anchor: gestureHandler.scaleAnchor)
            .offset(gestureHandler.offset)
            .highPriorityGesture(
                dragGesture.simultaneously(with: tapGesture),
                isEnabled: gestureHandler.scale > 1
            )
            .gesture(tapGesture, isEnabled: gestureHandler.scale == 1)
            .gesture(magnificationGesture)
            .ignoresSafeArea()
            .id(store.forceRefreshID)

            ControlPanel(
                showsPanel: $store.showsPanel,
                showsSliderPreview: $store.showsSliderPreview,
                sliderValue: $bindablePageHandler.sliderValue, setting: effectiveSettingBinding,
                enablesLiveText: liveTextBinding,
                enablesMangaTranslation: mangaTranslationBinding,
                mangaTranslationPhase: mangaTranslationHandler.phase,
                autoPlayPolicy: .init(get: { autoPlayHandler.policy }, set: { setAutoPlayPolocy($0) }),
                range: 1...Float(store.gallery.pageCount),
                previewURLs: displayPreviewURLs,
                adPageIndices: store.adPageIndices,
                dismissGesture: controlPanelDismissGesture,
                dismissAction: { store.send(.onPerformDismiss) },
                navigateSettingAction: { store.send(.presentReadingSetting) },
                reloadAllImagesAction: { store.send(.reloadAllWebImages) },
                retryAllFailedImagesAction: { store.send(.retryAllFailedWebImages) },
                fetchPreviewURLsAction: { store.send(.fetchPreviewURLs($0)) },
                translatePageAction: { mangaTranslationHandler.translatePage(currentPageNumber) },
                toggleMangaTranslationVisibilityAction: { mangaTranslationHandler.toggleVisibility() },
                navigateMangaTranslationSettingAction: { showsMangaTranslationSettings = true }
            )
        }
    }

    @ViewBuilder
    private func changeTriggers<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        pageAndAutoPlayTriggers(content: content)
            // Orientation
            .onChange(of: effectiveSetting.enablesLandscape) { _, newValue in
                store.send(.setOrientationPortrait(!newValue))
            }
    }

    @ViewBuilder
    private func pageAndAutoPlayTriggers<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            // Page
            .onChange(of: page.index) { _, newValue in
                let newValue = pageHandler.mapFromPager(
                    index: newValue, pageCount: store.gallery.pageCount, setting: effectiveSetting
                )
                pageHandler.sliderValue = .init(newValue)
                store.send(.syncReadingProgress(.init(newValue)))
                mangaTranslationHandler.syncQueue(currentIndex: newValue)
            }
            .onChange(of: store.forceRefreshID) { _, _ in
                mangaTranslationHandler.cancelAll()
                mangaTranslationHandler.syncQueue(currentIndex: currentPageNumber)
            }
            .onChange(of: pageHandler.sliderValue) { _, newValue in
                if !store.showsSliderPreview {
                    setPageIndex(sliderValue: newValue)
                }
            }
            .onChange(of: store.showsSliderPreview) { _, newValue in
                if !newValue {
                    setPageIndex(sliderValue: pageHandler.sliderValue)
                } else {
                    let currentIndex = Int(pageHandler.sliderValue)
                    store.send(.fetchPreviewURLs(currentIndex))
                }
                setAutoPlayPolocy(.off)
            }
            // AutoPlay
            .onChange(of: store.destination != nil) { _, isPresented in
                if isPresented {
                    setAutoPlayPolocy(.off)
                } else {
                    mangaTranslationHandler.refreshConfiguration()
                }
            }
            // Ad-page detections can land after translation already ran on a page:
            // drop those results and re-sync so the queue never works on ad pages.
            .onChange(of: store.adPageIndices) { _, newValue in
                mangaTranslationHandler.discardResults(for: newValue)
                mangaTranslationHandler.syncQueue(currentIndex: currentPageNumber)
            }
    }

    @ViewBuilder private func imageStack(index: Int) -> some View {
        let setting = effectiveSetting
        let imageStackConfig = store.state.imageContainerConfigs(
            index: index,
            setting: setting,
            isLandscape: DeviceUtil.isLandscape
        )
        let isDualPage = setting.enablesDualPageMode
            && setting.readingDirection != .vertical && DeviceUtil.isLandscape
        let dataSource = store.state.containerDataSource(setting: setting, isLandscape: DeviceUtil.isLandscape)
        let activeStackIndex = dataSource.indices.contains(page.index) ? dataSource[page.index] : nil
        HorizontalImageStack(
            index: index,
            isDualPage: isDualPage,
            isActive: index == activeStackIndex,
            backgroundColor: backgroundColor,
            config: imageStackConfig,
            imageURLs: displayImageURLs,
            originalImageURLs: displayOriginalImageURLs,
            loadingStates: store.imageURLLoadingStates,
            adPageIndices: store.adPageIndices,
            enablesLiveText: enablesLiveText,
            mangaTranslationHandler: mangaTranslationHandler,
            fetchAction: { store.send(.fetchImageURLs($0)) },
            refetchAction: { store.send(.refetchImageURLs($0)) },
            prefetchAction: { store.send(.prefetchImages($0, effectiveSetting.prefetchLimit)) },
            detectAdPageAction: { store.send(.detectAdPage($0)) },
            loadRetryAction: { store.send(.onWebImageRetry($0)) },
            loadSucceededAction: { store.send(.onWebImageSucceeded($0)) },
            loadFailedAction: { store.send(.onWebImageFailed($0)) },
            copyImageAction: { store.send(.copyImage($0)) },
            saveImageAction: { store.send(.saveImage($0)) },
            shareImageAction: { store.send(.shareImage($0)) }
        )
    }
}

// MARK: Handler methods
extension ReadingView {
    func setPageIndex(sliderValue: Float) {
        let newValue = pageHandler.mapToPager(
            index: .init(sliderValue), setting: effectiveSetting
        )
        if page.index != newValue {
            page.update(.new(index: newValue))
        }
    }
    func setAutoPlayPolocy(_ policy: AutoPlayPolicy) {
        autoPlayHandler.setPolicy(policy, updatePageAction: {
            page.update(.next)
        })
    }
}

struct ReadingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Color.clear
                .fullScreenCover(isPresented: .constant(true)) {
                    ReadingView(
                        store: .init(initialState: .init(gallery: .preview), reducer: ReadingReducer.init),
                        gid: .init(),
                        blurRadius: 0
                    )
                }
        }
    }
}
