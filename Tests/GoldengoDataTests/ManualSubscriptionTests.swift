import XCTest
import GoldengoCore
@testable import GoldengoData

final class ManualSubscriptionTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    func test_addManual_surfacesAsTracked_reAddConverges() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "Claude", amount: 20, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 7, 20))
        var rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.displayName, "Claude")
        XCTAssertTrue(rows.first?.isConfirmed ?? false,
                      "A manual sub is a user statement — tracked immediately, never a guess to review")
        // WHY converge: matchKey is the dedupe contract with detection — re-adding must update, not duplicate.
        try await store.addManualSubscription(name: "claude", amount: 22, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 8, 20))
        rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.amount, 22)
    }

    func test_detectedSeries_convergesOntoManualRecord_keepsConfirmed() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "Claude", amount: 20, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 7, 20))
        for m in 4...6 {
            _ = try await store.logManual(amount: 20, currency: .eur, merchant: "Claude",
                                          categoryName: nil, date: day(2026, m, 20))
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 7, 1))
        let rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1, "Detection and the manual record share one matchKey — one row, not two")
        XCTAssertTrue(rows.first?.isConfirmed ?? false, "Detection updates never revoke the user's confirmation")
        XCTAssertEqual(rows.first?.occurrenceCount, 3)
    }
}
