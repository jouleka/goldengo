import XCTest
import SwiftData
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

/// End-to-end through the REAL data path (not synthetic snapshots): import the demo statement,
/// detect, confirm the subscription, then build reminders exactly as the UI does — proving a
/// confirmed real subscription yields one correctly-dated reminder, and unconfirmed/income do not.
final class SubscriptionRemindersIntegrationTests: XCTestCase {
    @MainActor
    func test_confirmedSampleSubscription_yieldsOneCorrectlyDatedReminder() async throws {
        let store = IngestionStore(modelContainer: try ModelContainer.goldengoInMemory())
        await ImportModel(store: store).importCSV(text: SampleStatement.csv, fileName: "sample.csv")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        _ = try await store.refreshSubscriptions(now: now)

        // Before confirming: nothing should be scheduled (reminders are confirmed-only).
        let beforeConfirm = SubscriptionReminders.plannedRequests(
            enabled: true, leadDays: 2, candidates: try await store.subscriptionCandidates(),
            now: now, calendar: cal)
        XCTAssertTrue(beforeConfirm.isEmpty, "no reminders until the user confirms")

        // Confirm the detected NETFLIX subscription.
        let netflix = try await store.subscriptionCandidates().first { $0.displayName.uppercased().contains("NETFLIX") }
        let key = try XCTUnwrap(netflix?.id, "sample should surface a NETFLIX candidate")
        try await store.confirmSubscription(matchKey: key)
        _ = try await store.refreshSubscriptions(now: now)

        // After confirming: exactly one reminder, for NETFLIX, fired 2 days before the Jun 15 charge.
        let reqs = SubscriptionReminders.plannedRequests(
            enabled: true, leadDays: 2, candidates: try await store.subscriptionCandidates(),
            now: now, calendar: cal)
        XCTAssertEqual(reqs.count, 1)
        XCTAssertTrue(reqs[0].title.uppercased().contains("NETFLIX"))
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: reqs[0].fireDate),
                       cal.dateComponents([.year, .month, .day],
                                          from: cal.date(from: DateComponents(year: 2026, month: 6, day: 13))!))

        // Toggle off → nothing scheduled even with a confirmed sub.
        let disabled = SubscriptionReminders.plannedRequests(
            enabled: false, leadDays: 2, candidates: try await store.subscriptionCandidates(),
            now: now, calendar: cal)
        XCTAssertTrue(disabled.isEmpty)
    }
}
