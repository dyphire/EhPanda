import SwiftUI
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#elseif os(macOS)
import AppKit
#endif

private extension Color {
    #if os(macOS)
    typealias SystemColor = NSColor
    #else
    typealias SystemColor = UIColor
    #endif

    struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    var colorComponents: RGBA? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if os(macOS)
        SystemColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        guard SystemColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #endif

        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Color: @retroactive Codable {
    public enum CodingKeys: String, CodingKey, Sendable {
        case red, green, blue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        self.init(red: red, green: green, blue: blue)
    }

    public func encode(to encoder: Encoder) throws {
        guard let colorComponents = self.colorComponents else { return }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(persistedComponent(colorComponents.red), forKey: .red)
        try container.encode(persistedComponent(colorComponents.green), forKey: .green)
        try container.encode(persistedComponent(colorComponents.blue), forKey: .blue)
    }
}

/// Rounds an RGBA component to 6 decimal places before persisting. SwiftUI stores colors in a
/// working color space and the `getRed` conversion can drift by a tiny amount per channel, so
/// persisting full precision is not idempotent across a decode→encode cycle — the rounded value
/// is (well below visual perception, and it keeps persisted blobs and backups byte-stable).
private func persistedComponent(_ component: CGFloat) -> Double {
    (component * 1_000_000).rounded() / 1_000_000
}
