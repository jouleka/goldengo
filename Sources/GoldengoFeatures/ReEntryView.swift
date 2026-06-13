import SwiftUI
import GoldengoDesignSystem

/// The calm "welcome back" soft-landing shown after a multi-day gap. No data entry, no guilt.
public struct ReEntryView: View {
    let daysAway: Int
    let onContinue: () -> Void
    public init(daysAway: Int, onContinue: @escaping () -> Void) {
        self.daysAway = daysAway; self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: GoldengoTheme.Spacing.l) {
            Spacer()
            GoldGlyphBadge("sunrise")
            Text("Welcome back")
                .font(.system(.title, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)
            Text("It's been \(daysAway) days — that stretch is behind you. Nothing's assumed.")
                .font(.body).foregroundStyle(GoldengoTheme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, GoldengoTheme.Spacing.xl)
            Spacer()
            GoldButton("Here's today") { onContinue() }
                .padding(.horizontal, GoldengoTheme.Spacing.l)
                .padding(.bottom, GoldengoTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.goldengoBackground.ignoresSafeArea())
    }
}
