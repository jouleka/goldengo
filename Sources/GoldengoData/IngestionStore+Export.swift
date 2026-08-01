import Foundation
import SwiftData
import GoldengoCore

extension IngestionStore {
    /// A single portable CSV containing transactions plus the planning records that give them
    /// meaning. `record_type` keeps the file spreadsheet-friendly without silently omitting goals,
    /// plans, investment accounts, valuations, or merchant rules.
    public func exportFinancialDataCSV() throws -> String {
        let header = ["record_type", "id", "date", "name", "amount", "currency", "kind",
                      "merchant", "note", "category", "context", "split_categories",
                      "paid_from", "capture_source", "status", "metadata"]
        var rows: [[String]] = [header]
        let date = ISO8601DateFormatter()

        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>())
        let sourceNames = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        let investmentAccounts = try modelContext.fetch(FetchDescriptor<InvestmentAccountRecord>())
        let investmentNames = Dictionary(uniqueKeysWithValues: investmentAccounts.map { ($0.id, $0.name) })

        for source in sources.sorted(by: { $0.createdAt < $1.createdAt }) {
            rows.append(["source", source.id, date.string(from: source.createdAt), source.name,
                         "", source.currencyCode, "money_source", "", "", "", "", "", "", "manual",
                         source.isArchived ? "archived" : "active", "color_index=\(source.colorIndex)"])
        }
        for category in try modelContext.fetch(FetchDescriptor<CategoryRecord>()).sorted(by: { $0.name < $1.name }) {
            rows.append(["category", category.name.lowercased(), "", category.name,
                         category.monthlyBudget.map(decimal) ?? "",
                         category.monthlyBudgetCurrencyCode ?? "", "spending_category", "", "", "", "", "",
                         "", "manual", "active", "icon=\(category.icon); color=\(category.colorHex)"])
        }

        var txFD = FetchDescriptor<ExpenseRecord>(sortBy: [SortDescriptor(\.date)])
        txFD.relationshipKeyPathsForPrefetching = [\.category, \.account, \.subscription, \.splits]
        for record in try modelContext.fetch(txFD) {
            let paidFrom: String
            if record.fundedBySourceID == FundingPin.wallet { paidFrom = "Wallet — cash" }
            else if let id = record.fundedBySourceID { paidFrom = sourceNames[id] ?? id }
            else { paidFrom = record.source == .manual ? "Wallet — cash" : "Automatic" }
            let splits = (record.splits ?? []).sorted { $0.categoryName < $1.categoryName }
                .map { "\($0.categoryName):\(decimal($0.amount))" }.joined(separator: " | ")
            var metadata: [String] = []
            if let account = record.account?.name { metadata.append("account=\(account)") }
            if let subscription = record.subscription {
                metadata.append("subscription=\(subscription.displayName)")
                metadata.append("subscription_key=\(subscription.matchKey)")
            }
            if let id = record.investmentAccountID {
                metadata.append("investment=\(investmentNames[id] ?? id)")
                metadata.append("investment_id=\(id)")
            }
            if let id = record.provenanceSource?.id { metadata.append("provenance_source_id=\(id)") }
            if let id = record.loan?.id { metadata.append("loan_id=\(id)") }
            if let key = record.refundedExpenseKey { metadata.append("refunded_expense_key=\(key)") }
            rows.append(["transaction", record.dedupeKey, date.string(from: record.date),
                         record.note ?? record.merchantName ?? record.category?.name ?? "Transaction",
                         decimal(record.amount), record.currencyCode, record.kindRaw,
                         record.merchantName ?? "", record.note ?? "", record.category?.name ?? "",
                         record.contextName ?? "", splits, paidFrom, record.sourceRaw,
                         record.isArchived ? "archived" : "active", metadata.joined(separator: "; ")])
        }

        for goal in try modelContext.fetch(FetchDescriptor<GoalRecord>(sortBy: [SortDescriptor(\.createdAt)])) {
            rows.append(["goal", goal.id, date.string(from: goal.createdAt), goal.name,
                         decimal(goal.savedAmount), goal.currencyCode, "goal", "", "", "", "", "", "", "manual",
                         goal.isArchived ? "archived" : "active",
                         "target=\(decimal(goal.targetAmount)); due=\(goal.dueDate.map(date.string(from:)) ?? "")"])
        }
        for plan in try modelContext.fetch(FetchDescriptor<ScheduledCommitmentRecord>(sortBy: [SortDescriptor(\.createdAt)])) {
            rows.append(["planned_commitment", plan.id, date.string(from: plan.nextDueDate), plan.name,
                         decimal(plan.amount), plan.currencyCode, plan.kindRaw, "", "", plan.categoryName,
                         plan.contextName ?? "", "", "", "manual", plan.isArchived ? "archived" : "active",
                         "cadence=\(plan.cadenceRaw); created=\(date.string(from: plan.createdAt))"])
        }
        for account in investmentAccounts.sorted(by: { $0.createdAt < $1.createdAt }) {
            rows.append(["investment_account", account.id, date.string(from: account.valueAsOf), account.name,
                         decimal(account.currentValue), account.currencyCode, account.kindName, "", "", "Investments",
                         "", "", "", "manual", account.isArchived ? "archived" : "active",
                         "created=\(date.string(from: account.createdAt))"])
        }
        for entry in try modelContext.fetch(FetchDescriptor<InvestmentEntryRecord>(sortBy: [SortDescriptor(\.date)])) {
            rows.append(["investment_entry", entry.id, date.string(from: entry.date),
                         investmentNames[entry.accountID] ?? entry.accountID, decimal(entry.amount), entry.currencyCode,
                         entry.kindRaw, "", entry.note ?? "", "Investments", "", "", "", "manual", "active",
                         "transaction_id=\(entry.transactionKey ?? "")"])
        }
        for rule in try merchantRules() {
            rows.append(["merchant_rule", rule.id, date.string(from: rule.lastUsed), rule.merchantName,
                         "", "", "categorization_rule", rule.merchantName, "", rule.categoryName,
                         "", "", "", "automatic", "active", "uses=\(rule.useCount)"])
        }
        for wallet in try modelContext.fetch(FetchDescriptor<WalletCount>(sortBy: [SortDescriptor(\.date)])) {
            rows.append(["wallet_balance", "wallet:\(wallet.date.timeIntervalSinceReferenceDate)",
                         date.string(from: wallet.date), "Wallet", decimal(wallet.total), wallet.currencyCode,
                         "balance", "", "", "", "", "", "Wallet — cash", "manual",
                         wallet.isArchived ? "archived" : "active", ""])
        }
        for sub in try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(sortBy: [SortDescriptor(\.detectedAt)])) {
            rows.append(["subscription", sub.matchKey, date.string(from: sub.nextChargeDate), sub.displayName,
                         decimal(sub.amount), sub.currencyCode, sub.cadenceRaw, sub.normalizedMerchant, "", "", "", "",
                         "", sub.isManual ? "manual" : "automatic", sub.isArchived ? "archived" : "active",
                         "confirmed=\(sub.isConfirmed); dismissed=\(sub.isDismissed); anchor=\(date.string(from: sub.manualAnchorDate)); occurrences=\(sub.occurrenceCount)"])
        }
        for loan in try modelContext.fetch(FetchDescriptor<LoanRecord>(sortBy: [SortDescriptor(\.createdAt)])) {
            rows.append(["loan", loan.id, date.string(from: loan.createdAt), loan.personName, "",
                         loan.currencyCode, "loan", "", "", "", "", "", "", "manual",
                         loan.isArchived ? "archived" : "active", "color_index=\(loan.colorIndex)"])
        }
        for period in try modelContext.fetch(FetchDescriptor<SpendingPeriodRecord>(sortBy: [SortDescriptor(\.updatedAt)])) {
            rows.append(["spending_period", period.id, date.string(from: period.startDate), "Spending period",
                         period.startingAmount.map(decimal) ?? "", period.currencyCode, period.fundingModeRaw,
                         "", "", "", "", "", "", "manual", period.isArchived ? "archived" : "active",
                         "end=\(date.string(from: period.endDate)); cadence=\(period.cadenceRaw); updated=\(date.string(from: period.updatedAt))"])
        }

        return rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
