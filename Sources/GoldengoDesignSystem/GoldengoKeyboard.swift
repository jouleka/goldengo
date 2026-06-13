import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Keyboard dismissal that never relies on a "Done" toolbar (project rule): resign first
/// responder programmatically (use after an action) or via `goldengoDismissKeyboard()` (tap-outside).
public enum GoldengoKeyboard {
    public static func dismiss() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
}

public extension View {
    /// Tap-outside keyboard dismissal. Apply to a background layer, NOT over interactive controls,
    /// so it does not swallow their taps.
    func goldengoDismissKeyboard() -> some View {
        contentShape(Rectangle())
            .onTapGesture { GoldengoKeyboard.dismiss() }
    }
}
