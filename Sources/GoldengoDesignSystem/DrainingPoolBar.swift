import SwiftUI

/// A horizontal "money draining" bar: a quiet track with a source-tinted fill sized to `fraction`
/// (remaining ÷ inflow). Clamps 0…1; at 0 the fill has zero width (no stray dot). Decorative —
/// the consuming row owns the accessibility label.
public struct DrainingPoolBar: View {
    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = min(max(fraction, 0), 1)
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.goldengoField)
                if fraction > 0 {
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                }
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}
