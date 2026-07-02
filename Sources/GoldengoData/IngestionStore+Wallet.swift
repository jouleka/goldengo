import Foundation
import SwiftData
import GoldengoCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// One currency line of the wallet (GOL-95 v2). Sendable snapshot across the actor boundary.
public struct WalletBalance: Sendable, Equatable, Identifiable {
    public var currencyCode: String
    public var baselineDate: Date
    public var expectedNow: Decimal
    public var id: String { currencyCode }
}

/// The result of setting a balance — one quiet confirmation line, never a question.
public struct WalletSetOutcome: Sendable, Equatable {
    public var expected: Decimal?            // nil on the first-ever set for this currency
    public var unaccountedLogged: Decimal?   // the auto-logged gap when set lower than expected
}

extension IngestionStore {
    /// dedupeKey prefix for auto-logged "Unaccounted" gap entries — identity-excluded from
    /// wallet math forever, so user date-edits can never corrupt the ledger.
    public static let driftKeyPrefix = "drift"

    /// Set what's actually in the wallet for one currency — typed directly, or via the optional
    /// denomination tally (just another way to produce the same number). The set amount IS the
    /// new baseline. Lower than expected → the gap is auto-logged as one visible "Unaccounted"
    /// expense (the user initiated the correction; the entry is its direct consequence, and it
    /// keeps spend totals truthful). Higher → the baseline absorbs it; nothing is fabricated.
    @discardableResult
    public func setWalletBalance(_ newTotal: Decimal, currency: CurrencyCode,
                                 tally: DenominationTally?, at date: Date = .now) throws -> WalletSetOutcome {
        var outcome = WalletSetOutcome(expected: nil, unaccountedLogged: nil)
        if let baseline = try latestBaseline(currencyCode: currency.rawValue) {
            let expected = CashLedger.expected(
                baselineTotal: baseline.total,
                flows: try cashFlows(after: baseline.date, until: date, currencyCode: currency.rawValue))
            outcome.expected = expected
            // Diff at display precision: a flow residue below what the user can SEE must not
            // turn "set it to exactly what the screen shows" into a junk Unaccounted entry.
            let displayedExpected = Money(amount: expected, currency: currency).roundedAmount()
            if newTotal < displayedExpected {
                let gap = displayedExpected - newTotal
                try logDrift(amount: gap, currency: currency, at: date)
                outcome.unaccountedLogged = gap
            }
        }
        modelContext.insert(WalletCount(total: newTotal, tally: tally,
                                        currencyCode: currency.rawValue, date: date))
        try modelContext.save()
        // GOL-98: a reconcile is the pocket claim's most important refresh — snap the lock
        // screen immediately (logDrift above already refreshed via logEntry when a gap logged).
        try? refreshSharedPocket()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return outcome
    }

    /// The wallet's per-currency lines — one per currency the user has ever set a balance for.
    /// Empty before the first set (the card shows its begin state).
    public func walletBalances(now: Date = .now) throws -> [WalletBalance] {
        let counts = try modelContext.fetch(FetchDescriptor<WalletCount>(
            predicate: #Predicate { $0.isArchived == false }))
        // Latest baseline per currency (date desc, total as the deterministic tiebreak).
        var latest: [String: WalletCount] = [:]
        for c in counts {
            if let kept = latest[c.currencyCode],
               (kept.date, kept.total) >= (c.date, c.total) { continue }
            latest[c.currencyCode] = c
        }
        return try latest.values.map { baseline in
            let expected = CashLedger.expected(
                baselineTotal: baseline.total,
                flows: try cashFlows(after: baseline.date, until: now, currencyCode: baseline.currencyCode))
            return WalletBalance(currencyCode: baseline.currencyCode,
                                 baselineDate: baseline.date, expectedNow: expected)
        }
        // ALL (the user's primary currency) first, then alphabetical. Written as a strict weak
        // ordering — equal codes compare false (the old form returned true for two "ALL"s, an
        // irreflexivity violation that can trap `sort` if a currency ever duplicates).
        .sorted {
            if $0.currencyCode == $1.currencyCode { return false }
            if $0.currencyCode == "ALL" { return true }
            if $1.currencyCode == "ALL" { return false }
            return $0.currencyCode < $1.currencyCode
        }
    }

    /// Stop tracking a currency: archive its baselines so the line disappears from
    /// `walletBalances`. Money records are never touched — only the tracking line goes. A later
    /// set (or cash-in-hand income) starts a fresh baseline with no drift against the old one.
    public func removeWalletCurrency(_ currency: CurrencyCode) throws {
        let code = currency.rawValue
        let counts = try modelContext.fetch(FetchDescriptor<WalletCount>(
            predicate: #Predicate { $0.isArchived == false && $0.currencyCode == code }))
        guard !counts.isEmpty else { return }
        for c in counts { c.isArchived = true }
        try modelContext.save()
        // The pocket claim may have been computed from this line — republish it.
        try? refreshSharedPocket()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Record an auto-logged gap as an ordinary, visible "Unaccounted" expense.
    func logDrift(amount: Decimal, currency: CurrencyCode, at date: Date = .now) throws {
        _ = try logEntry(amount: amount, currency: currency, merchant: nil, note: nil,
                         categoryName: "Unaccounted", source: .manual,
                         keyPrefix: Self.driftKeyPrefix, date: date)
    }

    /// Seed a zero baseline for a currency that has none, dated just before `date` so the
    /// triggering inflow lands inside (baseline, now]. Used when cash income arrives for a
    /// currency the wallet isn't tracking yet (GOL-95 v2 review).
    func seedWalletBaselineIfMissing(currency: CurrencyCode, before date: Date) throws {
        guard try latestBaseline(currencyCode: currency.rawValue) == nil else { return }
        modelContext.insert(WalletCount(total: 0, tally: nil, currencyCode: currency.rawValue,
                                        date: date.addingTimeInterval(-1)))
    }

    private func latestBaseline(currencyCode: String) throws -> WalletCount? {
        var fd = FetchDescriptor<WalletCount>(
            predicate: #Predicate { $0.isArchived == false && $0.currencyCode == currencyCode },
            sortBy: [SortDescriptor(\.date, order: .reverse),
                     SortDescriptor(\.total, order: .reverse)])
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first
    }

    /// Cash flows in (baseline, until] for one currency (GOL-95 v2 rules):
    /// in — transfers (ATM withdrawals) and wallet-pinned income ("cash in hand");
    /// out — cash-funded expenses (wallet-pinned, or unpinned `.manual` = cash by default),
    ///       except drift entries (identity-excluded by key prefix).
    /// Bank income, source-pinned spends, and card/imported spends never touch the wallet.
    private func cashFlows(after baseline: Date, until: Date, currencyCode: String) throws -> [CashLedger.Flow] {
        let rows = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate {
                $0.isArchived == false && $0.currencyCode == currencyCode
                    && $0.date > baseline && $0.date <= until
            }))
        let manualRaw = ExpenseSource.manual.rawValue
        let driftPrefix = Self.driftKeyPrefix + ":"
        let forgivePrefix = Self.forgiveKeyPrefix + ":"
        return rows.compactMap { r in
            switch r.kindRaw {
            case TransactionKind.transfer.rawValue:
                return CashLedger.Flow(amount: abs(r.amount), isInflow: true)
            case TransactionKind.income.rawValue where r.fundedBySourceID == FundingPin.wallet:
                return CashLedger.Flow(amount: abs(r.amount), isInflow: true)
            // Forgive entries are wallet-neutral: the pocket already drained at LEND time —
            // the forgiveness expense reclassifies that money, never re-drains it.
            case TransactionKind.expense.rawValue where !r.dedupeKey.hasPrefix(driftPrefix)
                    && !r.dedupeKey.hasPrefix(forgivePrefix)
                    && (r.fundedBySourceID == FundingPin.wallet
                        || (r.fundedBySourceID == nil && r.sourceRaw == manualRaw)):
                return CashLedger.Flow(amount: abs(r.amount), isInflow: false)
            // Lending is cash leaving the pocket — drains exactly like a cash spend.
            case TransactionKind.lent.rawValue where r.fundedBySourceID == FundingPin.wallet
                    || (r.fundedBySourceID == nil && r.sourceRaw == manualRaw):
                return CashLedger.Flow(amount: abs(r.amount), isInflow: false)
            // A payback is cash coming home.
            case TransactionKind.repayment.rawValue where r.fundedBySourceID == FundingPin.wallet:
                return CashLedger.Flow(amount: abs(r.amount), isInflow: true)
            default:
                return nil
            }
        }
    }
}
