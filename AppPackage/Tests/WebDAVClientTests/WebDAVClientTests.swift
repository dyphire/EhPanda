import Foundation
import Testing
import Synchronization
import AppModels
import WebDAVClient

// Exercises the live client against a stubbed URLProtocol: method/URL/header construction,
// the MKCOL retry on a missing directory, PROPFIND multistatus parsing, and status mapping.
// Serialized: the stub swaps a shared handler and records into a shared buffer.
@Suite(.serialized)
struct WebDAVClientTests {
    private let configuration = WebDAVConfiguration(
        serverURL: "https://dav.example.com",
        path: "/ehpanda",
        username: "alice",
        password: "wonderland"
    )

    private func makeClient() -> WebDAVClient {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        return WebDAVClient.live(sessionConfiguration: sessionConfiguration)
    }

    private func respond(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        StubURLProtocol.handler = handler
        StubURLProtocol.recorded.withLock { $0.removeAll() }
    }

    private var recorded: [RecordedRequest] {
        StubURLProtocol.recorded.withLock { $0 }
    }

    private func httpResponse(
        _ request: URLRequest, status: Int, body: Data = Data()
    ) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil
        ) else {
            throw URLError(.badServerResponse)
        }
        return (response, body)
    }

    @Test
    func uploadPutsFileAtConfiguredPathWithBasicCredentials() async throws {
        respond { [self] request in
            try httpResponse(request, status: 201)
        }
        defer { StubURLProtocol.handler = nil }

        let result = await makeClient().upload(configuration, "backup.json", Data("payload".utf8))

        #expect((try? result.get()) != nil)
        let request = try #require(recorded.first)
        #expect(request.method == "PUT")
        #expect(request.path == "/ehpanda/backup.json")
        let expected = "Basic " + Data("alice:wonderland".utf8).base64EncodedString()
        #expect(request.authorization == expected)
    }

    @Test
    func uploadCreatesMissingDirectoryThenRetriesPut() async throws {
        respond { [self] request in
            switch (request.httpMethod, request.url?.path) {
            case ("PUT", "/ehpanda/backup.json") where self.recorded.isEmpty:
                // First PUT sees the missing directory; the MKCOL+retry pair succeeds.
                return try httpResponse(request, status: 409)
            case ("MKCOL", "/ehpanda"):
                return try httpResponse(request, status: 201)
            default:
                return try httpResponse(request, status: 201)
            }
        }
        defer { StubURLProtocol.handler = nil }

        let result = await makeClient().upload(configuration, "backup.json", Data("payload".utf8))

        #expect((try? result.get()) != nil)
        #expect(recorded.map(\.method) == ["PUT", "MKCOL", "PUT"])
    }

    @Test
    func uploadRetriesWhenMissingDirectoryIsReportedAsForbidden() async throws {
        // Nutstore and some nginx/Synology setups report a missing parent directory as
        // 403 instead of the standard 409 — it must drive the same MKCOL retry.
        respond { [self] request in
            switch (request.httpMethod, request.url?.path) {
            case ("PUT", "/ehpanda/backup.json") where self.recorded.isEmpty:
                return try httpResponse(request, status: 403)
            case ("MKCOL", "/ehpanda"):
                return try httpResponse(request, status: 201)
            default:
                return try httpResponse(request, status: 201)
            }
        }
        defer { StubURLProtocol.handler = nil }

        let result = await makeClient().upload(configuration, "backup.json", Data("payload".utf8))

        #expect((try? result.get()) != nil)
        #expect(recorded.map(\.method) == ["PUT", "MKCOL", "PUT"])
    }

    @Test
    func downloadReturnsBodyAndMapsStatuses() async throws {
        respond { [self] request in
            try httpResponse(request, status: 200, body: Data("remote-backup".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let data = try await makeClient().download(configuration, "backup.json").get()
        #expect(String(data: data, encoding: .utf8) == "remote-backup")

        respond { [self] request in
            try httpResponse(request, status: 404)
        }
        #expect(await makeClient().download(configuration, "missing.json") == .failure(.notFound))

        respond { [self] request in
            try httpResponse(request, status: 401)
        }
        #expect(
            await makeClient().download(configuration, "backup.json")
                == .failure(.authenticationRequired)
        )
    }

    @Test
    func listParsesMultistatusAndExcludesDirectoryEntries() async throws {
        let body = """
            <?xml version="1.0" encoding="utf-8"?>
            <D:multistatus xmlns:D="DAV:">
              <D:response>
                <D:href>/ehpanda/</D:href>
                <D:propstat><D:prop>
                  <D:resourcetype><D:collection/></D:resourcetype>
                </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
              </D:response>
              <D:response>
                <D:href>/ehpanda/ehpanda-backup-latest.json</D:href>
                <D:propstat><D:prop>
                  <D:getcontentlength>13655</D:getcontentlength>
                  <D:getlastmodified>Wed, 15 Oct 2026 08:12:23 GMT</D:getlastmodified>
                  <D:resourcetype/>
                </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
              </D:response>
              <D:response>
                <D:href>/ehpanda/ehpanda-backup-20261014.json</D:href>
                <D:propstat><D:prop>
                  <D:getcontentlength>12000</D:getcontentlength>
                </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
              </D:response>
            </D:multistatus>
            """
        respond { [self] request in
            #expect(request.httpMethod == "PROPFIND")
            #expect(request.depth == "1")
            return try httpResponse(request, status: 207, body: Data(body.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let files = try await makeClient().list(configuration).get()

        #expect(files.count == 2)
        #expect(files[0].name == "ehpanda-backup-latest.json")
        #expect(files[0].size == 13655)
        #expect(files[0].modifiedDate != nil)
        #expect(files[1].name == "ehpanda-backup-20261014.json")
        #expect(files[1].modifiedDate == nil)
    }

    @Test
    func listTreatsMissingDirectoryAsEmptyBackupSet() async throws {
        respond { [self] request in
            try httpResponse(request, status: 404)
        }
        defer { StubURLProtocol.handler = nil }

        #expect(await makeClient().list(configuration) == .success([]))
    }

    @Test
    func testConnectionFailsOnlyOnAuthOrTransport() async throws {
        respond { [self] request in
            // A missing directory still proves the server and credentials work.
            try httpResponse(request, status: 404)
        }
        defer { StubURLProtocol.handler = nil }

        let connectResult = await makeClient().testConnection(configuration)
        #expect((try? connectResult.get()) != nil)

        respond { [self] request in
            try httpResponse(request, status: 401)
        }
        let authResult = await makeClient().testConnection(configuration)
        #expect(throws: (any Error).self) { try authResult.get() }

        respond { _ in
            throw URLError(.cannotConnectToHost)
        }
        let unreachableResult = await makeClient().testConnection(configuration)
        #expect(throws: (any Error).self) { try unreachableResult.get() }
    }

    @Test
    func serverURLWithoutSchemeDefaultsToHTTPS() async throws {
        respond { [self] request in
            try httpResponse(request, status: 200)
        }
        defer { StubURLProtocol.handler = nil }

        var config = configuration
        config.serverURL = "dav.example.com"
        _ = await makeClient().download(config, "backup.json")

        let request = try #require(recorded.first)
        #expect(request.absoluteURL == "https://dav.example.com/ehpanda/backup.json")
    }
}

// MARK: - Stub

private struct RecordedRequest: Equatable, Sendable {
    var method: String?
    var path: String?
    var absoluteURL: String?
    var authorization: String?
    var depth: String?
}

private final class StubURLProtocol: URLProtocol {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    static let recorded = Mutex<[RecordedRequest]>([])

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            Self.recorded.withLock {
                $0.append(.init(
                    method: request.httpMethod,
                    path: request.url?.path,
                    absoluteURL: request.url?.absoluteString,
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    depth: request.value(forHTTPHeaderField: "Depth")
                ))
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
