import Testing
import Foundation
import AppModels
import Sharing
import Synchronization
import WebDAVClient
@testable import SettingFeature
import ComposableArchitecture

// Covers the scheduled WebDAV auto-backup: the staleness guard (enabled + usable + older than a
// day), the silent-failure posture, and the lastBackupDate watermark refresh on success.
@Suite
@MainActor
struct SettingReducerAutoBackupTests {
    @Test
    func staleEnabledConfigurationUploadsTwiceAndRefreshesWatermark() async {
        let defaults = UserDefaults.inMemory
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let uploads = Mutex<[(String, Data)]>([])
            let store = TestStore(initialState: .init(), reducer: SettingReducer.init) {
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
                $0.isEnabled = true
                $0.lastBackupDate = Date().addingTimeInterval(-86400 * 2)
            }

            await store.send(.autoBackupToWebdav)
            await store.receive(\.autoBackupToWebdavDone)
            await store.finish()

            let uploaded = uploads.withLock { $0 }
            #expect(uploaded.count == 2)
            #expect(uploaded[0].0 == SettingsBackup.latestFileName)
            #expect(uploaded[1].0.hasPrefix("ehpanda-backup-"))
            // The watermark advanced well past the seeded (two-day-old) value.
            #expect(config.lastBackupDate ?? .distantPast > Date().addingTimeInterval(-3600))
        }
    }

    @Test
    func freshWatermarkSkipsUpload() async {
        let defaults = UserDefaults.inMemory
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let uploads = Mutex<[(String, Data)]>([])
            let store = TestStore(initialState: .init(), reducer: SettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.webDAVClient.upload = { _, filename, data in
                    uploads.withLock { $0.append((filename, data)) }
                    return .success(())
                }
            }

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.serverURL = "https://dav.example.com"
                $0.username = "alice"
                $0.isEnabled = true
                $0.lastBackupDate = Date()
            }

            // The guard returns `.none` — an exhaustive store fails on any unasserted effect.
            await store.send(.autoBackupToWebdav)
            #expect(uploads.withLock { $0 }.isEmpty)
        }
    }

    @Test
    func disabledFeatureSkipsUpload() async {
        let defaults = UserDefaults.inMemory
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let uploads = Mutex<[(String, Data)]>([])
            let store = TestStore(initialState: .init(), reducer: SettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.webDAVClient.upload = { _, filename, data in
                    uploads.withLock { $0.append((filename, data)) }
                    return .success(())
                }
            }

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.serverURL = "https://dav.example.com"
                $0.username = "alice"
                $0.isEnabled = false
                $0.lastBackupDate = .distantPast
            }

            await store.send(.autoBackupToWebdav)
            #expect(uploads.withLock { $0 }.isEmpty)
        }
    }

    @Test
    func incompleteConfigurationSkipsUpload() async {
        let defaults = UserDefaults.inMemory
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let uploads = Mutex<[(String, Data)]>([])
            let store = TestStore(initialState: .init(), reducer: SettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.webDAVClient.upload = { _, filename, data in
                    uploads.withLock { $0.append((filename, data)) }
                    return .success(())
                }
            }

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.isEnabled = true
                $0.lastBackupDate = .distantPast
            }

            await store.send(.autoBackupToWebdav)
            #expect(uploads.withLock { $0 }.isEmpty)
        }
    }

    @Test
    func uploadFailureStaysSilentAndKeepsWatermark() async {
        let defaults = UserDefaults.inMemory
        await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let store = TestStore(initialState: .init(), reducer: SettingReducer.init) {
                $0.defaultAppStorage = defaults
                $0.cookieClient.snapshotSessionCookies = { [] }
                $0.webDAVClient.upload = { _, _, _ in .failure(.networkingFailed) }
            }
            store.exhaustivity = .off

            @Shared(.webDAVConfiguration) var config
            $config.withLock {
                $0.serverURL = "https://dav.example.com"
                $0.username = "alice"
                $0.isEnabled = true
                $0.lastBackupDate = Date().addingTimeInterval(-86400 * 2)
            }
            let originalWatermark = config.lastBackupDate

            await store.send(.autoBackupToWebdav)
            await store.finish()

            // No `.autoBackupToWebdavDone` arrived and the watermark is untouched (compare with
            // tolerance: the stored date round-trips through JSON as a Double).
            let difference = config.lastBackupDate?
                .timeIntervalSince(originalWatermark ?? .distantPast) ?? .infinity
            #expect(abs(difference) < 1)
        }
    }
}
