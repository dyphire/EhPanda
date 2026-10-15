import Foundation
import TestingSupport
import Testing
import AppTools
import AppModels
import DownloadClient
import CookieClient
import NetworkingFeature
@testable import AppFeature

@Suite(.serialized)
struct DownloadAuthenticationRecoveryTests: DownloadFeatureTestCase {
    @Test
    func exAuthenticationFailureRefreshesCookieAndReplaysDownloadOnce() async throws {
        let sessionID = UUID().uuidString
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let placeholderData = try fixtureData(resource: "Kokomade", pathExtension: "jpg")
        let recoveredData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let requestCount = UncheckedBox(0)
        let refreshCount = UncheckedBox(0)
        let (_, manager) = makeStubbedDownloadCoordinator(
            rootURL: rootURL,
            sessionID: sessionID,
            cookieRefreshClient: makeRefreshClient(
                refreshCookieClient: CookieClient.testing(
                    memberID: "4172984",
                    passHash: "pass-hash"
                ),
                refreshCount: refreshCount
            )
        )
        SharedSessionStubURLProtocol.setHandler(for: sessionID) { request in
            guard let requestURL = request.url else { throw URLError(.badURL) }
            #expect(requestURL.isExHentai)
            requestCount.value += 1
            let data = requestCount.value == 1 ? placeholderData : recoveredData
            let response = try #require(HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            ))
            return (response, data)
        }
        defer { SharedSessionStubURLProtocol.removeHandler(for: sessionID) }

        let url = try #require(URL(string: "https://exhentai.org/s/sample/1.jpg"))
        let (fileURL, _) = try await manager.downloadResponse(for: URLRequest(url: url))

        #expect(requestCount.value == 2)
        #expect(refreshCount.value == 1)
        #expect(try Data(contentsOf: fileURL) == recoveredData)
    }

    @Test
    func failedCookieRefreshPreservesAuthenticationErrorWithoutReplay() async throws {
        let sessionID = UUID().uuidString
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let placeholderData = try fixtureData(resource: "Kokomade", pathExtension: "jpg")
        let requestCount = UncheckedBox(0)
        let refreshCount = UncheckedBox(0)
        let refreshCookieClient = CookieClient.testing(memberID: "4172984", passHash: "pass-hash")
        let (_, manager) = makeStubbedDownloadCoordinator(
            rootURL: rootURL,
            sessionID: sessionID,
            cookieRefreshClient: CookieRefreshClient.live(
                cookieClient: refreshCookieClient
            ) { _ in
                refreshCount.value += 1
                let response = try #require(HTTPURLResponse(
                    url: Defaults.URL.exUConfig,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (Data("uconfig".utf8), response)
            }
        )
        SharedSessionStubURLProtocol.setHandler(for: sessionID) { request in
            guard let requestURL = request.url else { throw URLError(.badURL) }
            requestCount.value += 1
            let response = try #require(HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            ))
            return (response, placeholderData)
        }
        defer { SharedSessionStubURLProtocol.removeHandler(for: sessionID) }

        let url = try #require(URL(string: "https://exhentai.org/s/sample/1.jpg"))
        do {
            _ = try await manager.downloadResponse(for: URLRequest(url: url))
            Issue.record("Expected downloadResponse to preserve the authentication error")
        } catch let error as AppError {
            #expect(error == .authenticationRequired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(requestCount.value == 1)
        #expect(refreshCount.value == 1)
    }

    private func makeRefreshClient(
        refreshCookieClient: CookieClient,
        refreshCount: UncheckedBox<Int>
    ) -> CookieRefreshClient {
        CookieRefreshClient.live(cookieClient: refreshCookieClient) { _ in
            refreshCount.value += 1
            let response = try #require(HTTPURLResponse(
                url: Defaults.URL.exUConfig,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie": "\(Defaults.Cookie.igneous)=download-token; path=/; max-age=3600"
                ]
            ))
            return (Data("uconfig".utf8), response)
        }
    }
}
