import XCTest
@testable import GoldengoCore

final class SmokeTests: XCTestCase {
    func test_schemaVersion_isOne() {
        XCTAssertEqual(GoldengoCore.schemaVersion, 1)
    }
}
