import SwiftUI

/// A small muted icon tile (matches the design's .gg-tile): 38×38, field fill, radius-chip, ink-muted glyph.
public struct GoldengoIconTile: View {
    private let systemName: String
    private let size: CGFloat
    public init(_ systemName: String, size: CGFloat = 19) { self.systemName = systemName; self.size = size }
    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(GoldengoTheme.inkMuted)
            .frame(width: 38, height: 38)
            .background(Color.goldengoField)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
    }
}
