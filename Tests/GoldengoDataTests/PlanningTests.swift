import XCTest
import GoldengoCore
@testable import GoldengoData

final class PlanningTests: XCTestCase {
    private func makeStore() throws -> IngestionStore {
        IngestionStore(modelContainer: try .goldengoInMemory())
    }

    func test_splitPurchase_drivesCategories_andKeepsInvestmentOutOfSpend() async throws {
        let store = try makeStore()
        let now = Date()
        let key = try await store.logManual(
            amount: 100, currency: .all, merchant: "Mixed checkout", categoryName: "Other", date: now,
            contextName: "Household",
            splits: [.init(amount: 60, categoryName: "Groceries"),
                     .init(amount: 40, categoryName: "Investments")]
        )

        let snapshot = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snapshot?.contextName, "Household")
        XCTAssertEqual(snapshot?.splits.count, 2)
        let breakdown = try await store.categoryBreakdown(monthContaining: now,
                                                          displayCurrency: .all,
                                                          rates: SeedRates.table)
        XCTAssertEqual(breakdown.spendingTotal, 60)
        XCTAssertEqual(breakdown.investedTotal, 40)
        XCTAssertEqual(breakdown.rows.first(where: { $0.name == "Groceries" })?.spent, 60)
    }

    func test_invalidSplit_isRejected() async throws {
        let store = try makeStore()
        do {
            _ = try await store.logManual(amount: 100, currency: .all, merchant: nil,
                                          categoryName: "Other",
                                          splits: [.init(amount: 90, categoryName: "Food")])
            XCTFail("Expected an invalid split error")
        } catch let error as PlanningValidationError {
            XCTAssertEqual(error.errorDescription,
                           PlanningValidationError.invalidSplits.errorDescription)
        }
    }

    func test_existingTransaction_canGainContextAndSplits() async throws {
        let store = try makeStore()
        let key = try await store.logManual(amount: 75, currency: .all, merchant: "Market",
                                            categoryName: "Other")
        try await store.updateExpensePlanning(
            dedupeKey: key, contextName: "Business",
            splits: [.init(amount: 50, categoryName: "Groceries"),
                     .init(amount: 25, categoryName: "Office")]
        )
        let snapshot = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snapshot?.contextName, "Business")
        XCTAssertEqual(snapshot?.splits.map(\.amount).reduce(0, +), 75)
    }

    func test_classicAmountEdit_clearsNowInvalidSplit() async throws {
        let store = try makeStore()
        let key = try await store.logManual(amount: 75, currency: .all, merchant: "Market",
                                            categoryName: "Other",
                                            splits: [.init(amount: 50, categoryName: "Groceries"),
                                                     .init(amount: 25, categoryName: "Office")])
        try await store.updateExpense(dedupeKey: key, amount: 90, merchant: "Market",
                                      categoryName: "Other", date: .now)
        let snapshot = try await store.snapshot(dedupeKey: key)
        XCTAssertTrue(snapshot?.splits.isEmpty == true)
    }

    func test_goalAndCommitment_reduceSafeToSpend() async throws {
        let store = try makeStore()
        let now = Date()
        try await store.setWalletBalance(1_000, currency: .all, tally: nil, at: now)
        try await store.addGoal(name: "Emergency", targetAmount: 500, savedAmount: 200,
                                currency: .all, dueDate: nil)
        try await store.addScheduledCommitment(name: "Rent", amount: 300, currency: .all,
                                               categoryName: "Rent",
                                               nextDueDate: now.addingTimeInterval(86_400 * 3),
                                               cadence: .monthly, contextName: "Household")

        let plan = try await store.moneyPlanSnapshot(displayCurrency: .all,
                                                     rates: SeedRates.table, now: now)
        XCTAssertEqual(plan.safe.available, 1_000)
        XCTAssertEqual(plan.safe.reservedForGoals, 200)
        XCTAssertEqual(plan.safe.upcomingCommitments, 300)
        XCTAssertEqual(plan.safe.safeTotal, 500)
        XCTAssertEqual(plan.goals.first?.name, "Emergency")
        XCTAssertEqual(plan.upcoming.first(where: { $0.title == "Rent" })?.contextName, "Household")
    }

    func test_reviewInbox_assigningCategory_resolvesIssue() async throws {
        let store = try makeStore()
        let key = try await store.logManual(amount: 42, currency: .all, merchant: "Unknown shop",
                                            categoryName: nil)
        var issues = try await store.reviewIssues(displayCurrency: .all, rates: SeedRates.table)
        XCTAssertTrue(issues.contains { $0.expenseKey == key && $0.kind == .uncategorized })

        try await store.reviewAndAssign(categoryName: "Shopping", dedupeKey: key)
        issues = try await store.reviewIssues(displayCurrency: .all, rates: SeedRates.table)
        XCTAssertFalse(issues.contains { $0.expenseKey == key })
        let reviewed = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(reviewed?.categoryName, "Shopping")
    }

    func test_loggingScheduledCommitment_advancesNextOccurrence() async throws {
        let store = try makeStore()
        let now = Date()
        try await store.addScheduledCommitment(name: "Gym", amount: 30, currency: .all,
                                               categoryName: "Fitness", nextDueDate: now,
                                               cadence: .monthly, contextName: "Personal")
        let first = try await store.upcomingMoney(until: now.addingTimeInterval(86_400 * 40), now: now)
            .first { $0.title == "Gym" }!
        try await store.logScheduledCommitment(id: first.sourceID, occurrenceDate: first.date)
        let next = try await store.upcomingMoney(until: now.addingTimeInterval(86_400 * 70), now: now)
            .first { $0.title == "Gym" }
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!.date, first.date)
        let recent = try await store.recentExpenses(limit: 1)
        let logged = try await store.snapshot(dedupeKey: recent[0].dedupeKey)
        XCTAssertEqual(logged?.contextName, "Personal")
    }

    func test_investmentContribution_buildsWealth_withoutOrdinarySpend() async throws {
        let store = try makeStore()
        try await store.addInvestmentAccount(name: "Index fund", kindName: "Brokerage",
                                             currency: .all, currentValue: 1_000)
        let account = try await store.investmentSnapshots().first!
        try await store.addInvestmentContribution(accountID: account.id, amount: 250)
        let investments = try await store.investmentSnapshots()
        XCTAssertEqual(investments.first?.contributed, 250)
        XCTAssertEqual(investments.first?.currentValue, 1_250)
        let breakdown = try await store.categoryBreakdown(monthContaining: .now,
                                                          displayCurrency: .all,
                                                          rates: SeedRates.table)
        XCTAssertEqual(breakdown.spendingTotal, 0)
        XCTAssertEqual(breakdown.investedTotal, 250)
    }

    func test_plannedIncome_logsAnIncomeAndAdvances() async throws {
        let store = try makeStore()
        let now = Date()
        try await store.addScheduledCommitment(name: "Salary", amount: 2_000, currency: .all,
                                               categoryName: "Income", nextDueDate: now,
                                               cadence: .monthly, contextName: nil, kind: .income)
        let item = try await store.upcomingMoney(until: now.addingTimeInterval(86_400 * 40), now: now)
            .first { $0.kind == .income }!
        try await store.logScheduledCommitment(id: item.sourceID, occurrenceDate: item.date)
        let rows = try await store.recentExpenses(limit: 1)
        XCTAssertEqual(rows.first?.kind, .income)
        XCTAssertEqual(rows.first?.amount, 2_000)
        let next = try await store.upcomingMoney(until: now.addingTimeInterval(86_400 * 70), now: now)
            .first { $0.kind == .income }
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!.date, item.date)
    }

    func test_weeklySubscriptionReservesEveryOccurrenceInsideHorizon() async throws {
        let store = try makeStore()
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: Date())
        try await store.addManualSubscription(name: "Weekly box", amount: 25, currency: .all,
                                              cadence: .weekly,
                                              nextChargeDate: cal.date(byAdding: .day, value: 1, to: now)!,
                                              now: now)

        let items = try await store.upcomingMoney(
            until: cal.date(byAdding: .day, value: 22, to: now)!, now: now
        ).filter { $0.kind == .subscription && $0.title == "Weekly box" }

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.reduce(Decimal.zero) { $0 + $1.amount }, 100)
    }

    func test_fixedPeriodUsesExplicitDatesAndTracksNetCash() async throws {
        let store = try makeStore()
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let end = cal.date(byAdding: .day, value: 9, to: start)!
        let now = cal.date(byAdding: .day, value: 2, to: start)!
        try await store.setSpendingPeriod(startDate: start, endDate: end,
                                          fundingMode: .fixedAmount, startingAmount: 1_000,
                                          currency: .all, cadence: .once)
        _ = try await store.logManual(amount: 100, currency: .all, merchant: "Market",
                                      categoryName: "Groceries",
                                      date: cal.date(byAdding: .day, value: 1, to: start)!)
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "refund", amount: 20, currency: .all, date: now,
            rawMerchant: "Market refund", kind: .refund, accountRef: "card"
        ))
        try await store.addGoal(name: "Buffer", targetAmount: 300, savedAmount: 100,
                                currency: .all, dueDate: nil)
        try await store.addScheduledCommitment(name: "Bill", amount: 50, currency: .all,
                                               categoryName: "Bills", nextDueDate: end,
                                               cadence: .once, contextName: nil)

        let plan = try await store.moneyPlanSnapshot(displayCurrency: .all,
                                                     rates: SeedRates.table, now: now)
        XCTAssertEqual(plan.safe.available, 920)
        XCTAssertEqual(plan.safe.spentSinceStart, 80)
        XCTAssertEqual(plan.safe.reservedForGoals, 100)
        XCTAssertEqual(plan.safe.upcomingCommitments, 50)
        XCTAssertEqual(plan.safe.safeTotal, 770)
        XCTAssertEqual(plan.safe.dayCount, 8, "Aug 3 through Aug 10 is eight inclusive days")
        XCTAssertTrue(cal.isDate(plan.safe.horizonDate, inSameDayAs: end))
        XCTAssertTrue(plan.safe.isPeriodConfigured)
        XCTAssertEqual(plan.period?.fundingMode, .fixedAmount)
    }

    func test_recurringPeriodRollsForwardWithoutReturningToInference() async throws {
        let store = try makeStore()
        let cal = Calendar.current
        let oldStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let oldEnd = cal.date(from: DateComponents(year: 2026, month: 7, day: 31))!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        try await store.setSpendingPeriod(startDate: oldStart, endDate: oldEnd,
                                          fundingMode: .fixedAmount, startingAmount: 2_000,
                                          currency: .all, cadence: .monthly)

        let plan = try await store.moneyPlanSnapshot(displayCurrency: .all,
                                                     rates: SeedRates.table, now: now)
        XCTAssertTrue(cal.isDate(try XCTUnwrap(plan.period?.startDate), inSameDayAs:
            cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!))
        XCTAssertTrue(cal.isDate(try XCTUnwrap(plan.period?.endDate), inSameDayAs:
            cal.date(from: DateComponents(year: 2026, month: 8, day: 31))!))
        XCTAssertFalse(plan.safe.periodNeedsRenewal)
    }
}
