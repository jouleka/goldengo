import XCTest
@testable import GoldengoCore

final class NormalizedTransactionTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }

    func test_externalID_takesPrecedenceInDedupeKey() {
        let tx = NormalizedTransaction(
            externalID: "abc123", amount: 1500, currency: .all,
            date: date("2026-05-30T10:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "raiffeisen-visa")
        XCTAssertEqual(tx.dedupeKey, "ext:abc123")
    }

    func test_compositeKey_isStableAcrossSameDayDifferentTime() {
        let a = NormalizedTransaction(externalID: nil, amount: 1500, currency: .all,
            date: date("2026-05-30T09:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        let b = NormalizedTransaction(externalID: nil, amount: 1500, currency: .all,
            date: date("2026-05-30T21:30:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        XCTAssertEqual(a.dedupeKey, b.dedupeKey)
    }

    func test_compositeKey_differsWhenAmountDiffers() {
        let a = NormalizedTransaction(externalID: nil, amount: 1500, currency: .all,
            date: date("2026-05-30T09:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        let b = NormalizedTransaction(externalID: nil, amount: 1600, currency: .all,
            date: date("2026-05-30T09:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        XCTAssertNotEqual(a.dedupeKey, b.dedupeKey)
    }
}
