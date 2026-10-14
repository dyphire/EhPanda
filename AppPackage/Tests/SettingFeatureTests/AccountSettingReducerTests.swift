import Foundation
import Synchronization
import ComposableArchitecture
import Testing
import AppTools
import AppModels
import CookieClient
import UserDefaultsClient
@testable import ClipboardClient
@testable import NetworkingFeature
@testable import SettingFeature

@MainActor
struct AccountSettingReducerTests {
    // The gallery-host picker writes into `@Shared(.setting)`; the reducer mirrors the choice into
    // UserDefaults (a non-capturable fire-and-forget client), so this pins that the wiring is handled
    // and runs to completion.
    @Test
    func galleryHostChangedRunsToCompletion() async {
        let store = TestStore(initialState: .init(), reducer: AccountSettingReducer.init) {
            $0.userDefaultsClient = .noop
        }
        await store.send(.galleryHostChanged(.exhentai))
        await store.finish()
    }

    @Test
    func logoutClearsCookiesBeforeReloadingState() async {
        let cookieClient = CookieClient.testing(
            memberID: "4172984",
            passHash: "pass-hash",
            igneous: "igneous-token"
        )
        let store = TestStore(initialState: .init(), reducer: AccountSettingReducer.init) {
            $0.cookieClient = cookieClient
            $0.cookieRefreshClient = .noop
            $0.userDefaultsClient = .noop
        }

        await store.send(.onLogoutConfirmButtonTapped)
        await store.receive(\.loadCookies)

        #expect(cookieClient.didLogin == false)
        #expect(store.state.ehCookiesState.memberID.value.rawValue.isEmpty)
        #expect(store.state.exCookiesState.igneous.value.rawValue.isEmpty)
    }

    @Test
    func submittedExCookieEditRefreshesIgneousOnce() async {
        let refreshCalls = Mutex(0)
        let cookieClient = CookieClient.testing(memberID: "4172984", passHash: "pass-hash")
        let refreshClient = CookieRefreshClient(
            revision: { 0 },
            refresh: {
                refreshCalls.withLock { $0 += 1 }
                return true
            },
            refreshIfNeeded: { _ in true }
        )
        let store = TestStore(initialState: .init(), reducer: AccountSettingReducer.init) {
            $0.cookieClient = cookieClient
            $0.cookieRefreshClient = refreshClient
            $0.userDefaultsClient = .noop
        }

        await store.send(.cookiesSubmitted(.exhentai))
        await store.receive(\.loadCookies)
        #expect(refreshCalls.withLock { $0 } == 1)
    }

    @Test
    func submittedEhentaiCookieEditDoesNotRefreshIgneous() async {
        let refreshCalls = Mutex(0)
        let store = TestStore(initialState: .init(), reducer: AccountSettingReducer.init) {
            $0.cookieClient = .testing(memberID: "4172984", passHash: "pass-hash")
            $0.cookieRefreshClient = CookieRefreshClient(
                revision: { 0 },
                refresh: {
                    refreshCalls.withLock { $0 += 1 }
                    return true
                },
                refreshIfNeeded: { _ in true }
            )
            $0.userDefaultsClient = .noop
        }

        await store.send(.cookiesSubmitted(.ehentai))
        await store.receive(\.loadCookies)
        #expect(refreshCalls.withLock { $0 } == 0)
    }

    @Test
    func importCookiesFromClipboardParsesAndStoresCookieString() async {
        let cookieClient = CookieClient.testing()
        let clipboardClient = ClipboardClient(
            url: { nil },
            text: {
                "ipb_member_id=4172984; ipb_pass_hash=pass-hash; igneous=igneous-token"
            },
            changeCount: { 0 },
            saveText: { _ in },
            saveImage: { _, _ in },
            saveImageData: { _ in false }
        )
        let store = TestStore(initialState: .init(), reducer: AccountSettingReducer.init) {
            $0.cookieClient = cookieClient
            $0.cookieRefreshClient = .noop
            $0.clipboardClient = clipboardClient
            $0.userDefaultsClient = .noop
        }

        await store.send(.importCookiesFromClipboard)
        await store.receive(\.importCookiesFromClipboardDone, true)
        await store.receive(\.loadCookies)

        #expect(cookieClient.getCookie(Defaults.URL.ehentai, Defaults.Cookie.ipbMemberId).rawValue == "4172984")
        #expect(cookieClient.getCookie(Defaults.URL.exhentai, Defaults.Cookie.igneous).rawValue == "igneous-token")
        #expect(store.state.toast != nil)
    }

    @Test
    func invalidClipboardCookieStringShowsFailureToast() async {
        let store = TestStore(initialState: .init(), reducer: AccountSettingReducer.init) {
            $0.cookieClient = .testing()
            $0.cookieRefreshClient = .noop
            $0.clipboardClient = ClipboardClient(
                url: { nil },
                text: { "foo=bar; unrelated=value" },
                changeCount: { 0 },
                saveText: { _ in },
                saveImage: { _, _ in },
                saveImageData: { _ in false }
            )
            $0.userDefaultsClient = .noop
        }

        await store.send(.importCookiesFromClipboard)
        await store.receive(\.importCookiesFromClipboardDone, false)
        #expect(store.state.toast != nil)
    }
}
