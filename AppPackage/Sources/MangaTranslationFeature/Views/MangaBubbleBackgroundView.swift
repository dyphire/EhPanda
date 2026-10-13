import Foundation
import UIKit

public final class MangaBubbleBackgroundView: UIView {
    public var fillColor: UIColor = .white {
        didSet { if fillColor != oldValue { setNeedsLayout() } }
    }
    public var cornerRadius: CGFloat = 12 {
        didSet { if cornerRadius != oldValue { setNeedsLayout() } }
    }
    public var feather: CGFloat = 10 {
        didSet { if feather != oldValue { setNeedsLayout() } }
    }

    private var renderedSize: CGSize?
    private var renderedColor: UIColor?
    private var renderedCornerRadius: CGFloat = 0
    private var renderedFeather: CGFloat = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.contentsGravity = .resize
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.contentsGravity = .resize
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else {
            layer.contents = nil
            renderedSize = nil
            return
        }
        guard
            size != renderedSize || fillColor != renderedColor || cornerRadius != renderedCornerRadius
                || feather != renderedFeather
        else { return }
        renderedSize = size
        renderedColor = fillColor
        renderedCornerRadius = cornerRadius
        renderedFeather = feather
        layer.contents = MangaBubbleBackground.blobImage(
            size: size, feather: feather, cornerRadius: cornerRadius, color: fillColor.cgColor)
    }
}
