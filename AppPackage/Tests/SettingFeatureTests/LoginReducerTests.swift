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

        await store.send(.loginCookiesImported(true))
        await store.receive(\.loginDone) {
            $0.loginState = .idle
        }
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
        await store.receive(\.loginDone) {
            $0.loginState = .idle
        }
        #expect(cookieClient.didLogin)
    }
}
