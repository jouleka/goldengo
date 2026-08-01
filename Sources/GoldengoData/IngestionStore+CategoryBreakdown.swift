import Foundation
import SwiftData
import GoldengoCore

public struct CategoryBreakdownRow: Sendable, Hashable, Identifiable {
    public var name: String
    public var groupName: String
    public var subcategoryName: String?
    public var purpose: MoneyPurpose
    public var icon: String
    public var colorHex: String
    public var spent: Decimal
    public var budget: Decimal?
    public var share: Double
    public var level: BudgetLevel
    public var id: String { name }

    // Explicit public init: the auto-synthesized memberwise init is only `internal`, which blocks
    // constructing sample/preview rows from another module (e.g. GoldengoFeatures's DEBUG preview).
    public init(name: String, groupName: String? = nil, subcategoryName: String? = nil,
                purpose: MoneyPurpose? = nil, icon: String, colorHex: String, spent: Decimal,
                budget: Decimal? = nil, share: Double, level: BudgetLevel) {
        let classification = SpendingCategoryCatalog.classify(name)
        self.name = name
        self.groupName = groupName ?? classification.groupName
        self.subcategoryName = subcategoryName ?? classification.subcategoryName
        self.purpose = purpose ?? classification.purpose
        self.icon = icon; self.colorHex = colorHex; self.spent = spent
        self.budget = budget; self.share = share; self.level = level
    }
}

public struct CategoryBreakdown: Sendable, Equatable {
    public var monthStart: Date
    public var total: Decimal
    /// Consumption only. Wealth-building outflow is kept separate in `investedTotal`.
    public var spendingTotal: Decimal
    public var essentialTotal: Decimal
    public var lifestyleTotal: Decimal
    public var investedTotal: Decimal
    public var wasteTotal: Decimal
    public var otherTotal: Decimal
    public var rows: [CategoryBreakdownRow]
    public var currencyCode: String
    public var ratesAsOf: Date?

    // Explicit public init — see CategoryBreakdownRow's for why (internal-only synthesized init).
    public init(monthStart: Date, total: Decimal, rows: [CategoryBreakdownRow], currencyCode: String,
                ratesAsOf: Date? = nil) {
        self.init(monthStart: monthStart, total: total, rows: rows, currencyCode: currencyCode,
                  ratesAsOf: ratesAsOf, spendingTotal: nil, essentialTotal: nil,
                  lifestyleTotal: nil, investedTotal: nil, wasteTotal: nil, otherTotal: nil)
    }

    public init(monthStart: Date, total: Decimal, rows: [CategoryBreakdownRow], currencyCode: String,
                ratesAsOf: Date?, spendingTotal: Decimal?, essentialTotal: Decimal?,
                lifestyleTotal: Decimal?, investedTotal: Decimal?, wasteTotal: Decimal?,
                otherTotal: Decimal?) {
        let totals = Dictionary(grouping: rows, by: \.purpose)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.spent } }
        let invested = investedTotal ?? totals[.wealth, default: 0]
        self.monthStart = monthStart; self.total = total; self.rows = rows
        self.spendingTotal = spendingTotal ?? max(0, total - invested)
        self.essentialTotal = essentialTotal ?? totals[.essential, default: 0]
        self.lifestyleTotal = lifestyleTotal ?? totals[.lifestyle, default: 0]
        self.investedTotal = invested
        self.wasteTotal = wasteTotal ?? totals[.waste, default: 0]
        self.otherTotal = otherTotal ?? totals[.other, default: 0]
        self.currencyCode = currencyCode; self.ratesAsOf = ratesAsOf
    }
}

extension IngestionStore {
    /// Persist a cap on a category (creating it if missing, case-insensitively — same reuse rule as
    /// `findOrCreateCategory`). Used by the UI and tests.
    @discardableResult
    public func setMonthlyBudget(categoryNamed name: String, cap: Decimal?,
                                 currency: CurrencyCode) throws -> Bool {
        let cat = try findOrCreateCategory(named: name)
        cat.monthlyBudget = cap
        cat.monthlyBudgetCurrencyCode = cap == nil ? nil : currency.rawValue
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
        fd.relationshipKeyPathsForPrefetching = [\.category, \.splits]
        let records = try modelContext.fetch(fd)
        let categories = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
        let categoryByName = Dictionary(categories.map { ($0.name.lowercased(), $0) },
                                        uniquingKeysWith: { first, _ in first })

        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue
        let expenseRaw = TransactionKind.expense.rawValue
        let refundRaw = TransactionKind.refund.rawValue
        var usedConversion = false
        var boundLegacyBudgetCurrency = false

        func budgetInDisplayCurrency(for category: CategoryRecord?) -> Decimal? {
            guard let category, let cap = category.monthlyBudget else { return nil }
            let sourceCode: String
            if let persisted = category.monthlyBudgetCurrencyCode, !persisted.isEmpty {
                sourceCode = persisted
            } else {
                // Old records did not retain a currency. Bind once to the display currency in
                // which the user had been seeing the value, so later currency changes convert it.
                sourceCode = display
                category.monthlyBudgetCurrencyCode = display
                boundLegacyBudgetCurrency = true
            }
            if sourceCode != display { usedConversion = true }
            return try? converter.convert(cap, from: CurrencyCode(sourceCode), to: displayCurrency)
        }

        var spentByName: [String: Decimal] = [:]
        var metaByName: [String: (icon: String, colorHex: String, budget: Decimal?,
                                  groupName: String, subcategoryName: String?, purpose: MoneyPurpose)] = [:]
        var total = Decimal(0)
        for r in records where r.kindRaw == expenseRaw || r.kindRaw == refundRaw {
            if r.currencyCode != display { usedConversion = true }
            let sign = r.kindRaw == refundRaw ? Decimal(-1) : Decimal(1)
            let allocations: [(String, Decimal)] = (r.splits ?? []).isEmpty
                ? [(r.category?.name ?? "Other", r.amount)]
                : (r.splits ?? []).map { ($0.categoryName, $0.amount) }
            for (key, nativeAmount) in allocations {
                let v = ((try? converter.convert(nativeAmount, from: CurrencyCode(r.currencyCode),
                                                 to: displayCurrency)) ?? 0) * sign
                spentByName[key, default: 0] += v
                total += v
                if metaByName[key] != nil { continue }
                let classification = SpendingCategoryCatalog.classify(key)
                let storedCategory = categoryByName[key.lowercased()]
                // Known taxonomy colors are authoritative so existing all-blue records are fixed
                // immediately. Custom categories retain an explicitly stored presentation.
                let storedIcon = storedCategory?.icon
                let storedColor = storedCategory?.colorHex
                let icon = classification.isKnown || storedIcon == nil || storedIcon == "circle"
                    ? classification.icon : storedIcon!
                let color = classification.isKnown || storedColor == nil || storedColor == "#0A84FF"
                    ? classification.colorHex : storedColor!
                let budget = classification.purpose == .wealth
                    ? nil : budgetInDisplayCurrency(for: storedCategory)
                metaByName[key] = (icon, color, budget,
                                   classification.groupName, classification.subcategoryName,
                                   classification.purpose)
            }
        }

        // A cap is a plan, not merely a warning after money has already been spent. Include capped
        // zero-spend categories so users can plan proactively and still open/edit them this month.
        var rowNames = Array(spentByName.keys)
        var rowNameKeys = Set(rowNames.map { $0.lowercased() })
        for category in categories
        where category.monthlyBudget != nil
            && SpendingCategoryCatalog.classify(category.name).purpose != .wealth
            && rowNameKeys.insert(category.name.lowercased()).inserted {
            rowNames.append(category.name)
        }

        let totalDouble = (total as NSDecimalNumber).doubleValue
        let rows = rowNames.map { name -> CategoryBreakdownRow in
            let spent = spentByName[name] ?? 0
            let classification = SpendingCategoryCatalog.classify(name)
            let storedCategory = categoryByName[name.lowercased()]
            let m = metaByName[name] ?? (
                classification.isKnown || storedCategory?.icon == nil || storedCategory?.icon == "circle"
                    ? classification.icon : storedCategory!.icon,
                classification.isKnown || storedCategory?.colorHex == nil || storedCategory?.colorHex == "#0A84FF"
                    ? classification.colorHex : storedCategory!.colorHex,
                classification.purpose == .wealth ? nil : budgetInDisplayCurrency(for: storedCategory),
                classification.groupName, classification.subcategoryName, classification.purpose
            )
            let share = totalDouble > 0 ? (spent as NSDecimalNumber).doubleValue / totalDouble : 0
            return CategoryBreakdownRow(name: name, groupName: m.groupName,
                                        subcategoryName: m.subcategoryName, purpose: m.purpose,
                                        icon: m.icon, colorHex: m.colorHex,
                                        spent: spent, budget: m.budget, share: share,
                                        level: BudgetLevel.forSpend(spent, cap: m.budget))
        }
        .sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }

        if boundLegacyBudgetCurrency { try modelContext.save() }
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
        fd.relationshipKeyPathsForPrefetching = [\.category, \.splits]
        let records = try modelContext.fetch(fd)

        let converter = CurrencyConverter(table: rates)
        let expenseRaw = TransactionKind.expense.rawValue
        let refundRaw = TransactionKind.refund.rawValue

        var spentByName: [String: Decimal] = [:]
        for r in records where r.kindRaw == expenseRaw || r.kindRaw == refundRaw {
            let sign = r.kindRaw == refundRaw ? Decimal(-1) : Decimal(1)
            let allocations: [(String, Decimal)] = (r.splits ?? []).isEmpty
                ? [(r.category?.name ?? "Other", r.amount)]
                : (r.splits ?? []).map { ($0.categoryName, $0.amount) }
            for (name, nativeAmount) in allocations {
                let v = ((try? converter.convert(nativeAmount, from: CurrencyCode(r.currencyCode),
                                                 to: displayCurrency)) ?? 0) * sign
                spentByName[name.lowercased(), default: 0] += v
            }
        }

        // Categories with a cap — Decimal filtered in memory, never in a #Predicate.
        let capped = try modelContext.fetch(FetchDescriptor<CategoryRecord>()).filter { $0.monthlyBudget != nil }

        var alerts: [BudgetAlert] = []
        var mutated = false
        for cat in capped {
            // Investments are asset-building outflow, not consumption to police with a spending cap.
            guard SpendingCategoryCatalog.classify(cat.name).purpose != .wealth else { continue }
            guard let storedCap = cat.monthlyBudget else { continue }
            let capCurrency: String
            if let persisted = cat.monthlyBudgetCurrencyCode, !persisted.isEmpty {
                capCurrency = persisted
            } else {
                capCurrency = displayCurrency.rawValue
                cat.monthlyBudgetCurrencyCode = capCurrency
                mutated = true
            }
            guard let cap = try? converter.convert(storedCap, from: CurrencyCode(capCurrency),
                                                   to: displayCurrency) else { continue }
            let spent = spentByName[cat.name.lowercased()] ?? 0
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
        fd.relationshipKeyPathsForPrefetching = [\.category, \.splits]
        let records = try modelContext.fetch(fd)

        let expenseRaw = TransactionKind.expense.rawValue
        let refundRaw = TransactionKind.refund.rawValue
        let isOther = name.caseInsensitiveCompare("Other") == .orderedSame
        let matches: (ExpenseRecord) -> Bool = isOther
            ? { record in
                if !(record.splits ?? []).isEmpty {
                    return (record.splits ?? []).contains {
                        $0.categoryName.caseInsensitiveCompare("Other") == .orderedSame
                    }
                }
                guard let categoryName = record.category?.name else { return true }
                return categoryName.caseInsensitiveCompare("Other") == .orderedSame
            }
            : { record in
                if !(record.splits ?? []).isEmpty {
                    return (record.splits ?? []).contains {
                        $0.categoryName.caseInsensitiveCompare(name) == .orderedSame
                    }
                }
                return record.category?.name.caseInsensitiveCompare(name) == .orderedSame
            }

        return records
            .filter { ($0.kindRaw == expenseRaw || $0.kindRaw == refundRaw) && matches($0) }
            .map { makeSnapshot($0) }
    }

    /// Assigns (or creates, case-insensitively) a category to a single expense by its `dedupeKey` —
    /// how a row leaves "Other" from the detail screen's categorize affordance.
    public func assignCategory(named categoryName: String, toExpenseWithKey dedupeKey: String,
                               rememberMerchant: Bool = false) throws {
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.dedupeKey == dedupeKey && $0.isArchived == false })
        fd.fetchLimit = 1
        guard let record = try modelContext.fetch(fd).first else { return }
        record.category = try findOrCreateCategory(named: categoryName)
        if rememberMerchant, let merchant = record.merchantName {
            try setMerchantRule(merchantName: merchant, categoryName: categoryName)
        }
        try modelContext.save()
    }
}
