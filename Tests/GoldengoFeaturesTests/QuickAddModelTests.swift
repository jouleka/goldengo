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
        await m.save()
        let count = try await m.store.expenseCount()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(m.amountString, "")          // resets for the next entry
    }

    func test_save_incrementsSavedCount_onlyOnSuccess() async throws {
        // The Add screen shows an "Added" confirmation by observing savedCount, so it must tick
        // exactly once per successful save and never on a no-op (empty amount) save.
        let m = try makeModel()
        XCTAssertEqual(m.savedCount, 0)
        await m.save()                       // nothing entered → no-op
        XCTAssertEqual(m.savedCount, 0)
        m.tap("2"); m.tap("5"); m.tap("0")
        await m.save()                       // valid → confirmation should fire once
        XCTAssertEqual(m.savedCount, 1)
    }

    func test_allowsDecimal_onlyForCurrenciesWithAMinorUnit() throws {
        // The keypad should hide the "." key for currencies with no minor unit (e.g. lek), where
        // tapping it does nothing.
        XCTAssertFalse(try makeModel(.all).allowsDecimal)   // lek: no minor unit
        XCTAssertTrue(try makeModel(.eur).allowsDecimal)    // eur: 2 decimal places
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

    func test_setCurrency_truncatesTypedAmount_whenSwitchingToZeroDecimalCurrency() throws {
        let m = try makeModel(.eur)                 // euro: 2 decimals
        m.tap("1"); m.tap("2"); m.tap("."); m.tap("5"); m.tap("0")
        XCTAssertEqual(m.amountString, "12.50")
        m.setCurrency(.all)                         // lek: no minor unit
        XCTAssertEqual(m.currency, .all)
        XCTAssertEqual(m.amountString, "12")        // decimals dropped → display == saved value
        XCTAssertFalse(m.allowsDecimal)             // "." key now hidden
    }

    func test_setCurrency_keepsAmount_whenSwitchingToHigherPrecision() throws {
        let m = try makeModel(.all)                 // lek
        m.tap("1"); m.tap("5"); m.tap("0")
        m.setCurrency(.eur)                          // euro
        XCTAssertEqual(m.currency, .eur)
        XCTAssertEqual(m.amountString, "150")        // integer amount unaffected
        XCTAssertTrue(m.allowsDecimal)
    }
}
