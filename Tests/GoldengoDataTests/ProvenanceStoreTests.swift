import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ProvenanceStoreTests: XCTestCase {
    func test_sourceRecord_linksIncomeViaProvenanceRelationship() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let src = SourceRecord(id: "s1", name: "Sister", currencyCode: "EUR", colorIndex: 0)
        ctx.insert(src)
        let inc = ExpenseRecord(amount: 200, currencyCode: "EUR", date: .now,
                                kind: .income, source: .manual, dedupeKey: "income:1")
        inc.provenanceSource = src
        ctx.insert(inc)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<SourceRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.incomes?.count, 1)
        XCTAssertEqual(fetched.first?.incomes?.first?.amount, 200)
    }
}
