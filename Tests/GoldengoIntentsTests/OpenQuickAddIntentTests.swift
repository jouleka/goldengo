import XCTest
import GoldengoData
@testable import GoldengoIntents

// KEEP THIS TARGET SYNC-ONLY. Linking AppIntents into an xctest process breaks XCTest's
// async bridge: an async test here is silently abandoned mid-run (false green) and its
// orphaned task corrupts the process (layout-dependent SIGSEGV; found 2026-07-02,
// Xcode 26.6). Async coverage of intent logic belongs in GoldengoDataTests — see
// ExpenseLoggingTests there.
@available(iOS 17.0, *)
final class OpenQuickAddIntentTests: XCTestCase {
    func test_intent_hasTitle() {
        XCTAssertFalse(String(localized: OpenQuickAddIntent.title).isEmpty)
    }

    func test_intent_opensApp() {
        XCTAssertTrue(OpenQuickAddIntent.openAppWhenRun)
    }

    // The actual behavior: staging the Quick-Add tab (0) so RootView routes there when
    // the app opens. Without it, the control would open the app but land on the wrong
    // screen. perform() is a one-line wrapper over stageQuickAdd() (sync-only target).
    @MainActor
    func test_stageQuickAdd_stagesQuickAddTab() {
        SharedSummary().setPendingTab(nil)
        OpenQuickAddIntent.stageQuickAdd()
        XCTAssertEqual(SharedSummary().readPendingTab(), 0)
    }
}
