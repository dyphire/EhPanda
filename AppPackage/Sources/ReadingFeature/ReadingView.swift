import SwiftUI
import Sharing
import AppModels
import Observation
import SFSafeSymbols
import SwiftUIPager
import ComposableArchitecture
import AppTools
import AnimatedImageFeature
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
            .toast($store.scope(state: \.toast, action: \.toast))

            .animation(.linear(duration: 0.1), value: gestureHandler.offset)
            .animation(.default, value: enablesLiveText)
            .animation(.default, value: gestureHandler.scale)
            .animation(.default, value: store.showsPanel)
            .statusBar(hidden: !store.showsPanel)
            .onDisappear {
                setAutoPlayPolocy(.off)
            }
            .onAppear {
                store.send(.onAppear(gid))
            }
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
                enablesLiveText: $enablesLiveText,
                autoPlayPolicy: .init(get: { autoPlayHandler.policy }, set: { setAutoPlayPolocy($0) }),
                range: 1...Float(store.gallery.pageCount),
                previewURLs: displayPreviewURLs,
                dismissGesture: controlPanelDismissGesture,
                dismissAction: { store.send(.onPerformDismiss) },
                navigateSettingAction: { store.send(.presentReadingSetting) },
                reloadAllImagesAction: { store.send(.reloadAllWebImages) },
                retryAllFailedImagesAction: { store.send(.retryAllFailedWebImages) },
                fetchPreviewURLsAction: { store.send(.fetchPreviewURLs($0)) }
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
                }
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
            enablesLiveText: enablesLiveText,
            fetchAction: { store.send(.fetchImageURLs($0)) },
            refetchAction: { store.send(.refetchImageURLs($0)) },
            prefetchAction: { store.send(.prefetchImages($0, effectiveSetting.prefetchLimit)) },
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
