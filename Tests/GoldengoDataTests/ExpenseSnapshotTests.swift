import XCTest
import GoldengoCore
@testable import GoldengoData

final class ExpenseSnapshotTests: XCTestCase {
    /// Build a snapshot overriding only the three fields that drive the row label.
    private func snap(note: String? = nil, merchant: String? = nil, category: String? = nil) -> ExpenseSnapshot {
        ExpenseSnapshot(dedupeKey: "k", amount: 1, currencyCode: "ALL", source: .manual,
                        categoryName: category, date: .now, merchantName: merchant, note: note,
                        kind: .expense, subscriptionName: nil)
    }

    func test_displayTitle_prefersNoteThenMerchantThenCategoryThenFallback() {
        // The Recent row must lead with the most specific label the user gave: the note ("what was
        // bought") wins over the merchant ("who"), which wins over the category, with a generic
        // fallback only when nothing is set. This is the contract the row and undo toast rely on.
        XCTAssertEqual(snap(note: "lunch with Ana", merchant: "Joe's", category: "Food").displayTitle,
                       "lunch with Ana")
        XCTAssertEqual(snap(merchant: "Netflix", category: "Bills").displayTitle, "Netflix")
        XCTAssertEqual(snap(category: "Groceries").displayTitle, "Groceries")
        XCTAssertEqual(snap().displayTitle, "Expense")
    }
}
