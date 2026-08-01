import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class MoneyPlanModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var snapshot: MoneyPlanSnapshot?
    public private(set) var isLoading = false
    public var errorText: String?

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await store.moneyPlanSnapshot(
                displayCurrency: currency,
                rates: ExchangeRateCache().load() ?? SeedRates.table,
                now: .now
            )
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    public var safeTotalText: String {
        Money(amount: snapshot?.safe.safeTotal ?? 0, currency: currency).formatted()
    }
    public var safePerDayText: String {
        Money(amount: snapshot?.safe.perDay ?? 0, currency: currency).formatted()
    }
    public var reviewCount: Int { snapshot?.reviewIssues.count ?? 0 }
    public var upcomingCount: Int { snapshot?.upcoming.filter { $0.kind != .goal }.count ?? 0 }
    public var isPeriodConfigured: Bool { snapshot?.safe.isPeriodConfigured == true }
    public var periodNeedsRenewal: Bool { snapshot?.safe.periodNeedsRenewal == true }

    public func purchaseImpact(amount: Decimal, date: Date) -> PurchaseImpactSnapshot? {
        snapshot?.safe.impact(of: amount, on: date)
    }

    public func savePeriod(startDate: Date, endDate: Date,
                           fundingMode: SpendingPeriodFundingMode, startingAmount: Decimal?,
                           cadence: SpendingPeriodCadence) async -> Bool {
        do {
            try await store.setSpendingPeriod(startDate: startDate, endDate: endDate,
                                              fundingMode: fundingMode,
                                              startingAmount: startingAmount,
                                              currency: currency, cadence: cadence)
            await load()
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    public func planPurchase(name: String, amount: Decimal, category: String, date: Date) async {
        await addCommitment(name: name, amount: amount, category: category, dueDate: date,
                            cadence: .once, context: nil, kind: .bill)
    }

    public func logPurchaseNow(name: String, amount: Decimal, category: String) async {
        await mutate {
            _ = try await store.logManual(amount: amount, currency: currency,
                                          merchant: name, categoryName: category, date: .now)
        }
    }

    public func addGoal(name: String, target: Decimal, saved: Decimal, dueDate: Date?) async {
        await mutate { try await store.addGoal(name: name, targetAmount: target, savedAmount: saved,
                                               currency: currency, dueDate: dueDate) }
    }

    public func setGoalSaved(id: String, amount: Decimal) async {
        await mutate { try await store.setGoalSaved(id: id, amount: amount) }
    }

    public func archiveGoal(id: String) async {
        await mutate { try await store.archiveGoal(id: id) }
    }

    public func addCommitment(name: String, amount: Decimal, category: String, dueDate: Date,
                              cadence: PlanCadence, context: String?, kind: UpcomingMoneyKind) async {
        await mutate {
            try await store.addScheduledCommitment(name: name, amount: amount, currency: currency,
                                                   categoryName: category, nextDueDate: dueDate,
                                                   cadence: cadence, contextName: context, kind: kind)
        }
    }

    public func logUpcoming(_ item: UpcomingMoneyItem) async {
        guard item.kind == .bill || item.kind == .income else { return }
        await mutate { try await store.logScheduledCommitment(id: item.sourceID, occurrenceDate: item.date) }
    }

    public func archiveCommitment(id: String) async {
        await mutate { try await store.archiveScheduledCommitment(id: id) }
    }

    public func addInvestment(name: String, kind: String, value: Decimal) async {
        await mutate { try await store.addInvestmentAccount(name: name, kindName: kind,
                                                             currency: currency, currentValue: value) }
    }

    public func setInvestmentValue(id: String, value: Decimal) async {
        await mutate { try await store.setInvestmentValue(id: id, value: value) }
    }

    public func addContribution(accountID: String, amount: Decimal) async {
        await mutate { try await store.addInvestmentContribution(accountID: accountID, amount: amount) }
    }

    public func archiveInvestment(id: String) async {
        await mutate { try await store.archiveInvestmentAccount(id: id) }
    }

    public func assign(_ issue: ReviewIssue, category: String, rememberMerchant: Bool = false) async {
        guard let key = issue.expenseKey else { return }
        await mutate { try await store.reviewAndAssign(categoryName: category, dedupeKey: key,
                                                       rememberMerchant: rememberMerchant) }
    }

    public func accept(_ issue: ReviewIssue) async {
        guard let key = issue.expenseKey else { return }
        await mutate { try await store.markExpenseReviewed(dedupeKey: key) }
    }

    public func confirmSubscription(_ issue: ReviewIssue) async {
        guard let key = issue.subscriptionKey else { return }
        await mutate { try await store.confirmSubscription(matchKey: key) }
    }

    public func dismissSubscription(_ issue: ReviewIssue) async {
        guard let key = issue.subscriptionKey else { return }
        await mutate { try await store.dismissSubscription(matchKey: key) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
