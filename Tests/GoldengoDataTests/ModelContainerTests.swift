import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ModelContainerTests: XCTestCase {
    func test_inMemoryContainer_buildsAndPersistsExpense() throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let e = ExpenseRecord(amount: 1500, currencyCode: "ALL", date: .now,
                              kind: .expense, source: .manual, dedupeKey: "cmp:x")
        ctx.insert(e)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<ExpenseRecord>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.kind, .expense)
        XCTAssertEqual(all.first?.money, Money(amount: 1500, currency: .all))
    }
}
