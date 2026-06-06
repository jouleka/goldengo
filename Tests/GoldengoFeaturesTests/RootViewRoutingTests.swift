import XCTest
@testable import GoldengoFeatures

final class RootViewRoutingTests: XCTestCase {
    func test_deepLink_routesToExpectedTabs() {
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://quickadd")!), 0)
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://recent")!), 1)
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://home")!), 1)
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://settings")!), 2)
        XCTAssertNil(RootView.tab(forDeepLink: URL(string: "goldengo://unknown")!))
        XCTAssertNil(RootView.tab(forDeepLink: URL(string: "https://quickadd")!))
    }

    // T2 — import deep link routes to tag 3
    func test_deepLink_importRoutesToTag3() {
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://import")!), 3)
    }

    // T3 — subscriptions deep link routes to tag 4
    func test_deepLink_subscriptionsRoutesToTag4() {
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://subscriptions")!), 4)
    }

    // GOL-79 — a shared statement arrives as a file:// URL, not a goldengo:// deep link.
    func test_fileURL_isRecognizedAsStatementFile() {
        let fileURL = URL(fileURLWithPath: "/tmp/statement.pdf")
        XCTAssertTrue(RootView.isStatementFile(fileURL))
        XCTAssertNil(RootView.tab(forDeepLink: fileURL), "A file URL must not be mis-routed as a deep link.")
    }

    func test_deepLinkURL_isNotAStatementFile() {
        let deepLink = URL(string: "goldengo://import")!
        XCTAssertFalse(RootView.isStatementFile(deepLink))
        XCTAssertEqual(RootView.tab(forDeepLink: deepLink), 3)
    }
}
