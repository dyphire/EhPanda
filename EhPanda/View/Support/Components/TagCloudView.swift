//
//  TagCloudView.swift
//  EhPanda
//
//  Copied from https://stackoverflow.com/questions/62102647/
//

import SwiftUI
import Kingfisher

struct TagCloudView<Element, ID, TagCell>: View
where TagCell: View, Element: Equatable & Identifiable, ID == Element.ID {
    private let data: [Element]
    private let id: KeyPath<Element, ID>
    private let spacing: Double
    private let content: (Element) -> TagCell

    @State private var totalHeight: CGFloat = .zero
    @State private var availableWidth: CGFloat = .zero

    init<Data: RandomAccessCollection>(
        data: Data, id: KeyPath<Element, ID> = \Element.id, spacing: Double = 4,
        @ViewBuilder content: @escaping (Element) -> TagCell
    ) where Data.Index == Int, Data.Element == Element {
        self.data = .init(data)
        self.id = id
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        let cloud = Group {
            var width = CGFloat.zero
            var height = CGFloat.zero
            ForEach(data, id: id) { element in
                self.content(element)
                    .padding([.trailing, .bottom], spacing)
                    .alignmentGuide(.leading, computeValue: { dimensions in
                        let proxyWidth = max(availableWidth, 1)
                        if abs(width - dimensions.width) > proxyWidth {
                            width = 0
                            height -= dimensions.height
                        }
                        let result = width
                        if element == data.last {
                            width = 0
                        } else {
                            width -= dimensions.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: { _ in
                        let result = height
                        if element == data.last {
                            height = 0
                        }
                        return result
                    })
            }
        }
        return cloud
            .frame(height: totalHeight)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self) { size in
            if availableWidth != size.width {
                availableWidth = size.width
            }
            totalHeight = size.height
        }
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct TagCloudCell: View {
    private let text: String
    private let imageURL: URL?
    private let showsImages: Bool
    private let font: Font
    private let padding: EdgeInsets
    private let textColor: Color
    private let backgroundColor: Color

    init(
        text: String, imageURL: URL?, showsImages: Bool, font: Font,
        padding: EdgeInsets, textColor: Color, backgroundColor: Color
    ) {
        self.text = text
        self.imageURL = imageURL
        self.showsImages = showsImages
        self.font = font
        self.padding = padding
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(showsImages ? text : text.emojisRipped)
            if let imageURL = imageURL, showsImages {
                Image(systemSymbol: .photo).opacity(0)
                    .overlay(KFImage(imageURL).resizable().scaledToFit())
            }
        }
        .font(font.bold()).lineLimit(1).foregroundColor(textColor)
        .padding(padding).background(backgroundColor).cornerRadius(5)
    }
}
