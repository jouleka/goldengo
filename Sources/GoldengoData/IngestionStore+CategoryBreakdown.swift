import Foundation
import SwiftData
import GoldengoCore

public struct CategoryBreakdownRow: Sendable, Hashable, Identifiable {
    public var name: String
    public var icon: String
    public var colorHex: String
    public var spent: Decimal
    public var budget: Decimal?
    public var share: Double
    public var level: BudgetLevel
    public var id: String { name }

    // Explicit public init: the auto-synthesized memberwise init is only `internal`, which blocks
    // constructing sample/preview rows from another module (e.g. GoldengoFeatures's DEBUG preview).
    public init(name: String, icon: String, colorHex: String, spent: Decimal, budget: Decimal? = nil,
                share: Double, level: BudgetLevel) {
        self.name = name; self.icon = icon; self.colorHex = colorHex; self.spent = spent
        self.budget = budget; self.share = share; self.level = level
    }
}

public struct CategoryBreakdown: Sendable, Equatable {
    public var monthStart: Date
    public var total: Decimal
    public var rows: [CategoryBreakdownRow]
    public var currencyCode: String
    public var ratesAsOf: Date?

    // Explicit public init — see CategoryBreakdownRow's for why (internal-only synthesized init).
    public init(monthStart: Date, total: Decimal, rows: [CategoryBreakdownRow], currencyCode: String,
                ratesAsOf: Date? = nil) {
        self.monthStart = monthStart; self.total = total; self.rows = rows
        self.currencyCode = currencyCode; self.ratesAsOf = ratesAsOf
    }
}

extension IngestionStore {
    /// Persist a cap on a category (creating it if missing, case-insensitively — same reuse rule as
    /// `findOrCreateCategory`). Used by the UI and tests.
    @discardableResult
    public func setMonthlyBudget(categoryNamed name: String, cap: Decimal?) throws -> Bool {
        let cat = try findOrCreateCategory(named: name)
        cat.monthlyBudget = cap
        try modelContext.save()
        return true
    }

    public func categoryBreakdown(monthContaining date: Date,
                                  displayCurrency: CurrencyCode,
                                  rates: RateTable) throws -> CategoryBreakdown {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? date

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.date >= monthStart && $0.date < monthEnd })
        fd.relationshipKeyPathsForPrefetching = [\.category]
        let records = try modelContext.fetch(fd)

        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue
        let expenseRaw = TransactionKind.expense.rawValue

        var spentByName: [String: Decimal] = [:]
        var metaByName: [String: (icon: String, colorHex: String, budget: Decimal?)] = [:]
        var total = Decimal(0)
        var usedConversion = false
        for r in records where r.kindRaw == expenseRaw {
            if r.currencyCode != display { usedConversion = true }
            let key = r.category?.name ?? "Other"
            let v = (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            spentByName[key, default: 0] += v
            total += v
            if metaByName[key] == nil {
                metaByName[key] = (r.category?.icon ?? "tag",
                                   r.category?.colorHex ?? "#8C8373",
                                   r.category?.monthlyBudget)
            }
        }

        let totalDouble = (total as NSDecimalNumber).doubleValue
        let rows = spentByName.map { (name, spent) -> CategoryBreakdownRow in
            let m = metaByName[name] ?? ("tag", "#8C8373", nil)
            let share = totalDouble > 0 ? (spent as NSDecimalNumber).doubleValue / totalDouble : 0
            return CategoryBreakdownRow(name: name, icon: m.icon, colorHex: m.colorHex,
                                        spent: spent, budget: m.budget, share: share,
                                        level: BudgetLevel.forSpend(spent, cap: m.budget))
        }
        .sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }

        return CategoryBreakdown(monthStart: monthStart, total: total, rows: rows,
                                 currencyCode: display, ratesAsOf: usedConversion ? rates.asOf : nil)
    }
}

public struct BudgetAlert: Sendable, Equatable {
    public var categoryName: String
    public var level: BudgetLevel      // .near or .over
    public var spent: Decimal
    public var budget: Decimal
    public var currencyCode: String
}

extension IngestionStore {
    /// Evaluates this month's capped categories and returns the alerts that NEWLY escalated
    /// (each level fires at most once per category per month). Side effect: this CONSUMES the
    /// notify-once token — it persists the new level so that alert won't fire again. Call it only
    /// where notifications are actually delivered; never from a read-only / status-display path.
    public func evaluateBudgetAlerts(asOf now: Date = .now,
                                     displayCurrency: CurrencyCode,
                                     rates: RateTable) throws -> [BudgetAlert] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        guard let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [] }

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.date >= monthStart && $0.date < monthEnd })
        fd.relationshipKeyPathsForPrefetching = [\.category]
        let records = try modelContext.fetch(fd)

        let converter = CurrencyConverter(table: rates)
        let expenseRaw = TransactionKind.expense.rawValue

        var spentByName: [String: Decimal] = [:]
        for r in records where r.kindRaw == expenseRaw {
            guard let name = r.category?.name else { continue }
            let v = (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            spentByName[name, default: 0] += v
        }

        // Categories with a cap — Decimal filtered in memory, never in a #Predicate.
        let capped = try modelContext.fetch(FetchDescriptor<CategoryRecord>()).filter { $0.monthlyBudget != nil }

        var alerts: [BudgetAlert] = []
        var mutated = false
        for cat in capped {
            guard let cap = cat.monthlyBudget else { continue }
            let spent = spentByName[cat.name] ?? 0
            let level = BudgetLevel.forSpend(spent, cap: cap)

            let sameMonth = cat.budgetAlertMonth.map {
                cal.isDate($0, equalTo: monthStart, toGranularity: .month)
            } ?? false
            let storedRank = sameMonth ? (BudgetLevel(rawValue: cat.budgetAlertLevelRaw)?.rank ?? 0) : 0

            if level.rank > storedRank {
                alerts.append(BudgetAlert(categoryName: cat.name, level: level, spent: spent,
                                          budget: cap, currencyCode: displayCurrency.rawValue))
                cat.budgetAlertLevelRaw = level.rawValue
                cat.budgetAlertMonth = monthStart
                mutated = true
            } else if !sameMonth {
                cat.budgetAlertLevelRaw = level.rawValue     // new-month baseline, no spurious alert
                cat.budgetAlertMonth = monthStart
                mutated = true
            }
        }
        if mutated { try modelContext.save() }
        return alerts
    }
}

extension IngestionStore {
    /// This category's expenses for the given month, date-desc — backs the category detail screen.
    /// Date-only `#Predicate` (never `Decimal`); kind/category/archived filtered in memory. For
    /// `"Other"` this buckets BOTH nil-category and literally-"Other"-named records (mirrors
    /// `categoryBreakdown`'s `category?.name ?? "Other"` grouping), so the detail list matches what
    /// the breakdown row actually summed.
    public func expenses(inCategoryNamed name: String, monthContaining date: Date) throws -> [ExpenseSnapshot] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? date

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.date >= monthStart && $0.date < monthEnd },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.relationshipKeyPathsForPrefetching = [\.category]
        let records = try modelContext.fetch(fd)

        let expenseRaw = TransactionKind.expense.rawValue
        let matches: (ExpenseRecord) -> Bool = name == "Other"
            ? { $0.category == nil || $0.category?.name == "Other" }
            : { $0.category?.name == name }

        return records
            .filter { $0.kindRaw == expenseRaw && matches($0) }
            .map { makeSnapshot($0) }
    }

    /// Assigns (or creates, case-insensitively) a category to a single expense by its `dedupeKey` —
    /// how a row leaves "Other" from the detail screen's categorize affordance.
    public func assignCategory(named categoryName: String, toExpenseWithKey dedupeKey: String) throws {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == dedupeKey })
        fd.fetchLimit = 1
        guard let record = try modelContext.fetch(fd).first else { return }
        record.category = try findOrCreateCategory(named: categoryName)
        try modelContext.save()
    }
}
