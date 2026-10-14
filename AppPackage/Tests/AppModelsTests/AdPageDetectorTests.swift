import Foundation
import Testing
import UIKit
import AppModels

@Suite
struct AdPageDetectorTests {
    private func makePageData(
        background: UIColor, size: CGSize = CGSize(width: 600, height: 800)
    ) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }

    @Test
    func aMonochromePageIsNeverAnAd() throws {
        let data = try #require(makePageData(background: .white))
        #expect(!AdPageDetector.isAdPage(imageData: data))
    }

    @Test
    func aColoredPageWithoutAQRCodeIsNotAnAd() throws {
        let data = try #require(makePageData(background: .red))
        #expect(!AdPageDetector.isAdPage(imageData: data))
    }

    @Test
    func undecodableDataIsNotAnAd() {
        #expect(!AdPageDetector.isAdPage(imageData: Data("not an image".utf8)))
    }

    @Test
    func identicalImagesProduceIdenticalHashes() throws {
        let firstData = try #require(makePageData(background: .red))
        let secondData = try #require(makePageData(background: .red))
        let first = try #require(UIImage(data: firstData)?.cgImage)
        let second = try #require(UIImage(data: secondData)?.cgImage)
        let firstHash = AdPageDetector.imageHash(for: first)
        #expect(!firstHash.isEmpty)
        #expect(firstHash == AdPageDetector.imageHash(for: second))
    }

    @Test
    func differentImagesProduceDifferentHashes() throws {
        let redData = try #require(makePageData(background: .red))
        let blueData = try #require(makePageData(background: .blue))
        let red = try #require(UIImage(data: redData)?.cgImage)
        let blue = try #require(UIImage(data: blueData)?.cgImage)
        #expect(AdPageDetector.imageHash(for: red) != AdPageDetector.imageHash(for: blue))
    }

    @Test
    func tailWindowCoversTheLastTenPages() {
        #expect(AdPageDetector.tailWindowIndices(pageCount: 200) == Array(191...200))
        #expect(AdPageDetector.tailWindowIndices(pageCount: 3) == [1, 2, 3])
        #expect(AdPageDetector.tailWindowIndices(pageCount: 0) == [])
    }

    @Test
    func backfillCatchesSandwichedPages() {
        let detected: Set<Int> = [198, 200]
        #expect(AdPageDetector.backfilled(detected, pageCount: 200) == [198, 199, 200])
    }

    @Test
    func backfillCascadesToTheEndAfterAnAdRun() {
        // Ads cluster at the tail: once two consecutive ads are seen, everything after
        // is assumed part of the same ad block even without per-page QR evidence.
        let detected: Set<Int> = [191, 192]
        #expect(AdPageDetector.backfilled(detected, pageCount: 200) == Set(191...200))
    }

    @Test
    func backfillCatchesPagesFollowingAnAdRun() {
        let detected: Set<Int> = [198, 199]
        #expect(AdPageDetector.backfilled(detected, pageCount: 200) == [198, 199, 200])
    }

    @Test
    func backfillLeavesIsolatedSinglesAlone() {
        let detected: Set<Int> = [195, 200]
        #expect(AdPageDetector.backfilled(detected, pageCount: 200) == detected)
    }

    @Test
    func backfillOfAnEmptySetIsEmpty() {
        #expect(AdPageDetector.backfilled([], pageCount: 200).isEmpty)
    }
}
