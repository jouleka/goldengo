import Foundation
import SwiftData
import GoldengoCore

public struct CategoryBreakdownRow: Sendable, Equatable, Identifiable {
    public var name: String
    public var icon: String
    public var colorHex: String
    public var spent: Decimal
    public var budget: Decimal?
    public var share: Double
    public var level: BudgetLevel
    public var id: String { name }
}

public struct CategoryBreakdown: Sendable, Equatable {
    public var monthStart: Date
    public var total: Decimal
    public var rows: [CategoryBreakdownRow]
    public var currencyCode: String
    public var ratesAsOf: Date?
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
