import Foundation

/// Per-gallery ad-page detection verdicts, shared by the previews grid, the reader, and
/// the download engine so a page is scanned once no matter which surface triggered it.
///
/// Verdicts are disposable derived data — re-scanning a cached thumbnail is cheap. The
/// cache is capped (`galleryCap`, FIFO) per the bounded-app-storage policy in
/// `AppSharedKeys`.
public struct AdPageVerdictCache: Codable, Equatable, Sendable, SchemaVersioned {
    public static let galleryCap = 200
    public static let adImageHashCap = 500

    public init() {}

    /// This model's schema history (oldest → newest); see `SchemaVersioned` / `VersionedSchema`.
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    /// The v1 base schema. Its `migrate` is empty — nothing precedes v1, and the engine only runs
    /// schemas newer than the stored version, so it exists solely to anchor version 1.
    enum SchemaV1: VersionedSchema {
        static let version = 1
        static func migrate(_ object: inout [String: JSONValue]) throws {}
    }
    public var schemaVersion: SchemaVersion<AdPageVerdictCache> = 1

    /// gid → (1-based page index → is-ad verdict). Negative verdicts are recorded too,
    /// so a clean page is never re-scanned.
    public private(set) var verdicts: [String: [Int: Bool]] = [:]
    /// Most-recently-touched gids, oldest first; drives FIFO eviction at `galleryCap`.
    public private(set) var recentGids: [String] = []
    /// Pixel hashes of detected ad images, most recent last; FIFO-capped. A page whose
    /// thumbnail hashes to a known entry is an ad without further detection — ad images
    /// are byte-identical across galleries. Optional per the additive-field convention
    /// (`AppSharedKeys`): blobs from before this key existed keep decoding.
    public private(set) var adImageHashes: [String]?

    public func verdict(gid: String, pageIndex: Int) -> Bool? {
        verdicts[gid]?[pageIndex]
    }

    /// All recorded verdicts for the gallery (both polarities) — the download engine
    /// reads this to skip re-scanning judged pages.
    public func verdicts(gid: String) -> [Int: Bool] {
        verdicts[gid] ?? [:]
    }

    /// Ad pages currently on record for the gallery, *without* neighbour backfilling —
    /// consumers apply `AdPageDetector.backfilled` so the widening rule lives in one place.
    public func adPageIndices(gid: String) -> Set<Int> {
        Set(verdicts[gid]?.filter(\.value).map(\.key) ?? [])
    }

    /// The display-ready ad set: recorded positives widened by neighbour backfilling.
    public func displayAdIndices(gid: String, pageCount: Int) -> Set<Int> {
        AdPageDetector.backfilled(adPageIndices(gid: gid), pageCount: pageCount)
    }

    public mutating func record(gid: String, pageIndex: Int, isAd: Bool) {
        verdicts[gid, default: [:]][pageIndex] = isAd
        recentGids.removeAll { $0 == gid }
        recentGids.append(gid)
        while recentGids.count > Self.galleryCap {
            let evicted = recentGids.removeFirst()
            verdicts[evicted] = nil
        }
    }

    public var adImageHashSet: Set<String> {
        Set(adImageHashes ?? [])
    }

    public func containsAdImageHash(_ hash: String) -> Bool {
        adImageHashes?.contains(hash) == true
    }

    public mutating func recordAdImageHash(_ hash: String) {
        guard !hash.isEmpty else { return }
        var hashes = adImageHashes ?? []
        hashes.removeAll { $0 == hash }
        hashes.append(hash)
        while hashes.count > Self.adImageHashCap {
            hashes.removeFirst()
        }
        adImageHashes = hashes
    }
}

/// What the download engine needs up front for ad-page detection: per-page verdicts for
/// this gallery plus every known ad-image hash. One value so the provider closure makes
/// a single round trip into the shared cache.
public struct AdPageVerdictSnapshot: Equatable, Sendable {
    public var verdicts: [Int: Bool]
    public var adImageHashes: Set<String>

    public init(verdicts: [Int: Bool] = [:], adImageHashes: Set<String> = []) {
        self.verdicts = verdicts
        self.adImageHashes = adImageHashes
    }
}
