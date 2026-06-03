import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class SubscriptionsCurrencyTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    // GOL-69: a euro-billed merchant is detected as a EUR subscription and shown in euro on the
    // Subscriptions tab (not coerced to lek).
    func test_euroBilledSubscription_detectsAndDisplaysInEuro() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        for m in [3, 4, 5] {
            _ = try await store.ingest(NormalizedTransaction(externalID: "e\(m)", amount: Decimal(string: "9.99")!,
                currency: CurrencyCode("EUR"), date: day(2026, m, 5), rawMerchant: "Spotify",
                kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 5, 10))
        let cands = try await store.subscriptionCandidates()
        let sub = try XCTUnwrap(cands.first)
        XCTAssertEqual(sub.currencyCode, "EUR")                                  // detected in euro
        XCTAssertTrue(SubscriptionsModel(store: store).amountCadenceText(sub).hasPrefix("€ 9.99")) // shown in euro
    }
}
