import Foundation
import Observation
import GoldengoCore
import GoldengoData

/// Backs `CategoryDetailView`: one category's month expenses, its monthly cap, and (for "Other")
/// reassigning a row to a real category. Mirrors `CategoryBreakdownModel`'s shape — `store` is
/// Optional so `.preview` can exist with no SwiftData behind it.
@MainActor
@Observable
public final class CategoryDetailModel {
    private let store: IngestionStore?
    public let categoryName: String
    public var monthAnchor: Date
    public private(set) var expenses: [ExpenseSnapshot] = []
    public private(set) var cap: Decimal?
    /// Existing category names offered as one-tap chips when categorizing an "Other" row —
    /// same MRU-first source QuickAdd's chip row uses.
    public private(set) var existingCategoryNames: [String] = []

    public var isOther: Bool { categoryName == "Other" }

    public init(store: IngestionStore, categoryName: String, monthAnchor: Date, cap: Decimal?) {
        self.store = store
        self.categoryName = categoryName
        self.monthAnchor = monthAnchor
        self.cap = cap
    }

    private init(previewCategoryName: String, monthAnchor: Date, cap: Decimal?) {
        self.store = nil
        self.categoryName = previewCategoryName
        self.monthAnchor = monthAnchor
        self.cap = cap
    }

    public func load() async {
        guard let store else { return }   // preview instance — sample data stays as-is
        expenses = (try? await store.expenses(inCategoryNamed: categoryName, monthContaining: monthAnchor)) ?? expenses
        existingCategoryNames = (try? await store.recentCategoryNames()) ?? existingCategoryNames
    }

    /// Sets, edits, or clears (`nil`) the cap. Returns whether THIS category just transitioned from
    /// no-cap to capped (nil -> non-nil) — a necessary-but-not-sufficient signal for "first cap ever
    /// set app-wide"; the caller (`BudgetNotificationPermission.askOnce`) holds the actual app-wide
    /// once-ever gate via `UserDefaults`, since a second category's first cap must NOT re-prompt.
    @discardableResult
    public func setCap(_ newCap: Decimal?) async -> Bool {
        let wasFirstCap = cap == nil && newCap != nil
        guard let store else { cap = newCap; return wasFirstCap }
        try? await store.setMonthlyBudget(categoryNamed: categoryName, cap: newCap)
        cap = newCap
        return wasFirstCap
    }

    /// Assigns `name` to the expense at `dedupeKey`, then reloads — the row leaves "Other" on the
    /// next `load()` since it no longer matches the nil/"Other" bucket.
    public func assignCategory(_ name: String, toExpenseWithKey dedupeKey: String) async {
        guard let store else { return }
        try? await store.assignCategory(named: name, toExpenseWithKey: dedupeKey)
        await load()
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    /// e.g. "July 2026" — same formatting as `CategoryBreakdownModel.monthTitle`.
    public var monthTitle: String {
        Self.monthTitleFormatter.string(from: monthAnchor)
    }

    /// Preloaded with hardcoded sample expenses (no SwiftData) so the view renders standalone.
    public static var preview: CategoryDetailModel {
        let model = CategoryDetailModel(previewCategoryName: "Food", monthAnchor: .now, cap: nil)
        model.expenses = [
            ExpenseSnapshot(dedupeKey: "1", amount: 1200, currencyCode: "ALL", source: .manual,
                            categoryName: "Food", date: .now, merchantName: "Diner", note: nil,
                            kind: .expense, subscriptionName: nil),
            ExpenseSnapshot(dedupeKey: "2", amount: 800, currencyCode: "ALL", source: .manual,
                            categoryName: "Food", date: .now.addingTimeInterval(-86_400), merchantName: "Bakery",
                            note: nil, kind: .expense, subscriptionName: nil),
        ]
        model.existingCategoryNames = ["Food", "Groceries", "Coffee"]
        return model
    }

    /// Preview variant for the "Other" bucket, to check the categorize affordance standalone.
    public static var previewOther: CategoryDetailModel {
        let model = CategoryDetailModel(previewCategoryName: "Other", monthAnchor: .now, cap: nil)
        model.expenses = [
            ExpenseSnapshot(dedupeKey: "3", amount: 400, currencyCode: "ALL", source: .manual,
                            categoryName: nil, date: .now, merchantName: "Kiosk", note: nil,
                            kind: .expense, subscriptionName: nil),
        ]
        model.existingCategoryNames = ["Food", "Groceries", "Coffee"]
        return model
    }
}
