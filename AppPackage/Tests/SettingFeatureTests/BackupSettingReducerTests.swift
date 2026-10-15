import Testing
import Foundation
import AppModels
import Sharing
import CookieClient
import FileClient
import Synchronization
import WebDAVClient
@testable import SettingFeature
import ComposableArchitecture

// Covers the Backup screen's export share-sheet flow, the import confirm-then-replace flow, and the
// parent interception that runs the file import (mirroring the tag-translations flow).
@Suite
@MainActor
struct BackupSettingReducerTests {
    private let exportURL = URL(filePath: "/tmp/ehpanda-backup.json")

    // MARK: Export

    @Test
    func exportButtonPresentsShareSheetOnSuccess() async {
        let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
            $0.fileClient.exportSettingsBackup = { _ in .success(exportURL) }
            $0.cookieClient.snapshotSessionCookies = { [] }
        }

        await store.send(.exportBackupButtonTapped)
        await store.receive(.exportBackupDone(.success(exportURL))) {
            $0.destination = .share(exportURL)
        }
    }

    @Test
    func exportFailureShowsErrorToast() async {
        let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
            $0.fileClient.exportSettingsBackup = { _ in .failure(.parseFailed) }
            $0.cookieClient.snapshotSessionCookies = { [] }
        }

        await store.send(.exportBackupButtonTapped)
        await store.receive(.exportBackupDone(.failure(.parseFailed))) {
            $0.toast = .error(caption: .settingsBackupFailed)
        }
    }

    // MARK: Import

    @Test
    func importButtonPresentsFileImporter() async {
        let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init)

        await store.send(.importBackupButtonTapped) {
            $0.destination = .importBackup
        }

        // Cancelling or picking flips the `isPresented` binding back to false → dismiss.
        await store.send(.destination(.dismiss)) {
            $0.destination = nil
        }
    }

    @Test
    func decodedBackupPresentsConfirmationDialog() async {
        let envelope = SettingsBackupEnvelope(exportDate: .now)
        let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init)

        await store.send(.onBackupDecoded(.success(envelope))) {
            $0.importBackupDialog = BackupSettingReducer.importConfirmationDialog(envelope: envelope)
        }
    }

    @Test
    func undecodableBackupShowsErrorToast() async {
        let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init)

        await store.send(.onBackupDecoded(.failure(.parseFailed))) {
            $0.toast = .error(caption: .settingsBackupFailed)
        }
    }

    @Test
    func confirmImportReplacesSharedKeysAndRestoresCookies() async {
        let defaults = UserDefaults.inMemory
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let restored = Mutex<[ExportedCookie]>([])
            let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.cookieClient.snapshotSessionCookies = { [] }
                $0.cookieClient.restoreSessionCookies = { cookies in
                    restored.withLock { $0 = cookies }
                }
            }

            let history = GalleryHistoryEntry(gid: "1", token: "a", lastOpenDate: .now)
            let cookies = [ExportedCookie(name: "ipb_member_id", value: "42", domain: "e-hentai.org")]
            let envelope = SettingsBackupEnvelope(
                exportDate: .now,
                setting: Setting(galleryHost: .exhentai, displaysJapaneseTitle: false),
                searchFilter: Filter(doujinshi: true),
                globalFilter: Filter(manga: true),
                watchedFilter: Filter(western: true),
                quickSearchWords: [QuickSearchWord(name: "preset", content: "f:abc")],
                historyKeywords: ["keyword"],
                galleryHistory: [history],
                user: User(displayName: "Tester"),
                cookies: cookies
            )

            await store.send(.onBackupDecoded(.success(envelope))) {
                $0.importBackupDialog = BackupSettingReducer.importConfirmationDialog(envelope: envelope)
            }
            // `ConfirmationDialogState` is ephemeral: TCA dismisses it after the presented action.
            // The expected closure replays the reducer's tracked `@Shared` write-throughs.
            await store.send(.importBackupDialog(.presented(.confirmImport(envelope)))) {
                $0.importBackupDialog = nil
                $0.restoreSharedMembers(from: envelope)
                $0.toast = .success(caption: .settingsImportSucceeded)
            }

            // Assert through INDEPENDENT `@Shared` handles (see `SettingWriteThroughTests`), not
            // `store.state`, so a working-copy regression can't pass silently.
            @Shared(.setting) var persistedSetting
            @Shared(.searchFilter) var persistedSearchFilter
            @Shared(.globalFilter) var persistedGlobalFilter
            @Shared(.watchedFilter) var persistedWatchedFilter
            @Shared(.quickSearchWords) var persistedQuickSearchWords
            @Shared(.historyKeywords) var persistedHistoryKeywords
            @Shared(.galleryHistory) var persistedGalleryHistory
            @Shared(.user) var persistedUser

            #expect(persistedSetting.galleryHost == .exhentai)
            #expect(persistedSetting.displaysJapaneseTitle == false)
            #expect(persistedSearchFilter.doujinshi)
            #expect(persistedGlobalFilter.manga)
            #expect(persistedWatchedFilter.western)
            #expect(persistedQuickSearchWords.map(\.name) == ["preset"])
            #expect(persistedHistoryKeywords == ["keyword"])
            #expect(persistedGalleryHistory.map(\.gid) == ["1"])
            #expect(persistedUser.displayName == "Tester")
            #expect(restored.withLock { $0 } == cookies)
        }
    }

    @Test
    func confirmImportKeepsCurrentValuesForAbsentMembers() async {
        let defaults = UserDefaults.inMemory
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            @Shared(.setting) var setting
            $setting.withLock { $0.galleryHost = .exhentai }

            let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
                $0.defaultAppStorage = defaults
            }

            // An old backup file carrying only the settings blob: the filter slots it lacks must
            // keep their current values instead of being blanked.
            let envelope = SettingsBackupEnvelope(exportDate: .now, setting: Setting())
            await store.send(.onBackupDecoded(.success(envelope))) {
                $0.importBackupDialog = BackupSettingReducer.importConfirmationDialog(envelope: envelope)
            }
            // `ConfirmationDialogState` is ephemeral: TCA dismisses it after the presented action.
            // The expected closure replays the reducer's tracked `@Shared` write-throughs.
            await store.send(.importBackupDialog(.presented(.confirmImport(envelope)))) {
                $0.importBackupDialog = nil
                $0.restoreSharedMembers(from: envelope)
                $0.toast = .success(caption: .settingsImportSucceeded)
            }

            @Shared(.setting) var persistedSetting
            @Shared(.globalFilter) var persistedGlobalFilter
            #expect(persistedSetting.galleryHost == .ehentai)
            #expect(persistedGlobalFilter == Filter())
        }
    }

    // MARK: Parent interception

    @Test
    func backupFilePickedImportsAndFeedsBackDecodedEnvelope() async throws {
        let envelope = SettingsBackupEnvelope(exportDate: .now, setting: Setting(galleryHost: .exhentai))
        let store = TestStore(initialState: .init(), reducer: SettingReducer.init) {
            $0.fileClient.importSettingsBackup = { _ in .success(envelope) }
            $0.defaultAppStorage = UserDefaults.inMemory
        }
        store.exhaustivity = .off

        await store.send(.settingRowTapped(.backup))
        let id = try #require(store.state.path.ids.last)
        let url = URL(filePath: "/tmp/backup.json")
        await store.send(.path(.element(id: id, action: .backup(.delegate(.importFilePicked(url))))))
        // `finish()` waits for the parent's import effect; the action it feeds back into the child
        // lands in the store's received-action buffer (exhaustivity is off), and skipping applies
        // the buffered state — `finish()` alone would leave it unapplied.
        await store.finish()
        await store.skipReceivedActions(strict: false)

        // The parent's effect fed the decoded envelope back into the child, which presented its
        // own confirmation dialog.
        guard case .backup(let child) = store.state.path.last else {
            Issue.record("Expected .backup on top of the Setting stack")
            return
        }
        #expect(child.importBackupDialog != nil)
    }

    // MARK: WebDAV

    @Test
    func webDAVBackupUploadsLatestAndTimestampedCopies() async throws {
        let defaults = UserDefaults.inMemory
        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let uploads = Mutex<[(String, Data)]>([])
            let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.cookieClient.snapshotSessionCookies = { [] }
                $0.webDAVClient.upload = { _, filename, data in
                    uploads.withLock { $0.append((filename, data)) }
                    return .success(())
                }
            }
            store.exhaustivity = .off

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.serverURL = "https://dav.example.com"
                $0.username = "alice"
            }
            #expect(config.lastBackupDate == nil)

            await store.send(.webDAVBackupButtonTapped)
            await store.receive(.webDAVBackupDone(nil))
            await store.finish()

            #expect(store.state.webDAVBackingUp == false)
            #expect(store.state.toast == .success(caption: .webdavBackupSucceeded))
            let uploaded = uploads.withLock { $0 }
            #expect(uploaded.count == 2)
            #expect(uploaded[0].0 == SettingsBackup.latestFileName)
            #expect(uploaded[1].0.hasPrefix("ehpanda-backup-"))
            #expect(uploaded[1].0.hasSuffix(".json"))
            #expect(uploaded[0].1 == uploaded[1].1)
            // Success refreshes the staleness watermark.
            #expect(config.lastBackupDate != nil)
        }
    }

    @Test
    func webDAVBackupFailureLeavesWatermarkUntouched() async throws {
        let defaults = UserDefaults.inMemory
        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.cookieClient.snapshotSessionCookies = { [] }
                $0.webDAVClient.upload = { _, _, _ in .failure(.authenticationRequired) }
            }
            store.exhaustivity = .off

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.serverURL = "https://dav.example.com"
                $0.username = "alice"
            }

            await store.send(.webDAVBackupButtonTapped)
            await store.receive(.webDAVBackupDone(.authenticationRequired))
            await store.finish()

            #expect(store.state.webDAVBackingUp == false)
            #expect(store.state.toast != nil)
            #expect(config.lastBackupDate == nil)
        }
    }

    @Test
    func webDAVRestoreFiltersAndSortsBackupsThenDecodesPick() async throws {
        let defaults = UserDefaults.inMemory
        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let envelope = SettingsBackupEnvelope(
                exportDate: .now, setting: Setting(galleryHost: .exhentai)
            )
            // The downloaded bytes must be a valid envelope, but the decoded value can't be
            // compared wholesale: `Color` doesn't round-trip identically (its decoded provider
            // is a resolved HDR value containing NaN), so the assertions below check the flow
            // semantics instead of envelope equality.
            let encoded = try #require(SettingsBackup.encode(envelope))
            let older = Date(timeIntervalSinceNow: -3600 * 30)
            let files = [
                WebDAVFile(
                    name: "ehpanda-backup-old.json",
                    path: "/ehpanda/ehpanda-backup-old.json", size: 10, modifiedDate: older
                ),
                WebDAVFile(
                    name: "ehpanda-backup-latest.json",
                    path: "/ehpanda/ehpanda-backup-latest.json", size: 10, modifiedDate: .now
                ),
                WebDAVFile(
                    name: "unrelated.txt", path: "/ehpanda/unrelated.txt", size: 10, modifiedDate: .now
                )
            ]
            let downloadedName = Mutex<String?>(nil)
            let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.webDAVClient.list = { _ in .success(files) }
                $0.webDAVClient.download = { _, filename in
                    downloadedName.withLock { $0 = filename }
                    return .success(encoded)
                }
            }
            store.exhaustivity = .off

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.serverURL = "https://dav.example.com"
                $0.username = "alice"
            }

            await store.send(.webDAVRestoreButtonTapped)
            await store.receive(.webDAVListDone(.success(files))) {
                $0.webDAVListing = false
                // Only backup JSON files, newest first.
                $0.destination = .restoreFileList([files[1], files[0]])
            }

            await store.send(.webDAVFilePicked(files[1])) {
                $0.destination = nil
            }
            await store.skipReceivedActions(strict: false)
            // The pick downloaded and decoded into the shared confirmation dialog.
            #expect(store.state.importBackupDialog != nil)
            #expect(downloadedName.withLock { $0 } == "ehpanda-backup-latest.json")
        }
    }

    @Test
    func webDAVDownloadFailureShowsToastWithoutDialog() async throws {
        let defaults = UserDefaults.inMemory
        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.webDAVClient.download = { _, _ in .failure(.notFound) }
            }

            await store.send(.webDAVDownloadDone(.failure(.notFound))) {
                $0.toast = .error(caption: AppError.notFound.localizedDescription)
            }
            #expect(store.state.importBackupDialog == nil)
        }
    }

    @Test
    func webDAVTestConnectionTogglesLoadingAndToastsResult() async throws {
        let defaults = UserDefaults.inMemory
        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.webDAVClient.testConnection = { _ in .success(()) }
            }

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.serverURL = "https://dav.example.com"
                $0.username = "alice"
            }

            await store.send(.webDAVTestConnectionButtonTapped) {
                $0.webDAVTesting = true
            }
            await store.receive(.webDAVTestConnectionDone(nil)) {
                $0.webDAVTesting = false
                $0.toast = .success(caption: .webdavConnectionSucceeded)
            }
        }
    }

    @Test
    func webDAVOperationsRequireUsableConfiguration() async {
        let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init)

        // Empty configuration: every operation guards out with no effect.
        await store.send(.webDAVTestConnectionButtonTapped)
        await store.send(.webDAVBackupButtonTapped)
        await store.send(.webDAVRestoreButtonTapped)

        #expect(store.state.webDAVTesting == false)
        #expect(store.state.webDAVBackingUp == false)
        #expect(store.state.webDAVListing == false)
    }

    @Test
    func webDAVAutoBackupRejectedShowsToast() async {
        let store = TestStore(initialState: .init(), reducer: BackupSettingReducer.init)

        await store.send(.webDAVAutoBackupRejected) {
            $0.toast = .error(caption: .webdavConfigIncomplete)
        }
    }
}
