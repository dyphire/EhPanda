import Foundation
import Synchronization
import ComposableArchitecture
import Testing
import AppTools
import AppModels
import CookieClient
import UserDefaultsClient
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
}
