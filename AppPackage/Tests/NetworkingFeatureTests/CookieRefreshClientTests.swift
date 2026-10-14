import Foundation
import Synchronization
import Testing
import AppTools
import AppModels
import CookieClient
@testable import NetworkingFeature

struct CookieRefreshClientTests {
    @Test
    func refreshImportsValidIgneousAcrossExHosts() async throws {
        let cookieClient = CookieClient.testing(memberID: "4172984", passHash: "pass-hash")
        cookieClient.clearAll()
        defer { cookieClient.clearAll() }
        let refreshClient = CookieRefreshClient.live(cookieClient: cookieClient) { request in
            #expect(request.url == Defaults.URL.exUConfig)
            let response = try #require(HTTPURLResponse(
                url: Defaults.URL.exUConfig,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie": "\(Defaults.Cookie.igneous)=refreshed-token; path=/; max-age=3600"
                ]
            ))
            return (Data("uconfig".utf8), response)
        }

        #expect(await refreshClient.refresh())
        #expect(cookieClient.getCookie(Defaults.URL.exhentai, Defaults.Cookie.igneous).rawValue == "refreshed-token")
        #expect(cookieClient.getCookie(Defaults.URL.sexhentai, Defaults.Cookie.igneous).rawValue == "refreshed-token")
        #expect(cookieClient.hasValidExAuthentication)
    }

    @Test
    func refreshSkipsNetworkWithoutExCredentials() async {
        let cookieClient = CookieClient.testing()
        cookieClient.clearAll()
        defer { cookieClient.clearAll() }
        let providerCalls = Mutex(0)
        let refreshClient = CookieRefreshClient.live(cookieClient: cookieClient) { _ in
            providerCalls.withLock { $0 += 1 }
            throw URLError(.badServerResponse)
        }

        #expect(await refreshClient.refresh() == false)
        #expect(providerCalls.withLock { $0 } == 0)
    }

    @Test
    func refreshRejectsAuthenticationWall() async throws {
        let cookieClient = CookieClient.testing(memberID: "4172984", passHash: "pass-hash")
        cookieClient.clearAll()
        defer { cookieClient.clearAll() }
        let refreshClient = CookieRefreshClient.live(cookieClient: cookieClient) { _ in
            let response = try #require(HTTPURLResponse(
                url: Defaults.URL.exUConfig,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data("<html><body><img src=\"kokomade.jpg\"></body></html>".utf8), response)
        }

        #expect(await refreshClient.refresh() == false)
        #expect(cookieClient.getCookie(Defaults.URL.exhentai, Defaults.Cookie.igneous).rawValue.isEmpty)
    }

    @Test
    func concurrentRefreshUsesSingleFlightAndRevisionSkipsDuplicate() async throws {
        let cookieClient = CookieClient.testing(memberID: "4172984", passHash: "pass-hash")
        cookieClient.clearAll()
        defer { cookieClient.clearAll() }
        let providerCalls = Mutex(0)
        let refreshClient = CookieRefreshClient.live(cookieClient: cookieClient) { _ in
            providerCalls.withLock { $0 += 1 }
            let response = try #require(HTTPURLResponse(
                url: Defaults.URL.exUConfig,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie": "\(Defaults.Cookie.igneous)=shared-token; path=/; max-age=3600"
                ]
            ))
            return (Data("uconfig".utf8), response)
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    #expect(await refreshClient.refreshIfNeeded(0))
                }
            }
        }

        #expect(providerCalls.withLock { $0 } == 1)
        #expect(await refreshClient.refreshIfNeeded(0))
        #expect(providerCalls.withLock { $0 } == 1)
        #expect(cookieClient.getCookie(Defaults.URL.sexhentai, Defaults.Cookie.igneous).rawValue == "shared-token")
    }
}
