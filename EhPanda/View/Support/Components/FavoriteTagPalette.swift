//
//  FavoriteTagPalette.swift
//  EhPanda
//

import SwiftUI

/// Palette and helper for favorite category colors — inspired by JHenTai implementation.
enum FavoriteTagPalette {
    // Ten-color palette used for favorite categories.
    static let colors: [Color] = [
        Color(red: 158.0/255.0, green: 158.0/255.0, blue: 158.0/255.0),
        Color(red: 252.0/255.0, green: 78.0/255.0, blue: 78.0/255.0),
        Color(red: 252.0/255.0, green: 180.0/255.0, blue: 23.0/255.0),
        Color(red: 221.0/255.0, green: 229.0/255.0, blue: 0.0/255.0),
        Color(red: 23.0/255.0, green: 185.0/255.0, blue: 27.0/255.0),
        Color(red: 54.0/255.0, green: 185.0/255.0, blue: 64.0/255.0),
        Color(red: 104.0/255.0, green: 201.0/255.0, blue: 222.0/255.0),
        Color(red: 80.0/255.0, green: 80.0/255.0, blue: 215.0/255.0),
        Color(red: 151.0/255.0, green: 85.0/255.0, blue: 245.0/255.0),
        Color(red: 254.0/255.0, green: 147.0/255.0, blue: 255.0/255.0)
    ]

    /// Return color for a given favorite index (0-9), or nil if out of range.
    static func color(forIndex index: Int?) -> Color? {
        guard let index = index, index >= 0, index < colors.count else { return nil }
        return colors[index]
    }

    /// Derive a stable color from a favorite name by hashing.
    static func color(forName name: String?) -> Color? {
        guard let name = name, !name.isEmpty else { return nil }
        let idx = abs(name.hashValue) % colors.count
        return colors[idx]
    }

    /// Convenience: prefer explicit index, fallback to name-derived color.
    static func color(forGalleryFavoriteIndex index: Int?, name: String?) -> Color? {
        return color(forIndex: index) ?? color(forName: name)
    }
}
