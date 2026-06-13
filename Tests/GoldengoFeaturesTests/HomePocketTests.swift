import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

final class HomePocketTests: XCTestCase {
    private func line(_ code: String, expected: Decimal, typical: Decimal, daysAgo: Int) -> PocketLine {
        let when = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: .now)!
        return PocketLine(currencyCode: code, expected: expected, confidence: .even,
                          typicalCashDay: typical, lastMovement: when)
    }

    func test_heroPocketLine_prefersSelectedCurrencyThenFirst() {
        let lines = [line("ALL", expected: 8000, typical: 0, daysAgo: 0),
                     line("EUR", expected: 120, typical: 0, daysAgo: 0)]
        XCTAssertEqual(RecentExpensesModel.heroPocketLine(from: lines, currency: .init("EUR"))?.currencyCode, "EUR")
        XCTAssertEqual(RecentExpensesModel.heroPocketLine(from: lines, currency: .all)?.currencyCode, "ALL")
        XCTAssertNil(RecentExpensesModel.heroPocketLine(from: [], currency: .all))
    }

    func test_pocketCaption_threeStates() {
        XCTAssertEqual(RecentExpensesModel.pocketCaption(for: line("EUR", expected: 100, typical: 0, daysAgo: 0), now: .now),
                       "ready to spend")
        let fogged = line("EUR", expected: 100, typical: 5, daysAgo: 4)   // 20 < 100
        XCTAssertEqual(RecentExpensesModel.pocketCaption(for: fogged, now: .now),
                       "losing track — reconcile when your wallet's out")
        let lost = line("EUR", expected: 100, typical: 40, daysAgo: 4)    // 160 >= 100
        XCTAssertEqual(RecentExpensesModel.pocketCaption(for: lost, now: .now),
                       "lost track — reconcile when your wallet's out")
    }
}
