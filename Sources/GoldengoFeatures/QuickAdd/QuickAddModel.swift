import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class QuickAddModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var amountString: String = ""
    public var selectedCategory: String?
    public var merchant: String = ""

    /// Most-used categories surfaced as one-tap chips (smart defaults come later).
    public let quickCategories = ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping"]

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store
        self.currency = currency
    }

    public var amountDecimal: Decimal { Decimal(string: amountString) ?? 0 }
    public var canSave: Bool { amountDecimal > 0 }
    public var formattedAmount: String { Money(amount: amountDecimal, currency: currency).formatted() }

    public func tap(_ digit: String) {
        guard amountString.count < 12 else { return }
        if amountString.isEmpty && digit == "0" { return }
        amountString.append(digit)
    }

    public func backspace() {
        guard !amountString.isEmpty else { return }
        amountString.removeLast()
    }

    public func save() async throws {
        guard canSave else { return }
        try await store.logManual(amount: amountDecimal, currency: currency,
                                  merchant: merchant.isEmpty ? nil : merchant,
                                  categoryName: selectedCategory)
        reset()
    }

    public func reset() {
        amountString = ""
        merchant = ""
        selectedCategory = nil
    }
}
