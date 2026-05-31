import XCTest
import GoldengoCore
@testable import GoldengoImport

final class MappingDetectorTests: XCTestCase {
    func test_detects_columnsFromHeaderNames() throws {
        let header = ["Date", "Amount", "Description", "Reference"]
        let m = try XCTUnwrap(MappingDetector.detect(header: header, currency: .all))
        XCTAssertEqual(m.dateIndex, 0)
        // Amount column → signed(index: 1)
        if case let .signed(idx) = m.amount { XCTAssertEqual(idx, 1) } else { XCTFail("expected signed amount") }
        XCTAssertEqual(m.merchantIndex, 2)
        XCTAssertEqual(m.externalIDIndex, 3)
    }
    func test_returnsNil_whenRequiredColumnsMissing() {
        XCTAssertNil(MappingDetector.detect(header: ["Foo","Bar"], currency: .all))
    }
}
