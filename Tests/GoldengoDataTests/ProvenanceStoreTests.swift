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
        // GOL-95 v2: unpinned manual spends are wallet-cash and bypass the pools entirely, so
        // this drain test pins the spend to the source (bank-paid) to exercise the FIFO path.
        let pre = try await store.provenanceSnapshot(displayCurrency: .all, rates: rates)
        let cashID = try XCTUnwrap(pre.sources.first?.id)
        try await store.logManual(amount: 300, currency: .all, merchant: "Spar", categoryName: nil,
                                  date: Date(timeIntervalSince1970: 1_700_086_400),
                                  fundedBySourceID: cashID)
        let snap = try await store.provenanceSnapshot(displayCurrency: .all, rates: rates)
        XCTAssertEqual(snap.sources.first?.remaining, 700)
        XCTAssertEqual(snap.unaccounted, 0)
        let recents = try await store.recentExpenses(limit: 10)
        let spend = recents.first { $0.kind == .expense }
        XCTAssertEqual(spend?.fundedBy, "Cash")
    }

    func test_deleteSource_archivesPoolAndItsMoney() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.logIncome(amount: 200, currency: .eur, sourceName: "Sister", date: d)
        try await store.logIncome(amount: 100, currency: .eur, sourceName: "Freelance", date: d)
        let pre = try await store.provenanceSnapshot(displayCurrency: .eur)
        let sisterID = try XCTUnwrap(pre.sources.first { $0.name == "Sister" }?.id)
        try await store.deleteSource(id: sisterID)
        let snap = try await store.provenanceSnapshot(displayCurrency: .eur)
        XCTAssertEqual(snap.sources.map(\.name), ["Freelance"], "The deleted pool is gone; others untouched")
        // WHY: the pool's money must leave the books WITH it — otherwise its archived inflows
        // keep funding future spends from a source that no longer exists (ghost funding), and a
        // re-created same-name source would resurrect the old balance instead of starting fresh.
        try await store.logIncome(amount: 50, currency: .eur, sourceName: "Sister", date: d.addingTimeInterval(60))
        let after = try await store.provenanceSnapshot(displayCurrency: .eur)
        XCTAssertEqual(after.sources.first { $0.name == "Sister" }?.remaining, 50,
                       "A re-created source starts fresh — the archived 200 stays archived")
    }

    func test_renameSource_keepsBalance_refusesLiveDuplicate() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.logIncome(amount: 200, currency: .eur, sourceName: "Sister", date: d)
        try await store.logIncome(amount: 100, currency: .eur, sourceName: "Freelance", date: d)
        let pre = try await store.provenanceSnapshot(displayCurrency: .eur)
        let id = try XCTUnwrap(pre.sources.first { $0.name == "Sister" }?.id)
        try await store.renameSource(id: id, to: "  Family ")
        let snap = try await store.provenanceSnapshot(displayCurrency: .eur)
        XCTAssertEqual(snap.sources.map(\.name).sorted(), ["Family", "Freelance"])
        // WHY: allocation keys on the stable source id — a rename must never move or lose money.
        XCTAssertEqual(snap.sources.first { $0.name == "Family" }?.remaining, 200)
        // WHY refuse: income routes to sources BY NAME (findOrCreateSource); two live pools with
        // the same name would make every future top-up ambiguous.
        try await store.renameSource(id: id, to: " freelance ")
        let after = try await store.provenanceSnapshot(displayCurrency: .eur)
        XCTAssertEqual(after.sources.map(\.name).sorted(), ["Family", "Freelance"],
                       "Case-insensitive collision with another live source is refused")
    }

    func test_setSourceRemaining_typedDisplayValue_isANoop() async throws {
        // ALL displays with 0 fraction digits. FIFO/FX residue below display precision must not
        // turn "set it to exactly what the screen shows" into a junk correction entry.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.logIncome(amount: 100, currency: .all, sourceName: "Cash", date: d)
        let pre = try await store.provenanceSnapshot(displayCurrency: .all)
        let id = try XCTUnwrap(pre.sources.first?.id)
        // A pinned sub-unit spend leaves 99.6 — which the screen shows as "ALL 100".
        _ = try await store.logManual(amount: Decimal(string: "0.4")!, currency: .all,
                                      merchant: "Residue", categoryName: nil,
                                      date: d.addingTimeInterval(60), fundedBySourceID: id)
        try await store.setSourceRemaining(100, sourceID: id, at: d.addingTimeInterval(120))
        let rows = try await store.recentExpenses(limit: 10)
        XCTAssertEqual(rows.filter { $0.kind == .income }.count, 1,
                       "Typing the displayed number adds no correction income")
        XCTAssertFalse(rows.contains { $0.dedupeKey.hasPrefix("drift:") },
                       "…and logs no Unaccounted entry either")
    }

    func test_setSourceRemaining_higherAddsIncome_lowerLogsVisibleUnaccounted() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.logIncome(amount: 200, currency: .eur, sourceName: "Sister", date: d)
        let pre = try await store.provenanceSnapshot(displayCurrency: .eur)
        let id = try XCTUnwrap(pre.sources.first?.id)

        // Higher: the gap arrives as ordinary income into the same pool — nothing is fabricated.
        try await store.setSourceRemaining(250, sourceID: id, at: d.addingTimeInterval(3600))
        var snap = try await store.provenanceSnapshot(displayCurrency: .eur)
        XCTAssertEqual(snap.sources.first?.remaining, 250)
        let afterHigher = try await store.recentExpenses(limit: 10)
        XCTAssertFalse(afterHigher.contains { $0.kind == .expense },
                       "Setting higher writes income, never an expense row")

        // Lower: the gap is a VISIBLE Unaccounted spend pinned to this pool (mirrors the wallet's
        // set-lower rule) — spend totals stay truthful and the user can delete it if it's wrong.
        try await store.setSourceRemaining(180, sourceID: id, at: d.addingTimeInterval(7200))
        snap = try await store.provenanceSnapshot(displayCurrency: .eur)
        XCTAssertEqual(snap.sources.first?.remaining, 180)
        let rows = try await store.recentExpenses(limit: 10)
        XCTAssertTrue(rows.contains { $0.dedupeKey.hasPrefix("drift:") && $0.amount == 70 },
                      "The correction is an honest, visible entry — never a silent balance rewrite")
    }
}
