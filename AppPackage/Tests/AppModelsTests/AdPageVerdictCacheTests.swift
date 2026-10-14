import Foundation
import Testing
import AppModels

@Suite
struct AdPageVerdictCacheTests {
    @Test
    func recordedVerdictsAreReadBack() {
        var cache = AdPageVerdictCache()
        cache.record(gid: "1", pageIndex: 199, isAd: true)
        cache.record(gid: "1", pageIndex: 200, isAd: false)
        #expect(cache.verdict(gid: "1", pageIndex: 199) == true)
        #expect(cache.verdict(gid: "1", pageIndex: 200) == false)
        #expect(cache.adPageIndices(gid: "1") == [199])
        #expect(cache.verdict(gid: "2", pageIndex: 199) == nil)
    }

    @Test
    func theOldestGalleryIsEvictedAtTheCap() {
        var cache = AdPageVerdictCache()
        for gid in 1...AdPageVerdictCache.galleryCap {
            cache.record(gid: String(gid), pageIndex: 1, isAd: true)
        }
        cache.record(gid: "overflow", pageIndex: 1, isAd: true)
        #expect(cache.verdicts.count == AdPageVerdictCache.galleryCap)
        #expect(cache.verdict(gid: "1", pageIndex: 1) == nil)
        #expect(cache.verdict(gid: "overflow", pageIndex: 1) == true)
    }

    @Test
    func touchingAGalleryRefreshesItsRecency() {
        var cache = AdPageVerdictCache()
        for gid in 1...AdPageVerdictCache.galleryCap {
            cache.record(gid: String(gid), pageIndex: 1, isAd: true)
        }
        cache.record(gid: "1", pageIndex: 2, isAd: false)
        cache.record(gid: "overflow", pageIndex: 1, isAd: true)
        #expect(cache.verdict(gid: "1", pageIndex: 1) == true)
        #expect(cache.verdict(gid: "2", pageIndex: 1) == nil)
    }

    @Test
    func valuesRoundTripThroughCodable() throws {
        var cache = AdPageVerdictCache()
        cache.record(gid: "1", pageIndex: 199, isAd: true)
        cache.recordAdImageHash("abc")
        let decoded = try JSONDecoder().decode(
            AdPageVerdictCache.self, from: JSONEncoder().encode(cache)
        )
        #expect(decoded == cache)
    }

    @Test
    func adImageHashesAreRecordedAndMatched() {
        var cache = AdPageVerdictCache()
        cache.recordAdImageHash("abc")
        #expect(cache.containsAdImageHash("abc"))
        #expect(!cache.containsAdImageHash("def"))
        #expect(cache.adImageHashSet == ["abc"])
    }

    @Test
    func anEmptyHashIsNeverRecorded() {
        var cache = AdPageVerdictCache()
        cache.recordAdImageHash("")
        #expect(cache.adImageHashes == nil)
    }

    @Test
    func recordingAHashTwiceRefreshesItsRecency() {
        var cache = AdPageVerdictCache()
        for index in 0..<AdPageVerdictCache.adImageHashCap {
            cache.recordAdImageHash(String(index))
        }
        cache.recordAdImageHash("0")
        cache.recordAdImageHash("overflow")
        #expect(cache.containsAdImageHash("0"))
        #expect(!cache.containsAdImageHash("1"))
        #expect(cache.adImageHashes?.count == AdPageVerdictCache.adImageHashCap)
    }

    @Test
    func aBlobFromBeforeTheHashFieldStillDecodes() throws {
        // `adImageHashes` is an additive optional: a blob written before it existed
        // must keep decoding rather than resetting the whole cache.
        let json = #"{"schemaVersion": 1, "verdicts": {}, "recentGids": []}"#
        let cache = try JSONDecoder().decode(AdPageVerdictCache.self, from: Data(json.utf8))
        #expect(cache.adImageHashes == nil)
        #expect(cache.adImageHashSet.isEmpty)
    }
}
