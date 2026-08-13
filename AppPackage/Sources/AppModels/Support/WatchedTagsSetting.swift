import Foundation
import SwiftUI
import AppTools

public actor WatchedTagsSetting {
    public static let shared = WatchedTagsSetting()

    private var onlineTags: [Int: TagSetInfo] = [:]
    private var lastFetchedApuid: String = ""
    private var lastRefreshTimestamp: Date = .distantPast
    private var cachedLookup: [String: (tagSetBackgroundColor: Color?, tag: WatchedTag)] = [:]

    private init() {}

    public func updateTagSet(_ tagSet: TagSetInfo) {
        onlineTags[tagSet.number] = tagSet
    }

    public func updateTagSet(_ tagSet: TagSetInfo, apiuid: String) {
        onlineTags[tagSet.number] = tagSet
        lastFetchedApuid = apiuid
        lastRefreshTimestamp = Date()
    }

    public func buildTagLookup() -> [String: (tagSetBackgroundColor: Color?, tag: WatchedTag)] {
        if !cachedLookup.isEmpty { return cachedLookup }
        var lookup: [String: (Color?, WatchedTag)] = [:]
        for tagSetInfo in onlineTags.values {
            for tag in tagSetInfo.tags {
                let key = "\(tag.namespace):\(tag.key)"
                lookup[key] = (tagSetInfo.backgroundColor, tag)
            }
        }
        cachedLookup = lookup
        return cachedLookup
    }

    public func clearOnlineTagSets() {
        onlineTags.removeAll()
        cachedLookup.removeAll()
        lastFetchedApuid = ""
        lastRefreshTimestamp = .distantPast
    }

    public func needsRefresh(apiuid: String, maxAge: TimeInterval = 3600) -> Bool {
        return onlineTags.isEmpty || lastFetchedApuid != apiuid || isStale(maxAge: maxAge)
    }

    public func isStale(maxAge: TimeInterval = 3600) -> Bool {
        return Date().timeIntervalSince(lastRefreshTimestamp) > maxAge
    }

    public func allTagSets() -> [TagSetInfo] {
        Array(onlineTags.values).sorted { $0.number < $1.number }
    }
}
