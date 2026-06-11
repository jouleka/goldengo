import Foundation
import SwiftData
import GoldengoCore

/// What the Sources-tab wallet card shows. Sendable snapshot across the actor boundary.
public struct WalletSnapshot: Sendable, Equatable {
    public var baselineDate: Date
    public var expectedNow: Decimal
}

/// The result of saving a count — drives the drift moment in the count sheet.
public struct WalletCountOutcome: Sendable, Equatable {
    public var countedTotal: Decimal
    public var expected: Decimal?      // nil on the first-ever count
    public var drift: Decimal?         // counted − expected; nil on the first-ever count
}

extension IngestionStore {
    /// dedupeKey prefix for drift ("street money") entries — identity-excluded from wallet
    /// math forever, so user date-edits can never corrupt the ledger (the GOL-92 lesson).
    public static let driftKeyPrefix = "drift"

    /// Save a denomination count. The count is TRUTH: it always becomes the new baseline;
    /// the returned drift only decides whether the gap gets RECORDED (via logDrift).
    @discardableResult
    public func recordWalletCount(_ tally: DenominationTally, at date: Date = .now) throws -> WalletCountOutcome {
        let counted = tally.total
        var outcome = WalletCountOutcome(countedTotal: counted, expected: nil, drift: nil)
        if let baseline = try latestCount() {
            let expected = CashLedger.expected(baselineTotal: baseline.total,
                                               flows: try cashFlows(after: baseline.date, until: date))
            outcome.expected = expected
            outcome.drift = CashLedger.drift(counted: counted, expected: expected)
        }
        modelContext.insert(WalletCount(tally: tally, date: date))
        try modelContext.save()
        return outcome
    }

    /// The wallet card's state, or nil before the first-ever count.
    public func walletSnapshot(now: Date = .now) throws -> WalletSnapshot? {
        guard let baseline = try latestCount() else { return nil }
        let expected = CashLedger.expected(baselineTotal: baseline.total,
                                           flows: try cashFlows(after: baseline.date, until: now))
        return WalletSnapshot(baselineDate: baseline.date, expectedNow: expected)
    }

    /// Record accepted drift as an ordinary, visible "street money" expense.
    public func logDrift(amount: Decimal, at date: Date = .now) throws {
        _ = try logEntry(amount: amount, currency: .all, merchant: nil, note: "street money",
                         categoryName: "Unaccounted", source: .manual,
                         keyPrefix: Self.driftKeyPrefix, date: date)
    }

    private func latestCount() throws -> WalletCount? {
        // Latest date wins as baseline; total as a stable second key so a (CloudKit-rare)
        // same-instant count pair resolves deterministically on every device.
        var fd = FetchDescriptor<WalletCount>(predicate: #Predicate { $0.isArchived == false },
                                              sortBy: [SortDescriptor(\.date, order: .reverse),
                                                       SortDescriptor(\.total, order: .reverse)])
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first
    }

    /// Cash flows in (baseline, until]: transfers (ATM) + manual income are inflows; manual
    /// expenses are outflows — except drift entries (identity-excluded by key prefix). ALL-only
    /// in v1. Source/kind filters stay out of the #Predicate where they'd need Decimals; the
    /// date/currency/archived filters are store-side, the rest in memory.
    private func cashFlows(after baseline: Date, until: Date) throws -> [CashLedger.Flow] {
        let all = "ALL"
        let rows = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate {
                $0.isArchived == false && $0.currencyCode == all
                    && $0.date > baseline && $0.date <= until
            }))
        let manualRaw = ExpenseSource.manual.rawValue
        let driftPrefix = Self.driftKeyPrefix + ":"
        return rows.compactMap { r in
            switch r.kindRaw {
            case TransactionKind.transfer.rawValue:
                return CashLedger.Flow(amount: abs(r.amount), isInflow: true)
            case TransactionKind.income.rawValue where r.sourceRaw == manualRaw:
                return CashLedger.Flow(amount: abs(r.amount), isInflow: true)
            case TransactionKind.expense.rawValue where r.sourceRaw == manualRaw
                    && !r.dedupeKey.hasPrefix(driftPrefix):
                return CashLedger.Flow(amount: abs(r.amount), isInflow: false)
            default:
                return nil
            }
        }
    }
}
