import SwiftUI
import Foundation
import AppModels
import ComposableArchitecture
import HapticsClient
import NetworkingFeature
import CookieClient
import OSLogExt

private let logger = Logger(category: .init(describing: LoginReducer.self))

@Reducer
public struct LoginReducer: Sendable {
    private enum CancelID: Hashable {
        case login
    }

    @Reducer
    public enum Destination {
        @ReducerCaseIgnored
        case webView(URL)
    }

    public enum FocusedField: Sendable {
        case username
        case password
    }

    public struct ImportedCookie: Equatable, Sendable {
        public let domain: String
        public let path: String
        public let name: String
        public let value: String
        public let expiresDate: Date?
        public let isSessionOnly: Bool
        public let isSecure: Bool

        public init(cookie: HTTPCookie) {
            domain = cookie.domain
            path = cookie.path
            name = cookie.name
            value = cookie.value
            expiresDate = cookie.expiresDate
            isSessionOnly = cookie.isSessionOnly
            isSecure = cookie.isSecure
        }

        func httpCookie() -> HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value
            ]
            if let expiresDate {
                properties[.expires] = expiresDate
            }
            if isSessionOnly {
                properties[.discard] = "TRUE"
            }
            if isSecure {
                properties[.secure] = "TRUE"
            }
            return HTTPCookie(properties: properties)
        }
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        @Presents public var destination: Destination.State?
        public var focusedField: FocusedField?
        public var username = ""
        public var password = ""
        public var loginState: LoadingState = .idle

        var loginButtonDisabled: Bool {
            username.isEmpty || password.isEmpty
        }
        var loginButtonColor: Color {
            loginState == .loading ? .clear : loginButtonDisabled
                ? .primary.opacity(0.25) : .primary.opacity(0.75)
        }
    }

    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case destination(PresentationAction<Destination.Action>)
        case presentWebView(URL)

        case login
        case webViewCookiesReceived([ImportedCookie])
        case loginCookiesImported(Bool)
        case loginDone(Result<HTTPURLResponse?, AppError>)
    }

    @Dependency(\.hapticsClient) private var hapticsClient
    @Dependency(\.cookieClient) private var cookieClient
    @Dependency(\.dismiss) private var dismiss

    public init() {}

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .destination:
                return .none

            case .presentWebView(let url):
                state.destination = .webView(url)
                return .none

            case .login:
                guard !state.loginButtonDisabled || state.loginState == .loading else { return .none }
                state.focusedField = nil
                state.loginState = .loading
                return .merge(
                    .run(operation: { _ in await hapticsClient.generateFeedback(.soft) }),
                    .run { [username = state.username, password = state.password] send in
                        let result = await LoginRequest(username: username, password: password).response()
                        switch result {
                        case .success(let response):
                            let imported = response.map { cookieClient.importCredentials(response: $0) } ?? false
                            cookieClient.prepareAuthentication()
                            await send(.loginCookiesImported(imported))
                        case .failure(let error):
                            await send(.loginDone(.failure(error)))
                        }
                    }
                    .cancellable(id: CancelID.login)
                )

            case .webViewCookiesReceived(let importedCookies):
                return .run { send in
                    let cookies = importedCookies.compactMap { $0.httpCookie() }
                    let imported = cookieClient.importWebViewCookies(cookies)
                    cookieClient.prepareAuthentication()
                    await send(.loginCookiesImported(imported))
                }

            case .loginCookiesImported:
                let result: Result<HTTPURLResponse?, AppError> = cookieClient.didLogin
                    ? .success(nil)
                    : .failure(.unknown)
                return .send(.loginDone(result))

            case .loginDone(let result):
                state.destination = nil
                var effects = [Effect<Action>]()
                if case .success = result, cookieClient.didLogin {
                    state.loginState = .idle
                    effects.append(.run(operation: { _ in
                        logger.notice("Login succeeded.")
                        await hapticsClient.generateNotificationFeedback(.success)
                    }))
                    effects.append(.run { _ in await dismiss() })
                } else {
                    state.loginState = .failed(.unknown)
                    effects.append(.run(operation: { _ in
                        logger.notice("Login failed.")
                        await hapticsClient.generateNotificationFeedback(.error)
                    }))
                }
                return .merge(effects)
            }
        }
        .haptics(
            unwrapping: \.destination,
            case: \.webView,
            hapticsClient: hapticsClient
        )
        .ifLet(\.$destination, action: \.destination)
    }
}

extension LoginReducer.Destination.State: Equatable, Sendable {}
extension LoginReducer.Destination.Action: Equatable, Sendable {}
