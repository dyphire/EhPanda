import Foundation
import Testing
import AppTools
import AppModels
import CookieClient
import HapticsClient
import ComposableArchitecture
@testable import SettingFeature

@MainActor
struct LoginReducerTests {
    @Test
    func importedCredentialsCompleteLoginOnlyWhenAuthenticated() async {
        let store = TestStore(initialState: .init(), reducer: LoginReducer.init) {
            $0.cookieClient = .testing(memberID: "4172984", passHash: "pass-hash")
            $0.hapticsClient = .noop
        }

        // The initial `loginState` is `.idle`; a successful `.loginDone` sets it back to `.idle`,
        // so the receive asserts no state change — the success path is pinned by the fact that a
        // `.failure` result (see the test below) would have changed state and failed this receive.
        await store.send(.loginCookiesImported(true))
        await store.receive(\.loginDone)
    }

    @Test
    func missingImportedCredentialsFailLogin() async {
        let store = TestStore(initialState: .init(), reducer: LoginReducer.init) {
            $0.cookieClient = .testing()
            $0.hapticsClient = .noop
        }

        await store.send(.loginCookiesImported(false))
        await store.receive(\.loginDone) {
            $0.loginState = .failed(.unknown)
        }
    }

    @Test
    func webViewCookiesImportBeforeLoginCompletion() async throws {
        let cookieClient = CookieClient.testing()
        let store = TestStore(initialState: .init(), reducer: LoginReducer.init) {
            $0.cookieClient = cookieClient
            $0.hapticsClient = .noop
        }
        let memberCookie = try #require(HTTPCookie(properties: [
            .domain: ".e-hentai.org",
            .path: "/",
            .name: Defaults.Cookie.ipbMemberId,
            .value: "4172984"
        ]))
        let passCookie = try #require(HTTPCookie(properties: [
            .domain: ".e-hentai.org",
            .path: "/",
            .name: Defaults.Cookie.ipbPassHash,
            .value: "pass-hash"
        ]))
        let importedCookies = [memberCookie, passCookie].map(LoginReducer.ImportedCookie.init(cookie:))

        await store.send(.webViewCookiesReceived(importedCookies))
        await store.receive(\.loginCookiesImported, true)
        // A successful `.loginDone` leaves the initial `.idle` state untouched.
        await store.receive(\.loginDone)
        #expect(cookieClient.didLogin)
    }
}
