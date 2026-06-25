import XCTest
import GoldengoCore
@testable import GoldengoImport

final class ATMTaggingTests: XCTestCase {
    private let keywords = StatementProfile.raiffeisenAlbania.atmKeywords

    private let exclusions = StatementProfile.raiffeisenAlbania.atmExclusionKeywords

    func test_keywordMatch_isCaseAndDiacriticInsensitive() {
        XCTAssertTrue(ATMKeywords.isWithdrawal("TERHEQJE NGA ATM 4471", keywords: keywords, exclusions: exclusions))
        XCTAssertTrue(ATMKeywords.isWithdrawal("Tërheqje bankomat", keywords: keywords, exclusions: exclusions))
        XCTAssertTrue(ATMKeywords.isWithdrawal("Cash Withdrawal RBAL", keywords: keywords, exclusions: exclusions))
        XCTAssertFalse(ATMKeywords.isWithdrawal("Bar Atmosfera Tirane", keywords: keywords, exclusions: exclusions),
                       "A merchant containing 'atm' inside a word must not be tagged")
        XCTAssertFalse(ATMKeywords.isWithdrawal(nil, keywords: keywords, exclusions: exclusions))
        XCTAssertFalse(ATMKeywords.isWithdrawal("Spar Market", keywords: keywords, exclusions: exclusions))
    }

    func test_feeRows_areNeverWithdrawals() {
        // A commission row is SPEND, not money entering the wallet — tagging it a transfer
        // would hide the fee from totals AND fabricate a wallet inflow (review finding).
        XCTAssertFalse(ATMKeywords.isWithdrawal("KOMISION TERHEQJE ATM", keywords: keywords, exclusions: exclusions))
        XCTAssertFalse(ATMKeywords.isWithdrawal("Komision terheqje ne bankomat", keywords: keywords, exclusions: exclusions))
        XCTAssertFalse(ATMKeywords.isWithdrawal("Cash Withdrawal Fee", keywords: keywords, exclusions: exclusions))
        XCTAssertFalse(ATMKeywords.isWithdrawal("ATM FEE", keywords: keywords, exclusions: exclusions))
        XCTAssertFalse(ATMKeywords.isWithdrawal("Tarifa terheqje", keywords: keywords, exclusions: exclusions))
    }

    func test_albanianInflectedForms_match() {
        XCTAssertTrue(ATMKeywords.isWithdrawal("TERHEQJA NGA BANKOMATI", keywords: keywords, exclusions: exclusions))
        XCTAssertTrue(ATMKeywords.isWithdrawal("Tërheqjes cash", keywords: keywords, exclusions: exclusions))
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
        XCTAssertEqual(mapping.atmExclusionKeywords, StatementProfile.raiffeisenAlbania.atmExclusionKeywords)
        XCTAssertEqual(mapping.skipRowKeywords, StatementProfile.raiffeisenAlbania.skipRowKeywords)
    }

    // End-to-end: a fee row matches an ATM keyword ('terheqje') but the exclusion must veto the
    // transfer retag through a mapping built by detectMapping (not just the ATMKeywords unit).
    func test_detectMapping_feeRowThroughMapper_isExpenseNotTransfer() throws {
        let header = ["Data e transaksionit", "Pershkrimi", "Debi", "Kredi"]
        let mapping = try XCTUnwrap(StatementProfile.detectMapping(header: header, currency: .all))
        let fee = StatementRowMapper.map(row: ["05/06/2026", "KOMISION TERHEQJE ATM", "150", ""], using: mapping)
        XCTAssertEqual(fee?.kind, .expense, "A commission/fee is spend, never a wallet transfer")
        let atm = StatementRowMapper.map(row: ["05/06/2026", "TERHEQJE ATM", "10000", ""], using: mapping)
        XCTAssertEqual(atm?.kind, .transfer, "A non-fee ATM withdrawal still tags as transfer")
    }
}
