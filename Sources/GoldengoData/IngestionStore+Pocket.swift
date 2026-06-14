import Foundation
import SwiftData
import GoldengoCore

/// One pocket-claim line (GOL-98). Sendable snapshot across the actor boundary.
public struct PocketLine: Sendable, Equatable {
    public var currencyCode: String
    public var expected: Decimal
    public var confidence: PocketFog.Confidence
    public var typicalCashDay: Decimal     // 0 = static currency (never fogs)
    public var lastMovement: Date          // latest of: reconcile, any wallet cash flow

    public init(currencyCode: String, expected: Decimal, confidence: PocketFog.Confidence,
                typicalCashDay: Decimal, lastMovement: Date) {
        self.currencyCode = currencyCode; self.expected = expected; self.confidence = confidence
        self.typicalCashDay = typicalCashDay; self.lastMovement = lastMovement
    }
}

extension IngestionStore {
    /// The pocket claim per tracked currency. Fog accrues only while the books sit still for
    /// a currency that HAS movement history — static money never fogs (the app must not
    /// confess blindness about money that provably didn't move).
    public func pocketSnapshot(now: Date = .now) throws -> [PocketLine] {
        let balances = try walletBalances(now: now)
        guard !balances.isEmpty else { return [] }
        let expenseRaw = TransactionKind.expense.rawValue
        let manualRaw = ExpenseSource.manual.rawValue
        let driftPrefix = Self.driftKeyPrefix + ":"
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let lookback = cal.date(byAdding: .day, value: -60, to: now) else { return [] }

        return try balances.map { b in
            let code = b.currencyCode
            // Wallet-draining cash spends for this currency, trailing 60 days (tombstones
            // excluded: deleted entries are not movement). Decimal math in memory only.
            let rows = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
                predicate: #Predicate {
                    $0.isArchived == false && $0.currencyCode == code
                        && $0.kindRaw == expenseRaw && $0.date >= lookback
                }))
            let cashSpends = rows.filter {
                !$0.dedupeKey.hasPrefix(driftPrefix)
                    && ($0.fundedBySourceID == FundingPin.wallet
                        || ($0.fundedBySourceID == nil && $0.sourceRaw == manualRaw))
            }
            let lastMovement = max(b.baselineDate, cashSpends.map(\.date).max() ?? .distantPast)
            let silentDays = PocketFog.silentDays(from: lastMovement, to: now)
            // Static currency: no movement history → never fogs (typical 0 keeps it even
            // however long the widget re-renders the payload without a save).
            guard !cashSpends.isEmpty else {
                return PocketLine(currencyCode: code, expected: b.expectedNow,
                                  confidence: .even, typicalCashDay: 0, lastMovement: lastMovement)
            }
            // Median daily outflow over days that HAD outflow; floor = wallet lasting ~a month.
            let byDay = Dictionary(grouping: cashSpends) { cal.startOfDay(for: $0.date) }
                .values.map { $0.reduce(Decimal(0)) { $0 + abs($1.amount) } }
            let typical = PocketFog.typicalCashDay(dailyOutflows: byDay,
                                                   floor: max(b.expectedNow / 30, 1))
            let confidence = PocketFog.confidence(silentDays: silentDays,
                                                  typicalCashDay: typical,
                                                  walletTotal: b.expectedNow)
            return PocketLine(currencyCode: code, expected: b.expectedNow,
                              confidence: confidence, typicalCashDay: typical,
                              lastMovement: lastMovement)
        }
    }

    /// Publish the pocket claim DATA for the widget. The widget re-renders it per timeline
    /// date with PocketPayload.content(at:), so fog keeps advancing on days the app never
    /// runs (review: pre-rendered strings froze the claim at the last save).
    func refreshSharedPocket(now: Date = .now) throws {
        let lines = try pocketSnapshot(now: now)
        SharedSummary().writePocketPayload(PocketPayload(
            lines: lines.map {
                PocketPayload.Line(currencyCode: $0.currencyCode, expected: $0.expected,
                                   typicalCashDay: $0.typicalCashDay, lastMovement: $0.lastMovement)
            },
            hasWallet: !lines.isEmpty))
    }
}
