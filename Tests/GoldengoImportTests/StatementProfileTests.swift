import XCTest
import GoldengoCore
@testable import GoldengoImport

final class StatementProfileTests: XCTestCase {
    func test_genericCSV_resolvesSignedMapping() throws {
        let m = try XCTUnwrap(StatementProfile.detectMapping(header: ["Date","Description","Amount","Reference"], currency: .all))
        if case .signed = m.amount {} else { XCTFail("expected signed") }
    }

    func test_raiffeisenAlbanianHeader_resolvesDebitCredit() throws {
        let header = ["DATA E TRANSAKSIONIT","PERSHKRIMI","DATE VALUTA","DEBI","KREDI","BALANCA"]
        let m = try XCTUnwrap(StatementProfile.detectMapping(header: header, currency: .all))
        if case let .debitCredit(d, c) = m.amount {
            XCTAssertEqual(d, 3)
            XCTAssertEqual(c, 4)
        } else {
            XCTFail("expected debitCredit")
        }
        XCTAssertEqual(m.dateFormats.first, "dd/MM/yy")
    }
}
