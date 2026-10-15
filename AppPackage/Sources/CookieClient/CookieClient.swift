import Foundation
import AppModels
import ComposableArchitecture
import AppTools
#if DEBUG
import Synchronization
#endif

private func cookieValue(in cookies: [HTTPCookie], key: String) -> CookieValue {
    let cookie = cookies
        .filter { $0.name == key && !$0.value.isEmpty }
        .sorted { lhs, rhs in
            let lhsPriority = cookiePriority(lhs)
            let rhsPriority = cookiePriority(rhs)
            return lhsPriority == rhsPriority
                ? lhs.path.count > rhs.path.count
                : lhsPriority > rhsPriority
        }
        .first
    guard let cookie else {
        return CookieValue(rawValue: "", localizedString: String(localized: .cookieValueNone))
    }
    if let expiresDate = cookie.expiresDate, expiresDate <= .now {
        return CookieValue(rawValue: "", localizedString: String(localized: .cookieValueExpired))
    }
    if cookie.value == Defaults.Cookie.mystery {
        return CookieValue(
            rawValue: cookie.value,
            localizedString: String(localized: .cookieValueMystery)
        )
    }
    return CookieValue(rawValue: cookie.value, localizedString: "")
}

private func cookiePriority(_ cookie: HTTPCookie) -> Int {
    if let expiresDate = cookie.expiresDate, expiresDate <= .now {
        return 1
    }
    return cookie.value == Defaults.Cookie.mystery ? 2 : 3
}

public struct CookieClient: Sendable {
    public let clearAll: @Sendable () -> Void
    public let getCookie: @Sendable (URL, String) -> CookieValue
    private let cookiesForURL: @Sendable (URL) -> [HTTPCookie]
    private let removeCookie: @Sendable (URL, String) -> Void
    private let deleteCookie: @Sendable (HTTPCookie) -> Void
    private let checkExistence: @Sendable (URL, String) -> Bool
    private let initializeCookie: @Sendable (HTTPCookie, String) -> HTTPCookie?
    private let storeCookie: @Sendable (HTTPCookie) -> Void
    private let setCookieValue: @Sendable (URL, String, String, String, TimeInterval, Bool) -> Void
}

extension CookieClient {
    public static let live: Self = live(cookieStorage: .shared)

    public static func live(cookieStorage: HTTPCookieStorage) -> Self {
        .init(
            clearAll: {
                if let historyCookies = cookieStorage.cookies {
                    historyCookies.forEach {
                        cookieStorage.deleteCookie($0)
                    }
                }
            },
            getCookie: { url, key in
                cookieValue(in: cookieStorage.cookies(for: url) ?? [], key: key)
            },
            cookiesForURL: { url in
                cookieStorage.cookies(for: url) ?? []
            },
            removeCookie: { url, key in
                if let cookies = cookieStorage.cookies(for: url) {
                    cookies.forEach { cookie in
                        guard cookie.name == key else { return }
                        cookieStorage.deleteCookie(cookie)
                    }
                }
            },
            deleteCookie: { cookie in
                cookieStorage.deleteCookie(cookie)
            },
            checkExistence: { url, key in
                if let cookies = cookieStorage.cookies(for: url) {
                    var existence: HTTPCookie?
                    cookies.forEach { cookie in
                        guard cookie.name == key else { return }
                        existence = cookie
                    }
                    return existence != nil
                } else {
                    return false
                }
            },
            initializeCookie: { cookie, value in
                var properties = cookie.properties
                properties?[.value] = value
                return HTTPCookie(properties: properties ?? [:])
            },
            storeCookie: { cookie in
                cookieStorage.setCookie(cookie)
            },
            setCookieValue: { url, key, value, path, expiresTime, sessionOnly in
                let properties: [HTTPCookiePropertyKey: Any] = [
                    .path: path, .name: key, .value: value,
                    .originURL: url
                ]
                var mutableProperties = properties
                if let host = url.host {
                    mutableProperties[.domain] = host
                }
                if sessionOnly {
                    mutableProperties[.discard] = "TRUE"
                } else {
                    mutableProperties[.expires] = Date(timeIntervalSinceNow: expiresTime)
                }
                if let cookie = HTTPCookie(properties: mutableProperties) {
                    cookieStorage.setCookie(cookie)
                }
            }
        )
    }
}

// MARK: Foundation
extension CookieClient {
    public func importAutomationCookies(memberID: String, passHash: String, igneous: String?) {
        let urls = [Defaults.URL.ehentai, Defaults.URL.exhentai, Defaults.URL.sexhentai]
        let authKeys = [Defaults.Cookie.ipbMemberId, Defaults.Cookie.ipbPassHash]

        urls.forEach { url in
            authKeys.forEach { key in
                removeCookie(url, key)
            }
        }
        [Defaults.URL.exhentai, Defaults.URL.sexhentai].forEach { url in
            removeCookie(url, Defaults.Cookie.igneous)
        }

        urls.forEach { url in
            setCookie(
                for: url,
                key: Defaults.Cookie.ipbMemberId,
                value: memberID,
                sessionOnly: true
            )
            setCookie(
                for: url,
                key: Defaults.Cookie.ipbPassHash,
                value: passHash,
                sessionOnly: true
            )
        }

        if let igneous, !igneous.isEmpty {
            [Defaults.URL.exhentai, Defaults.URL.sexhentai].forEach { url in
                setCookie(
                    for: url,
                    key: Defaults.Cookie.igneous,
                    value: igneous,
                    sessionOnly: true
                )
            }
        }

        ignoreOffensive()
        fulfillAnotherHostField()
    }

    private func setCookie(
        for url: URL, key: String, value: String, path: String = "/",
        expiresTime: TimeInterval = .oneYear,
        sessionOnly: Bool = false
    ) {
        setCookieValue(url, key, value, path, expiresTime, sessionOnly)
    }
    private func validCookie(for url: URL, key: String) -> HTTPCookie? {
        let value = getCookie(url, key).rawValue
        guard !value.isEmpty, value != Defaults.Cookie.mystery else { return nil }
        return cookiesForURL(url)
            .filter { cookie in
                guard cookie.name == key, cookie.value == value else { return false }
                guard let expiresDate = cookie.expiresDate else { return true }
                return expiresDate > .now
            }
            .sorted { $0.path.count > $1.path.count }
            .first
    }
    private func replicatedCookie(_ cookie: HTTPCookie, for url: URL) -> HTTPCookie? {
        guard let host = url.host else { return nil }
        var properties = cookie.properties ?? [:]
        properties[.name] = cookie.name
        properties[.value] = cookie.value
        properties[.domain] = host
        properties[.originURL] = url
        properties[.path] = cookie.path.isEmpty ? "/" : cookie.path
        return HTTPCookie(properties: properties)
    }
    @discardableResult
    private func storeReplica(_ cookie: HTTPCookie, for url: URL) -> Bool {
        guard let replica = replicatedCookie(cookie, for: url) else { return false }
        removeCookie(url, cookie.name)
        storeCookie(replica)
        return true
    }
    public func editCookie(for url: URL, key: String, value: String) {
        cookiesForURL(url).forEach { cookie in
            guard cookie.name == key, let newCookie = initializeCookie(cookie, value) else { return }
            deleteCookie(cookie)
            storeCookie(newCookie)
        }
    }
    public func setOrEditCookie(for url: URL, key: String, value: String) {
        if checkExistence(url, key) {
            editCookie(for: url, key: key, value: value)
        } else {
            setCookie(for: url, key: key, value: value)
        }
    }
    public func cookies(for url: URL) -> [HTTPCookie] {
        cookiesForURL(url)
    }
}

// MARK: Accessor
extension CookieClient {
    public func hasCredentials(for url: URL) -> Bool {
        !getCookie(url, Defaults.Cookie.ipbMemberId).rawValue.isEmpty
            && !getCookie(url, Defaults.Cookie.ipbPassHash).rawValue.isEmpty
    }
    public func hasValidIgneous(for url: URL) -> Bool {
        let value = getCookie(url, Defaults.Cookie.igneous).rawValue
        return !value.isEmpty && value != Defaults.Cookie.mystery
    }
    public var hasExCredentials: Bool {
        hasCredentials(for: Defaults.URL.exhentai)
    }
    public var hasValidExAuthentication: Bool {
        hasExCredentials
            && hasCredentials(for: Defaults.URL.sexhentai)
            && hasValidIgneous(for: Defaults.URL.exhentai)
            && hasValidIgneous(for: Defaults.URL.sexhentai)
    }
    public var didLogin: Bool {
        hasCredentials(for: Defaults.URL.ehentai)
            || hasExCredentials && hasValidIgneous(for: Defaults.URL.exhentai)
    }
    public var apiuid: String {
        getCookie(Defaults.URL.host, Defaults.Cookie.ipbMemberId).rawValue
    }
    public var isSameAccount: Bool {
        let ehUID = getCookie(Defaults.URL.ehentai, Defaults.Cookie.ipbMemberId).rawValue
        let exUID = getCookie(Defaults.URL.exhentai, Defaults.Cookie.ipbMemberId).rawValue
        if !ehUID.isEmpty && !exUID.isEmpty { return ehUID == exUID } else { return false }
    }
    public var shouldFetchIgneous: Bool {
        hasExCredentials && !hasValidIgneous(for: Defaults.URL.exhentai)
    }
    public func removeYay() {
        removeCookie(Defaults.URL.exhentai, Defaults.Cookie.yay)
        removeCookie(Defaults.URL.sexhentai, Defaults.Cookie.yay)
    }
    public func clearIgneous() {
        removeCookie(Defaults.URL.exhentai, Defaults.Cookie.igneous)
        removeCookie(Defaults.URL.sexhentai, Defaults.Cookie.igneous)
    }
    public func syncExCookies() {
        let keys = [
            Defaults.Cookie.ipbMemberId,
            Defaults.Cookie.ipbPassHash,
            Defaults.Cookie.igneous
        ]
        for key in keys {
            guard let cookie = validCookie(for: Defaults.URL.exhentai, key: key) else { continue }
            storeReplica(cookie, for: Defaults.URL.sexhentai)
        }
    }
    public func ignoreOffensive() {
        setOrEditCookie(for: Defaults.URL.ehentai, key: Defaults.Cookie.ignoreOffensive, value: "1")
        setOrEditCookie(for: Defaults.URL.exhentai, key: Defaults.Cookie.ignoreOffensive, value: "1")
    }
    public func fulfillAnotherHostField() {
        let keys = [Defaults.Cookie.ipbMemberId, Defaults.Cookie.ipbPassHash]
        for key in keys {
            let ehCookie = validCookie(for: Defaults.URL.ehentai, key: key)
            let exCookie = validCookie(for: Defaults.URL.exhentai, key: key)
            if ehCookie == nil, let exCookie {
                storeReplica(exCookie, for: Defaults.URL.ehentai)
            } else if exCookie == nil, let ehCookie {
                storeReplica(ehCookie, for: Defaults.URL.exhentai)
            }
        }
    }
    public func prepareAuthentication() {
        removeYay()
        ignoreOffensive()
        fulfillAnotherHostField()
        syncExCookies()
    }
    public func loadCookiesState(host: GalleryHost) -> CookiesState {
        let igneousKey = Defaults.Cookie.igneous
        let memberIDKey = Defaults.Cookie.ipbMemberId
        let passHashKey = Defaults.Cookie.ipbPassHash
        let igneous = getCookie(host.url, igneousKey)
        let memberID = getCookie(host.url, memberIDKey)
        let passHash = getCookie(host.url, passHashKey)
        return .init(
            host: host,
            igneous: .init(key: igneousKey, value: igneous, editingText: igneous.rawValue),
            memberID: .init(key: memberIDKey, value: memberID, editingText: memberID.rawValue),
            passHash: .init(key: passHashKey, value: passHash, editingText: passHash.rawValue)
        )
    }
    public func getCookiesDescription(host: GalleryHost) -> String {
        var dictionary = [String: String]()
        [Defaults.Cookie.igneous, Defaults.Cookie.ipbMemberId, Defaults.Cookie.ipbPassHash].forEach { key in
            let cookieValue = getCookie(host.url, key)
            if !cookieValue.rawValue.isEmpty {
                dictionary[key] = cookieValue.rawValue
            }
        }
        return dictionary
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }
}

// MARK: SetCookies
extension CookieClient {
    public func setCookies(state: CookiesState, trimsSpaces: Bool = true) {
        for subState in state.allCases {
            guard !(state.host == .ehentai && subState.key == Defaults.Cookie.igneous) else { continue }
            for url in state.host.cookieURLs {
                let value = trimsSpaces
                    ? subState.editingText.trimmingCharacters(in: .whitespaces)
                    : subState.editingText
                if value.isEmpty {
                    removeCookie(url, subState.key)
                } else {
                    setOrEditCookie(for: url, key: subState.key, value: value)
                }
            }
        }
    }
    @discardableResult
    public func importCookieString(_ string: String) -> Bool {
        let values = Self.cookieValues(in: string)
        var importedCredentials = false
        var importedIgneous = false
        let memberID = values[Defaults.Cookie.ipbMemberId]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let passHash = values[Defaults.Cookie.ipbPassHash]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let memberID, !memberID.isEmpty, let passHash, !passHash.isEmpty {
            for url in [Defaults.URL.ehentai, Defaults.URL.exhentai, Defaults.URL.sexhentai] {
                setOrEditCookie(for: url, key: Defaults.Cookie.ipbMemberId, value: memberID)
                setOrEditCookie(for: url, key: Defaults.Cookie.ipbPassHash, value: passHash)
            }
            importedCredentials = true
        }
        if let igneous = values[Defaults.Cookie.igneous]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !igneous.isEmpty,
           hasCredentials(for: Defaults.URL.ehentai) || hasCredentials(for: Defaults.URL.exhentai) {
            setOrEditCookie(for: Defaults.URL.exhentai, key: Defaults.Cookie.igneous, value: igneous)
            setOrEditCookie(for: Defaults.URL.sexhentai, key: Defaults.Cookie.igneous, value: igneous)
            importedIgneous = true
        }
        return importedCredentials || importedIgneous
    }
    private static func cookieValues(in string: String) -> [String: String] {
        let keys = [
            Defaults.Cookie.ipbMemberId,
            Defaults.Cookie.ipbPassHash,
            Defaults.Cookie.igneous
        ]
        var values = [String: String]()
        for key in keys {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                "\\b\(escapedKey)=\\s*([^;,\\s]+)",
                "\"\(escapedKey)\"\\s*:\\s*\"([^\"]+)\""
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(string.startIndex..., in: string)
                guard let match = regex.firstMatch(in: string, range: range),
                      let valueRange = Range(match.range(at: 1), in: string) else { continue }
                let value = String(string[valueRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty {
                    values[key] = value
                    break
                }
            }
        }
        return values
    }
    public func importCredentials(response: HTTPURLResponse) -> Bool {
        guard let url = response.url else { return false }
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String, let value = item.value as? String else { return }
            result[key] = value
        }
        return importAuthenticationCookies(
            HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        )
    }
    @discardableResult
    public func importWebViewCookies(_ cookies: [HTTPCookie]) -> Bool {
        let filteredCookies = cookies.filter(isSupportedWebViewCookie)
        filteredCookies.forEach(storeCookie)
        return importAuthenticationCookies(filteredCookies)
    }
    private func isSupportedWebViewCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "e-hentai.org" || domain.hasSuffix(".e-hentai.org")
            || domain == "exhentai.org" || domain.hasSuffix(".exhentai.org")
    }
    private func importAuthenticationCookies(_ cookies: [HTTPCookie]) -> Bool {
        var imported = false
        for cookie in cookies {
            let urls: [URL]
            switch cookie.name {
            case Defaults.Cookie.ipbMemberId, Defaults.Cookie.ipbPassHash:
                urls = [Defaults.URL.ehentai, Defaults.URL.exhentai, Defaults.URL.sexhentai]
            case Defaults.Cookie.igneous:
                urls = [Defaults.URL.exhentai, Defaults.URL.sexhentai]
            default:
                continue
            }
            let isExpired = cookie.expiresDate.map { $0 <= .now } ?? false
            if cookie.value.isEmpty || isExpired {
                urls.forEach { removeCookie($0, cookie.name) }
                continue
            }
            for url in urls where storeReplica(cookie, for: url) {
                imported = true
            }
        }
        return imported
    }
    public func setSkipServer(response: HTTPURLResponse) {
        guard let setString = response.allHeaderFields["Set-Cookie"] as? String else { return }
        setString.components(separatedBy: ", ")
            .flatMap { $0.components(separatedBy: "; ") }
            .forEach { value in
                let key = Defaults.Cookie.skipServer
                if let range = value.range(of: "\(key)=") {
                    setCookie(
                        for: Defaults.URL.host, key: key,
                        value: String(value[range.upperBound...]), path: "/s/"
                    )
                }
            }
    }
}

// MARK: API
public enum CookieClientKey: DependencyKey {
    public static let liveValue = CookieClient.live
    public static let previewValue = CookieClient.noop
    public static let testValue = CookieClient.unimplemented
}

extension DependencyValues {
    public var cookieClient: CookieClient {
        get { self[CookieClientKey.self] }
        set { self[CookieClientKey.self] = newValue }
    }
}

// MARK: Test
extension CookieClient {
    public static let noop: Self = .init(
        clearAll: {},
        getCookie: { _, _ in .empty },
        cookiesForURL: { _ in [] },
        removeCookie: { _, _ in },
        deleteCookie: { _ in },
        checkExistence: { _, _ in false },
        initializeCookie: { _, _ in .init() },
        storeCookie: { _ in },
        setCookieValue: { _, _, _, _, _, _ in }
    )

    public static func placeholder<Result>() -> Result { fatalError() }

    public static let unimplemented: Self = .init(
        clearAll: IssueReporting.unimplemented(placeholder: placeholder()),
        getCookie: IssueReporting.unimplemented(placeholder: placeholder()),
        cookiesForURL: IssueReporting.unimplemented(placeholder: placeholder()),
        removeCookie: IssueReporting.unimplemented(placeholder: placeholder()),
        deleteCookie: IssueReporting.unimplemented(placeholder: placeholder()),
        checkExistence: IssueReporting.unimplemented(placeholder: placeholder()),
        initializeCookie: IssueReporting.unimplemented(placeholder: placeholder()),
        storeCookie: IssueReporting.unimplemented(placeholder: placeholder()),
        setCookieValue: IssueReporting.unimplemented(placeholder: placeholder())
    )
}

#if DEBUG
private struct CookieClientTestingCookie: Sendable {
    public var domain: String
    public var path: String
    public var name: String
    public var value: String
    public var expiresDate: Date?
    public var isSessionOnly: Bool
    public var isSecure: Bool

    public func matches(url: URL, key: String? = nil) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        // Host-exact: the store only ever holds concrete-host cookies (never a wildcard `.domain`
        // one), so a subdomain query such as `s.exhentai.org` must NOT match an `exhentai.org`
        // cookie. A suffix match let a `syncExCookies` write to one host collaterally delete a
        // sibling host's login cookies (via `editCookie`'s remove-all-matching), nondeterministically.
        let normalizedDomain = domain.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainMatches = host == normalizedDomain
        let keyMatches = key.map { name == $0 } ?? true
        let pathMatches = url.path.hasPrefix(path)
        return domainMatches && keyMatches && pathMatches
    }

    public func httpCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value
        ]
        if isSessionOnly {
            properties[.discard] = "TRUE"
        } else if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }
}

private final class CookieClientTestingStore: Sendable {
    private let cookies: Mutex<[String: CookieClientTestingCookie]>

    public init(cookies: [String: CookieClientTestingCookie]) {
        self.cookies = Mutex(cookies)
    }

    public func value(for url: URL, key: String) -> String {
        cookie(for: url, key: key)?.value ?? ""
    }

    public func setValue(
        _ value: String,
        for url: URL,
        key: String,
        path: String = "/",
        expiresTime: TimeInterval = .oneYear,
        sessionOnly: Bool = false
    ) {
        guard let domain = url.host else { return }
        let cookie = CookieClientTestingCookie(
            domain: domain,
            path: path,
            name: key,
            value: value,
            expiresDate: sessionOnly ? nil : Date(timeIntervalSinceNow: expiresTime),
            isSessionOnly: sessionOnly,
            isSecure: false
        )
        cookies.withLock { $0[storageKey(domain: domain, path: path, key: key)] = cookie }
    }

    public func removeValue(for url: URL, key: String) {
        cookies.withLock { storage in
            storage = storage.filter { !$0.value.matches(url: url, key: key) }
        }
    }

    public func containsValue(for url: URL, key: String) -> Bool {
        cookie(for: url, key: key) != nil
    }

    public func cookies(for url: URL) -> [HTTPCookie] {
        cookies.withLock { storage in
            storage.values
                .filter { $0.matches(url: url) }
                .compactMap { $0.httpCookie() }
        }
    }

    public func store(_ cookie: HTTPCookie) {
        let testingCookie = CookieClientTestingCookie(
            domain: cookie.domain,
            path: cookie.path,
            name: cookie.name,
            value: cookie.value,
            expiresDate: cookie.expiresDate,
            isSessionOnly: cookie.isSessionOnly,
            isSecure: cookie.isSecure
        )
        cookies.withLock {
            $0[storageKey(domain: cookie.domain, path: cookie.path, key: cookie.name)] = testingCookie
        }
    }

    public func remove(_ cookie: HTTPCookie) {
        cookies.withLock {
            $0.removeValue(forKey: storageKey(domain: cookie.domain, path: cookie.path, key: cookie.name))
        }
    }

    public func removeAll() {
        cookies.withLock { $0.removeAll() }
    }

    private func cookie(for url: URL, key: String) -> CookieClientTestingCookie? {
        cookies.withLock { storage in
            storage.values
                .filter { $0.matches(url: url, key: key) }
                .sorted { $0.path.count > $1.path.count }
                .first
        }
    }

    private func storageKey(domain: String, path: String, key: String) -> String {
        "\(domain.lowercased())|\(path)|\(key)"
    }
}

extension CookieClient {
    public static func testing(
        memberID: String = "",
        passHash: String = "",
        igneous: String? = nil
    ) -> Self {
        let store = CookieClientTestingStore(cookies: [:])
        for url in [Defaults.URL.ehentai, Defaults.URL.exhentai, Defaults.URL.sexhentai] {
            if !memberID.isEmpty {
                store.setValue(memberID, for: url, key: Defaults.Cookie.ipbMemberId)
            }
            if !passHash.isEmpty {
                store.setValue(passHash, for: url, key: Defaults.Cookie.ipbPassHash)
            }
        }
        if let igneous, !igneous.isEmpty {
            for url in [Defaults.URL.exhentai, Defaults.URL.sexhentai] {
                store.setValue(igneous, for: url, key: Defaults.Cookie.igneous)
            }
        }

        return .init(
            clearAll: {
                store.removeAll()
            },
            getCookie: { url, key in
                cookieValue(in: store.cookies(for: url), key: key)
            },
            cookiesForURL: { url in
                store.cookies(for: url)
            },
            removeCookie: { url, key in
                store.removeValue(for: url, key: key)
            },
            deleteCookie: { cookie in
                store.remove(cookie)
            },
            checkExistence: { url, key in
                store.containsValue(for: url, key: key)
            },
            initializeCookie: { cookie, value in
                var properties = cookie.properties
                properties?[.value] = value
                return HTTPCookie(properties: properties ?? [:])
            },
            storeCookie: { cookie in
                store.store(cookie)
            },
            setCookieValue: { url, key, value, path, expiresTime, sessionOnly in
                store.setValue(
                    value,
                    for: url,
                    key: key,
                    path: path,
                    expiresTime: expiresTime,
                    sessionOnly: sessionOnly
                )
            }
        )
    }
}
#endif
