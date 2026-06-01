import SwiftUI

public enum GoldengoTheme {
    public static let accentGoldHex = "#E8B341"
    public static var accent: Color { Color(hex: accentGoldHex) }

    /// Faint gold wash used behind icons and selected states.
    public static var accentSoft: Color { accent.opacity(0.16) }

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
