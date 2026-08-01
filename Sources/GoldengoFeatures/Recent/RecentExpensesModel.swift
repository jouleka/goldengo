import Foundation
import Observation
import GoldengoCore
import GoldengoData

/// A calendar-day bucket of recent rows, backing the Home "Recent" list's day sections.
public struct DayGroup: Identifiable, Equatable {
    public let id: Date          // start-of-day — stable bucket key (survives reloads, drives collapse state)
    public let title: String     // "Today" / "Yesterday" / a concrete date like "Mon 23 Jun"
    public let rows: [ExpenseSnapshot]
}

@MainActor
@Observable
public final class RecentExpensesModel {
    private let reader: any RecentExpensesReading
    public var currency: CurrencyCode
    public private(set) var rows: [ExpenseSnapshot] = []
    public private(set) var todayTotalText: String = ""
    public private(set) var summary: DashboardSummary?
    /// True when the last load threw. The view surfaces this instead of silently showing an empty
    /// list (errors used to be swallowed with `try?`).
    public private(set) var loadFailed = false
    public private(set) var ghosts: [RhythmGhost] = []
    /// Due-but-unlogged subscription charges for the one-tap "Due" section (GOL-92).
    public private(set) var pendingCharges: [PendingSubscriptionCharge] = []
    /// Named sources for the edit sheet's "Paid from" chips (GOL-89); rides along in homeData.
    public private(set) var fundingSources: [FundingSourceOption] = []
    /// Read-only per-currency wallet snapshot driving the "In your pocket" hero. Home never writes wallet.
    public private(set) var pocketLines: [PocketLine] = []
    /// Top rows (already spent-desc) for the compact Spending card — at most 3, each with its
    /// per-category budget bar when capped. Read-only; never touches `evaluateBudgetAlerts`.
    public private(set) var spendingCardRows: [CategoryBreakdownRow] = []
    /// True when any category this month is over its cap — drives the card's terracotta dot.
    public private(set) var hasOverBudgetCategory = false
    /// The currency the breakdown rows were computed in — always `currency` at load time, but kept
    /// alongside the rows so a card render mid-currency-switch never mismatches amount vs. symbol.
    public private(set) var spendingCardCurrency: CurrencyCode = .all

    public init(store: any RecentExpensesReading, currency: CurrencyCode = .all) {
        self.reader = store; self.currency = currency
    }

    public func load() async {
        let rates = ExchangeRateCache().load() ?? SeedRates.table
        do {
            let data = try await reader.homeData(in: currency, rates: rates, now: .now, topCategoryLimit: 4)
            rows = data.rows
            todayTotalText = Money(amount: data.todayTotal, currency: currency).formatted()
            summary = data.summary
            ghosts = data.ghosts
            pendingCharges = data.pending
            fundingSources = data.sources
            pocketLines = data.pocket
            loadFailed = false
        } catch {
            // Keep any previously-loaded rows on screen; surface the failure so the user can retry.
            loadFailed = true
        }
        // A second, independent read for the Spending card. Kept out of the `do/catch` above so a
        // breakdown failure never flips `loadFailed` (which drives the Recent list's error banner) —
        // the card degrades to empty instead. Read-only: never call `evaluateBudgetAlerts` here, it
        // consumes the notify-once token meant for actual notification delivery.
        if let breakdown = try? await reader.categoryBreakdown(monthContaining: .now, displayCurrency: currency, rates: rates) {
            spendingCardRows = Array(breakdown.rows.prefix(3))
            hasOverBudgetCategory = breakdown.rows.contains { $0.level == .over }
            spendingCardCurrency = currency
        } else {
            spendingCardRows = []
            hasOverBudgetCategory = false
        }
    }

    /// The wallet line the hero shows: the one matching the display currency, else the first
    /// (balances arrive ALL-first), else nil when there is no wallet.
    public nonisolated static func heroPocketLine(from lines: [PocketLine], currency: CurrencyCode) -> PocketLine? {
        if let match = lines.first(where: { $0.currencyCode == currency.rawValue }) { return match }
        return lines.first
    }

    /// In-app fog caption (the lock-screen widget keeps its own phrasing). Always paired with the
    /// REAL figure in the hero — the caption conveys uncertainty, it never hides the number.
    public nonisolated static func pocketCaption(for line: PocketLine?, now: Date) -> String {
        guard let line else { return "" }
        let silent = PocketFog.silentDays(from: line.lastMovement, to: now)
        switch PocketFog.confidence(silentDays: silent, typicalCashDay: line.typicalCashDay, walletTotal: line.expected) {
        case .even:   return "ready to spend"
        case .fogged: return "losing track — reconcile when your wallet's out"
        case .lost:   return "lost track — reconcile when your wallet's out"
        }
    }

    /// Bucket already-newest-first rows into calendar days, preserving order so groups come out
    /// newest-day-first (rows within a day stay newest-first). `now` — not the system clock — drives
    /// the relative "Today"/"Yesterday" labels, so the result is deterministic and unit-testable.
    public nonisolated static func dayGroups(from rows: [ExpenseSnapshot], now: Date,
                                             calendar: Calendar = .current) -> [DayGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var order: [Date] = []
        var buckets: [Date: [ExpenseSnapshot]] = [:]
        for row in rows {
            let day = calendar.startOfDay(for: row.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(row)
        }
        return order.map { day in
            let title: String
            if day == today {
                title = "Today"
            } else if let yesterday, day == yesterday {
                title = "Yesterday"
            } else {
                title = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            return DayGroup(id: day, title: title, rows: buckets[day] ?? [])
        }
    }

    /// Like `dayGroups`, but buckets by calendar month — the Year view's grouping. Newest month first.
    /// Labels: "This month" for the month containing `now`, "June" for other months this year, and
    /// "June 2025" for months in a prior year (so a year is never ambiguous).
    public nonisolated static func monthGroups(from rows: [ExpenseSnapshot], now: Date,
                                               calendar: Calendar = .current) -> [DayGroup] {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start
        let nowYear = calendar.component(.year, from: now)
        var order: [Date] = []
        var buckets: [Date: [ExpenseSnapshot]] = [:]
        for row in rows {
            let monthStart = calendar.dateInterval(of: .month, for: row.date)?.start
                ?? calendar.startOfDay(for: row.date)
            if buckets[monthStart] == nil { order.append(monthStart) }
            buckets[monthStart, default: []].append(row)
        }
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        return order.map { month in
            let title: String
            if let thisMonth, month == thisMonth {
                title = "This month"
            } else if calendar.component(.year, from: month) == nowYear {
                fmt.setLocalizedDateFormatFromTemplate("MMMM")
                title = fmt.string(from: month)
            } else {
                fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
                title = fmt.string(from: month)
            }
            return DayGroup(id: month, title: title, rows: buckets[month] ?? [])
        }
    }

    public var hasWallet: Bool { !pocketLines.isEmpty }

    /// The hero's money string (real figure, formatted in the line's own currency), or "" if no wallet.
    public var pocketHeroText: String {
        guard let line = Self.heroPocketLine(from: pocketLines, currency: currency) else { return "" }
        return Money(amount: line.expected, currency: CurrencyCode(line.currencyCode)).formatted()
    }

    public var pocketCaptionText: String {
        Self.pocketCaption(for: Self.heroPocketLine(from: pocketLines, currency: currency), now: .now)
    }

    /// A short summary of the non-hero wallet currencies, e.g. "and €35.00 on hand".
    /// Returns "" when there are no secondary currencies or no wallet.
    public var pocketSecondaryText: String {
        guard hasWallet else { return "" }
        let heroCode = Self.heroPocketLine(from: pocketLines, currency: currency)?.currencyCode
        let others = pocketLines.filter { $0.currencyCode != heroCode }
        guard !others.isEmpty else { return "" }
        let parts = others.map { Money(amount: $0.expected, currency: CurrencyCode($0.currencyCode)).formatted() }
        return "and \(parts.joined(separator: " · ")) on hand"
    }

    /// The rate date behind the converted totals, when conversion was involved (for the staleness caption).
    public var ratesAsOf: Date? { summary?.ratesAsOf }

    /// Soft-delete an expense, then reload so the row disappears.
    public func delete(_ snapshot: ExpenseSnapshot) async {
        try? await reader.deleteExpense(dedupeKey: snapshot.dedupeKey)
        await load()
    }

    /// Undo a soft-delete, then reload so the row reappears (backs the "Undo" toast).
    public func restore(_ snapshot: ExpenseSnapshot) async {
        try? await reader.restoreExpense(dedupeKey: snapshot.dedupeKey)
        await load()
    }

    /// Confirm a daily "usual": log it at `amount` (default = its median), then reload so it clears.
    public func confirm(_ ghost: RhythmGhost, amount: Decimal? = nil) async {
        try? await reader.confirmRhythmGhost(ghost, amount: amount ?? ghost.amount)
        await load()
    }

    /// Log a due subscription charge from its "Due" ghost (GOL-92): backdated to the due date,
    /// `.automatic` so a later statement import merges into it. Reload clears the ghost (the new
    /// row now covers its due date).
    public func logPending(_ charge: PendingSubscriptionCharge) async {
        // Drop the ghost SYNCHRONOUSLY, before the first await: every log is a distinct insert
        // (unique key), so a double-tap during the actor round-trip would double-count. The
        // guard makes a re-entrant second tap a no-op; load() recomputes the true list after.
        guard pendingCharges.contains(charge) else { return }
        pendingCharges.removeAll { $0.id == charge.id }
        _ = try? await reader.logAutomatic(amount: charge.amount,
                                           currency: CurrencyCode(charge.currencyCode),
                                           merchant: charge.merchantName,
                                           categoryName: nil, date: charge.dueDate)
        await load()
    }

    /// Apply an edit to an expense, then reload so the change is reflected. `fundedBySourceID` is the
    /// FINAL funding pin (nil = automatic FIFO) — callers pass the sheet's selection, which starts
    /// from the row's current pin, so an untouched picker leaves the pin unchanged.
    public func update(_ snapshot: ExpenseSnapshot, amount: Decimal, currency: CurrencyCode? = nil,
                       merchant: String?, note: String? = nil, categoryName: String?, date: Date,
                       fundedBySourceID: String?, contextName: String? = nil,
                       splits: [TransactionSplit] = [], kind: TransactionKind? = nil) async {
        try? await reader.updateExpense(dedupeKey: snapshot.dedupeKey, amount: amount, currency: currency,
                                        merchant: merchant, note: note, categoryName: categoryName, date: date,
                                        fundedBySourceID: fundedBySourceID)
        try? await reader.updateTransactionKind(dedupeKey: snapshot.dedupeKey,
                                                kind: kind ?? snapshot.kind)
        try? await reader.updateExpensePlanning(dedupeKey: snapshot.dedupeKey,
                                                contextName: contextName,
                                                splits: (kind ?? snapshot.kind) == .expense ? splits : [])
        await load()
    }

    public func monthTotalText() -> String {
        Money(amount: summary?.monthTotal ?? 0, currency: currency).formatted()
    }
    /// The month total as a number without the currency symbol — the symbol is shown separately as a
    /// tappable currency control, so the big number can scale to fit instead of clipping.
    public func monthAmountText() -> String {
        Money(amount: summary?.monthTotal ?? 0, currency: currency).amountText()
    }
    public func subscriptionsText() -> String? {
        guard let s = summary, s.confirmedSubscriptionCount > 0 else { return nil }
        let monthly = Money(amount: s.confirmedSubscriptionsMonthly, currency: currency).formatted()
        return "\(s.confirmedSubscriptionCount) confirmed · ~\(monthly)/mo"
    }

    /// Formats a category total in the dashboard's currency (for the Top Categories card).
    public func categoryTotalText(_ total: Decimal) -> String {
        Money(amount: total, currency: currency).formatted()
    }

    /// A category's share of the largest category this month, in 0...1, for the proportional bar.
    /// Returns 0 when there's no spend to compare against.
    public func categoryFraction(_ total: Decimal) -> Double {
        guard let top = summary?.topCategories.map(\.total).max(), top > 0 else { return 0 }
        let value = (total as NSDecimalNumber).doubleValue / (top as NSDecimalNumber).doubleValue
        return min(max(value, 0), 1)
    }
}
