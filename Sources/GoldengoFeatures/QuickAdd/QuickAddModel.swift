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
    public var note: String = ""
    /// GOL-90: the source the user chose to pay from for THIS expense (nil = automatic FIFO).
    public var selectedSourceID: String?
    /// Named sources + remaining balances for the "Paid from" picker; empty hides the control.
    public private(set) var sourceBalances: [SourceBalance] = []

    /// Most-used categories surfaced as one-tap chips (smart defaults come later).
    public let quickCategories = ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping", "Other"]

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store
        self.currency = currency
    }

    /// Load the named sources (+ remaining balances) for the "Paid from" picker. Best-effort: a
    /// failure just leaves the control hidden. Reuses the cached provenance allocation (GOL-86).
    public func loadSources() async {
        let rates = ExchangeRateCache().load() ?? SeedRates.table
        sourceBalances = (try? await store.provenanceSnapshot(displayCurrency: currency, rates: rates))?.sources ?? []
    }

    /// Switch the currency for the in-progress expense, trimming the typed amount so it stays valid
    /// for the new currency's precision (e.g. €12.50 → L12). The symbol, "." key, and amount update
    /// via Observation.
    public func setCurrency(_ code: CurrencyCode) {
        currency = code
        amountString = CurrencyInput.fit(amountString, toFractionDigits: code.fractionDigits)
    }

    public var amountDecimal: Decimal { Decimal(string: amountString) ?? 0 }
    public var canSave: Bool { amountDecimal > 0 }

    /// Whether the keypad should offer a decimal point — only for currencies with a minor unit.
    /// For currencies like lek (no minor unit) the "." key does nothing, so it's hidden.
    public var allowsDecimal: Bool { currency.fractionDigits > 0 }
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
                                      note: note.isEmpty ? nil : note,
                                      categoryName: selectedCategory,
                                      fundedBySourceID: selectedSourceID)
            savedCount += 1
            reset()
            await loadSources()   // refresh remaining balances after the spend drew from a source
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
        note = ""
        selectedCategory = nil
        selectedSourceID = nil   // back to Automatic, so one tagged expense never mis-attributes the next
    }
}
