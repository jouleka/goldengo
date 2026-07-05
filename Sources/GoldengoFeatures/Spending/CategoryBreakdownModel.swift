import Foundation
import Observation
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

@MainActor
@Observable
public final class CategoryBreakdownModel {
    // Optional so `.preview` can exist with NO SwiftData behind it — `load()` is a no-op without
    // a store, leaving the hardcoded sample `breakdown` on screen untouched.
    private let store: IngestionStore?
    public var currency: CurrencyCode
    public var monthAnchor: Date
    public private(set) var breakdown: CategoryBreakdown?

    public init(store: IngestionStore, currency: CurrencyCode = .all, monthAnchor: Date = .now) {
        self.store = store
        self.currency = currency
        self.monthAnchor = monthAnchor
    }

    private init(previewCurrency currency: CurrencyCode, monthAnchor: Date) {
        self.store = nil
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
        return CategoryDetailModel(store: store, categoryName: row.name, monthAnchor: monthAnchor, cap: row.budget)
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

    /// Preloaded with a hardcoded sample breakdown (no SwiftData) so the view renders standalone —
    /// backs the DEBUG simulator look-check entry.
    public static var preview: CategoryBreakdownModel {
        let model = CategoryBreakdownModel(previewCurrency: CurrencyCode("ALL"), monthAnchor: .now)
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        model.breakdown = CategoryBreakdown(
            monthStart: monthStart,
            total: 84200,
            rows: [
                CategoryBreakdownRow(name: "Food", icon: GoldengoCategoryIcon.symbol(for: "Food"),
                                     colorHex: GoldengoTheme.Hex.accentLight, spent: 24500, budget: nil,
                                     share: 0.291, level: .ok),
                CategoryBreakdownRow(name: "Other", icon: GoldengoCategoryIcon.symbol(for: "Other"),
                                     colorHex: GoldengoTheme.Hex.inkMutedLight, spent: 21700, budget: nil,
                                     share: 0.258, level: .noBudget),
                CategoryBreakdownRow(name: "Groceries", icon: GoldengoCategoryIcon.symbol(for: "Groceries"),
                                     colorHex: GoldengoTheme.Hex.incomeLight, spent: 18000, budget: 20000,
                                     share: 0.214, level: .near),
                // "Cigarettes" has no dedicated case in GoldengoCategoryIcon — using its own
                // documented fallback symbol ("tag") rather than guessing an unverified SF Symbol name.
                CategoryBreakdownRow(name: "Cigarettes", icon: GoldengoCategoryIcon.symbol(for: "Cigarettes"),
                                     colorHex: GoldengoTheme.Hex.dangerLight, spent: 12600, budget: 10000,
                                     share: 0.150, level: .over),
                CategoryBreakdownRow(name: "Coffee", icon: GoldengoCategoryIcon.symbol(for: "Coffee"),
                                     colorHex: "#8A77C0", spent: 7400, budget: 8000,
                                     share: 0.088, level: .near),
            ],
            currencyCode: "ALL",
            ratesAsOf: nil)
        return model
    }
}
