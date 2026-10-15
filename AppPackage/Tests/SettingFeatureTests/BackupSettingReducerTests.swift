import Testing
import Foundation
import AppModels
import Sharing
import CookieClient
import FileClient
import Synchronization
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
}
