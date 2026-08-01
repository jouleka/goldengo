import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class CategoryBreakdownModel {
    private let store: IngestionStore?
    public var currency: CurrencyCode
    public var monthAnchor: Date
    public private(set) var breakdown: CategoryBreakdown?

    public init(store: IngestionStore, currency: CurrencyCode = .all, monthAnchor: Date = .now) {
        self.store = store
        self.currency = currency
        self.monthAnchor = monthAnchor
    }

    public func load() async {
        guard let store else { return }   // preview instance — sample data stays as-is
        let rates = ExchangeRateCache().load() ?? SeedRates.table
        // categoryBreakdown lives directly on the IngestionStore actor (not the async
        // RecentExpensesReading protocol surface), so the call still needs `await` to cross into
        // actor isolation even though the method itself isn't declared `async`. Same rates/currency
        // sourcing as RecentExpensesModel.load().
        if let result = try? await store.categoryBreakdown(monthContaining: monthAnchor,
                                                           displayCurrency: currency, rates: rates) {
            breakdown = result
        }
        // On failure, leave `breakdown` as-is (nil or the last good value) — never crash.
    }

    /// Advance the shown month by `delta` calendar months, then reload. Clamped so the current
    /// calendar month is the max — never steps into the future.
    public func step(_ delta: Int) async {
        let cal = Calendar.current
        guard let stepped = cal.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        let currentMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        let steppedMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: stepped)) ?? stepped
        monthAnchor = min(steppedMonthStart, currentMonthStart)
        await load()
    }

    /// True while the shown month is already the current calendar month — disables stepping forward.
    public var isCurrentMonth: Bool {
        Calendar.current.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    /// Builds the detail model for a tapped category row, carrying the same store/month/currency.
    /// Nil in the preview instance (no store to back it) — the view simply doesn't push in that case.
    public func detailModel(for row: CategoryBreakdownRow) -> CategoryDetailModel? {
        guard let store else { return nil }
        return CategoryDetailModel(store: store, categoryName: row.name, monthAnchor: monthAnchor,
                                   cap: row.budget, currency: currency)
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    /// e.g. "July 2026".
    public var monthTitle: String {
        Self.monthTitleFormatter.string(from: monthAnchor)
    }
}
