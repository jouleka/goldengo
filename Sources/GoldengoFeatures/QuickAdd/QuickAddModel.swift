import Foundation
import Observation
import GoldengoCore
import GoldengoData
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    public var errorText: String?

    /// Bumped once per successful save. The view observes it to flash an "Added" confirmation, since
    /// after a save the fields reset and there's otherwise no cue that anything happened.
    public private(set) var savedCount: Int = 0

    public func tap(_ digit: String) {
        guard amountString.count < 12 else { return }
        if digit == "." {
            // No decimal point for currencies without a minor unit (e.g. lek), and only one.
            guard currency.fractionDigits > 0, !amountString.contains(".") else { return }
            amountString.append(amountString.isEmpty ? "0." : ".")
            return
        }
        if amountString.isEmpty && digit == "0" { return }   // no leading zero
        // Don't let the fractional part exceed the currency's digits (keeps display == saved value).
        if let dot = amountString.firstIndex(of: "."),
           amountString.distance(from: amountString.index(after: dot), to: amountString.endIndex) >= currency.fractionDigits {
            return
        }
        amountString.append(digit)
    }

    public func backspace() {
        guard !amountString.isEmpty else { return }
        amountString.removeLast()
    }

    public func save() async {
        guard canSave else { return }
        do {
            try await store.logManual(amount: amountDecimal, currency: currency,
                                      merchant: merchant.isEmpty ? nil : merchant,
                                      categoryName: selectedCategory)
            savedCount += 1
            reset()
#if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
#endif
        } catch {
            errorText = error.localizedDescription
        }
    }

    public func reset() {
        amountString = ""
        merchant = ""
        selectedCategory = nil
    }
}
