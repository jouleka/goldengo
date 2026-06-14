import SwiftUI

/// The center action of the tab bar: a prominent gold circle that opens the Add sheet.
/// Presentation-only — the navigation decision lives in `RootView`.
public struct AddFAB: View {
    private let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(GoldengoTheme.onAccent)
                .frame(width: 62, height: 62)
                .background(GoldengoTheme.accent)
                .clipShape(Circle())
                // warm --shadow-fab from the design (rgba(60,46,16,...)), not a cold black drop
                .shadow(color: Color(red: 60 / 255, green: 46 / 255, blue: 16 / 255).opacity(0.22), radius: 9, y: 6)
                .shadow(color: Color(red: 60 / 255, green: 46 / 255, blue: 16 / 255).opacity(0.14), radius: 2.5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add expense")
    }
}
