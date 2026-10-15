import Foundation
import AppModels
import AppTools
import Resources
import Sharing
import AppComponents
import CookieClient
import FileClient
import MangaTranslationFeature
import WebDAVClient
import ComposableArchitecture

@Reducer
public struct BackupSettingReducer: Sendable {
    @Reducer
    public enum Destination {
        // Drives the document-picker presentation for importing a backup file.
        @ReducerCaseIgnored
        case importBackup
        // Holds the exported file URL while the `ActivityView` share sheet presents it.
        @ReducerCaseIgnored
        case share(URL)
        // Holds the WebDAV backup files while the restore list presents them.
        @ReducerCaseIgnored
        case restoreFileList([WebDAVFile])
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
        @Shared(.webDAVConfiguration) public var webDAVConfig: WebDAVConfiguration

        // Loading flags for the three WebDAV operations — each drives a ProgressView on its
        // button row and disables the other buttons while active.
        public var webDAVTesting = false
        public var webDAVBackingUp = false
        public var webDAVListing = false

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

        case webDAVAutoBackupRejected
        case webDAVTestConnectionButtonTapped
        // `AppError?` rather than `Result<Void, AppError>`: `Void` is not `Equatable`, which the
        // `Equatable` action synthesis requires. `nil` means success.
        case webDAVTestConnectionDone(AppError?)
        case webDAVBackupButtonTapped
        case webDAVBackupDone(AppError?)
        case webDAVRestoreButtonTapped
        case webDAVListDone(Result<[WebDAVFile], AppError>)
        case webDAVFilePicked(WebDAVFile)
        case webDAVDownloadDone(Result<Data, AppError>)
    }

    @Dependency(\.fileClient) private var fileClient
    @Dependency(\.cookieClient) private var cookieClient
    @Dependency(\.webDAVClient) private var webDAVClient

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

            // Assemble the envelope synchronously from the current shared values (a pure
            // snapshot via `SettingsBackup`), then hand the bytes work to `fileClient`.
            case .exportBackupButtonTapped:
                let envelope = SettingsBackup.envelope(
                    exportDate: Date(),
                    cookies: cookieClient.snapshotSessionCookies()
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
                state.importBackupDialog = Self.importConfirmationDialog(envelope: envelope)
                return .none

            case .onBackupDecoded(.failure):
                state.toast = .error(caption: .settingsBackupFailed)
                return .none

            // The toggle was flipped on while the configuration is incomplete; the view has
            // already reverted it, so only explain why.
            case .webDAVAutoBackupRejected:
                state.toast = .error(caption: .webdavConfigIncomplete)
                return .none

            case .webDAVTestConnectionButtonTapped:
                guard state.webDAVConfig.isUsable, !state.webDAVTesting else { return .none }
                state.webDAVTesting = true
                let config = state.webDAVConfig
                return .run { send in
                    switch await webDAVClient.testConnection(config) {
                    case .success:
                        await send(.webDAVTestConnectionDone(nil))
                    case .failure(let error):
                        await send(.webDAVTestConnectionDone(error))
                    }
                }

            case .webDAVTestConnectionDone(let error):
                state.webDAVTesting = false
                if let error {
                    state.toast = .error(caption: error.localizedDescription)
                } else {
                    state.toast = .success(caption: .webdavConnectionSucceeded)
                }
                return .none

            // Uploads the current snapshot twice: `latest` (overwrite, what restore lists
            // first) and a timestamped copy (immutable history).
            case .webDAVBackupButtonTapped:
                guard state.webDAVConfig.isUsable, !state.webDAVBackingUp else { return .none }
                state.webDAVBackingUp = true
                let config = state.webDAVConfig
                let envelope = SettingsBackup.envelope(
                    exportDate: Date(),
                    cookies: cookieClient.snapshotSessionCookies()
                )
                return .run { send in
                    guard let data = SettingsBackup.encode(envelope) else {
                        await send(.webDAVBackupDone(.fileOperationFailed("encode")))
                        return
                    }
                    let timestamped = SettingsBackup.timestampedFileName(exportDate: envelope.exportDate)
                    switch await webDAVClient.upload(config, SettingsBackup.latestFileName, data) {
                    case .success:
                        break
                    case .failure(let error):
                        await send(.webDAVBackupDone(error))
                        return
                    }
                    switch await webDAVClient.upload(config, timestamped, data) {
                    case .success:
                        await send(.webDAVBackupDone(nil))
                    case .failure(let error):
                        await send(.webDAVBackupDone(error))
                    }
                }

            case .webDAVBackupDone(let error):
                state.webDAVBackingUp = false
                if let error {
                    state.toast = .error(caption: error.localizedDescription)
                } else {
                    state.$webDAVConfig.withLock { $0.lastBackupDate = Date() }
                    state.toast = .success(caption: .webdavBackupSucceeded)
                }
                return .none

            case .webDAVRestoreButtonTapped:
                guard state.webDAVConfig.isUsable, !state.webDAVListing else { return .none }
                state.webDAVListing = true
                let config = state.webDAVConfig
                return .run { send in
                    await send(.webDAVListDone(await webDAVClient.list(config)))
                }

            case .webDAVListDone(.success(let files)):
                state.webDAVListing = false
                let backups = files
                    .filter { $0.name.hasPrefix("ehpanda-backup-") && $0.name.hasSuffix(".json") }
                    .sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
                state.destination = .restoreFileList(backups)
                return .none

            case .webDAVListDone(.failure(let error)):
                state.webDAVListing = false
                state.toast = .error(caption: error.localizedDescription)
                return .none

            // Download the picked file and feed it through the SAME decode → confirm → apply
            // pipeline as a local import.
            case .webDAVFilePicked(let file):
                state.destination = nil
                let config = state.webDAVConfig
                return .run { send in
                    await send(.webDAVDownloadDone(await webDAVClient.download(config, file.name)))
                }

            case .webDAVDownloadDone(.success(let data)):
                guard let envelope = try? JSONDecoder().decode(
                    SettingsBackupEnvelope.self, from: data
                ), envelope.formatVersion <= SettingsBackupEnvelope.currentFormatVersion else {
                    state.toast = .error(caption: .settingsBackupFailed)
                    return .none
                }
                return .send(.onBackupDecoded(.success(envelope)))

            case .webDAVDownloadDone(.failure(let error)):
                state.toast = .error(caption: error.localizedDescription)
                return .none

            // Whole-package replace, then the model's own invariants re-apply through `didSet`.
            // Cookies restore through `cookieClient`.
            case .importBackupDialog(.presented(.confirmImport(let envelope))):
                state.restoreSharedMembers(from: envelope)
                if let cookies = envelope.cookies {
                    cookieClient.restoreSessionCookies(cookies)
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

extension BackupSettingReducer.State {
    /// Whole-package replace: each present member overwrites its `@Shared` key (absent members
    /// keep the current value), then the model's own invariants re-apply through `didSet`.
    /// Shared with the reducer's tests: TestStore requires the expected-state closure to replay
    /// every tracked `@Shared` write, so both sides must perform the exact same mutations.
    mutating func restoreSharedMembers(from envelope: SettingsBackupEnvelope) {
        if let setting = envelope.setting {
            $setting.withLock { $0 = setting }
        }
        if let searchFilter = envelope.searchFilter {
            $searchFilter.withLock { $0 = searchFilter }
        }
        if let globalFilter = envelope.globalFilter {
            $globalFilter.withLock { $0 = globalFilter }
        }
        if let watchedFilter = envelope.watchedFilter {
            $watchedFilter.withLock { $0 = watchedFilter }
        }
        if let quickSearchWords = envelope.quickSearchWords {
            $quickSearchWords.withLock { $0 = quickSearchWords }
        }
        if let historyKeywords = envelope.historyKeywords {
            $historyKeywords.withLock { $0 = historyKeywords }
        }
        if let galleryHistory = envelope.galleryHistory {
            $galleryHistory.withLock { $0 = galleryHistory }
        }
        if let user = envelope.user {
            $user.withLock { $0 = user }
        }
        if let preferences = envelope.mangaTranslationPreferences?
            .decoded(as: MangaTranslationPreferences.self) {
            $mangaTranslationPreferences.withLock { $0 = preferences }
        }
        if let providers = envelope.mangaTranslationProviders?
            .decoded(as: [MangaProviderConfig].self) {
            $mangaTranslationProviders.withLock { $0 = providers }
        }
        if let modelLibrary = envelope.mangaModelLibrary?
            .decoded(as: ModelLibraryConfiguration.self) {
            $mangaModelLibrary.withLock { $0 = modelLibrary }
        }
    }
}

extension BackupSettingReducer {
    /// Builds the import confirmation dialog for a decoded envelope. Shared with the reducer's
    /// tests: the message embeds the formatted export date, which tests can't reconstruct by hand
    /// (and the date formatting must match exactly for state equality).
    static func importConfirmationDialog(
        envelope: SettingsBackupEnvelope
    ) -> ConfirmationDialogState<Dialog> {
        let formatter = DateFormatter()
        formatter.dateFormat = Defaults.DateFormat.publish
        let dateString = formatter.string(from: envelope.exportDate)
        return ConfirmationDialogState(titleVisibility: .hidden) {
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
    }
}

extension BackupSettingReducer.Destination.State: Equatable, Sendable {}
extension BackupSettingReducer.Destination.Action: Equatable, Sendable {}
