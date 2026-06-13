import SwiftUI

/// The center action of the tab bar: a prominent gold circle that opens the Add sheet.
/// Presentation-only — the navigation decision lives in `RootView`.
public struct AddFAB: View {
    private let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(GoldengoTheme.onAccent)
                .frame(width: 60, height: 60)
                .background(GoldengoTheme.accent)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add expense")
    }
}
