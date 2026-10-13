import CoreText
import Foundation
import UIKit

public final class MangaVerticalTextLabel: UIView {
    public var text: String = "" {
        didSet { setNeedsDisplay() }
    }

    private var fontSize: CGFloat = 14

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        isUserInteractionEnabled = false
    }

    public func fitFont() {
        fontSize = MangaVerticalTextCompositor.fittedFontSize(text: text, in: bounds.size) {
            UIFont.systemFont(ofSize: $0, weight: .medium) as CTFont
        }
        setNeedsDisplay()
    }

    public override func draw(_ rect: CGRect) {
        guard !text.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium) as CTFont
        MangaVerticalTextCompositor.draw(
            text: text, font: font, color: UIColor.black.cgColor, in: context, size: bounds.size
        )
    }
}
