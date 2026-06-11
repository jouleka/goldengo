import Foundation
import SwiftData
import GoldengoCore

/// One pocket-claim line (GOL-98). Sendable snapshot across the actor boundary.
public struct PocketLine: Sendable, Equatable {
    public var currencyCode: String
    public var expected: Decimal
    public var confidence: PocketFog.Confidence
    public var lastMovement: Date          // latest of: reconcile, any wallet cash flow
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
            let silentDays = cal.dateComponents([.day], from: lastMovement, to: now).day ?? 0
            // Static currency: no movement history → never fogs.
            guard !cashSpends.isEmpty else {
                return PocketLine(currencyCode: code, expected: b.expectedNow,
                                  confidence: .even, lastMovement: lastMovement)
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
                              confidence: confidence, lastMovement: lastMovement)
        }
    }

    /// Compose and persist the widget payload (both privacy variants, pre-formatted).
    func refreshSharedPocket(now: Date = .now) throws {
        let lines = try pocketSnapshot(now: now)
        let summary = SharedSummary()
        guard !lines.isEmpty else {
            summary.writePocketPayload(PocketPayload(
                revealedInline: "Set your wallet", hiddenInline: "Set your wallet",
                revealedLines: [], hiddenLines: [], hasWallet: false))
            return
        }
        func state(_ l: PocketLine) -> String {
            let since = l.lastMovement.formatted(.dateTime.weekday(.abbreviated))
            switch l.confidence {
            case .even: return "even since \(since)"
            case .fogged: return "losing track since \(since)"
            case .lost: return "lost track — tap when your wallet's out"
            }
        }
        func amount(_ l: PocketLine) -> String {
            let money = Money(amount: l.expected, currency: CurrencyCode(l.currencyCode)).formatted()
            if case .fogged = l.confidence { return "~" + money }
            return money
        }
        let name: (String) -> String = { code in
            code == "ALL" ? "Lek" : (Locale.current.localizedString(forCurrencyCode: code) ?? code)
        }
        summary.writePocketPayload(PocketPayload(
            revealedInline: lines.map { amount($0) }.joined(separator: " · "),
            hiddenInline: state(lines[0]),
            revealedLines: lines.map { amount($0) + " — " + state($0) },
            hiddenLines: lines.map { name($0.currencyCode) + " — " + state($0) },
            hasWallet: true))
    }
}
