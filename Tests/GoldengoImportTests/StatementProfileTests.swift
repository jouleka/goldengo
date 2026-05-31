import XCTest
import GoldengoCore
@testable import GoldengoImport

final class StatementProfileTests: XCTestCase {
    func test_genericCSV_resolvesSignedMapping() throws {
        let m = try XCTUnwrap(StatementProfile.detectMapping(header: ["Date","Description","Amount","Reference"], currency: .all))
        if case .signed = m.amount {} else { XCTFail("expected signed") }
    }

    func test_genericHeader_withBareData_doesNotMatchRaiffeisen() throws {
        // A non-Albanian header containing bare "Data" must NOT pick Raiffeisen's dd/MM/yy format
        let header = ["Data", "Description", "Debit", "Credit"]
        let m = try XCTUnwrap(StatementProfile.detectMapping(header: header, currency: .all))
        XCTAssertNotEqual(m.dateFormats.first, "dd/MM/yy",
            "Header with bare 'Data' must not resolve to Raiffeisen (dd/MM/yy) profile")
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
