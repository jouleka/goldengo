import Foundation
import Observation
import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

@MainActor
@Observable
public final class SourcesModel {
    private let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var snapshot: ProvenanceSnapshot?
    public private(set) var loadFailed = false
    /// The wallet's per-currency lines (GOL-95 v2); empty before the first balance is set.
    public private(set) var wallet: [WalletBalance] = []
    /// Open "owed to you" claims (balance > 0), oldest debt first.
    public private(set) var loans: [LoanBalance] = []
    /// Notification permission was explicitly denied — the claim cards must say so instead
    /// of promising a nudge that can never arrive.
    public private(set) var loanNudgesDenied = false
    /// One-shot: a pocket-widget tap should land ON the Adjust screen (GOL-98). In-memory on
    /// purpose — a persisted flag outlives a killed launch and replays the navigation days
    /// later as an unprompted sheet (review); losing one tap to a process death is the
    /// acceptable failure, surprise navigation is not.
    public var pendingWalletAdjust = false

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        do { snapshot = try await store.provenanceSnapshot(displayCurrency: currency); loadFailed = false }
        catch { loadFailed = true }
        wallet = (try? await store.walletBalances()) ?? []
        loans = (try? await store.loanBalances()) ?? []
        loanNudgesDenied = await LocalNotificationScheduler.authorizationDenied()
        await syncLoanReminders()
    }

    /// The visible promise: the exact date the next nudge fires ("25 Jul"). nil when nudges
    /// can't/won't arrive (toggle off, or permission denied) so the UI never promises what
    /// the system won't deliver.
    public func nextNudgeDateText(_ loan: LoanBalance) -> String? {
        guard SharedSummary().loanRemindersEnabled(), !loanNudgesDenied,
              let date = LoanReminderPlanner.nextNudge(after: loan.lastEventDate,
                                                       now: .now, calendar: .current)
        else { return nil }
        return Self.compactDay(date)
    }

    /// "25 Jun" — the year earns its place only when it isn't this year. Card meta lines
    /// live on one line; full dates are date soup there.
    public static func compactDay(_ date: Date, now: Date = .now) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return (sameYear ? thisYearFormatter : otherYearFormatter).string(from: date)
    }
    private static let thisYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()
    private static let otherYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMMy"); return f
    }()

    /// Keep the owed-to-you nudges in sync with the open claims. One nudge per loan, 30 days
    /// after its newest event (any lend/payback re-arms it — load() runs after every mutation).
    /// Toggle off → plan() returns [] and the replace-sync clears stale nudges (self-healing).
    private func syncLoanReminders() async {
        let inputs = loans.map {
            LoanReminderPlanner.LoanInput(
                id: $0.id, personName: $0.personName,
                remainingText: Money(amount: $0.remaining, currency: CurrencyCode($0.currencyCode)).formatted(),
                lastEventDate: $0.lastEventDate)
        }
        let requests = LoanReminderPlanner.plan(inputs, enabled: SharedSummary().loanRemindersEnabled(),
                                                now: .now, calendar: .current)
            .map { SubscriptionReminderPlanner.ReminderRequest(id: $0.id, title: $0.title,
                                                               body: $0.body, fireDate: $0.fireDate) }
        await LocalNotificationScheduler.sync(requests, prefix: LoanNudge.notificationPrefix,
                                              categoryID: LoanNudge.categoryID)
    }

    /// Lend money to a person (wallet-cash by default, or pinned to a source). The first lend
    /// also asks for notification permission — the 30-day nudge is the feature's safety net.
    public func lend(amount: Decimal, currency: CurrencyCode, personName: String,
                     fundedBySourceID: String? = nil, date: Date = .now) async {
        try? await store.lend(amount: amount, currency: currency, personName: personName,
                              fundedBySourceID: fundedBySourceID, date: date)
        _ = await LocalNotificationScheduler.requestAuthorization()
        await load()
    }

    public func repayLoan(_ loan: LoanBalance, amount: Decimal) async {
        try? await store.logRepayment(amount: amount, loanID: loan.id)
        await load()
    }

    public func renameLoan(_ loan: LoanBalance, to name: String) async {
        try? await store.renameLoan(id: loan.id, to: name)
        await load()
    }

    public func forgiveLoan(_ loan: LoanBalance) async {
        try? await store.forgiveLoan(id: loan.id)
        await load()
    }

    public func deleteLoan(_ loan: LoanBalance) async {
        try? await store.deleteLoan(id: loan.id)
        await load()
    }

    /// Set what's actually in the wallet for one currency (typed, or via the optional tally).
    public func setWalletBalance(_ total: Decimal, currency: CurrencyCode,
                                 tally: DenominationTally?) async -> WalletSetOutcome? {
        let outcome = try? await store.setWalletBalance(total, currency: currency, tally: tally)
        await load()
        return outcome
    }

    /// Stop tracking a currency's wallet line (money records stay; the line just goes).
    public func removeWalletCurrency(_ currency: CurrencyCode) async {
        try? await store.removeWalletCurrency(currency)
        await load()
    }

    /// Set what's actually left in a source (higher → income; lower → visible Unaccounted).
    public func setSourceRemaining(_ amount: Decimal, source: SourceBalance) async {
        try? await store.setSourceRemaining(amount, sourceID: source.id)
        await load()
    }

    /// Rename a source (refused when another live source already uses the name).
    public func renameSource(_ source: SourceBalance, to name: String) async {
        try? await store.renameSource(id: source.id, to: name)
        await load()
    }

    /// Delete a source — its pool and income records archive together.
    public func deleteSource(_ source: SourceBalance) async {
        try? await store.deleteSource(id: source.id)
        await load()
    }

    public func addIncome(amount: Decimal, currency: CurrencyCode, sourceName: String,
                          intoWallet: Bool = false, date: Date = .now) async {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !name.isEmpty else { return }
        try? await store.logIncome(amount: amount, currency: currency, sourceName: name,
                                   date: date, intoWallet: intoWallet)
        await load()
    }

    /// Fraction remaining (0...1) for the draining bar.
    public func fraction(_ b: SourceBalance) -> Double {
        guard b.totalInflow > 0 else { return 0 }
        let r = (b.remaining as NSDecimalNumber).doubleValue / (b.totalInflow as NSDecimalNumber).doubleValue
        return min(max(r, 0), 1)
    }

    public func remainingText(_ b: SourceBalance) -> String {
        Money(amount: b.remaining, currency: CurrencyCode(b.currencyCode)).formatted()
    }
    public func unaccountedText() -> String? {
        guard let s = snapshot, s.unaccounted > 0 else { return nil }
        return Money(amount: s.unaccounted, currency: CurrencyCode(s.displayCurrencyCode)).formatted()
    }

    /// A stable, distinct color per source (by its colorIndex) — shared with the funded-by chips
    /// via the design-system palette so the same source is the same color everywhere.
    public func color(_ b: SourceBalance) -> Color {
        GoldengoTheme.sourceColor(b.colorIndex)
    }
}
