import SwiftUI

/// A calm focal glyph for landing/ritual screens: a thin gold SF Symbol in a gold-soft circle with a
/// hairline ring. Decorative (accessibility-hidden — the screen's title carries the meaning).
public struct GoldGlyphBadge: View {
    private let systemName: String
    public init(_ systemName: String) { self.systemName = systemName }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(GoldengoTheme.accent)
            .frame(width: 72, height: 72)
            .background(GoldengoTheme.accentSoft)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(GoldengoTheme.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
