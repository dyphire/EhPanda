//
//  GalleryHistoryCell.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

struct GalleryHistoryCell: View {
    private let gallery: Gallery

    init(gallery: Gallery) {
        self.gallery = gallery
    }

    var body: some View {
        HStack(spacing: 20) {
            KFImage(gallery.coverURL)
                .placeholder { Placeholder(style: .activity(ratio: Defaults.ImageSize.headerAspect)) }.defaultModifier()
                .scaledToFill().frame(width: Defaults.ImageSize.rowW * 0.75, height: Defaults.ImageSize.rowH * 0.75)
                .cornerRadius(2)
            VStack(alignment: .leading) {
                Text(gallery.trimmedTitle).bold().lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let uploader = gallery.uploader {
                    Text(uploader).foregroundColor(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                        if gallery.readingProgress > 0 {
                            ReadingProgressRing(progress: gallery.readingProgress, pageCount: gallery.pageCount)
                        }
                    Spacer()
                    RatingView(rating: gallery.rating, highlighted: gallery.hasRated)
                }
            }
            .font(.caption)
            Spacer()
        }
        .frame(width: Defaults.ImageSize.rowW * 3, height: Defaults.ImageSize.rowH * 0.75)
    }
}

private struct ReadingProgressRing: View {
    let progress: Int
    let pageCount: Int

    var body: some View {
        let fraction = pageCount > 0 ? Double(min(progress, pageCount)) / Double(pageCount) : 0
        ZStack {
            Circle().trim(from: 0, to: 1).stroke(Color(.systemGray4), lineWidth: 2)
            Circle().trim(from: 0, to: fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 16, height: 16)
    }
}

struct GalleryHistoryCell_Previews: PreviewProvider {
    static var previews: some View {
        GalleryHistoryCell(gallery: .preview)
    }
}
