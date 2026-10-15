import Foundation
import AppModels
import AppTools
import Resources
import Sharing
import AppComponents
import CookieClient
import FileClient
import MangaTranslationFeature
import ComposableArchitecture

@Reducer
public struct BackupSettingReducer: Sendable {
    @Reducer
    public enum Destination {
        // Drives the native `.fileImporter` presentation for importing a backup file.
        @ReducerCaseIgnored
        case importBackup
        // Holds the exported file URL while the `ActivityView` share sheet presents it.
        @ReducerCaseIgnored
        case share(URL)
    }

    public enum Dialog: Equatable, Sendable {
        case confirmImport(SettingsBackupEnvelope)
    }

    // Relays the picked file to `SettingReducer`, which runs the import effect (it owns the
    // `fileClient` dependency) and feeds the decoded envelope back through `onBackupDecoded` —
    // mirroring the tag-translations import flow.
    public enum Delegate: Equatable, Sendable {
        case importFilePicked(URL)
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        @Presents public var destination: Destination.State?
        @Presents public var importBackupDialog: ConfirmationDialogState<Dialog>?
        @Presents public var toast: AppAlertState<Never>?

        // Every persisted model the backup covers, read through their own `@Shared` handles;
        // there is no working copy (see `SettingReducer.State`).
        @Shared(.setting) public var setting: Setting
        @Shared(.user) public var user: User
        @Shared(.searchFilter) public var searchFilter: Filter
        @Shared(.globalFilter) public var globalFilter: Filter
        @Shared(.watchedFilter) public var watchedFilter: Filter
        @Shared(.quickSearchWords) public var quickSearchWords: [QuickSearchWord]
        @Shared(.historyKeywords) public var historyKeywords: [String]
        @Shared(.galleryHistory) public var galleryHistory: [GalleryHistoryEntry]
        @Shared(.mangaTranslationPreferences) public var mangaTranslationPreferences: MangaTranslationPreferences
        @Shared(.mangaTranslationProviders) public var mangaTranslationProviders: [MangaProviderConfig]
        @Shared(.mangaModelLibrary) public var mangaModelLibrary: ModelLibraryConfiguration

        public init() {}
    }

    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case destination(PresentationAction<Destination.Action>)
        case importBackupDialog(PresentationAction<Dialog>)
        case toast(PresentationAction<Never>)
        case delegate(Delegate)

        case exportBackupButtonTapped
        case exportBackupDone(Result<URL, AppError>)
        case importBackupButtonTapped
        case onBackupDecoded(Result<SettingsBackupEnvelope, AppError>)
    }

    @Dependency(\.fileClient) private var fileClient
    @Dependency(\.cookieClient) private var cookieClient

    public init() {}

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .destination:
                return .none

            case .toast:
                return .none

            case .delegate:
                return .none

            // Assemble the envelope synchronously from the current shared values (a pure snapshot),
            // then hand the bytes work to `fileClient`. `nil` JSON payloads are simply omitted.
            case .exportBackupButtonTapped:
                let envelope = SettingsBackupEnvelope(
                    exportDate: Date(),
                    setting: state.setting,
                    searchFilter: state.searchFilter,
                    globalFilter: state.globalFilter,
                    watchedFilter: state.watchedFilter,
                    quickSearchWords: state.quickSearchWords,
                    historyKeywords: state.historyKeywords,
                    galleryHistory: state.galleryHistory,
                    user: state.user,
                    cookies: cookieClient.snapshotSessionCookies(),
                    mangaTranslationPreferences: JSONValue(encoding: state.mangaTranslationPreferences),
                    mangaTranslationProviders: JSONValue(encoding: state.mangaTranslationProviders),
                    mangaModelLibrary: JSONValue(encoding: state.mangaModelLibrary)
                )
                return .run { send in
                    await send(.exportBackupDone(await fileClient.exportSettingsBackup(envelope)))
                }

            case .exportBackupDone(.success(let url)):
                state.destination = .share(url)
                return .none

            case .exportBackupDone(.failure):
                state.toast = .error(caption: .settingsBackupFailed)
                return .none

            case .importBackupButtonTapped:
                state.destination = .importBackup
                return .none

            // The decoded envelope is shown for confirmation before anything is overwritten.
            case .onBackupDecoded(.success(let envelope)):
                let formatter = DateFormatter()
                formatter.dateFormat = Defaults.DateFormat.publish
                let dateString = formatter.string(from: envelope.exportDate)
                state.importBackupDialog = ConfirmationDialogState(titleVisibility: .hidden) {
                    TextState(localized: .importBackup)
                } actions: {
                    ButtonState(role: .destructive, action: .confirmImport(envelope)) {
                        TextState(localized: .importBackup)
                    }
                    ButtonState(role: .cancel) {
                        TextState(localized: .RLocalizable.cancel)
                    }
                } message: {
                    TextState(localized: .importBackupConfirmation(dateString))
                }
                return .none

            case .onBackupDecoded(.failure):
                state.toast = .error(caption: .settingsBackupFailed)
                return .none

            // Whole-package replace: each present member overwrites its `@Shared` key (absent
            // members keep the current value), then the model's own invariants re-apply through
            // `didSet`. Cookies restore through `cookieClient`.
            case .importBackupDialog(.presented(.confirmImport(let envelope))):
                if let setting = envelope.setting {
                    state.$setting.withLock { $0 = setting }
                }
                if let searchFilter = envelope.searchFilter {
                    state.$searchFilter.withLock { $0 = searchFilter }
                }
                if let globalFilter = envelope.globalFilter {
                    state.$globalFilter.withLock { $0 = globalFilter }
                }
                if let watchedFilter = envelope.watchedFilter {
                    state.$watchedFilter.withLock { $0 = watchedFilter }
                }
                if let quickSearchWords = envelope.quickSearchWords {
                    state.$quickSearchWords.withLock { $0 = quickSearchWords }
                }
                if let historyKeywords = envelope.historyKeywords {
                    state.$historyKeywords.withLock { $0 = historyKeywords }
                }
                if let galleryHistory = envelope.galleryHistory {
                    state.$galleryHistory.withLock { $0 = galleryHistory }
                }
                if let user = envelope.user {
                    state.$user.withLock { $0 = user }
                }
                if let cookies = envelope.cookies {
                    cookieClient.restoreSessionCookies(cookies)
                }
                if let preferences = envelope.mangaTranslationPreferences?
                    .decoded(as: MangaTranslationPreferences.self) {
                    state.$mangaTranslationPreferences.withLock { $0 = preferences }
                }
                if let providers = envelope.mangaTranslationProviders?
                    .decoded(as: [MangaProviderConfig].self) {
                    state.$mangaTranslationProviders.withLock { $0 = providers }
                }
                if let modelLibrary = envelope.mangaModelLibrary?
                    .decoded(as: ModelLibraryConfiguration.self) {
                    state.$mangaModelLibrary.withLock { $0 = modelLibrary }
                }
                state.toast = .success(caption: .settingsImportSucceeded)
                return .none

            case .importBackupDialog:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .ifLet(\.$importBackupDialog, action: \.importBackupDialog)
        .ifLet(\.$toast, action: \.toast)
    }
}

extension BackupSettingReducer.Destination.State: Equatable, Sendable {}
extension BackupSettingReducer.Destination.Action: Equatable, Sendable {}
