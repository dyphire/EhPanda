import Foundation
import UIKit

public final class MangaOverlayView: UIView {
    private var result: MangaPageTranslation?
    private var visible = true
    private var direction: MangaTranslationTextDirection = .auto
    private var sourceImageID: ObjectIdentifier?
    private var regionColors: [CGColor] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        isHidden = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        clipsToBounds = true
        isHidden = true
    }

    public func update(
        result: MangaPageTranslation?,
        visible: Bool,
        direction: MangaTranslationTextDirection,
        image: UIImage?
    ) {
        self.visible = visible
        let directionChanged = self.direction != direction
        self.direction = direction
        let imageID = image.map { ObjectIdentifier($0) }
        let imageChanged = imageID != sourceImageID
        sourceImageID = imageID
        if result != self.result || directionChanged || imageChanged {
            self.result = result
            regionColors = sampleColors(for: result, image: image)
            subviews.forEach { $0.removeFromSuperview() }
            if let result {
                for (index, region) in result.regions.enumerated() {
                    let container = UIView()
                    container.isUserInteractionEnabled = false

                    let bubbleBackground = MangaBubbleBackgroundView()
                    bubbleBackground.fillColor = UIColor(cgColor: regionColors[index])
                    container.addSubview(bubbleBackground)

                    if direction.usesVerticalLayout(for: region, targetLanguage: result.targetLanguage) {
                        let bubble = MangaVerticalTextLabel()
                        bubble.text = region.translatedText ?? region.text
                        container.addSubview(bubble)
                    } else {
                        let bubble = UILabel()
                        bubble.text = region.translatedText ?? region.text
                        bubble.font = .systemFont(ofSize: 14, weight: .medium)
                        bubble.textColor = .black
                        bubble.textAlignment = .center
                        bubble.numberOfLines = 0
                        bubble.lineBreakMode = .byWordWrapping
                        bubble.adjustsFontSizeToFitWidth = true
                        bubble.minimumScaleFactor = 0.5
                        bubble.backgroundColor = .clear
                        bubble.isUserInteractionEnabled = false
                        container.addSubview(bubble)
                    }

                    addSubview(container)
                }
            }
        }
        isHidden = result == nil || !visible
        setNeedsLayout()
    }

    public func clear() {
        result = nil
        sourceImageID = nil
        regionColors = []
        subviews.forEach { $0.removeFromSuperview() }
        isHidden = true
    }

    private func sampleColors(for result: MangaPageTranslation?, image: UIImage?) -> [CGColor] {
        guard let result else { return [] }
        let normalized = image.flatMap(MangaBubbleBackground.normalizedCGImage(from:))
        return result.regions.map { region in
            let sampled = normalized.flatMap {
                MangaBubbleBackground.backgroundColor(in: $0, normalizedBox: region.box)
            }
            return sampled ?? UIColor.white.cgColor
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let result else { return }
        for (index, container) in subviews.enumerated() {
            guard index < result.regions.count else { continue }
            let region = result.regions[index]
            container.frame = CGRect(
                x: region.box.minX * bounds.width - 2,
                y: region.box.minY * bounds.height - 2,
                width: region.box.width * bounds.width + 4,
                height: region.box.height * bounds.height + 4
            )

            let cornerRadius = min(32, max(12, min(container.bounds.width, container.bounds.height) * 0.4))
            let feather = MangaBubbleBackground.feather(forCoreSize: container.bounds.size)
            if let bubbleBackground = container.subviews.first(where: {
                $0 is MangaBubbleBackgroundView
            }) as? MangaBubbleBackgroundView {
                bubbleBackground.frame = container.bounds.insetBy(dx: -feather, dy: -feather)
                bubbleBackground.cornerRadius = cornerRadius
                bubbleBackground.feather = feather
            }

            let textFrame = container.bounds.insetBy(
                dx: min(5, max(2, container.bounds.width * 0.04)),
                dy: min(4, max(1, container.bounds.height * 0.03))
            )
            guard
                let child = container.subviews.first(where: {
                    $0 is UILabel || $0 is MangaVerticalTextLabel
                })
            else { continue }
            child.frame = CGRect(
                x: textFrame.minX,
                y: textFrame.minY,
                width: max(0, textFrame.width),
                height: max(0, textFrame.height)
            )
            if let bubble = child as? UILabel {
                fitFont(for: bubble)
            } else if let bubble = child as? MangaVerticalTextLabel {
                bubble.fitFont()
            }
        }
    }

    private func fitFont(for bubble: UILabel) {
        guard bubble.bounds.width > 0, bubble.bounds.height > 0 else { return }
        var fontSize = min(17, max(12, bubble.bounds.height * 0.35))
        for _ in 0..<4 {
            bubble.font = .systemFont(ofSize: fontSize, weight: .medium)
            let neededSize = bubble.sizeThatFits(
                CGSize(width: bubble.bounds.width, height: .greatestFiniteMagnitude)
            )
            if neededSize.height <= bubble.bounds.height + 0.5 { break }
            let scale = max(0.7, bubble.bounds.height / max(neededSize.height, 1))
            let nextSize = max(8, fontSize * scale)
            if nextSize == fontSize { break }
            fontSize = nextSize
        }
        bubble.font = .systemFont(ofSize: fontSize, weight: .medium)
    }
}
