import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum GoldengoTheme {
    /// The locked "Quiet luxe" palette as hex (light, dark). This is the stable, testable contract;
    /// the `Color` tokens below are derived from it.
    public enum Hex {
        public static let canvasLight = "#F7F3EA"
        public static let canvasDark = "#17140F"
        public static let surfaceLight = "#FCFAF4"
        public static let surfaceDark = "#211D16"
        public static let fieldLight = "#EFE7D6"
        public static let fieldDark = "#2B261D"
        public static let inkPrimaryLight = "#2A2620"
        public static let inkPrimaryDark = "#F3ECDD"
        public static let inkMutedLight = "#8C8373"
        public static let inkMutedDark = "#A89E89"
        public static let hairlineLight = "#E7DECE"
        public static let hairlineDark = "#322C22"
        public static let accentLight = "#B68A2E"
        public static let accentDark = "#E0AE4A"
        /// Label/glyph color on a gold fill — colour-constant (same value in light and dark), so no `*Dark` pair.
        public static let onAccent = "#2A2620"
    }

    public static let accentGoldHex = "#E8B341"
    public static var accent: Color { Color(hex: accentGoldHex) }

    /// Faint gold wash used behind icons and selected states.
    public static var accentSoft: Color { accent.opacity(0.16) }

    /// Destructive-action red (e.g. swipe-to-delete). Uses the system red so it adapts to light/dark
    /// and reads as the platform's standard "delete" tint.
    public static var danger: Color {
#if canImport(UIKit)
        Color(uiColor: .systemRed)
#elseif canImport(AppKit)
        Color(nsColor: .systemRed)
#else
        .red
#endif
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
    }

    public enum Radius {
        public static let chip: CGFloat = 12
        public static let control: CGFloat = 16
        public static let card: CGFloat = 22
    }

    /// The shared per-source palette (by `SourceRecord.colorIndex`) — the Sources tab bars and the
    /// funded-by chips must agree on a source's color, so both resolve through here.
    public static let sourcePalette: [Color] = [.blue, .teal, .green, .orange, .pink, .purple, .indigo, .brown]
    public static func sourceColor(_ index: Int) -> Color {
        let n = sourcePalette.count
        return sourcePalette[((index % n) + n) % n]
    }
}

public extension Color {
    init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }

    /// Resolves between two colors by the current interface style (light/dark).
    /// The light/dark legs are evaluated *inside* the trait/appearance closure, so passing an
    /// already-adaptive `Color` still resolves correctly per appearance — keep them in the closure.
    init(light: Color, dark: Color) {
#if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
#elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
#else
        self = light
#endif
    }

    /// Convenience: resolve between two hex strings.
    init(light: String, dark: String) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }

    /// The app canvas (the muted backdrop cards sit on).
    static var goldengoBackground: Color {
#if canImport(UIKit)
        Color(.systemGroupedBackground)
#elseif canImport(AppKit)
        Color(.windowBackgroundColor)
#else
        Color.gray.opacity(0.1)
#endif
    }

    /// An elevated card / row surface.
    static var goldengoSurface: Color {
#if canImport(UIKit)
        Color(.secondarySystemGroupedBackground)
#elseif canImport(AppKit)
        Color(.controlBackgroundColor)
#else
        Color.white
#endif
    }

    /// A subtle fill for fields and keypad keys.
    static var goldengoField: Color {
#if canImport(UIKit)
        Color(.tertiarySystemFill)
#elseif canImport(AppKit)
        Color(.underPageBackgroundColor)
#else
        Color.gray.opacity(0.15)
#endif
    }
}

/// Wraps content in the shared rounded card surface so every screen reads as one system.
public struct GoldengoCardStyle: ViewModifier {
    private let padding: CGFloat
    public init(padding: CGFloat) { self.padding = padding }
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.goldengoSurface)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
    }
}

public extension View {
    /// Standard Goldengo card: rounded surface with consistent inset.
    func goldengoCard(padding: CGFloat = GoldengoTheme.Spacing.m) -> some View {
        modifier(GoldengoCardStyle(padding: padding))
    }
}

/// Maps a category name to a recognisable SF Symbol, shared by the Add chips and the Home
/// dashboard so a category reads the same everywhere. Unknown names fall back to a tag.
public enum GoldengoCategoryIcon {
    public static func symbol(for category: String?) -> String {
        switch category {
        case "Groceries": return "cart"
        case "Food":      return "fork.knife"
        case "Transport": return "car"
        case "Coffee":    return "cup.and.saucer"
        case "Bills":     return "doc.text"
        case "Shopping":  return "bag"
        default:          return "tag"
        }
    }
}

/// A small uppercase label that titles a card section without the heaviness of a `Form` header.
public struct GoldengoSectionLabel: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
