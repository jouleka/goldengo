import XCTest
@testable import GoldengoIntents

@available(iOS 17.0, *)
final class OpenQuickAddIntentTests: XCTestCase {
    func test_intent_hasTitle() {
        XCTAssertFalse(String(localized: OpenQuickAddIntent.title).isEmpty)
    }

    func test_intent_opensApp() {
        XCTAssertTrue(OpenQuickAddIntent.openAppWhenRun)
    }
}
