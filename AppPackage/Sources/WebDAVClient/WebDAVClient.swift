import Foundation
import AppModels
import OSLogExt
import ComposableArchitecture

private let logger = Logger(category: .init(describing: WebDAVClient.self))

/// Minimal WebDAV operations (RFC 4918) against a user-configured server: backup upload, restore
/// download, and directory listing. Plain `URLRequest`s on `URLSession` — no third-party client —
/// with Basic credentials sent proactively and Digest (as well as server-initiated Basic) answered
/// through the session delegate. All operations are per-call sessions because the credentials are
/// per-configuration and the ops are infrequent (manual backup/restore and at most one staleness
/// upload per day).
public struct WebDAVClient: Sendable {
    /// Any completed HTTP response counts as reachable — a 404 means the directory is missing,
    /// which upload fixes on demand. Only auth failures and transport errors fail the test.
    public var testConnection: @Sendable (WebDAVConfiguration) async -> Result<Void, AppError>
    /// PUTs `data` at `path`/`filename`, creating the directory with MKCOL first when the server
    /// reports it missing (Nextcloud and friends do not auto-create collections).
    public var upload: @Sendable (WebDAVConfiguration, String, Data) async -> Result<Void, AppError>
    public var download: @Sendable (WebDAVConfiguration, String) async -> Result<Data, AppError>
    /// PROPFIND Depth 1 on the configured directory, returning its files (directories excluded).
    public var list: @Sendable (WebDAVConfiguration) async -> Result<[WebDAVFile], AppError>
}

// MARK: - Live
extension WebDAVClient {
    public static func live(
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) -> Self {
        Self(
            testConnection: { config in
                guard let url = directoryURL(config) else { return .failure(.networkingFailed) }
                return connectionTestResult(await perform(
                    config, url: url, method: "PROPFIND", depth: "0",
                    sessionConfiguration: sessionConfiguration
                ))
            },
            upload: { config, filename, data in
                await uploadWithRetry(
                    config, filename: filename, data: data,
                    sessionConfiguration: sessionConfiguration
                )
            },
            download: { config, filename in
                guard let url = fileURL(config, filename: filename) else {
                    return .failure(.networkingFailed)
                }
                return downloadResult(await perform(
                    config, url: url, method: "GET",
                    sessionConfiguration: sessionConfiguration
                ))
            },
            list: { config in
                guard let url = directoryURL(config) else { return .failure(.networkingFailed) }
                return listResult(await perform(
                    config, url: url, method: "PROPFIND", depth: "1",
                    sessionConfiguration: sessionConfiguration
                ))
            }
        )
    }

    // Any completed HTTP response counts as reachable — a 404 means the directory is missing,
    // which upload fixes on demand. Only auth failures and transport errors fail the test.
    private static func connectionTestResult(
        _ result: Result<(status: Int, data: Data), AppError>
    ) -> Result<Void, AppError> {
        switch result {
        case .success(let status, _) where (200...299).contains(status):
            return .success(())
        case .success(let status, _) where status == 401 || status == 403:
            return .failure(.authenticationRequired)
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func downloadResult(
        _ result: Result<(status: Int, data: Data), AppError>
    ) -> Result<Data, AppError> {
        switch result {
        case .success(let status, let data) where (200...299).contains(status):
            return .success(data)
        case .success(let status, _) where status == 401 || status == 403:
            return .failure(.authenticationRequired)
        case .success(let status, _) where status == 404:
            return .failure(.notFound)
        case .success(let status, _):
            return .failure(.fileOperationFailed("GET \(status)"))
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func listResult(
        _ result: Result<(status: Int, data: Data), AppError>
    ) -> Result<[WebDAVFile], AppError> {
        switch result {
        case .success(let status, let data) where (200...299).contains(status):
            guard let files = MultistatusParser.parse(data) else {
                return .failure(.parseFailed)
            }
            return .success(files)
        case .success(let status, _) where status == 401 || status == 403:
            return .failure(.authenticationRequired)
        case .success(let status, _) where status == 404:
            // Missing directory means no backups yet, not an error.
            return .success([])
        case .success(let status, _):
            return .failure(.fileOperationFailed("PROPFIND \(status)"))
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func uploadWithRetry(
        _ config: WebDAVConfiguration, filename: String, data: Data,
        sessionConfiguration: URLSessionConfiguration
    ) async -> Result<Void, AppError> {
        let first = await putOnce(
            config, filename: filename, data: data,
            sessionConfiguration: sessionConfiguration
        )
        guard isMissingDirectoryFailure(first) else { return first }
        // Parent directory missing — create it and retry the PUT exactly once.
        guard let url = directoryURL(config) else { return .failure(.networkingFailed) }
        switch await perform(
            config, url: url, method: "MKCOL", sessionConfiguration: sessionConfiguration
        ) {
        case .success(let status, _) where (200...299).contains(status) || status == 405:
            // 405 = already exists (a racing upload or a lax server) — fine.
            break
        case .success(let status, _):
            logger.notice("WebDAV MKCOL failed with status \(status).")
            return .failure(.fileOperationFailed("MKCOL \(status)"))
        case .failure(let error):
            logger.notice("WebDAV MKCOL failed: \(error.localizedDescription)")
            return .failure(error)
        }
        return await putOnce(
            config, filename: filename, data: data,
            sessionConfiguration: sessionConfiguration
        )
    }

    private static func isMissingDirectoryFailure(_ result: Result<Void, AppError>) -> Bool {
        guard case .failure(.fileOperationFailed(let detail)) = result else { return false }
        // RFC 4918 says 409 Conflict; Nutstore, some nginx/Synology setups answer 403 Forbidden.
        return detail == "PUT 409" || detail == "PUT 403"
    }
}

// MARK: - Request plumbing
extension WebDAVClient {
    private static func directoryURL(_ config: WebDAVConfiguration) -> URL? {
        guard let base = config.normalizedServerURL else { return nil }
        let trimmedPath = config.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmedPath.isEmpty ? base : base.appending(path: trimmedPath)
    }

    private static func fileURL(_ config: WebDAVConfiguration, filename: String) -> URL? {
        directoryURL(config)?.appending(path: filename)
    }

    private static func putOnce(
        _ config: WebDAVConfiguration, filename: String, data: Data,
        sessionConfiguration: URLSessionConfiguration
    ) async -> Result<Void, AppError> {
        guard let url = fileURL(config, filename: filename) else {
            return .failure(.networkingFailed)
        }
        switch await perform(
            config, url: url, method: "PUT", body: data,
            sessionConfiguration: sessionConfiguration
        ) {
        case .success(let status, _) where (200...299).contains(status):
            return .success(())
        case .success(let status, _) where status == 401:
            return .failure(.authenticationRequired)
        case .success(let status, _):
            // 409 and 403 are consumed by `upload` to drive the MKCOL retry — many servers
            // report a missing parent directory as 403 rather than the standard 409.
            return .failure(.fileOperationFailed("PUT \(status)"))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Runs one request on a throwaway session whose delegate answers Basic/Digest challenges
    /// with the configuration's credentials. Returns the raw status and body on any completed
    /// HTTP response; transport failures map to `.networkingFailed`.
    private static func perform(
        _ config: WebDAVConfiguration, url: URL, method: String,
        depth: String? = nil, body: Data? = nil,
        sessionConfiguration: URLSessionConfiguration
    ) async -> Result<(status: Int, data: Data), AppError> {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let depth {
            request.setValue(depth, forHTTPHeaderField: "Depth")
        }
        if method == "PROPFIND" || method == "MKCOL" {
            request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if !config.username.isEmpty {
            let token = Data("\(config.username):\(config.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: WebDAVAuthDelegate(username: config.username, password: config.password),
            delegateQueue: .main
        )
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkingFailed)
            }
            return .success((httpResponse.statusCode, data))
        } catch {
            return .failure(.networkingFailed)
        }
    }
}

/// Answers server-initiated Basic and Digest challenges with the configuration's credentials;
/// proactive Basic already rides in the request header, so this mainly covers Digest servers.
private final class WebDAVAuthDelegate: NSObject, URLSessionTaskDelegate {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic
                || method == NSURLAuthenticationMethodHTTPDigest else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard !username.isEmpty else {
            completionHandler(.rejectProtectionSpace, nil)
            return
        }
        completionHandler(
            .useCredential,
            URLCredential(user: username, password: password, persistence: .forSession)
        )
    }
}

// MARK: - API
public enum WebDAVClientKey: DependencyKey {
    public static let liveValue = WebDAVClient.live()
    public static let previewValue = WebDAVClient.noop
    public static let testValue = WebDAVClient.unimplemented
}

extension DependencyValues {
    public var webDAVClient: WebDAVClient {
        get { self[WebDAVClientKey.self] }
        set { self[WebDAVClientKey.self] = newValue }
    }
}

// MARK: - Test
extension WebDAVClient {
    public static let noop: Self = .init(
        testConnection: { _ in .success(()) },
        upload: { _, _, _ in .success(()) },
        download: { _, _ in .failure(.unknown) },
        list: { _ in .success([]) }
    )

    public static func placeholder<Result>() -> Result { fatalError() }

    public static let unimplemented: Self = .init(
        testConnection: IssueReporting.unimplemented(placeholder: placeholder()),
        upload: IssueReporting.unimplemented(placeholder: placeholder()),
        download: IssueReporting.unimplemented(placeholder: placeholder()),
        list: IssueReporting.unimplemented(placeholder: placeholder())
    )
}
