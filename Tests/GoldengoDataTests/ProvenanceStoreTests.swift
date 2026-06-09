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

    func test_logIncome_createsSourceAndLinkedIncome() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logIncome(amount: 200, currency: .eur, sourceName: "Sister", date: .now)
        let snap = try await store.provenanceSnapshot(displayCurrency: .all)
        XCTAssertEqual(snap.sources.count, 1)
        XCTAssertEqual(snap.sources.first?.name, "Sister")
        XCTAssertEqual(snap.sources.first?.remaining, 200)
    }

    func test_findOrCreateSource_isCaseInsensitive() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logIncome(amount: 100, currency: .eur, sourceName: "Sister", date: .now)
        try await store.logIncome(amount: 50, currency: .eur, sourceName: "sister ", date: .now)
        let snap = try await store.provenanceSnapshot(displayCurrency: .all)
        XCTAssertEqual(snap.sources.count, 1, "Same source, two top-ups")
        XCTAssertEqual(snap.sources.first?.remaining, 150)
    }

    func test_provenanceSnapshot_drainsAndReportsFunding() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                              asOf: Date(timeIntervalSince1970: 1_780_000_000))
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Cash",
                                  date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.logManual(amount: 300, currency: .all, merchant: "Spar", categoryName: nil,
                                  date: Date(timeIntervalSince1970: 1_700_086_400))
        let snap = try await store.provenanceSnapshot(displayCurrency: .all, rates: rates)
        XCTAssertEqual(snap.sources.first?.remaining, 700)
        XCTAssertEqual(snap.unaccounted, 0)
        let recents = try await store.recentExpenses(limit: 10)
        let spend = recents.first { $0.kind == .expense }
        XCTAssertEqual(spend?.fundedBy, "Cash")
    }
}
