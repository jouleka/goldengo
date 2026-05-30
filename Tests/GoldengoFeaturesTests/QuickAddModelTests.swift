import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class QuickAddModelTests: XCTestCase {
    private func makeModel(_ currency: CurrencyCode = .all) throws -> QuickAddModel {
        QuickAddModel(store: IngestionStore(modelContainer: try .goldengoInMemory()), currency: currency)
    }

    func test_keypad_buildsAmount_andCanSaveOnlyWhenPositive() throws {
        let m = try makeModel()
        XCTAssertFalse(m.canSave)
        m.tap("1"); m.tap("5"); m.tap("0"); m.tap("0")
        XCTAssertEqual(m.amountString, "1500")
        XCTAssertEqual(m.amountDecimal, 1500)
        XCTAssertTrue(m.canSave)
        m.backspace()
        XCTAssertEqual(m.amountString, "150")
    }

    func test_save_persistsExpense_andResets() async throws {
        let m = try makeModel()
        m.tap("2"); m.tap("5"); m.tap("0")
        m.selectedCategory = "Coffee"
        try await m.save()
        let count = try await m.store.expenseCount()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(m.amountString, "")          // resets for the next entry
    }

    func test_keypad_rejectsSecondDecimalPoint() throws {
        let m = try makeModel(.eur)
        m.tap("1"); m.tap("."); m.tap("2"); m.tap("."); m.tap("3")
        XCTAssertEqual(m.amountString, "1.23")
    }

    func test_keypad_ignoresDecimalForZeroFractionCurrency() throws {
        let m = try makeModel(.all)   // lek has no minor unit
        m.tap("1"); m.tap("."); m.tap("5")
        XCTAssertEqual(m.amountString, "15")
    }

    func test_keypad_capsFractionDigitsToCurrency() throws {
        let m = try makeModel(.eur)   // 2 fraction digits
        m.tap("1"); m.tap("2"); m.tap("."); m.tap("5"); m.tap("0"); m.tap("9")
        XCTAssertEqual(m.amountString, "12.50")
    }
}
