import XCTest
import GoldengoData
@testable import GoldengoIntents

@available(iOS 17.0, *)
final class OpenQuickAddIntentTests: XCTestCase {
    func test_intent_hasTitle() {
        XCTAssertFalse(String(localized: OpenQuickAddIntent.title).isEmpty)
    }

    func test_intent_opensApp() {
        XCTAssertTrue(OpenQuickAddIntent.openAppWhenRun)
    }

    // The actual behavior: perform() must stage the Quick-Add tab (0) so RootView routes there when
    // the app opens. Without it, the control would open the app but land on the wrong screen.
    @MainActor
    func test_perform_stagesQuickAddTab() async throws {
        SharedSummary().setPendingTab(nil)
        _ = try await OpenQuickAddIntent().perform()
        XCTAssertEqual(SharedSummary().readPendingTab(), 0)
    }
}
