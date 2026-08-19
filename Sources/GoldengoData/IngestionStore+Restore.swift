import Foundation
import SwiftData
import GoldengoCore

public struct FinancialRestoreSummary: Sendable, Equatable {
    public let restored: Int
    public let skippedExisting: Int
    public let unsupported: Int
}

extension IngestionStore {
    /// Merge a CSV produced by `exportFinancialDataCSV`. Existing stable IDs/dedupe keys win, so
    /// importing the same backup twice is safe. Restore is intentionally additive: it never deletes
    /// current data just because a row is absent from an older backup.
    public func restoreFinancialDataCSV(_ text: String) throws -> FinancialRestoreSummary {
        guard text.utf8.count <= 25_000_000 else { throw FinancialRestoreError.backupTooLarge }
        let table = Self.parseBackupCSV(text)
        guard let header = table.first, header.first == "record_type" else {
            throw FinancialRestoreError.notGoldengoBackup
        }
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func value(_ row: [String], _ key: String) -> String {
            guard let index = columns[key], row.indices.contains(index) else { return "" }
            let raw = row[index]
            let formulaMarkers: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]
            if raw.first == "'", raw.dropFirst().first.map(formulaMarkers.contains) == true {
                return String(raw.dropFirst())
            }
            return raw
        }
        func decimalValue(_ row: [String], _ key: String = "amount") -> Decimal? {
            Decimal(string: value(row, key))
        }
        func dateValue(_ row: [String], _ key: String = "date") -> Date? {
            ISO8601DateFormatter().date(from: value(row, key))
        }
        func metadata(_ row: [String]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: value(row, "metadata").split(separator: ";").compactMap { part in
                let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                guard pieces.count == 2 else { return nil }
                return (String(pieces[0]), String(pieces[1]))
            })
        }

        let rows = Array(table.dropFirst()).filter { !$0.isEmpty }
        var restored = 0, skipped = 0, unsupported = 0

        // Dependency records first; transactions can then reconnect their relationships.
        var categories = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
        for row in rows where value(row, "record_type") == "category" {
            let name = value(row, "name")
            guard !name.isEmpty else { unsupported += 1; continue }
            if categories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                skipped += 1; continue
            }
            let category = CategoryRecord(name: name); modelContext.insert(category)
            categories.append(category); restored += 1
            let meta = metadata(row)
            category.monthlyBudget = decimalValue(row)
            category.monthlyBudgetCurrencyCode = value(row, "currency").nilIfEmpty
            if let icon = meta["icon"] { category.icon = icon }
            if let color = meta["color"] { category.colorHex = color }
        }

        var sources = try modelContext.fetch(FetchDescriptor<SourceRecord>())
        for row in rows where value(row, "record_type") == "source" {
            let id = value(row, "id")
            guard !id.isEmpty else { unsupported += 1; continue }
            if sources.contains(where: { $0.id == id }) { skipped += 1; continue }
            let meta = metadata(row)
            let source = SourceRecord(id: id, name: value(row, "name"),
                                      currencyCode: value(row, "currency"),
                                      colorIndex: Int(meta["color_index"] ?? "") ?? 0,
                                      createdAt: dateValue(row) ?? .now,
                                      isArchived: value(row, "status") == "archived")
            modelContext.insert(source); sources.append(source); restored += 1
        }

        var loans = try modelContext.fetch(FetchDescriptor<LoanRecord>())
        for row in rows where value(row, "record_type") == "loan" {
            let id = value(row, "id")
            guard !id.isEmpty else { unsupported += 1; continue }
            if loans.contains(where: { $0.id == id }) { skipped += 1; continue }
            let loan = LoanRecord(id: id, personName: value(row, "name"),
                                  currencyCode: value(row, "currency"),
                                  colorIndex: Int(metadata(row)["color_index"] ?? "") ?? 0,
                                  createdAt: dateValue(row) ?? .now,
                                  isArchived: value(row, "status") == "archived")
            modelContext.insert(loan); loans.append(loan); restored += 1
        }

        var accounts = try modelContext.fetch(FetchDescriptor<InvestmentAccountRecord>())
        for row in rows where value(row, "record_type") == "investment_account" {
            let id = value(row, "id")
            guard !id.isEmpty else { unsupported += 1; continue }
            if accounts.contains(where: { $0.id == id }) { skipped += 1; continue }
            let account = InvestmentAccountRecord(id: id, name: value(row, "name"),
                kindName: value(row, "kind"), currencyCode: value(row, "currency"),
                currentValue: decimalValue(row) ?? 0, valueAsOf: dateValue(row) ?? .now)
            account.isArchived = value(row, "status") == "archived"
            modelContext.insert(account); accounts.append(account); restored += 1
        }

        var subscriptions = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
        for row in rows where value(row, "record_type") == "subscription" {
            let key = value(row, "id")
            guard !key.isEmpty else { unsupported += 1; continue }
            if subscriptions.contains(where: { $0.matchKey == key }) { skipped += 1; continue }
            let meta = metadata(row)
            let sub = SubscriptionRecord(matchKey: key, displayName: value(row, "name"),
                normalizedMerchant: value(row, "merchant"), amount: decimalValue(row) ?? 0,
                currencyCode: value(row, "currency"),
                cadence: SubscriptionCadence(rawValue: value(row, "kind")) ?? .monthly,
                nextChargeDate: dateValue(row) ?? .now,
                occurrenceCount: Int(meta["occurrences"] ?? "") ?? 0)
            sub.isConfirmed = meta["confirmed"] == "true"
            sub.isDismissed = meta["dismissed"] == "true"
            sub.isManual = value(row, "capture_source") == "manual"
            sub.manualAnchorDate = meta["anchor"].flatMap(ISO8601DateFormatter().date(from:)) ?? sub.nextChargeDate
            sub.isArchived = value(row, "status") == "archived"
            modelContext.insert(sub); subscriptions.append(sub); restored += 1
        }

        for row in rows where value(row, "record_type") == "spending_period" {
            let id = value(row, "id")
            let existing = try modelContext.fetch(FetchDescriptor<SpendingPeriodRecord>())
            if existing.contains(where: { $0.id == id && $0.updatedAt >= (metadata(row)["updated"].flatMap(ISO8601DateFormatter().date(from:)) ?? .distantPast) }) {
                skipped += 1; continue
            }
            for old in existing where !old.isArchived { old.isArchived = true }
            let meta = metadata(row)
            let period = SpendingPeriodRecord(startDate: dateValue(row) ?? .now,
                endDate: meta["end"].flatMap(ISO8601DateFormatter().date(from:)) ?? .now,
                fundingMode: SpendingPeriodFundingMode(rawValue: value(row, "kind")) ?? .liveBalances,
                startingAmount: decimalValue(row), currencyCode: value(row, "currency"),
                cadence: SpendingPeriodCadence(rawValue: meta["cadence"] ?? "") ?? .once)
            period.id = id.isEmpty ? "active-spending-period" : id
            period.updatedAt = meta["updated"].flatMap(ISO8601DateFormatter().date(from:)) ?? .now
            period.isArchived = value(row, "status") == "archived"
            modelContext.insert(period); restored += 1
        }

        var goals = try modelContext.fetch(FetchDescriptor<GoalRecord>())
        for row in rows where value(row, "record_type") == "goal" {
            let id = value(row, "id")
            if goals.contains(where: { $0.id == id }) { skipped += 1; continue }
            let meta = metadata(row)
            let goal = GoalRecord(id: id, name: value(row, "name"),
                targetAmount: Decimal(string: meta["target"] ?? "") ?? 0,
                savedAmount: decimalValue(row) ?? 0, currencyCode: value(row, "currency"),
                dueDate: meta["due"].flatMap(ISO8601DateFormatter().date(from:)))
            goal.createdAt = dateValue(row) ?? .now
            goal.isArchived = value(row, "status") == "archived"
            modelContext.insert(goal); goals.append(goal); restored += 1
        }

        var commitments = try modelContext.fetch(FetchDescriptor<ScheduledCommitmentRecord>())
        for row in rows where value(row, "record_type") == "planned_commitment" {
            let id = value(row, "id")
            if commitments.contains(where: { $0.id == id }) { skipped += 1; continue }
            let meta = metadata(row)
            let item = ScheduledCommitmentRecord(id: id, name: value(row, "name"),
                amount: decimalValue(row) ?? 0, currencyCode: value(row, "currency"),
                categoryName: value(row, "category"), nextDueDate: dateValue(row) ?? .now,
                cadence: PlanCadence(rawValue: meta["cadence"] ?? "") ?? .once,
                contextName: value(row, "context").nilIfEmpty,
                kind: UpcomingMoneyKind(rawValue: value(row, "kind")) ?? .bill)
            item.createdAt = meta["created"].flatMap(ISO8601DateFormatter().date(from:)) ?? .now
            item.isArchived = value(row, "status") == "archived"
            modelContext.insert(item); commitments.append(item); restored += 1
        }

        var transactions = try modelContext.fetch(FetchDescriptor<ExpenseRecord>())
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let loansByID = Dictionary(uniqueKeysWithValues: loans.map { ($0.id, $0) })
        let subsByKey = Dictionary(subscriptions.map { ($0.matchKey, $0) }, uniquingKeysWith: { first, _ in first })
        for row in rows where value(row, "record_type") == "transaction" {
            let key = value(row, "id")
            if transactions.contains(where: { $0.dedupeKey == key }) { skipped += 1; continue }
            guard let amount = decimalValue(row), let date = dateValue(row) else { unsupported += 1; continue }
            let categoryName = value(row, "category")
            let record = ExpenseRecord(amount: amount, currencyCode: value(row, "currency"), date: date,
                merchantName: value(row, "merchant").nilIfEmpty, note: value(row, "note").nilIfEmpty,
                kind: TransactionKind(rawValue: value(row, "kind")) ?? .expense,
                source: ExpenseSource(rawValue: value(row, "capture_source")) ?? .imported,
                dedupeKey: key,
                category: categories.first { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame })
            record.contextName = value(row, "context").nilIfEmpty
            record.isArchived = value(row, "status") == "archived"
            let paidFrom = value(row, "paid_from")
            if paidFrom == "Wallet — cash" { record.fundedBySourceID = FundingPin.wallet }
            else if paidFrom != "Automatic" {
                record.fundedBySourceID = sources.first { $0.name.caseInsensitiveCompare(paidFrom) == .orderedSame }?.id
            }
            let meta = metadata(row)
            record.provenanceSource = meta["provenance_source_id"].flatMap { sourcesByID[$0] }
            record.loan = meta["loan_id"].flatMap { loansByID[$0] }
            record.subscription = meta["subscription_key"].flatMap { subsByKey[$0] }
            record.investmentAccountID = meta["investment_id"]
            record.refundedExpenseKey = meta["refunded_expense_key"]
            modelContext.insert(record)
            record.splits = try Self.parseSplitField(value(row, "split_categories")).map { split in
                _ = try findOrCreateCategory(named: split.categoryName)
                let stored = ExpenseSplitRecord(amount: split.amount, categoryName: split.categoryName)
                stored.expense = record; modelContext.insert(stored); return stored
            }
            transactions.append(record); restored += 1
        }

        var entries = try modelContext.fetch(FetchDescriptor<InvestmentEntryRecord>())
        for row in rows where value(row, "record_type") == "investment_entry" {
            let id = value(row, "id")
            if entries.contains(where: { $0.id == id }) { skipped += 1; continue }
            let meta = metadata(row)
            let entry = InvestmentEntryRecord(id: id,
                accountID: accounts.first(where: { $0.name == value(row, "name") })?.id ?? "",
                amount: decimalValue(row) ?? 0, currencyCode: value(row, "currency"),
                date: dateValue(row) ?? .now, kind: value(row, "kind"),
                transactionKey: meta["transaction_id"], note: value(row, "note").nilIfEmpty)
            modelContext.insert(entry); entries.append(entry); restored += 1
        }

        let existingWallet = try modelContext.fetch(FetchDescriptor<WalletCount>())
        for row in rows where value(row, "record_type") == "wallet_balance" {
            guard let amount = decimalValue(row), let date = dateValue(row) else { unsupported += 1; continue }
            let currency = value(row, "currency")
            if existingWallet.contains(where: { $0.date == date && $0.currencyCode == currency }) {
                skipped += 1; continue
            }
            let wallet = WalletCount(total: amount, tally: nil, currencyCode: currency, date: date)
            wallet.isArchived = value(row, "status") == "archived"
            modelContext.insert(wallet); restored += 1
        }

        for row in rows where value(row, "record_type") == "merchant_rule" {
            let merchantName = value(row, "merchant")
            let categoryName = value(row, "category")
            guard !merchantName.isEmpty, !categoryName.isEmpty else { unsupported += 1; continue }
            let normalized = MerchantNormalizer.normalize(merchantName)
            let existing = try modelContext.fetch(FetchDescriptor<MerchantRecord>()).first {
                $0.normalizedName == normalized
            }
            if existing?.defaultCategory != nil { skipped += 1; continue }
            let merchant = existing ?? MerchantRecord(displayName: merchantName, normalizedName: normalized)
            if existing == nil { modelContext.insert(merchant) }
            merchant.defaultCategory = try findOrCreateCategory(named: categoryName)
            merchant.lastUsed = dateValue(row) ?? .now
            restored += 1
        }

        let supported = Set(["source", "category", "transaction", "goal", "planned_commitment",
                             "investment_account", "investment_entry", "merchant_rule", "wallet_balance",
                             "subscription", "loan", "spending_period"])
        unsupported += rows.filter { !supported.contains(value($0, "record_type")) }.count
        try modelContext.save()
        try? refreshSharedSummaries()
        return FinancialRestoreSummary(restored: restored, skippedExisting: skipped, unsupported: unsupported)
    }

    private static func parseSplitField(_ value: String) -> [TransactionSplit] {
        value.split(separator: "|").compactMap { raw in
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard let colon = text.lastIndex(of: ":"),
                  let amount = Decimal(string: String(text[text.index(after: colon)...])) else { return nil }
            return TransactionSplit(amount: amount,
                                    categoryName: String(text[..<colon]).trimmingCharacters(in: .whitespaces))
        }
    }

    /// RFC-4180-enough parser for Goldengo's own exporter: quoted fields, escaped quotes, CRLF/LF.
    private static func parseBackupCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if quoted {
                if char == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" { field.append("\""); index = next }
                    else { quoted = false }
                } else { field.append(char) }
            } else {
                switch char {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(char)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

public enum FinancialRestoreError: LocalizedError, Sendable {
    case notGoldengoBackup, backupTooLarge
    public var errorDescription: String? {
        switch self {
        case .notGoldengoBackup: "This CSV is not a Goldengo financial-data backup."
        case .backupTooLarge: "This backup is too large to restore safely on this device."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
