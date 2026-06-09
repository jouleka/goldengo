import XCTest
@testable import GoldengoCore

final class ProvenanceAllocatorTests: XCTestCase {
    // 1 EUR = 100 ALL, 1 USD = 100 ALL (base USD).
    private let rates = RateTable(base: CurrencyCode("USD"),
                                  rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                  asOf: Date(timeIntervalSince1970: 1_780_000_000))
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 86_400) }

    func test_fifo_drainsOldestSourceFirst() {
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 1000, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "B", amount: 1000, currency: .all, date: day(2)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 600, currency: .all, date: day(3))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 400)
        XCTAssertEqual(a.remainingBySource["B"], 1000)
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: 600)])
        XCTAssertEqual(a.totalUnaccounted, 0)
    }

    func test_outflow_spansTwoLots() {
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 500, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "B", amount: 500, currency: .all, date: day(1)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 800, currency: .all, date: day(2))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 0)
        XCTAssertEqual(a.remainingBySource["B"], 200)
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: 500), .init(sourceID: "B", amount: 300)])
    }

    func test_crossCurrency_eurSourceFundsLekSpend() {
        let inflows = [ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 10, currency: .eur, date: day(0))]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 250, currency: .all, date: day(1))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], d("7.5"))
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: d("2.5"))])
        XCTAssertEqual(a.totalUnaccounted, 0)
    }

    func test_overspend_goesToUnaccounted() {
        let inflows = [ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 100, currency: .all, date: day(0))]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 300, currency: .all, date: day(1))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 0)
        XCTAssertEqual(a.totalUnaccounted, 200)
    }

    func test_expenseBeforeAnyInflow_isUnaccounted_noRetroactiveFunding() {
        let inflows = [ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 1000, currency: .all, date: day(5))]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 200, currency: .all, date: day(1))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.totalUnaccounted, 200)
        XCTAssertEqual(a.remainingBySource["A"], 1000)
        XCTAssertNil(a.fundingByOutflow["o1"])
    }

    func test_remaining_neverNegative_multiSource() {
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 100, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "A", amount: 100, currency: .all, date: day(1)),
            ProvenanceAllocator.Inflow(id: "i3", sourceID: "B", amount: 100, currency: .all, date: day(2)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 250, currency: .all, date: day(3))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 0)
        XCTAssertEqual(a.remainingBySource["B"], 50)
    }

    // MARK: Pinned funding (GOL-89) — the user explicitly chose the source.

    func test_pin_overridesFifo_drawsFromPinnedSource() {
        // FIFO would pick A (older); the pin says B — the pin must win.
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 1000, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "B", amount: 1000, currency: .all, date: day(1)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 600, currency: .all, date: day(2),
                                                    pinnedSourceID: "B")]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "B", amount: 600)])
        XCTAssertEqual(a.remainingBySource["A"], 1000, "FIFO must not touch A when the pin names B.")
        XCTAssertEqual(a.remainingBySource["B"], 400)
    }

    func test_pin_reservesMoney_beforeUnpinnedFifo() {
        // An EARLIER unpinned spend would FIFO-drain A; the later pinned-to-A spend must still get
        // A's money (pins are allocated first), pushing the unpinned spend onto B.
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 500, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "B", amount: 500, currency: .all, date: day(0)),
        ]
        let outflows = [
            ProvenanceAllocator.Outflow(id: "o1", amount: 500, currency: .all, date: day(1)),                       // unpinned, earlier
            ProvenanceAllocator.Outflow(id: "o2", amount: 500, currency: .all, date: day(2), pinnedSourceID: "A"),  // pinned, later
        ]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.fundingByOutflow["o2"], [.init(sourceID: "A", amount: 500)], "The pin reserves A.")
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "B", amount: 500)], "FIFO takes what's left.")
        XCTAssertEqual(a.totalUnaccounted, 0)
    }

    func test_pin_ignoresDateRule_lateLoggedIncomeStillFunds() {
        // Income dated AFTER the spend: automatic FIFO refuses (no retroactive funding), but an
        // explicit pin is the user stating the origin — logging order must not fight them.
        let inflows = [ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 1000, currency: .all, date: day(5))]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 200, currency: .all, date: day(1),
                                                    pinnedSourceID: "A")]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: 200)])
        XCTAssertEqual(a.remainingBySource["A"], 800)
        XCTAssertEqual(a.totalUnaccounted, 0)
    }

    func test_pin_shortfall_goesUnaccounted_noFallbackToOtherSources() {
        // The pinned pool lacks the money: surface the gap honestly — never silently draw from B.
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 100, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "B", amount: 1000, currency: .all, date: day(0)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 300, currency: .all, date: day(1),
                                                    pinnedSourceID: "A")]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: 100)])
        XCTAssertEqual(a.remainingBySource["B"], 1000, "No fallback: B untouched.")
        XCTAssertEqual(a.totalUnaccounted, 200)
    }
}
