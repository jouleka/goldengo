import XCTest
@testable import GoldengoFeatures

final class RootViewRoutingTests: XCTestCase {
    func test_deepLink_routesToExpectedTabs() {
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://quickadd")!), 0)
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://recent")!), 1)
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://settings")!), 2)
        XCTAssertNil(RootView.tab(forDeepLink: URL(string: "goldengo://unknown")!))
        XCTAssertNil(RootView.tab(forDeepLink: URL(string: "https://quickadd")!))
    }
}
