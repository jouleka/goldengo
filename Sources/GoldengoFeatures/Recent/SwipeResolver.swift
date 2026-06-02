import CoreGraphics

/// What a released horizontal swipe should do. `leading` is the action revealed by swiping right
/// (Edit on the Home recent list); `trailing` is revealed by swiping left (Delete).
enum SwipeOutcome: Equatable {
    /// Snap the row back to rest, hiding both actions.
    case closed
    /// Park the row open, revealing the leading (Edit) action for a follow-up tap.
    case openLeading
    /// Park the row open, revealing the trailing (Delete) action for a follow-up tap.
    case openTrailing
    /// Fire the leading (Edit) action immediately — a full right-swipe or fast flick.
    case commitLeading
    /// Fire the trailing (Delete) action immediately — a full left-swipe or fast flick.
    case commitTrailing
}

/// Pure policy that turns a released drag into a `SwipeOutcome`. Separated from the SwiftUI gesture
/// plumbing so the "far enough? / which action?" decisions are unit-testable without a real gesture.
///
/// Sign convention: `translation`/`predictedEnd` are the drag's horizontal component — positive is a
/// rightward swipe (reveals `leading`/Edit), negative is leftward (reveals `trailing`/Delete).
enum SwipeResolver {
    /// - Parameters:
    ///   - translation: How far the finger actually moved horizontally at release.
    ///   - predictedEnd: Where the drag is projected to land given its release velocity
    ///     (SwiftUI's `predictedEndTranslation.width`); lets a fast flick commit on little travel.
    ///   - openThreshold: Minimum real travel to park the row open.
    ///   - commitThreshold: Projected distance past which the action fires outright.
    ///   - hasLeading: Whether an Edit (right-swipe) action is configured.
    ///   - hasTrailing: Whether a Delete (left-swipe) action is configured.
    static func outcome(translation: CGFloat,
                        predictedEnd: CGFloat,
                        openThreshold: CGFloat,
                        commitThreshold: CGFloat,
                        hasLeading: Bool,
                        hasTrailing: Bool) -> SwipeOutcome {
        // Right / leading (Edit): both the actual drag and its projected end must point right, so a
        // swipe flicked back toward closed (predicted end crosses zero) doesn't stay open.
        if translation > 0 && predictedEnd > 0 {
            guard hasLeading else { return .closed }
            if predictedEnd >= commitThreshold { return .commitLeading }
            if translation >= openThreshold { return .openLeading }
            return .closed
        }
        // Left / trailing (Delete).
        if translation < 0 && predictedEnd < 0 {
            guard hasTrailing else { return .closed }
            if -predictedEnd >= commitThreshold { return .commitTrailing }
            if -translation >= openThreshold { return .openTrailing }
            return .closed
        }
        return .closed
    }
}
