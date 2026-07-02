import Foundation
import GoldengoCore
import GoldengoData

public enum ExpenseLogging {
    /// Shared logging path for every capture surface. `automatic` tags hands-free captures
    /// (e.g. the Apple Pay Transaction automation) as `.automatic` so import reconciliation can
    /// dedupe them; everything else logs as `.manual`. Returns a short confirmation string.
    public static func log(amount: Decimal, currencyCode: String, merchant: String?,
                           categoryName: String?, store: IngestionStore,
                           automatic: Bool = false) async throws -> String {
        let currency = CurrencyCode(currencyCode)
        if automatic {
            try await store.logAutomatic(amount: amount, currency: currency,
                                         merchant: merchant, categoryName: categoryName)
        } else {
            try await store.logManual(amount: amount, currency: currency,
                                      merchant: merchant, categoryName: categoryName)
        }
        return "Logged \(Money(amount: amount, currency: currency).formatted())"
    }
}
