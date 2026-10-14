import ComposableArchitecture
import Foundation
import ImageClient
import Observation
import Sharing
import UIKit

/// Per-reading-session translation queue. The current page goes first, the
/// next page is prefetched, and every finished result is shared with the
/// overlay layer through `result(for:)`.
@Observable
@MainActor
public final class MangaTranslationHandler {
    /// Translated pages take a lot of memory only as text regions, so the
    /// session cache can be generous; eviction is FIFO.
    private static let resultCacheLimit = 80
    /// Pages translated ahead of the current one while the queue is idle.
    private static let prefetchItemCount = 1

    public private(set) var isEnabled = false
    public private(set) var phase: MangaTranslationPhase = .idle
    public var showTranslation = true

    private var results: [Int: MangaPageTranslation] = [:]
    private var resultOrder: [Int] = []

    private var queueTask: Task<Void, Never>?
    private var queueID = UUID()
    private var queueSnapshot: [Int] = []
    private var inFlightIndex: Int?

    private var gid = ""
    private var pageCount = 0
    private var currentIndex = 0
    private var isOffline = false
    private var metadata: MangaTranslationMetadata?
    public var imageURLForIndex: @MainActor (Int) -> URL? = { _ in nil }
    /// Live lookup into the reader's ad-page set; ad pages are never queued for
    /// translation (OCR + provider calls on them would be pure waste).
    public var isAdPage: @MainActor (Int) -> Bool = { _ in false }
    public var onFailure: (MangaTranslationFailure) -> Void = { _ in }

    @ObservationIgnored
    @Dependency(\.imageClient) private var imageClient

    public init() {
        @Shared(.mangaTranslationPreferences) var preferences
        showTranslation = preferences.showTranslation
    }

    public func result(for index: Int) -> MangaPageTranslation? {
        results[index]
    }

    /// Same-language sessions are a no-op, resolved before any model preparation or
    /// image fetch: no detection, no recognition, no provider call.
    private var needsTranslation: Bool {
        @Shared(.mangaTranslationPreferences) var preferences
        let languages = MangaTranslationConfiguration.resolvedLanguages(
            metadata: metadata, preferences: preferences
        )
        return !MangaTranslationLanguage.isSameLanguage(
            languages.sourceLanguage, languages.targetLanguage
        )
    }

    /// Scalar session facts. The closure lookups (`imageURLForIndex`, `isAdPage`,
    /// `onFailure`) are public vars assigned directly by the caller — folding them in
    /// here would push the signature past the parameter-count lint limit.
    public func setContext(
        gid: String,
        pageCount: Int,
        isOffline: Bool,
        metadata: MangaTranslationMetadata?
    ) {
        self.gid = gid
        self.pageCount = pageCount
        self.isOffline = isOffline
        self.metadata = metadata
    }

    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if !enabled {
            cancelAll()
        }
    }

    /// Manual button: translate the current page now (retrying it if a result
    /// already exists), then continue the queue.
    public func translatePage(_ index: Int) {
        guard isEnabled, needsTranslation else { return }
        guard !phase.isBusy else { return }
        currentIndex = index
        if results[index] != nil {
            results.removeValue(forKey: index)
            resultOrder.removeAll { $0 == index }
        }
        startQueue(indices: desiredIndices(currentIndex: index, includeCachedFront: true))
    }

    public func toggleVisibility() {
        showTranslation.toggle()
        @Shared(.mangaTranslationPreferences) var preferences
        guard preferences.showTranslation != showTranslation else { return }
        $preferences.withLock { $0.showTranslation = showTranslation }
    }

    public func syncQueue(currentIndex index: Int) {
        currentIndex = index
        guard isEnabled, gid != "" else { return }
        guard needsTranslation else {
            stopQueue()
            phase = .idle
            return
        }
        let indices = desiredIndices(currentIndex: index)
        if indices == pendingQueueIndices(), queueTask != nil { return }
        if let front = indices.first, front == index, let cached = results[index] {
            phase = phase(for: cached)
        }
        guard !indices.isEmpty else {
            stopQueue()
            return
        }
        startQueue(indices: indices)
    }

    public func cancelAll() {
        stopQueue()
        results = [:]
        resultOrder = []
        phase = .idle
    }

    /// Provider configuration edits are invisible to the session cache, so a
    /// settings-sheet dismissal clears and re-runs the session wholesale.
    public func refreshConfiguration() {
        guard isEnabled else { return }
        cancelAll()
        syncQueue(currentIndex: currentIndex)
    }

    // MARK: Queue

    private func desiredIndices(currentIndex index: Int, includeCachedFront: Bool = false) -> [Int] {
        var indices: [Int] = []
        guard index >= 1, index <= pageCount else { return indices }
        if !isAdPage(index), includeCachedFront || results[index] == nil {
            indices.append(index)
        }
        var next = index + 1
        var visited = 0
        while next <= pageCount, visited < Self.prefetchItemCount {
            // Ad pages are skipped without consuming the prefetch budget, so the
            // lookahead still reaches the next real page past an ad block.
            if isAdPage(next) {
                next += 1
                continue
            }
            visited += 1
            if results[next] == nil, !indices.contains(next) {
                indices.append(next)
            }
            next += 1
        }
        return indices
    }

    /// Work the running queue still owes, including the item being processed.
    private func pendingQueueIndices() -> [Int] {
        var indices = queueSnapshot
        if let inFlightIndex {
            indices.insert(inFlightIndex, at: 0)
        }
        return indices
    }

    private func startQueue(indices: [Int]) {
        stopQueue()
        queueID = UUID()
        queueSnapshot = indices
        showTranslation = true
        if indices.first == currentIndex {
            phase = .preparingModels
        }
        let id = queueID
        queueTask = Task { [weak self] in
            await self?.runQueue(id: id)
        }
    }

    private func stopQueue() {
        queueTask?.cancel()
        queueTask = nil
        queueSnapshot = []
        inFlightIndex = nil
    }

    private func isCurrentQueue(_ id: UUID) -> Bool {
        queueID == id && !Task.isCancelled
    }

    private func runQueue(id: UUID) async {
        while !queueSnapshot.isEmpty {
            guard isCurrentQueue(id) else { return }
            let index = queueSnapshot.removeFirst()
            // Defence in depth: the snapshot may predate a detection that landed while
            // the queue was running.
            if results[index] != nil || isAdPage(index) { continue }
            inFlightIndex = index
            await processItem(index, queueID: id)
            if inFlightIndex == index {
                inFlightIndex = nil
            }
        }
        guard isCurrentQueue(id) else { return }
        queueTask = nil
    }

    /// Drops cached translations for pages newly flagged as ads (detection lands after
    /// the fact) and resets the phase when the current page's result went away.
    public func discardResults(for indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        for index in indices {
            results.removeValue(forKey: index)
            resultOrder.removeAll { $0 == index }
        }
        if indices.contains(currentIndex), results[currentIndex] == nil, !phase.isBusy {
            phase = .idle
        }
    }

    /// Only the page the user is looking at reports failures and phase; the
    /// rest of the queue is pure prefetch and stays silent.
    private func processItem(_ index: Int, queueID id: UUID) async {
        let reportsToUI = index == currentIndex
        do {
            guard
                let configuration = try await MangaTranslationConfiguration.current(
                    metadata: metadata,
                    isOffline: isOffline
                )
            else {
                throw MangaTranslationFailure.modelPreparation
            }
            guard isCurrentQueue(id) else { return }
            guard let imageURL = imageURLForIndex(index) else {
                throw MangaTranslationFailure.inference
            }
            // Cached bytes make this a cache hit; a not-yet-downloaded page is
            // fetched here so the translation never depends on view lifecycle.
            guard let asset = await imageClient.fetchReaderImageAsset(url: imageURL), !asset.isAnimated else {
                throw MangaTranslationFailure.inference
            }
            guard isCurrentQueue(id) else { return }
            let key = MangaTranslationPageKey(
                galleryID: gid,
                pageNumber: index,
                sourceSignature: MangaSignature.make([
                    "url": imageURL.absoluteString,
                    "bytes": String(asset.data.count)
                ]),
                providerSignature: configuration.providerSignature,
                modelSignature: configuration.modelSignature
            )
            guard let cgImage = asset.image.cgImage else {
                throw MangaTranslationFailure.inference
            }
            let result = try await MangaTranslationService.shared.translate(
                key: key,
                image: cgImage,
                configuration: configuration,
                onProgress: { [weak self] phase in
                    guard let self else { return }
                    await self.updatePhase(phase, for: index, queueID: id)
                }
            )
            guard isCurrentQueue(id) else { return }
            if result.isFinalized {
                storeResult(result, for: index)
                if reportsToUI {
                    reportFailure(result.status.failure)
                }
            } else {
                let failure = result.status.failure ?? .inference
                if reportsToUI {
                    phase = failure == .noText ? .noText : .failed(failure)
                    reportFailure(failure)
                }
            }
        } catch let error as MangaTranslationFailure {
            guard isCurrentQueue(id) else { return }
            if reportsToUI {
                phase = error == .noText ? .noText : .failed(error)
                reportFailure(error)
            }
        } catch {
            guard isCurrentQueue(id) else { return }
            if reportsToUI {
                phase = .failed(.inference)
                reportFailure(.inference)
            }
        }
    }

    private func storeResult(_ result: MangaPageTranslation, for index: Int) {
        if results[index] == nil {
            resultOrder.append(index)
        }
        results[index] = result
        let overflow = resultOrder.count - Self.resultCacheLimit
        if overflow > 0 {
            for evicted in resultOrder.prefix(overflow) {
                results.removeValue(forKey: evicted)
            }
            resultOrder.removeFirst(overflow)
        }
        if index == currentIndex {
            phase = phase(for: result)
        }
    }

    private func reportFailure(_ failure: MangaTranslationFailure?) {
        guard let failure, failure.notifiesDuringAutomaticTranslation else { return }
        onFailure(failure)
    }

    private func phase(for result: MangaPageTranslation) -> MangaTranslationPhase {
        if result.isTranslated { return .completed }
        let failure = result.status.failure ?? .inference
        return failure == .noText ? .noText : .failed(failure)
    }

    private func updatePhase(
        _ phase: MangaTranslationPhase,
        for index: Int,
        queueID id: UUID
    ) {
        guard isCurrentQueue(id), index == currentIndex else { return }
        self.phase = phase
    }
}
