import Foundation
import AppModels
import AppTools
import ParserFeature
import CookieClient
import ComposableArchitecture

public struct CookieRefreshClient: Sendable {
    public let revision: @Sendable () async -> UInt
    public let refresh: @Sendable () async -> Bool
    public let refreshIfNeeded: @Sendable (UInt) async -> Bool
}

extension CookieRefreshClient {
    public static let live: Self = .live(cookieClient: .live)

    public static func live(
        cookieClient: CookieClient,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) -> Self {
        let coordinator = CookieRefreshCoordinator(
            isValid: { cookieClient.hasValidExAuthentication },
            operation: {
                await performRefresh(cookieClient: cookieClient, dataProvider: dataProvider)
            }
        )
        return .init(
            revision: { await coordinator.currentRevision() },
            refresh: { await coordinator.refresh() },
            refreshIfNeeded: { revision in await coordinator.refreshIfNeeded(since: revision) }
        )
    }

    public func response<Value: Sendable>(
        from operation: () async -> Result<Value, AppError>
    ) async -> Result<Value, AppError> {
        let currentRevision = await revision()
        let result = await operation()
        guard case .failure(.authenticationRequired) = result else { return result }
        guard await refreshIfNeeded(currentRevision), !Task.isCancelled else { return result }
        return await operation()
    }

    public func perform<Value>(
        operation: () async throws -> Value
    ) async throws -> Value {
        let currentRevision = await revision()
        do {
            return try await operation()
        } catch {
            guard let error = error as? AppError, error == .authenticationRequired else { throw error }
            guard await refreshIfNeeded(currentRevision) else { throw error }
            try Task.checkCancellation()
            return try await operation()
        }
    }
}

extension CookieRefreshClient {
    static func performRefresh(
        cookieClient: CookieClient,
        dataProvider: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> Bool {
        cookieClient.prepareAuthentication()
        guard cookieClient.hasExCredentials else { return false }
        cookieClient.clearIgneous()

        do {
            let (data, response) = try await dataProvider(URLRequest(url: Defaults.URL.exUConfig))
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  isExUConfig(httpResponse.url ?? Defaults.URL.exUConfig),
                  Parser.parseResponseError(content: String(decoding: data, as: UTF8.self)) == nil,
                  cookieClient.importCredentials(response: httpResponse) else {
                return false
            }
            cookieClient.syncExCookies()
            return cookieClient.hasValidExAuthentication
        } catch {
            return false
        }
    }

    static func isExUConfig(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "exhentai.org" || host.hasSuffix(".exhentai.org") else {
            return false
        }
        return url.lastPathComponent == "uconfig.php"
    }
}

private actor CookieRefreshCoordinator {
    private let operation: @Sendable () async -> Bool
    private let isValid: @Sendable () -> Bool
    private var inFlight: Task<Bool, Never>?
    private var revisionValue: UInt = 0

    init(
        isValid: @escaping @Sendable () -> Bool,
        operation: @escaping @Sendable () async -> Bool
    ) {
        self.isValid = isValid
        self.operation = operation
    }

    func currentRevision() -> UInt {
        revisionValue
    }

    func refresh() async -> Bool {
        await sharedRefresh()
    }

    func refreshIfNeeded(since revision: UInt) async -> Bool {
        if revisionValue != revision, isValid() {
            return true
        }
        return await sharedRefresh()
    }

    private func sharedRefresh() async -> Bool {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { @Sendable in
            let result = await operation()
            await complete(result)
            return result
        }
        inFlight = task
        return await task.value
    }

    private func complete(_ result: Bool) {
        inFlight = nil
        if result {
            revisionValue &+= 1
        }
    }
}

public enum CookieRefreshClientKey: DependencyKey {
    public static let liveValue = CookieRefreshClient.live
    public static let previewValue = CookieRefreshClient.noop
    public static let testValue = CookieRefreshClient.unimplemented
}

extension DependencyValues {
    public var cookieRefreshClient: CookieRefreshClient {
        get { self[CookieRefreshClientKey.self] }
        set { self[CookieRefreshClientKey.self] = newValue }
    }
}

extension CookieRefreshClient {
    public static let noop: Self = .init(
        revision: { 0 },
        refresh: { false },
        refreshIfNeeded: { _ in false }
    )

    private static func placeholder<Result>() -> Result { fatalError() }

    public static let unimplemented: Self = .init(
        revision: IssueReporting.unimplemented(placeholder: placeholder()),
        refresh: IssueReporting.unimplemented(placeholder: placeholder()),
        refreshIfNeeded: IssueReporting.unimplemented(placeholder: placeholder())
    )
}
