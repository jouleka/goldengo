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

    func test_refresh_keepsChargelessManualSub_andRollsNextChargeForward() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "iCloud", amount: 3, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 6, 20))
        // WHY: reconcile-archive exists to drop stale detector GUESSES; a manual sub is a user
        // statement and must survive refresh with zero charges.
        _ = try await store.refreshSubscriptions(now: day(2026, 8, 1))
        let rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1, "Chargeless manual sub survives refresh")
        // WHY roll: with no detected series to refresh it, "Next:" would assert a past date forever.
        XCTAssertEqual(rows.first?.nextChargeDate, day(2026, 8, 20))
    }

    func test_manualSub_ghostSurfacesOnlyOnceDue_neverBefore() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "Hetzner", amount: 9, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 6, 20))
        // WHY: predictions are surfaced as one-tap ghosts, never auto-logged, and never early —
        // a future declared date must stay silent.
        let before = try await store.pendingSubscriptionCharges(now: day(2026, 6, 15))
        XCTAssertTrue(before.isEmpty, "Nothing due before the declared date")
        let after = try await store.pendingSubscriptionCharges(now: day(2026, 6, 25))
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.dueDate, day(2026, 6, 20))
        XCTAssertEqual(after.first?.displayName, "Hetzner")
        XCTAssertEqual(after.first?.merchantName, "Hetzner",
                       "No evidence row yet — the display name is the merchant string a future import will merge on")
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
