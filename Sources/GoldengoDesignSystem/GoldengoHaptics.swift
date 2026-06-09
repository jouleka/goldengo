import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// App tactile feedback. `spendLanded` is a brief, firm "drop" — a spend landing (the felt cost
/// that cards/totals delete). No-op off UIKit (macOS build/tests) so callers need no platform guard.
public enum GoldengoHaptics {
    public static func spendLanded() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
