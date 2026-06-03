import Foundation
import GoldengoCore
import GoldengoData

public enum ExpenseLogging {
    /// Shared logging path for every capture surface. Returns a short confirmation string.
    public static func log(amount: Decimal, currencyCode: String, merchant: String?,
                           note: String? = nil, categoryName: String?, store: IngestionStore) async throws -> String {
        let currency = CurrencyCode(currencyCode)
        try await store.logManual(amount: amount, currency: currency,
                                  merchant: merchant, note: note, categoryName: categoryName)
        let money = Money(amount: amount, currency: currency).formatted()
        let clean = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean?.isEmpty ?? true) ? "Logged \(money)" : "Logged \(money) — \(clean!)"
    }
}
