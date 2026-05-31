import XCTest
import GoldengoCore
@testable import GoldengoImport

final class MappingDetectorTests: XCTestCase {
    func test_detects_columnsFromHeaderNames() throws {
        let header = ["Date", "Amount", "Description", "Reference"]
        let m = try XCTUnwrap(MappingDetector.detect(header: header, currency: .all))
        XCTAssertEqual(m.dateIndex, 0)
        XCTAssertEqual(m.amountIndex, 1)
        XCTAssertEqual(m.merchantIndex, 2)
        XCTAssertEqual(m.externalIDIndex, 3)
    }
    func test_returnsNil_whenRequiredColumnsMissing() {
        XCTAssertNil(MappingDetector.detect(header: ["Foo","Bar"], currency: .all))
    }
}
