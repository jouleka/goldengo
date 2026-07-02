import SwiftUI

/// The app's motion vocabulary — three springs so every animation feels like one hand made it.
///
/// Springs (not eased curves) because they carry momentum, which is what reads as "smooth" on iOS.
/// All are state-driven and short; nothing loops. Pair them only with transform + opacity (offset,
/// scale, opacity) — never `frame`, `shadow`, or `blur` — so they stay GPU-composited and free.
public enum GoldengoMotion {
    /// Taps, toggles, tab selection — crisp and immediate.
    public static let quick: Animation = .spring(response: 0.28, dampingFraction: 0.9)
    /// The default for most state changes — the floating pill, section collapses, rolling numbers.
    public static let standard: Animation = .spring(response: 0.4, dampingFraction: 0.88)
    /// Larger content swaps — a touch softer.
    public static let gentle: Animation = .spring(response: 0.5, dampingFraction: 0.9)
}

/// Subtle press feedback for buttons: a small scale + dim while held, springing back on release.
/// Transform + opacity only, so it costs nothing to render. Put the FULL visual (including any
/// background) inside the button's label so the whole control presses as one piece.
public struct GoldengoPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(GoldengoMotion.quick, value: configuration.isPressed)
    }
}
