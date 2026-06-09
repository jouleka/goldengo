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
            Image(systemName: "sunrise.fill")
                .font(.system(size: 56))
                .foregroundStyle(GoldengoTheme.accent)
            Text("Welcome back")
                .font(.title.weight(.bold))
            Text("It's been \(daysAway) days — that stretch is behind you. Nothing's assumed.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, GoldengoTheme.Spacing.xl)
            Spacer()
            Button(action: onContinue) {
                Text("Here's today").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
            }
            .background(GoldengoTheme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
            .padding(.horizontal, GoldengoTheme.Spacing.l)
            .padding(.bottom, GoldengoTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.goldengoBackground.ignoresSafeArea())
    }
}
