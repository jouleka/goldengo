import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

/// App tactile feedback. `spendLanded` is a two-beat "drop" — a firm landing plus a soft settle,
/// the felt cost that cards/totals delete (GOL-83/94). Degrades to a single `.rigid` impact when
/// CoreHaptics can't play, and to a no-op off UIKit (macOS build/tests), so callers need no guard.
/// `@MainActor`: the shared engine is mutable state and every call site is a SwiftUI action.
@MainActor
public enum GoldengoHaptics {
    public static func spendLanded() {
        #if canImport(CoreHaptics)
        if playDrop() { return }
        #endif
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    #if canImport(CoreHaptics)
    /// Shared lazily-created engine — one per tap would cost milliseconds and audio-session churn
    /// on the hot log path. Auto-shutdown lets it sleep when idle; `start()` wakes it per play.
    private static var engine: CHHapticEngine?

    /// The drop: landing transient + a dull settle ~90 ms later (what a single `.rigid` tick
    /// lacks). The four constants are the feel — tuned on device, adjust on feedback.
    private static func playDrop() -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            let engine: CHHapticEngine
            if let running = Self.engine {
                engine = running
            } else {
                engine = try CHHapticEngine()
                engine.isAutoShutdownEnabled = true
                Self.engine = engine
            }
            try engine.start()
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.65),
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
                ], relativeTime: 0.09),
            ]
            try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
                .start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            // Fail soft: recreate the engine on the next tap; this tap gets the .rigid fallback.
            Self.engine = nil
            return false
        }
    }
    #endif
}
