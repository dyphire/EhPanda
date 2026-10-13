import Sharing
import SwiftUI
import UIKit

/// Hosts the bubble overlay on the aspect-fitted page image: SwiftUI sizes
/// this representable to the displayed image rect, and regions are
/// normalized in that same coordinate space, so no manual geometry is needed.
public struct MangaTranslationOverlay: UIViewRepresentable {
    @SharedReader(.mangaTranslationPreferences) private var preferences

    private let result: MangaPageTranslation?
    private let isVisible: Bool
    private let image: UIImage?

    public init(
        result: MangaPageTranslation?,
        isVisible: Bool,
        image: UIImage?
    ) {
        self.result = result
        self.isVisible = isVisible
        self.image = image
    }

    public func makeUIView(context: Context) -> MangaOverlayView {
        MangaOverlayView()
    }

    public func updateUIView(_ uiView: MangaOverlayView, context: Context) {
        uiView.update(
            result: result,
            visible: isVisible,
            direction: preferences.textDirection,
            image: image
        )
    }
}
