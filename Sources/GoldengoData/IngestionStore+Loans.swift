import Foundation
import SwiftData
import GoldengoCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// One person's claim, snapshot across the actor boundary. Balance fields are DERIVED
/// from the loan's events at read time — never stored.
public struct LoanBalance: Sendable, Identifiable, Equatable {
    public let id: String
    public let personName: String
    public let currencyCode: String
    public let colorIndex: Int
    public let lentTotal: Decimal
    public let remaining: Decimal
    public let sinceDate: Date        // oldest lent event ("since Jun 12")
    public let lastEventDate: Date    // newest event — the reminder re-arm anchor
}

extension IngestionStore {
    /// dedupeKey prefix for forgiveness expenses — excluded from wallet drains (the wallet
    /// already drained when the money was LENT; forgiving reclassifies it, never re-drains).
    public static let forgiveKeyPrefix = "forgive"

    /// Lend money to a person. Drains the wallet (nil pin + manual = cash, same rule as
    /// expenses) or a pinned source pool — the money really left — but it is a CLAIM, not
    /// spending: every total filters `.expense` and never sees it.
    public func lend(amount: Decimal, currency: CurrencyCode, personName: String,
                     fundedBySourceID: String? = nil, date: Date = .now) throws {
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !name.isEmpty else { return }
        let loan = try findOrCreateLoan(named: name, currency: currency)
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: date,
                                merchantName: loan.personName, kind: .lent, source: .manual,
                                dedupeKey: "lent:\(UUID().uuidString)")
        rec.fundedBySourceID = fundedBySourceID
        rec.loan = loan
        modelContext.insert(rec)
        try modelContext.save()
        try? refreshSharedPocket()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Log a payback (v1: cash back into the wallet). STRICT: 0 < amount <= remaining —
    /// a payback above the debt isn't a payback (a friend's tip is income; log it as income),
    /// and silently absorbing it would fabricate a negative claim.
    public func logRepayment(amount: Decimal, loanID: String, date: Date = .now) throws {
        guard amount > 0, let loan = try fetchLoan(id: loanID),
              amount <= remaining(of: loan) else { return }
        let rec = ExpenseRecord(amount: amount, currencyCode: loan.currencyCode, date: date,
                                merchantName: loan.personName, kind: .repayment, source: .manual,
                                dedupeKey: "repay:\(UUID().uuidString)")
        rec.fundedBySourceID = FundingPin.wallet
        rec.loan = loan
        // Cash coming home must be VISIBLE in the wallet immediately — seed a zero baseline
        // for an untracked currency, exactly like cash-in-hand income (GOL-95 v2 rule).
        try seedWalletBaselineIfMissing(currency: CurrencyCode(loan.currencyCode), before: date)
        modelContext.insert(rec)
        try modelContext.save()
        try? refreshSharedPocket()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Rename a person. Balances key on the stable `id`, so a rename never moves money.
    /// Refused (no-op) when another live person already uses the name case-insensitively —
    /// `lend` routes by name, and a duplicate would make every future lend ambiguous.
    public func renameLoan(id: String, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let all = try modelContext.fetch(FetchDescriptor<LoanRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        guard let loan = all.first(where: { $0.id == id }) else { return }
        guard !all.contains(where: { $0.id != id && $0.personName.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        loan.personName = name
        try modelContext.save()
    }

    /// Forgive what's left: the remaining balance becomes ONE visible "Gifts" expense —
    /// forgiveness is the moment the money truly became spending, and there are no silent
    /// write-offs. The loan archives; its events stay (the cash really left at lend time,
    /// so wallet history must keep draining — the forgive expense itself is wallet-neutral
    /// via its key prefix).
    public func forgiveLoan(id: String, date: Date = .now) throws {
        guard let loan = try fetchLoan(id: id) else { return }
        let rest = remaining(of: loan)
        if rest > 0 {
            _ = try logEntry(amount: rest, currency: CurrencyCode(loan.currencyCode),
                             merchant: loan.personName, note: nil, categoryName: "Gifts",
                             source: .manual, keyPrefix: Self.forgiveKeyPrefix, date: date)
        }
        loan.isArchived = true
        try modelContext.save()
    }

    /// Delete (archive) a person's claim AND its events — the claim and its history leave
    /// together (mirrors `deleteSource`), so a re-created person starts fresh.
    public func deleteLoan(id: String) throws {
        guard let loan = try fetchLoan(id: id) else { return }
        loan.isArchived = true
        for event in (loan.events ?? []) { event.isArchived = true }
        try modelContext.save()
        // Archived lent events restore the wallet's expected balance — republish the claim.
        try? refreshSharedPocket()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Every open claim, oldest-debt first. Loans whose balance reached zero stay listed
    /// until deleted? No — a fully-paid claim disappears (nothing is owed; the events keep
    /// living in Recent/wallet history).
    public func loanBalances() throws -> [LoanBalance] {
        let loans = try modelContext.fetch(FetchDescriptor<LoanRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        return loans.compactMap { loan -> LoanBalance? in
            let events = (loan.events ?? []).filter { !$0.isArchived }
            let lentEvents = events.filter { $0.kindRaw == TransactionKind.lent.rawValue }
            guard let oldest = lentEvents.map(\.date).min(),
                  let newest = events.map(\.date).max() else { return nil }
            let lentTotal = lentEvents.reduce(Decimal(0)) { $0 + abs($1.amount) }
            let repaid = events.filter { $0.kindRaw == TransactionKind.repayment.rawValue }
                .reduce(Decimal(0)) { $0 + abs($1.amount) }
            let remaining = lentTotal - repaid
            guard remaining > 0 else { return nil }
            return LoanBalance(id: loan.id, personName: loan.personName,
                               currencyCode: loan.currencyCode, colorIndex: loan.colorIndex,
                               lentTotal: lentTotal, remaining: remaining,
                               sinceDate: oldest, lastEventDate: newest)
        }
        .sorted { $0.sinceDate < $1.sinceDate }
    }

    // MARK: - Internals

    private func remaining(of loan: LoanRecord) -> Decimal {
        let events = (loan.events ?? []).filter { !$0.isArchived }
        let lent = events.filter { $0.kindRaw == TransactionKind.lent.rawValue }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
        let repaid = events.filter { $0.kindRaw == TransactionKind.repayment.rawValue }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
        return lent - repaid
    }

    private func fetchLoan(id: String) throws -> LoanRecord? {
        var fd = FetchDescriptor<LoanRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.id == id })
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first
    }

    // Find-or-create by case-insensitive name (mirrors findOrCreateSource). Internal —
    // returns a non-Sendable @Model, never exposed across the actor boundary.
    private func findOrCreateLoan(named name: String, currency: CurrencyCode) throws -> LoanRecord {
        let all = try modelContext.fetch(FetchDescriptor<LoanRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        if let existing = all.first(where: { $0.personName.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let used = Set(all.map(\.colorIndex))
        let colorIndex = (0..<8).first { !used.contains($0) } ?? (all.count % 8)
        let loan = LoanRecord(personName: name, currencyCode: currency.rawValue, colorIndex: colorIndex)
        modelContext.insert(loan)
        return loan
    }
}
