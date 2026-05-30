import Foundation
import GoldengoCore
import GoldengoData

public enum ExpenseLogging {
    /// Shared logging path for every capture surface. Returns a short confirmation string.
    public static func log(amount: Decimal, currencyCode: String, merchant: String?,
                           categoryName: String?, store: IngestionStore) async throws -> String {
        let currency = CurrencyCode(currencyCode)
        try await store.logManual(amount: amount, currency: currency,
                                  merchant: merchant, categoryName: categoryName)
        return "Logged \(Money(amount: amount, currency: currency).formatted())"
    }
}
