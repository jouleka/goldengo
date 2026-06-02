import XCTest
import Foundation
@testable import GoldengoFeatures

/// The swipe gesture's *policy*: given how far a row was dragged (and where the flick is projected
/// to land), decide whether to snap closed, rest open so the revealed action can be tapped, or
/// commit the action outright. Kept pure so the behaviour is testable without synthesising gestures
/// (which the dev simulator can't do).
final class SwipeResolverTests: XCTestCase {
    // Thresholds mirroring realistic row geometry (action panel ~76pt, row ~360pt).
    private let openThreshold: CGFloat = 40
    private let commitThreshold: CGFloat = 180

    private func resolve(translation: CGFloat, predictedEnd: CGFloat? = nil,
                         hasLeading: Bool = true, hasTrailing: Bool = true) -> SwipeOutcome {
        SwipeResolver.outcome(translation: translation,
                              predictedEnd: predictedEnd ?? translation,
                              openThreshold: openThreshold, commitThreshold: commitThreshold,
                              hasLeading: hasLeading, hasTrailing: hasTrailing)
    }

    // MARK: - Right swipe → Edit (leading)

    func test_shortRightDrag_snapsClosed() {
        // A tiny, possibly accidental nudge must not reveal an action.
        XCTAssertEqual(resolve(translation: 10), .closed)
    }

    func test_mediumRightDrag_restsOpenSoEditCanBeTapped() {
        // A deliberate but partial swipe parks the row open for a follow-up tap on Edit.
        XCTAssertEqual(resolve(translation: 60), .openLeading)
    }

    func test_longRightDrag_commitsEditWithoutASecondTap() {
        XCTAssertEqual(resolve(translation: 220), .commitLeading)
    }

    func test_fastRightFlick_commitsEditEvenWhenFingerTravelIsShort() {
        // Short distance but high velocity (projected far) should still open edit directly.
        XCTAssertEqual(resolve(translation: 50, predictedEnd: 300), .commitLeading)
    }

    // MARK: - Left swipe → Delete (trailing)

    func test_shortLeftDrag_snapsClosed() {
        XCTAssertEqual(resolve(translation: -10), .closed)
    }

    func test_mediumLeftDrag_restsOpenSoDeleteCanBeTapped() {
        XCTAssertEqual(resolve(translation: -60), .openTrailing)
    }

    func test_longLeftDrag_commitsDeleteWithoutASecondTap() {
        // A full left-swipe deletes (after confirmation) without tapping the revealed button.
        XCTAssertEqual(resolve(translation: -220), .commitTrailing)
    }

    func test_fastLeftFlick_commitsDeleteEvenWhenFingerTravelIsShort() {
        XCTAssertEqual(resolve(translation: -50, predictedEnd: -300), .commitTrailing)
    }

    // MARK: - Boundaries (pin the >= comparisons)

    func test_exactlyAtOpenThreshold_opens() {
        XCTAssertEqual(resolve(translation: 40), .openLeading)
    }

    func test_exactlyAtCommitThreshold_commits() {
        XCTAssertEqual(resolve(translation: 180, predictedEnd: 180), .commitLeading)
    }

    // MARK: - Absent actions

    func test_rightDragWithNoLeadingAction_doesNothing() {
        // No Edit configured → swiping right can neither open nor commit.
        XCTAssertEqual(resolve(translation: 220, hasLeading: false), .closed)
    }

    func test_leftDragWithNoTrailingAction_doesNothing() {
        XCTAssertEqual(resolve(translation: -220, hasTrailing: false), .closed)
    }

    // MARK: - Reversal

    func test_dragOpenedThenFlickedBack_snapsClosed() {
        // Dragged right into the open zone, but released with leftward momentum (predicted end
        // crosses zero) → should close, not stay open.
        XCTAssertEqual(resolve(translation: 60, predictedEnd: -20), .closed)
    }

    func test_zeroDrag_isClosed() {
        XCTAssertEqual(resolve(translation: 0), .closed)
    }
}
