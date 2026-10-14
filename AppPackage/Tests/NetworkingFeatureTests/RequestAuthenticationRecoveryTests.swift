import Foundation
import Synchronization
import Combine
import Testing
import ComposableArchitecture
import AppModels
@testable import NetworkingFeature

struct RequestAuthenticationRecoveryTests {
    @Test
    func authenticationFailureRefreshesAndReplaysOnce() async {
        let operationCalls = Counter()
        let refreshCalls = Counter()
        let request = MockRequest(policy: .refreshExHentai) {
            operationCalls.increment()
            return operationCalls.value == 1
                ? .failure(.authenticationRequired)
                : .success("recovered")
        }
        let client = makeRefreshClient(refreshCalls: refreshCalls)

        let result = await withDependencies {
            $0.cookieRefreshClient = client
        } operation: {
            await request.response()
        }

        #expect(result == .success("recovered"))
        #expect(operationCalls.value == 2)
        #expect(refreshCalls.value == 1)
    }

    @Test
    func repeatedAuthenticationFailureDoesNotRetryThirdTime() async {
        let operationCalls = Counter()
        let refreshCalls = Counter()
        let request = MockRequest(policy: .refreshExHentai) {
            operationCalls.increment()
            return .failure(.authenticationRequired)
        }
        let client = makeRefreshClient(refreshCalls: refreshCalls)

        let result = await withDependencies {
            $0.cookieRefreshClient = client
        } operation: {
            await request.response()
        }

        #expect(result == .failure(.authenticationRequired))
        #expect(operationCalls.value == 2)
        #expect(refreshCalls.value == 1)
    }

    @Test
    func failedRefreshPreservesOriginalAuthenticationErrorWithoutReplay() async {
        let operationCalls = Counter()
        let refreshCalls = Counter()
        let request = MockRequest(policy: .refreshExHentai) {
            operationCalls.increment()
            return .failure(.authenticationRequired)
        }
        var client = makeRefreshClient(refreshCalls: refreshCalls)
        client = CookieRefreshClient(
            revision: client.revision,
            refresh: client.refresh,
            refreshIfNeeded: { _ in false }
        )

        let result = await withDependencies {
            $0.cookieRefreshClient = client
        } operation: {
            await request.response()
        }

        #expect(result == .failure(.authenticationRequired))
        #expect(operationCalls.value == 1)
        #expect(refreshCalls.value == 0)
    }

    @Test
    func nonAuthenticationFailureAndDisabledPolicyDoNotRefresh() async {
        let operationCalls = Counter()
        let refreshCalls = Counter()
        let request = MockRequest(policy: .disabled) {
            operationCalls.increment()
            return .failure(.authenticationRequired)
        }
        let client = makeRefreshClient(refreshCalls: refreshCalls)

        let result = await withDependencies {
            $0.cookieRefreshClient = client
        } operation: {
            await request.response()
        }

        #expect(result == .failure(.authenticationRequired))
        #expect(operationCalls.value == 1)
        #expect(refreshCalls.value == 0)
    }

    @Test
    func exHentaiPolicyMatchesExHostsOnly() throws {
        let exURL = try #require(URL(string: "https://exhentai.org/g/1/token"))
        let siblingURL = try #require(URL(string: "https://s.exhentai.org/image.jpg"))
        let ehURL = try #require(URL(string: "https://e-hentai.org/"))
        let externalURL = try #require(URL(string: "https://example.com/"))

        #expect(RequestAuthenticationRecoveryPolicy.exHentai(for: exURL) == .refreshExHentai)
        #expect(RequestAuthenticationRecoveryPolicy.exHentai(for: siblingURL) == .refreshExHentai)
        #expect(RequestAuthenticationRecoveryPolicy.exHentai(for: ehURL) == .disabled)
        #expect(RequestAuthenticationRecoveryPolicy.exHentai(for: externalURL) == .disabled)
    }

    @Test
    func readRequestsOptInWhileWriteRequestsStayDisabled() throws {
        let exURL = try #require(URL(string: "https://exhentai.org/g/1/token"))

        #expect(GalleryDetailRequest(gid: "1", galleryURL: exURL).authenticationRecoveryPolicy == .refreshExHentai)
        #expect(FavorGalleryRequest(gid: "1", token: "token", favIndex: 0).authenticationRecoveryPolicy == .disabled)
        #expect(CommentGalleryRequest(content: "comment", galleryURL: exURL).authenticationRecoveryPolicy == .disabled)
        #expect(SendDownloadCommandRequest(
            archiveURL: exURL,
            resolution: "780"
        ).authenticationRecoveryPolicy == .disabled)
    }

    private final class Counter: Sendable {
        private let state = Mutex(0)

        var value: Int {
            state.withLock { $0 }
        }

        func increment() {
            state.withLock { $0 += 1 }
        }
    }

    private func makeRefreshClient(refreshCalls: Counter) -> CookieRefreshClient {
        CookieRefreshClient(
            revision: { 0 },
            refresh: {
                refreshCalls.increment()
                return true
            },
            refreshIfNeeded: { _ in
                refreshCalls.increment()
                return true
            }
        )
    }

    private struct MockRequest: Request {
        let policy: RequestAuthenticationRecoveryPolicy
        let resultProvider: @Sendable () -> Result<String, AppError>

        var authenticationRecoveryPolicy: RequestAuthenticationRecoveryPolicy { policy }

        var publisher: AnyPublisher<String, AppError> {
            Deferred<AnyPublisher<String, AppError>> {
                switch resultProvider() {
                case .success(let value):
                    return Just(value)
                        .setFailureType(to: AppError.self)
                        .eraseToAnyPublisher()
                case .failure(let error):
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
        }
    }
}
