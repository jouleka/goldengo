import SwiftUI

/// The serif "voice" section header for the rewrite. Distinct from `GoldengoSectionLabel`
/// (uppercase caption), which is kept for the screens that still use it (D3).
public struct GoldengoSerifSectionHeader: View {
    private let title: String
    private let hint: String?

    public init(_ title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            if let hint {
                Spacer(minLength: GoldengoTheme.Spacing.s)
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
    }
}
