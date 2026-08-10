//
//  CacheUtil.swift
//  EhPanda
//

import Foundation

enum CacheUtil {
    static func normalizedKey(from url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        // Remove query and fragment to normalize resource identity
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

extension URL {
    var cacheKey: String { CacheUtil.normalizedKey(from: self) }
}

extension Optional where Wrapped == URL {
    var cacheKey: String? { self.map { CacheUtil.normalizedKey(from: $0) } }
}
