import Foundation
import SwiftData
import GoldengoCore

public struct GoalSnapshot: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let targetAmount: Decimal
    public let savedAmount: Decimal
    public let currencyCode: String
    public let dueDate: Date?
    public let icon: String
    public let colorHex: String

    public var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, max(0, (savedAmount as NSDecimalNumber).doubleValue /
                            (targetAmount as NSDecimalNumber).doubleValue))
    }
}

public struct InvestmentSnapshot: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let kindName: String
    public let currencyCode: String
    public let contributed: Decimal
    public let currentValue: Decimal
    public let valueAsOf: Date
    public let colorIndex: Int
    public var gain: Decimal { currentValue - contributed }
}

public struct UpcomingMoneyItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let sourceID: String
    public let title: String
    public let amount: Decimal
    public let currencyCode: String
    public let date: Date
    public let kind: UpcomingMoneyKind
    public let categoryName: String?
    public let contextName: String?
    public let canLog: Bool
}

public struct ReviewIssue: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ReviewIssueKind
    public let title: String
    public let detail: String
    public let amount: Decimal?
    public let currencyCode: String?
    public let expenseKey: String?
    public let subscriptionKey: String?
    public let date: Date?
    public let merchantName: String?
}

public struct MoneyStory: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let icon: String
    public let colorHex: String
}

public struct SafeToSpendSnapshot: Sendable, Equatable {
    public let available: Decimal
    public let reservedForGoals: Decimal
    public let upcomingCommitments: Decimal
    public let safeTotal: Decimal
    public let perDay: Decimal
    public let horizonDate: Date
    public let dayCount: Int
    public let usesWallet: Bool
    public let periodStartDate: Date?
    public let isPeriodConfigured: Bool
    public let periodNeedsRenewal: Bool
    public let fundingMode: SpendingPeriodFundingMode
    public let startingAmount: Decimal?
    public let spentSinceStart: Decimal

    public init(available: Decimal, reservedForGoals: Decimal, upcomingCommitments: Decimal,
                safeTotal: Decimal, perDay: Decimal, horizonDate: Date, dayCount: Int,
                usesWallet: Bool, periodStartDate: Date? = nil,
                isPeriodConfigured: Bool = false, periodNeedsRenewal: Bool = false,
                fundingMode: SpendingPeriodFundingMode = .liveBalances,
                startingAmount: Decimal? = nil, spentSinceStart: Decimal = 0) {
        self.available = available; self.reservedForGoals = reservedForGoals
        self.upcomingCommitments = upcomingCommitments; self.safeTotal = safeTotal
        self.perDay = perDay; self.horizonDate = horizonDate; self.dayCount = dayCount
        self.usesWallet = usesWallet; self.periodStartDate = periodStartDate
        self.isPeriodConfigured = isPeriodConfigured; self.periodNeedsRenewal = periodNeedsRenewal
        self.fundingMode = fundingMode; self.startingAmount = startingAmount
        self.spentSinceStart = spentSinceStart
    }
}

public struct SpendingPeriodSnapshot: Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date
    public let fundingMode: SpendingPeriodFundingMode
    public let startingAmount: Decimal?
    public let currencyCode: String
    public let cadence: SpendingPeriodCadence
    public let needsRenewal: Bool
}

public enum PurchaseFit: String, Sendable, Equatable {
    case comfortable, fits, tight, notYet
}

public struct PurchaseImpactSnapshot: Sendable, Equatable {
    public let fit: PurchaseFit
    public let amount: Decimal
    public let safeBefore: Decimal
    public let safeAfter: Decimal
    public let perDayAfter: Decimal
    public let shortfall: Decimal
    public let isInsideCurrentHorizon: Bool
}

public extension SafeToSpendSnapshot {
    func impact(of amount: Decimal, on purchaseDate: Date, now: Date = .now,
                calendar: Calendar = .current) -> PurchaseImpactSnapshot {
        let clean = max(0, amount)
        let after = max(0, safeTotal - clean)
        let shortfall = max(0, clean - safeTotal)
        let ratio = safeTotal > 0 ? (clean as NSDecimalNumber).doubleValue /
            (safeTotal as NSDecimalNumber).doubleValue : (clean > 0 ? 2 : 0)
        let fit: PurchaseFit = shortfall > 0 ? .notYet : (ratio <= 0.35 ? .comfortable : (ratio <= 0.75 ? .fits : .tight))
        let daysLeft = max(1, calendar.dateComponents([.day],
            from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: horizonDate)).day ?? dayCount)
        return PurchaseImpactSnapshot(fit: fit, amount: clean, safeBefore: safeTotal,
                                      safeAfter: after, perDayAfter: after / Decimal(daysLeft),
                                      shortfall: shortfall,
                                      isInsideCurrentHorizon: purchaseDate <= horizonDate)
    }
}

public struct MoneyPlanSnapshot: Sendable, Equatable {
    public let safe: SafeToSpendSnapshot
    public let goals: [GoalSnapshot]
    public let upcoming: [UpcomingMoneyItem]
    public let investments: [InvestmentSnapshot]
    public let reviewIssues: [ReviewIssue]
    public let stories: [MoneyStory]
    public let currencyCode: String
    public let period: SpendingPeriodSnapshot?
}

extension IngestionStore {
    // MARK: - Snapshot

    public func moneyPlanSnapshot(displayCurrency: CurrencyCode, rates: RateTable,
                                  now: Date = .now) throws -> MoneyPlanSnapshot {
        let converter = CurrencyConverter(table: rates)
        let goals = try goalSnapshots()
        let investments = try investmentSnapshots()
        let issues = try reviewIssues(displayCurrency: displayCurrency, rates: rates, now: now)

        let period = try resolvedSpendingPeriod(now: now)
        let horizon = period?.endDate ?? inferredIncomeDate(now: now)
            ?? Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let sixtyDays = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        let upcoming = try upcomingMoney(until: max(sixtyDays, horizon), now: now)
        // Inclusive: both today and the end date are spending days.
        let dayCount = max(1, 1 + (Calendar.current.dateComponents([.day],
                                                               from: Calendar.current.startOfDay(for: now),
                                                               to: Calendar.current.startOfDay(for: horizon)).day ?? 13))

        let wallet = try walletBalances(now: now)
        let walletTotal = wallet.reduce(Decimal.zero) { total, line in
            total + ((try? converter.convert(line.expectedNow, from: CurrencyCode(line.currencyCode),
                                              to: displayCurrency)) ?? 0)
        }
        let sourceSnapshot = try provenanceSnapshot(displayCurrency: displayCurrency, rates: rates)
        let sourceTotal = sourceSnapshot.sources.reduce(Decimal.zero) { total, source in
            total + ((try? converter.convert(source.remaining, from: CurrencyCode(source.currencyCode),
                                              to: displayCurrency)) ?? 0)
        }
        let liveAvailable = max(0, walletTotal + sourceTotal)
        let fixedState = try period.flatMap { configured -> (available: Decimal, spent: Decimal)? in
            guard configured.fundingMode == .fixedAmount, let start = configured.startingAmount else { return nil }
            guard let convertedStart = try? converter.convert(start, from: CurrencyCode(configured.currencyCode),
                                                               to: displayCurrency) else { return nil }
            let change = try cashChange(from: configured.startDate, through: now,
                                        displayCurrency: displayCurrency, converter: converter)
            return (max(0, convertedStart + change.netCashChange), max(0, change.netSpending))
        }
        let available = fixedState?.available ?? liveAvailable

        let reserved = goals.reduce(Decimal.zero) { total, goal in
            total + ((try? converter.convert(goal.savedAmount, from: CurrencyCode(goal.currencyCode),
                                              to: displayCurrency)) ?? 0)
        }
        let commitments = upcoming
            .filter { $0.date <= horizon && ($0.kind == .bill || $0.kind == .subscription) }
            .reduce(Decimal.zero) { total, item in
                total + ((try? converter.convert(item.amount, from: CurrencyCode(item.currencyCode),
                                                  to: displayCurrency)) ?? 0)
            }
        let safeTotal = max(0, available - reserved - commitments)
        let safe = SafeToSpendSnapshot(available: available, reservedForGoals: reserved,
                                       upcomingCommitments: commitments, safeTotal: safeTotal,
                                       perDay: safeTotal / Decimal(dayCount), horizonDate: horizon,
                                       dayCount: dayCount, usesWallet: !wallet.isEmpty,
                                       periodStartDate: period?.startDate,
                                       isPeriodConfigured: period != nil,
                                       periodNeedsRenewal: period?.needsRenewal ?? false,
                                       fundingMode: period?.fundingMode ?? .liveBalances,
                                       startingAmount: period.flatMap { value in
                                           guard let amount = value.startingAmount else { return nil }
                                           return try? converter.convert(amount,
                                               from: CurrencyCode(value.currencyCode), to: displayCurrency)
                                       },
                                       spentSinceStart: fixedState?.spent ?? 0)

        let stories = try monthlyStories(displayCurrency: displayCurrency, rates: rates, now: now)
        return MoneyPlanSnapshot(safe: safe, goals: goals, upcoming: upcoming,
                                 investments: investments, reviewIssues: issues,
                                 stories: stories, currencyCode: displayCurrency.rawValue,
                                 period: period)
    }

    // MARK: - Spending period

    public func setSpendingPeriod(startDate: Date, endDate: Date,
                                  fundingMode: SpendingPeriodFundingMode,
                                  startingAmount: Decimal?, currency: CurrencyCode,
                                  cadence: SpendingPeriodCadence) throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard end >= start else { throw SpendingPeriodValidationError.endBeforeStart }
        if fundingMode == .fixedAmount, (startingAmount ?? 0) <= 0 {
            throw SpendingPeriodValidationError.invalidStartingAmount
        }
        let records = try modelContext.fetch(FetchDescriptor<SpendingPeriodRecord>())
        let record = records.first(where: { !$0.isArchived }) ?? SpendingPeriodRecord()
        if record.modelContext == nil { modelContext.insert(record) }
        for duplicate in records where duplicate !== record && !duplicate.isArchived {
            duplicate.isArchived = true
        }
        record.startDate = start; record.endDate = end
        record.fundingModeRaw = fundingMode.rawValue
        record.startingAmount = fundingMode == .fixedAmount ? startingAmount : nil
        record.currencyCode = currency.rawValue; record.cadenceRaw = cadence.rawValue
        record.updatedAt = .now
        try modelContext.save()
    }

    private func resolvedSpendingPeriod(now: Date) throws -> SpendingPeriodSnapshot? {
        let records = try modelContext.fetch(FetchDescriptor<SpendingPeriodRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        guard let record = records.first else { return nil }
        var mutated = false
        if record.cadence != .once {
            while record.endDate < Calendar.current.startOfDay(for: now) {
                record.startDate = record.cadence.advance(record.startDate)
                record.endDate = record.cadence.advance(record.endDate)
                mutated = true
            }
        }
        if mutated { record.updatedAt = now; try modelContext.save() }
        let needsRenewal = record.cadence == .once
            && record.endDate < Calendar.current.startOfDay(for: now)
        return SpendingPeriodSnapshot(startDate: record.startDate, endDate: record.endDate,
                                      fundingMode: record.fundingMode,
                                      startingAmount: record.startingAmount,
                                      currencyCode: record.currencyCode,
                                      cadence: record.cadence, needsRenewal: needsRenewal)
    }

    private func cashChange(from start: Date, through end: Date, displayCurrency: CurrencyCode,
                            converter: CurrencyConverter) throws
        -> (netCashChange: Decimal, netSpending: Decimal) {
        var descriptor = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.date >= start && $0.date <= end
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.category, \.splits]
        var cashChange = Decimal.zero
        var netSpending = Decimal.zero
        for record in try modelContext.fetch(descriptor) {
            let converted = (try? converter.convert(record.amount,
                from: CurrencyCode(record.currencyCode), to: displayCurrency)) ?? 0
            switch record.kind {
            case .expense:
                cashChange -= converted
                let consumption = (try? converter.convert(record.consumptionAmount,
                    from: CurrencyCode(record.currencyCode), to: displayCurrency)) ?? 0
                netSpending += consumption
            case .refund:
                cashChange += converted
                let consumption = (try? converter.convert(record.consumptionAmount,
                    from: CurrencyCode(record.currencyCode), to: displayCurrency)) ?? 0
                netSpending -= consumption
            case .income, .repayment:
                cashChange += converted
            case .lent:
                cashChange -= converted
            case .transfer:
                break
            }
        }
        return (cashChange, netSpending)
    }

    // MARK: - Goals

    public func goalSnapshots() throws -> [GoalSnapshot] {
        try modelContext.fetch(FetchDescriptor<GoalRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.dueDate), SortDescriptor(\.createdAt)]))
        .map { GoalSnapshot(id: $0.id, name: $0.name, targetAmount: $0.targetAmount,
                            savedAmount: $0.savedAmount, currencyCode: $0.currencyCode,
                            dueDate: $0.dueDate, icon: $0.icon, colorHex: $0.colorHex) }
    }

    public func addGoal(name: String, targetAmount: Decimal, savedAmount: Decimal,
                        currency: CurrencyCode, dueDate: Date?) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, targetAmount > 0 else { return }
        let colors = ["#D9A933", "#3E8F83", "#8B7FA8", "#C47945", "#4D88C7"]
        let count = try modelContext.fetchCount(FetchDescriptor<GoalRecord>())
        modelContext.insert(GoalRecord(name: clean, targetAmount: targetAmount,
                                       savedAmount: max(0, savedAmount), currencyCode: currency.rawValue,
                                       dueDate: dueDate, colorHex: colors[count % colors.count]))
        try modelContext.save()
    }

    public func setGoalSaved(id: String, amount: Decimal) throws {
        guard let goal = try modelContext.fetch(FetchDescriptor<GoalRecord>(
            predicate: #Predicate { $0.id == id && $0.isArchived == false })).first else { return }
        goal.savedAmount = max(0, amount)
        try modelContext.save()
    }

    public func archiveGoal(id: String) throws {
        guard let goal = try modelContext.fetch(FetchDescriptor<GoalRecord>(
            predicate: #Predicate { $0.id == id && $0.isArchived == false })).first else { return }
        goal.isArchived = true
        try modelContext.save()
    }

    // MARK: - Planned commitments and calendar

    public func addScheduledCommitment(name: String, amount: Decimal, currency: CurrencyCode,
                                       categoryName: String, nextDueDate: Date,
                                       cadence: PlanCadence, contextName: String?,
                                       kind: UpcomingMoneyKind = .bill) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, amount > 0 else { return }
        modelContext.insert(ScheduledCommitmentRecord(name: clean, amount: amount,
                                                       currencyCode: currency.rawValue,
                                                       categoryName: categoryName,
                                                       nextDueDate: nextDueDate, cadence: cadence,
                                                       contextName: contextName, kind: kind))
        try modelContext.save()
    }

    public func archiveScheduledCommitment(id: String) throws {
        guard let item = try modelContext.fetch(FetchDescriptor<ScheduledCommitmentRecord>(
            predicate: #Predicate { $0.id == id && $0.isArchived == false })).first else { return }
        item.isArchived = true
        try modelContext.save()
    }

    public func logScheduledCommitment(id: String, occurrenceDate: Date) throws {
        guard let item = try modelContext.fetch(FetchDescriptor<ScheduledCommitmentRecord>(
            predicate: #Predicate { $0.id == id && $0.isArchived == false })).first else { return }
        if item.kind == .income {
            try logIncome(amount: item.amount, currency: CurrencyCode(item.currencyCode),
                          sourceName: item.name, date: occurrenceDate)
        } else {
            _ = try logManual(amount: item.amount, currency: CurrencyCode(item.currencyCode),
                              merchant: item.name, categoryName: item.categoryName,
                              date: occurrenceDate, contextName: item.contextName)
        }
        if item.cadence == .once { item.isArchived = true }
        else {
            var next = item.nextDueDate
            repeat { next = item.cadence.advance(next) } while next <= occurrenceDate
            item.nextDueDate = next
        }
        try modelContext.save()
    }

    public func upcomingMoney(until end: Date, now: Date = .now) throws -> [UpcomingMoneyItem] {
        let start = Calendar.current.startOfDay(for: now)
        let schedules = try modelContext.fetch(FetchDescriptor<ScheduledCommitmentRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        var items: [UpcomingMoneyItem] = []
        for schedule in schedules {
            var date = schedule.nextDueDate
            while date < start, schedule.cadence != .once { date = schedule.cadence.advance(date) }
            while date <= end {
                if date >= start {
                    items.append(.init(id: "bill:\(schedule.id):\(date.timeIntervalSinceReferenceDate)",
                                       sourceID: schedule.id, title: schedule.name,
                                       amount: schedule.amount, currencyCode: schedule.currencyCode,
                                       date: date, kind: schedule.kind, categoryName: schedule.categoryName,
                                       contextName: schedule.contextName, canLog: true))
                }
                guard schedule.cadence != .once else { break }
                date = schedule.cadence.advance(date)
            }
        }

        let subscriptions = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(predicate: #Predicate {
            $0.isConfirmed == true && $0.isDismissed == false && $0.isArchived == false
        }))
        for sub in subscriptions {
            var date = sub.nextChargeDate
            while date < start { date = sub.cadence.advance(date, calendar: .current) }
            while date <= end {
                items.append(.init(id: "subscription:\(sub.matchKey):\(date.timeIntervalSinceReferenceDate)",
                                   sourceID: sub.matchKey, title: sub.displayName,
                                   amount: sub.amount, currencyCode: sub.currencyCode,
                                   date: date, kind: .subscription, categoryName: nil,
                                   contextName: nil, canLog: false))
                date = sub.cadence.advance(date, calendar: .current)
            }
        }

        for goal in try goalSnapshots() {
            if let due = goal.dueDate, due >= start, due <= end {
                items.append(.init(id: "goal:\(goal.id)", sourceID: goal.id, title: goal.name,
                                   amount: max(0, goal.targetAmount - goal.savedAmount),
                                   currencyCode: goal.currencyCode, date: due, kind: .goal,
                                   categoryName: nil, contextName: nil, canLog: false))
            }
        }
        return items.sorted { $0.date != $1.date ? $0.date < $1.date : $0.title < $1.title }
    }

    // MARK: - Investments

    public func investmentSnapshots() throws -> [InvestmentSnapshot] {
        let accounts = try modelContext.fetch(FetchDescriptor<InvestmentAccountRecord>(
            predicate: #Predicate { $0.isArchived == false }, sortBy: [SortDescriptor(\.createdAt)]))
        let entries = try modelContext.fetch(FetchDescriptor<InvestmentEntryRecord>())
        return accounts.map { account in
            let net = entries.filter { $0.accountID == account.id }.reduce(Decimal.zero) { total, entry in
                switch InvestmentEntryKind(rawValue: entry.kindRaw) ?? .contribution {
                case .contribution: return total + entry.amount
                case .withdrawal: return total - entry.amount
                case .valuation: return total
                }
            }
            return InvestmentSnapshot(id: account.id, name: account.name, kindName: account.kindName,
                                      currencyCode: account.currencyCode, contributed: net,
                                      currentValue: account.currentValue, valueAsOf: account.valueAsOf,
                                      colorIndex: account.colorIndex)
        }
    }

    public func addInvestmentAccount(name: String, kindName: String, currency: CurrencyCode,
                                     currentValue: Decimal) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let count = try modelContext.fetchCount(FetchDescriptor<InvestmentAccountRecord>())
        modelContext.insert(InvestmentAccountRecord(name: clean, kindName: kindName,
                                                      currencyCode: currency.rawValue,
                                                      currentValue: max(0, currentValue),
                                                      colorIndex: count % 8))
        try modelContext.save()
    }

    public func setInvestmentValue(id: String, value: Decimal, date: Date = .now) throws {
        guard let account = try modelContext.fetch(FetchDescriptor<InvestmentAccountRecord>(
            predicate: #Predicate { $0.id == id && $0.isArchived == false })).first else { return }
        account.currentValue = max(0, value); account.valueAsOf = date
        modelContext.insert(InvestmentEntryRecord(accountID: id, amount: max(0, value),
                                                   currencyCode: account.currencyCode, date: date,
                                                   kind: InvestmentEntryKind.valuation.rawValue))
        try modelContext.save()
    }

    public func addInvestmentContribution(accountID: String, amount: Decimal, date: Date = .now,
                                          fundedBySourceID: String? = nil) throws {
        guard amount > 0, let account = try modelContext.fetch(FetchDescriptor<InvestmentAccountRecord>(
            predicate: #Predicate { $0.id == accountID && $0.isArchived == false })).first else { return }
        let key = try logManual(amount: amount, currency: CurrencyCode(account.currencyCode),
                                merchant: account.name, note: "Investment contribution",
                                categoryName: "Investments", date: date,
                                fundedBySourceID: fundedBySourceID, investmentAccountID: accountID)
        modelContext.insert(InvestmentEntryRecord(accountID: accountID, amount: amount,
                                                   currencyCode: account.currencyCode, date: date,
                                                   kind: InvestmentEntryKind.contribution.rawValue,
                                                   transactionKey: key))
        // New cash raises the account value by the same amount; performance stays unchanged until
        // the user records a valuation. This avoids showing a deposit as an investment gain.
        account.currentValue += amount
        account.valueAsOf = date
        try modelContext.save()
    }

    public func archiveInvestmentAccount(id: String) throws {
        guard let account = try modelContext.fetch(FetchDescriptor<InvestmentAccountRecord>(
            predicate: #Predicate { $0.id == id && $0.isArchived == false })).first else { return }
        account.isArchived = true
        try modelContext.save()
    }

    // MARK: - Review Inbox

    public func reviewIssues(displayCurrency: CurrencyCode, rates: RateTable,
                             now: Date = .now) throws -> [ReviewIssue] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? .distantPast
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.date >= cutoff
        }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.relationshipKeyPathsForPrefetching = [\.category]
        let expenseRaw = TransactionKind.expense.rawValue
        let records = try modelContext.fetch(fd).filter { $0.kindRaw == expenseRaw && $0.reviewedAt == nil }
        let converter = CurrencyConverter(table: rates)
        let converted: [(ExpenseRecord, Decimal)] = records.map {
            ($0, (try? converter.convert($0.amount, from: CurrencyCode($0.currencyCode), to: displayCurrency)) ?? 0)
        }
        let sorted = converted.map(\.1).filter { $0 > 0 }.sorted()
        let median = sorted.isEmpty ? Decimal.zero : sorted[sorted.count / 2]
        let unusualFloor = max(Decimal(10_000), median * 3)

        var issues: [ReviewIssue] = []
        for (record, displayAmount) in converted {
            let name = record.note ?? record.merchantName ?? "Transaction"
            let category = record.category?.name
            if category == nil || category?.caseInsensitiveCompare("Other") == .orderedSame {
                issues.append(.init(id: "category:\(record.dedupeKey)", kind: .uncategorized,
                                    title: name, detail: "Choose what this spending was for",
                                    amount: record.amount, currencyCode: record.currencyCode,
                                    expenseKey: record.dedupeKey, subscriptionKey: nil, date: record.date,
                                    merchantName: record.merchantName))
            } else if displayAmount >= unusualFloor, median > 0 {
                issues.append(.init(id: "unusual:\(record.dedupeKey)", kind: .unusual,
                                    title: name, detail: "Much larger than your usual transaction",
                                    amount: record.amount, currencyCode: record.currencyCode,
                                    expenseKey: record.dedupeKey, subscriptionKey: nil, date: record.date,
                                    merchantName: record.merchantName))
            }
        }
        let candidates = try subscriptionCandidates(includeConfirmed: false)
        for sub in candidates where !sub.isConfirmed {
            issues.append(.init(id: "subscription:\(sub.id)", kind: .subscription,
                                title: sub.displayName, detail: "Looks like a recurring payment",
                                amount: sub.amount, currencyCode: sub.currencyCode,
                                expenseKey: nil, subscriptionKey: sub.id, date: sub.nextChargeDate,
                                merchantName: sub.displayName))
        }
        return issues
    }

    public func markExpenseReviewed(dedupeKey: String) throws {
        guard let record = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.dedupeKey == dedupeKey && $0.isArchived == false })).first else { return }
        record.reviewedAt = .now
        try modelContext.save()
    }

    public func reviewAndAssign(categoryName: String, dedupeKey: String,
                                rememberMerchant: Bool = false) throws {
        guard let record = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.dedupeKey == dedupeKey && $0.isArchived == false })).first else { return }
        record.category = try findOrCreateCategory(named: categoryName)
        record.reviewedAt = .now
        if rememberMerchant, let merchant = record.merchantName {
            try setMerchantRule(merchantName: merchant, categoryName: categoryName)
        }
        try modelContext.save()
    }

    // MARK: - Story and inferred horizon

    private func monthlyStories(displayCurrency: CurrencyCode, rates: RateTable,
                                now: Date) throws -> [MoneyStory] {
        let current = try categoryBreakdown(monthContaining: now, displayCurrency: displayCurrency, rates: rates)
        let previousDate = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let previous = try categoryBreakdown(monthContaining: previousDate,
                                             displayCurrency: displayCurrency, rates: rates)
        let currency = displayCurrency
        var stories: [MoneyStory] = []
        if current.investedTotal > 0 {
            stories.append(.init(id: "invested", title: "You built wealth",
                                 detail: "\(Money(amount: current.investedTotal, currency: currency).formatted()) invested this month",
                                 icon: "chart.line.uptrend.xyaxis", colorHex: MoneyPurpose.wealth.colorHex))
        }
        if let top = current.rows.filter({ $0.purpose != .wealth }).max(by: { $0.spent < $1.spent }) {
            stories.append(.init(id: "top", title: "\(top.name) led spending",
                                 detail: "\(Money(amount: top.spent, currency: currency).formatted()) so far",
                                 icon: top.icon, colorHex: top.colorHex))
        }
        if previous.spendingTotal > 0 {
            let delta = current.spendingTotal - previous.spendingTotal
            let direction = delta >= 0 ? "more" : "less"
            stories.append(.init(id: "change", title: "Spending is \(direction)",
                                 detail: "\(Money(amount: abs(delta), currency: currency).formatted()) \(direction) than last month so far",
                                 icon: delta >= 0 ? "arrow.up.right" : "arrow.down.right",
                                 colorHex: delta >= 0 ? MoneyPurpose.waste.colorHex : MoneyPurpose.wealth.colorHex))
        }
        if current.wasteTotal > 0 {
            stories.append(.init(id: "waste", title: "Worth another look",
                                 detail: "\(Money(amount: current.wasteTotal, currency: currency).formatted()) marked waste or risk",
                                 icon: "exclamationmark.triangle.fill", colorHex: MoneyPurpose.waste.colorHex))
        }
        return Array(stories.prefix(4))
    }

    /// Infer a next-payday horizon only when history demonstrates a plausible repeated income gap.
    /// Otherwise Safe to Spend uses a transparent 14-day window instead of pretending certainty.
    private func inferredIncomeDate(now: Date) -> Date? {
        let incomeRaw = TransactionKind.income.rawValue
        guard let records = try? modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.kindRaw == incomeRaw },
            sortBy: [SortDescriptor(\.date, order: .reverse)])), records.count >= 2 else { return nil }
        let dates = Array(records.prefix(6).map(\.date).sorted())
        let gaps = zip(dates.dropFirst(), dates).map { later, earlier in
            Calendar.current.dateComponents([.day], from: earlier, to: later).day ?? 0
        }.filter { (7...45).contains($0) }.sorted()
        guard !gaps.isEmpty, let last = dates.last else { return nil }
        let median = gaps[gaps.count / 2]
        var next = Calendar.current.date(byAdding: .day, value: median, to: last) ?? now
        while next <= now { next = Calendar.current.date(byAdding: .day, value: median, to: next) ?? now }
        return next
    }
}
