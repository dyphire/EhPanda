import SwiftUI
import UIKit
import VisionKit
import OSLogExt

private let liveTextLogger = Logger(category: "LiveText")

// Live Text overlay hosted per reader page. SwiftUI sizes this representable
// to the aspect-fitted image rect, so the inner image view's frame matches the
// displayed pixels exactly and VisionKit can map its analysis onto the view
// without any manual coordinate math.
struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage?
    let isEnabled: Bool

    func makeUIView(context: Context) -> LiveTextContainerView {
        LiveTextContainerView()
    }

    func updateUIView(_ uiView: LiveTextContainerView, context: Context) {
        uiView.apply(image: image, isEnabled: isEnabled)
    }
}

// MARK: LiveTextContainerView
final class LiveTextContainerView: UIView {
    private let imageView = UIImageView()
    private let interaction = ImageAnalysisInteraction()
    private var analysisTask: Task<Void, Never>?
    private var analyzedImage: UIImage?
    private var analysisRequestID: UInt64 = 0
    private var enabled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    isolated deinit {
        analysisTask?.cancel()
    }

    func apply(image: UIImage?, isEnabled: Bool) {
        enabled = isEnabled
        imageView.image = image
        guard isEnabled, image != nil else {
            removeInteractionIfNeeded()
            resetAnalysis()
            return
        }
        if imageView.interactions.isEmpty {
            imageView.addInteraction(interaction)
        }
        analyzeImageIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard enabled else { return }
        if window != nil {
            analyzeImageIfNeeded()
        } else {
            // Scrolled out of the hierarchy: cancel an in-flight request and drop its
            // bookkeeping so re-entry re-analyzes; a finished result stays attached.
            analysisTask?.cancel()
            analysisTask = nil
            if interaction.analysis == nil {
                analyzedImage = nil
            }
        }
    }

    private func analyzeImageIfNeeded() {
        guard enabled, let image = imageView.image, window != nil, image !== analyzedImage else { return }

        analyzedImage = image
        analysisTask?.cancel()
        let requestID = nextAnalysisRequestID()
        analysisTask = Task { [weak self] in
            let configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
            do {
                let analysis = try await ImageAnalyzer.readerShared.analyze(image, configuration: configuration)
                try Task.checkCancellation()
                guard let self, self.analysisRequestID == requestID else { return }
                self.interaction.analysis = analysis
                self.interaction.preferredInteractionTypes = .automatic
                self.analysisTask = nil
                liveTextLogger.debug("Finished Live Text analysis")
            } catch is CancellationError {
            } catch {
                guard let self, self.analysisRequestID == requestID else { return }
                self.analysisTask = nil
                liveTextLogger.error("Live Text analysis failed: \(error, privacy: .public)")
            }
        }
    }

    private func resetAnalysis() {
        _ = nextAnalysisRequestID()
        analysisTask?.cancel()
        analysisTask = nil
        analyzedImage = nil
        interaction.analysis = nil
        interaction.preferredInteractionTypes = []
    }

    private func removeInteractionIfNeeded() {
        if !imageView.interactions.isEmpty {
            imageView.removeInteraction(interaction)
        }
    }

    private func nextAnalysisRequestID() -> UInt64 {
        analysisRequestID &+= 1
        return analysisRequestID
    }
}

private extension ImageAnalyzer {
    static let readerShared = ImageAnalyzer()
}
