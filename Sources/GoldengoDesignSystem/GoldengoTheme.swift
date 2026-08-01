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
        /// 4.89:1 on the light canvas: safe for normal-size supporting text.
        public static let inkMutedLight = "#71695C"
        public static let inkMutedDark = "#A89E89"
        public static let hairlineLight = "#E7DECE"
        public static let hairlineDark = "#322C22"
        /// Darkened warm gold keeps the brand character while reaching 4.70:1 on the canvas.
        public static let accentLight = "#8A671A"
        public static let accentDark = "#E0AE4A"
        /// Label/glyph color on a gold fill — colour-constant (same value in light and dark), so no `*Dark` pair.
        public static let onAccent = "#2A2620"
        /// Warm terracotta destructive (prototype --danger), not harsh system red.
        public static let dangerLight = "#B64331"
        public static let dangerDark = "#E8705C"
        /// Soft warm green for income inflow (prototype --income), not loud system green.
        public static let incomeLight = "#3A7547"
        public static let incomeDark = "#6FB47E"
    }

    /// Light-mode gold hex. Kept for back-compat (was the single accent hex). Dark gold is `Hex.accentDark`.
    public static let accentGoldHex = Hex.accentLight

    /// The one brand accent. Sparingly used; semantic colors (danger/income) are separate.
    public static var accent: Color { Color(light: Hex.accentLight, dark: Hex.accentDark) }

    /// Faint gold wash behind icons and selected states. Per-scheme alpha (D6): 0.12 light / 0.16 dark.
    public static var accentSoft: Color {
        Color(light: Color(hex: Hex.accentLight).opacity(0.12),
              dark:  Color(hex: Hex.accentDark).opacity(0.16))
    }

    /// Foreground color for any label/glyph sitting on a gold fill (D1).
    public static var onAccent: Color { Color(hex: Hex.onAccent) }

    /// Primary text / amounts.
    public static var inkPrimary: Color { Color(light: Hex.inkPrimaryLight, dark: Hex.inkPrimaryDark) }

    /// Secondary text, captions.
    public static var inkMuted: Color { Color(light: Hex.inkMutedLight, dark: Hex.inkMutedDark) }

    /// 1px separators and card strokes.
    public static var hairline: Color { Color(light: Hex.hairlineLight, dark: Hex.hairlineDark) }

    /// Destructive-action red — a warm terracotta (prototype --danger), not harsh system red.
    public static var danger: Color { Color(light: Hex.dangerLight, dark: Hex.dangerDark) }

    /// Income inflow — a soft warm green (prototype --income), not loud system green.
    public static var income: Color { Color(light: Hex.incomeLight, dark: Hex.incomeDark) }

    /// A 55%-opacity gold for hairline accents / selected rings (prototype --accent-line).
    public static var accentLine: Color {
        Color(light: Color(hex: Hex.accentLight).opacity(0.55),
              dark:  Color(hex: Hex.accentDark).opacity(0.55))
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
        // Named aliases (same values) used by the rewrite spec; additive — base names retained.
        public static let xs4: CGFloat = xs
        public static let s8: CGFloat = s
        public static let m16: CGFloat = m
        public static let l24: CGFloat = l
        public static let xl32: CGFloat = xl
    }

    public enum Radius {
        public static let chip: CGFloat = 14
        public static let control: CGFloat = 20   // softer than the old 16 — harmonises with the 22pt cards
        public static let card: CGFloat = 22
    }

    /// The shared per-source palette (by `SourceRecord.colorIndex`) — the Sources tab bars and the
    /// funded-by chips must agree on a source's color, so both resolve through here.
    public static let sourcePalette: [Color] = [
        Color(hex: "#5B8DC9"), Color(hex: "#3FA9A0"), Color(hex: "#5FA86B"), Color(hex: "#D08A3E"),
        Color(hex: "#C77B9A"), Color(hex: "#8A77C0"), Color(hex: "#6E78C9"), Color(hex: "#9C7B5B"),
    ]
    public static func sourceColor(_ index: Int) -> Color {
        let n = sourcePalette.count
        return sourcePalette[((index % n) + n) % n]
    }
}

public extension Color {
    /// Parse `#RGB`, `#RRGGBB`, or `#RRGGBBAA` (the leading `#` is optional). Malformed input resolves
    /// to a loud debug magenta — never a silent black that hides the typo at a glance.
    init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        // Expand 3-digit shorthand (#RGB → #RRGGBB).
        let h = raw.count == 3 ? raw.map { "\($0)\($0)" }.joined() : raw
        guard h.count == 6 || h.count == 8, let value = UInt64(h, radix: 16) else {
            #if DEBUG
            print("⚠️ Color(hex:) got malformed hex '\(hex)' — expected #RGB, #RRGGBB, or #RRGGBBAA")
            #endif
            self.init(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)  // debug magenta, not silent black
            return
        }
        if h.count == 8 {   // #RRGGBBAA
            self.init(.sRGB,
                      red: Double((value >> 24) & 0xFF) / 255,
                      green: Double((value >> 16) & 0xFF) / 255,
                      blue: Double((value >> 8) & 0xFF) / 255,
                      opacity: Double(value & 0xFF) / 255)
        } else {            // #RRGGBB
            self.init(.sRGB,
                      red: Double((value >> 16) & 0xFF) / 255,
                      green: Double((value >> 8) & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255, opacity: 1)
        }
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

    /// The app canvas (the warm backdrop cards sit on).
    static var goldengoBackground: Color {
        Color(light: GoldengoTheme.Hex.canvasLight, dark: GoldengoTheme.Hex.canvasDark)
    }

    /// An elevated card / row surface.
    static var goldengoSurface: Color {
        Color(light: GoldengoTheme.Hex.surfaceLight, dark: GoldengoTheme.Hex.surfaceDark)
    }

    /// A subtle fill for fields and keypad keys.
    static var goldengoField: Color {
        Color(light: GoldengoTheme.Hex.fieldLight, dark: GoldengoTheme.Hex.fieldDark)
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
            .overlay(
                RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                    .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
            )
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
        case "Groceries": return "cart.fill"
        case "Food", "Dining out": return "fork.knife"
        case "Coffee": return "cup.and.saucer.fill"
        case "Housing", "Rent & mortgage", "Household", "Home maintenance": return "house.fill"
        case "Utilities": return "bolt.fill"
        case "Transport", "Fuel", "Car maintenance", "Parking": return "car.fill"
        case "Public transport": return "bus.fill"
        case "Taxi & rideshare": return "car.side.fill"
        case "Health", "Healthcare", "Pharmacy": return "cross.case.fill"
        case "Fitness": return "figure.run"
        case "Bills", "Phone & internet", "Insurance", "Taxes & fees": return "doc.text.fill"
        case "Subscriptions": return "repeat.circle.fill"
        case "Shopping": return "bag.fill"
        case "Travel": return "airplane"
        case "Entertainment", "Hobbies": return "sparkles"
        case "Investments", "General investing", "Stocks & funds", "Retirement", "Business investment":
            return "chart.line.uptrend.xyaxis"
        case "Savings": return "banknote.fill"
        case "Crypto": return "bitcoinsign.circle.fill"
        case "Gambling", "Waste & risk", "General waste", "Impulse spending":
            return "exclamationmark.triangle.fill"
        case "Tobacco & vape": return "smoke.fill"
        case "Fines & penalties": return "exclamationmark.octagon.fill"
        case "Other": return "square.grid.2x2"
        default:          return "tag"
        }
    }
}

/// A small uppercase label that titles a card section without the heaviness of a `Form` header.
public struct GoldengoSectionLabel: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(LocalizedStringKey(text.uppercased()))
            .font(.caption.weight(.semibold))
            // Labels orient a card; they should grow, but not crowd the card's actual controls at
            // the largest accessibility sizes.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
