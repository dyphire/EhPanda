import Foundation
import Testing
import AppTools
import AppModels
import CookieClient

@Suite(.serialized)
struct CookieClientTests {
    @Test
    func responseCredentialsImportAcrossHostsAndPreserveExpiry() throws {
        let cookieClient = CookieClient.testing()
        cookieClient.clearAll()
        defer { cookieClient.clearAll() }

        let header = """
            ipb_member_id=4172984; path=/; max-age=3600, \
            ipb_pass_hash=pass-hash; path=/; max-age=3600, \
            igneous=igneous-token; path=/; max-age=3600
            """
        let response = try #require(HTTPURLResponse(
            url: Defaults.URL.exhentai,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": header]
        ))

        #expect(cookieClient.importCredentials(response: response))

        for url in [Defaults.URL.ehentai, Defaults.URL.exhentai, Defaults.URL.sexhentai] {
            #expect(cookieClient.getCookie(url, Defaults.Cookie.ipbMemberId).rawValue == "4172984")
            #expect(cookieClient.getCookie(url, Defaults.Cookie.ipbPassHash).rawValue == "pass-hash")
        }
        for url in [Defaults.URL.exhentai, Defaults.URL.sexhentai] {
            #expect(cookieClient.getCookie(url, Defaults.Cookie.igneous).rawValue == "igneous-token")
        }
        #expect(cookieClient.cookies(for: Defaults.URL.ehentai)
            .contains(where: { $0.name == Defaults.Cookie.igneous }) == false)
        #expect(cookieClient.hasValidExAuthentication)
        #expect(cookieClient.shouldFetchIgneous == false)

        let importedCookie = try #require(cookieClient.cookies(for: Defaults.URL.exhentai)
            .first(where: { $0.name == Defaults.Cookie.igneous }))
        #expect(importedCookie.expiresDate != nil)
    }

    @Test
    func mysteryIgneousNeedsRefreshAndDoesNotOverwriteSiblingValue() {
        let cookieClient = CookieClient.testing(memberID: "4172984", passHash: "pass-hash")
        cookieClient.clearAll()
        defer { cookieClient.clearAll() }

        for url in [Defaults.URL.ehentai, Defaults.URL.exhentai, Defaults.URL.sexhentai] {
            cookieClient.setOrEditCookie(for: url, key: Defaults.Cookie.ipbMemberId, value: "4172984")
            cookieClient.setOrEditCookie(for: url, key: Defaults.Cookie.ipbPassHash, value: "pass-hash")
        }
        cookieClient.setOrEditCookie(
            for: Defaults.URL.sexhentai,
            key: Defaults.Cookie.igneous,
            value: "sibling-token"
        )
        cookieClient.setOrEditCookie(
            for: Defaults.URL.exhentai,
            key: Defaults.Cookie.igneous,
            value: Defaults.Cookie.mystery
        )

        #expect(cookieClient.shouldFetchIgneous)
        cookieClient.syncExCookies()
        #expect(cookieClient.getCookie(Defaults.URL.sexhentai, Defaults.Cookie.igneous).rawValue == "sibling-token")
    }

    @Test
    func manualEmptyValueRemovesCookieAndEhentaiNeverStoresIgneous() {
        let cookieClient = CookieClient.testing()
        cookieClient.clearAll()
        defer { cookieClient.clearAll() }

        var ehState = cookieClient.loadCookiesState(host: .ehentai)
        ehState.memberID.editingText = "4172984"
        ehState.passHash.editingText = "pass-hash"
        ehState.igneous.editingText = "ignored"
        cookieClient.setCookies(state: ehState)
        #expect(cookieClient.cookies(for: Defaults.URL.ehentai)
            .contains(where: { $0.name == Defaults.Cookie.igneous }) == false)

        var exState = cookieClient.loadCookiesState(host: .exhentai)
        exState.memberID.editingText = "4172984"
        exState.passHash.editingText = "pass-hash"
        exState.igneous.editingText = "token"
        cookieClient.setCookies(state: exState)
        #expect(cookieClient.getCookie(Defaults.URL.exhentai, Defaults.Cookie.igneous).rawValue == "token")

        exState.passHash.editingText = ""
        cookieClient.setCookies(state: exState)
        #expect(cookieClient.getCookie(Defaults.URL.exhentai, Defaults.Cookie.ipbPassHash).rawValue.isEmpty)
        #expect(cookieClient.getCookie(Defaults.URL.exhentai, Defaults.Cookie.ipbMemberId).rawValue == "4172984")
    }
}
