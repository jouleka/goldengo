import Foundation

/// Pure helpers for currency selection UIs. No `Locale`/UI dependency — the display-name lookup is
/// injected so the search filter stays deterministically unit-testable.
public enum CurrencyCatalog {
    /// Codes carried by FX feeds that aren't spendable everyday currencies (precious metals, SDR).
    public static let nonCurrencyCodes: Set<String> = ["XAU", "XAG", "XPD", "XPT", "XDR"]

    /// The selectable universe from a rate table: every rate code minus the non-currencies.
    public static func selectable(from table: RateTable) -> [CurrencyCode] {
        table.rates.keys
            .filter { !nonCurrencyCodes.contains($0) }
            .map(CurrencyCode.init)
    }

    /// Case-insensitive filter by ISO code OR display name. Empty query → input unchanged.
    public static func filter(_ codes: [CurrencyCode], query: String,
                              name: (CurrencyCode) -> String) -> [CurrencyCode] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return codes }
        return codes.filter {
            $0.rawValue.lowercased().contains(q) || name($0).lowercased().contains(q)
        }
    }
}
