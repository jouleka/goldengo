import XCTest
import GoldengoCore
@testable import GoldengoImport

final class ATMTaggingTests: XCTestCase {
    private let keywords = StatementProfile.raiffeisenAlbania.atmKeywords

    func test_keywordMatch_isCaseAndDiacriticInsensitive() {
        XCTAssertTrue(ATMKeywords.isWithdrawal("TERHEQJE NGA ATM 4471", keywords: keywords))
        XCTAssertTrue(ATMKeywords.isWithdrawal("Tërheqje bankomat", keywords: keywords))
        XCTAssertTrue(ATMKeywords.isWithdrawal("Cash Withdrawal RBAL", keywords: keywords))
        XCTAssertFalse(ATMKeywords.isWithdrawal("Bar Atmosfera Tirane", keywords: keywords),
                       "A merchant containing 'atm' inside a word must not be tagged")
        XCTAssertFalse(ATMKeywords.isWithdrawal(nil, keywords: keywords))
        XCTAssertFalse(ATMKeywords.isWithdrawal("Spar Market", keywords: keywords))
    }

    func test_rowMapper_tagsATMDebitAsTransfer() {
        var mapping = ColumnMapping(dateIndex: 0, amount: .debitCredit(debit: 2, credit: 3),
                                    merchantIndex: 1, externalIDIndex: nil,
                                    dateFormats: ["dd/MM/yyyy"], decimalSeparator: ".",
                                    groupingSeparator: ",", currency: .all)
        mapping.atmKeywords = keywords
        let atm = StatementRowMapper.map(row: ["05/06/2026", "TERHEQJE ATM", "10000", ""], using: mapping)
        XCTAssertEqual(atm?.kind, .transfer, "An ATM debit is money moving to the wallet, not spend")
        let coffee = StatementRowMapper.map(row: ["05/06/2026", "Mon Cheri", "350", ""], using: mapping)
        XCTAssertEqual(coffee?.kind, .expense, "Ordinary debits stay expenses")
        let credit = StatementRowMapper.map(row: ["05/06/2026", "TERHEQJE ATM REVERSAL", "", "10000"], using: mapping)
        XCTAssertEqual(credit?.kind, .income, "Only DEBIT rows can be withdrawals")
    }

    func test_detectMapping_carriesProfileKeywords() throws {
        let header = ["Data e transaksionit", "Pershkrimi", "Debi", "Kredi"]
        let mapping = try XCTUnwrap(StatementProfile.detectMapping(header: header, currency: .all))
        XCTAssertEqual(mapping.atmKeywords, StatementProfile.raiffeisenAlbania.atmKeywords)
    }
}
