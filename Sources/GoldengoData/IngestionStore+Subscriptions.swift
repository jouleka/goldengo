import Foundation
import SwiftData
import GoldengoCore

/// `Sendable` view of a detected/persisted subscription, safe to cross the actor boundary to the UI.
/// A due-but-unlogged subscription charge, surfaced as a one-tap ghost row (GOL-92).
/// Read-only candidate — becomes a real expense only when the user taps it.
public struct PendingSubscriptionCharge: Sendable, Equatable, Identifiable {
    public var matchKey: String
    public var displayName: String
    public var merchantName: String   // the anchor charge's REAL string, so a later import merges
    public var amount: Decimal
    public var currencyCode: String
    public var dueDate: Date
    public var id: String { "\(matchKey)|\(dueDate.timeIntervalSinceReferenceDate)" }

    public init(matchKey: String, displayName: String, merchantName: String,
                amount: Decimal, currencyCode: String, dueDate: Date) {
        self.matchKey = matchKey; self.displayName = displayName; self.merchantName = merchantName
        self.amount = amount; self.currencyCode = currencyCode; self.dueDate = dueDate
    }
}

public struct SubscriptionSnapshot: Sendable, Equatable, Identifiable {
    public var id: String              // matchKey
    public var displayName: String
    public var amount: Decimal
    public var currencyCode: String
    public var cadence: SubscriptionCadence
    public var nextChargeDate: Date
    public var occurrenceCount: Int
    public var confidence: Double
    public var isVariableAmount: Bool
    public var hadTrial: Bool
    public var isConfirmed: Bool

    public init(id: String, displayName: String, amount: Decimal, currencyCode: String,
                cadence: SubscriptionCadence, nextChargeDate: Date, occurrenceCount: Int,
                confidence: Double, isVariableAmount: Bool, hadTrial: Bool, isConfirmed: Bool) {
        self.id = id; self.displayName = displayName; self.amount = amount
        self.currencyCode = currencyCode; self.cadence = cadence; self.nextChargeDate = nextChargeDate
        self.occurrenceCount = occurrenceCount; self.confidence = confidence
        self.isVariableAmount = isVariableAmount; self.hadTrial = hadTrial; self.isConfirmed = isConfirmed
    }
}

extension IngestionStore {
    /// Run detection over all non-archived expense-kind records and UPSERT candidates by `matchKey`,
    /// preserving the user's confirm/dismiss decisions. Returns the surfaced candidate count
    /// (equal to `subscriptionCandidates().count`).
    @discardableResult
    public func refreshSubscriptions(now: Date = .now) throws -> Int {
        let expenseRaw = TransactionKind.expense.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw
        })
        let occurrences = try modelContext.fetch(fd).map { r in
            TransactionOccurrence(id: r.dedupeKey, date: r.date, amount: abs(r.amount),
                                  currency: CurrencyCode(r.currencyCode), merchant: r.merchantName)
        }
        let detected = SubscriptionDetector.detect(occurrences, options: .init(now: now))

        // Build the lookup defensively: `matchKey` is NOT unique (CloudKit cross-device inserts can
        // produce two rows with the same key). `Dictionary(uniqueKeysWithValues:)` would TRAP on that.
        // Converge duplicates here — keep the row carrying a user decision, archive the loser.
        let existingAll = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
        var byKey: [String: SubscriptionRecord] = [:]
        for r in existingAll {
            guard let kept = byKey[r.matchKey] else { byKey[r.matchKey] = r; continue }
            let rHasDecision = r.isConfirmed || r.isDismissed
            let keptHasDecision = kept.isConfirmed || kept.isDismissed
            let winner = (rHasDecision && !keptHasDecision) ? r : kept
            let loser = (winner === r) ? kept : r
            loser.isArchived = true
            byKey[r.matchKey] = winner
        }

        for c in detected {
            if let rec = byKey[c.id] {
                // Update detection-derived fields; NEVER touch isConfirmed / isDismissed.
                rec.displayName = c.displayName
                rec.amount = c.amount
                rec.cadenceRaw = c.cadence.rawValue
                rec.nextChargeDate = c.predictedNextCharge
                rec.occurrenceCount = c.occurrenceCount
                rec.confidence = c.confidence
                rec.isVariableAmount = c.isVariableAmount
                rec.hadTrial = c.hadTrial
                rec.isArchived = false
                rec.updatedAt = now
            } else {
                let rec = SubscriptionRecord(
                    matchKey: c.id, displayName: c.displayName, normalizedMerchant: c.normalizedMerchant,
                    amount: c.amount, currencyCode: c.currency.rawValue, cadence: c.cadence,
                    nextChargeDate: c.predictedNextCharge, occurrenceCount: c.occurrenceCount,
                    confidence: c.confidence, isVariableAmount: c.isVariableAmount, hadTrial: c.hadTrial)
                rec.detectedAt = now; rec.updatedAt = now
                modelContext.insert(rec)
                byKey[c.id] = rec
            }
        }

        // Reconcile records that are no longer detected (e.g. the user deleted charges so the series
        // fell below the cadence bar) so they don't linger with a stale count: drop unconfirmed
        // guesses; keep confirmed ones but correct their charge count to reality. Dismissed records
        // are left untouched.
        let detectedIDs = Set(detected.map(\.id))
        for rec in byKey.values where !rec.isArchived && !rec.isDismissed && !detectedIDs.contains(rec.matchKey) {
            if rec.isConfirmed {
                let count = try currentChargeCount(normalizedMerchant: rec.normalizedMerchant,
                                                   currencyCode: rec.currencyCode)
                if count == 0 {
                    rec.isArchived = true          // confirmed but no charges left → nothing to track
                } else {
                    rec.occurrenceCount = count     // keep, count corrected to reality
                }
            } else {
                rec.isArchived = true               // drop an unconfirmed guess that no longer repeats
            }
            rec.updatedAt = now
        }
        try modelContext.save()

        // Return the surfaced count so it matches exactly what `subscriptionCandidates()` will show.
        return try subscriptionCandidates().count
    }

    /// Count of current (non-archived) charge *days* for a merchant+currency — used to correct a
    /// confirmed subscription's displayed count after some charges are deleted. Counts distinct UTC
    /// days (not raw rows) to match `SubscriptionDetector`'s same-day collapse, so "Charged N times"
    /// means the same thing whether the series is currently detected or reconciled here.
    private func currentChargeCount(normalizedMerchant: String, currencyCode: String) throws -> Int {
        let expenseRaw = TransactionKind.expense.rawValue
        let recs = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.kindRaw == expenseRaw && $0.currencyCode == currencyCode }))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let days = Set(recs.filter { MerchantNormalizer.normalize($0.merchantName) == normalizedMerchant }
                           .map { cal.startOfDay(for: $0.date) })
        return days.count
    }

    /// Candidates to show the user: currently-detected, not dismissed, not archived, most confident first.
    public func subscriptionCandidates(includeConfirmed: Bool = true) throws -> [SubscriptionSnapshot] {
        let recs = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.isDismissed == false }))
        return recs
            .filter { includeConfirmed || !$0.isConfirmed }
            .sorted { $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.matchKey < $1.matchKey }
            .map(snapshot(of:))
    }

    /// Subscriptions the user marked "not a subscription" — surfaced so the dismissal can be undone
    /// (otherwise an accidentally dismissed recurring charge would stay hidden forever).
    public func dismissedSubscriptions() throws -> [SubscriptionSnapshot] {
        let recs = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.isDismissed == true }))
        return recs
            .sorted { $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.matchKey < $1.matchKey }
            .map(snapshot(of:))
    }

    private func snapshot(of rec: SubscriptionRecord) -> SubscriptionSnapshot {
        SubscriptionSnapshot(
            id: rec.matchKey, displayName: rec.displayName, amount: rec.amount,
            currencyCode: rec.currencyCode, cadence: rec.cadence, nextChargeDate: rec.nextChargeDate,
            occurrenceCount: rec.occurrenceCount, confidence: rec.confidence,
            isVariableAmount: rec.isVariableAmount, hadTrial: rec.hadTrial, isConfirmed: rec.isConfirmed)
    }

    public func confirmSubscription(matchKey: String) throws {
        guard let rec = try fetchSubscription(matchKey: matchKey) else { return }
        rec.isConfirmed = true; rec.isDismissed = false; rec.updatedAt = .now
        // Backfill: link existing expense-kind charges for this merchant+currency that aren't linked yet.
        let expenseRaw = TransactionKind.expense.rawValue
        let norm = rec.normalizedMerchant, code = rec.currencyCode
        let candidates = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.kindRaw == expenseRaw && $0.currencyCode == code && $0.subscription == nil }))
        for e in candidates where MerchantNormalizer.normalize(e.merchantName) == norm {
            e.subscription = rec
        }
        try modelContext.save()
    }

    public func dismissSubscription(matchKey: String) throws {
        guard let rec = try fetchSubscription(matchKey: matchKey) else { return }
        rec.isDismissed = true; rec.isConfirmed = false; rec.updatedAt = .now
        try modelContext.save()
    }

    /// Undo a dismissal — the candidate re-surfaces in `subscriptionCandidates()`.
    public func unDismissSubscription(matchKey: String) throws {
        guard let rec = try fetchSubscription(matchKey: matchKey) else { return }
        rec.isDismissed = false; rec.updatedAt = .now
        try modelContext.save()
    }

    /// Track a subscription the user declares directly — no charge history needed. Creates the
    /// same record detection creates, pre-confirmed, so the Tracked list, reminders, Upcoming
    /// and due-date ghosts all work unchanged. The matchKey uses the detector's scheme, so a
    /// later detected series for the same merchant converges on THIS record instead of duplicating.
    public func addManualSubscription(name: String, amount: Decimal, currency: CurrencyCode,
                                      cadence: SubscriptionCadence, nextChargeDate: Date,
                                      now: Date = .now) throws {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let norm = MerchantNormalizer.normalize(displayName)
        guard !norm.isEmpty, amount > 0 else { return }
        let key = "\(norm)|\(cadence.rawValue)|\(currency.rawValue)"
        if let rec = try fetchSubscription(matchKey: key) {
            rec.displayName = displayName
            rec.amount = amount
            rec.nextChargeDate = nextChargeDate
            rec.manualAnchorDate = nextChargeDate
            rec.isConfirmed = true; rec.isDismissed = false; rec.isManual = true
            rec.confidence = 1
            rec.updatedAt = now
        } else {
            let rec = SubscriptionRecord(matchKey: key, displayName: displayName,
                                         normalizedMerchant: norm, amount: amount,
                                         currencyCode: currency.rawValue, cadence: cadence,
                                         nextChargeDate: nextChargeDate,
                                         occurrenceCount: 0, confidence: 1)
            rec.isConfirmed = true
            rec.isManual = true
            rec.manualAnchorDate = nextChargeDate
            rec.detectedAt = now; rec.updatedAt = now
            modelContext.insert(rec)
        }
        try modelContext.save()
    }

    public func subscriptionRecordCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<SubscriptionRecord>())
    }

    private func fetchSubscription(matchKey key: String) throws -> SubscriptionRecord? {
        // Exclude archived tombstones: a converged CloudKit duplicate leaves an archived row with
        // the SAME matchKey, and confirm/dismiss must always target the active record.
        var fd = FetchDescriptor<SubscriptionRecord>(predicate: #Predicate { $0.matchKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first
    }

    /// GOL-92 (pending ghosts): the due-but-unlogged charges of confirmed fixed-amount
    /// subscriptions, as ONE-TAP ghost candidates for the Recent list. READ-ONLY — nothing
    /// is written until the user taps a ghost (which logs via `logAutomatic(date:)`, the same
    /// battle-tested path as Apple Pay captures, so later statement imports merge normally).
    ///
    /// Rules (spec "Final pivot", distilled from three adversarial review rounds):
    /// - The SCHEDULE anchors on the most recent real charge within the detector's amount
    ///   tolerance — a same-merchant one-off can't hijack it, and due dates are always
    ///   `advance(anchor, by: k)` so month-end billing days never drift.
    /// - A due date COVERED by any row (tombstones included) within half a cadence period
    ///   never surfaces — deletion is final; nothing re-asks about a deleted charge.
    /// - Eligibility per `settleableMatchKeys`: CloudKit same-matchKey duplicates count once;
    ///   competing same-merchant schedules surface nothing.
    public func pendingSubscriptionCharges(now: Date = .now) throws -> [PendingSubscriptionCharge] {
        let confirmed = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            .filter { $0.isConfirmed && !$0.isDismissed && !$0.isArchived }
        guard !confirmed.isEmpty else { return [] }
        let settleable = SubscriptionSettlementPlanner.settleableMatchKeys(confirmed: confirmed.map {
            .init(matchKey: $0.matchKey, normalizedMerchant: $0.normalizedMerchant,
                  currencyCode: $0.currencyCode, isVariableAmount: $0.isVariableAmount)
        })
        // One representative per key (duplicates are the same schedule; the freshest copy
        // carries the most current detector-derived amount).
        var representative: [String: SubscriptionRecord] = [:]
        for sub in confirmed where settleable.contains(sub.matchKey) {
            if let kept = representative[sub.matchKey], kept.updatedAt >= sub.updatedAt { continue }
            representative[sub.matchKey] = sub
        }
        guard !representative.isEmpty else { return [] }

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let expenseRaw = TransactionKind.expense.rawValue
        // ONE bounded fetch, tombstones INCLUDED (a deleted charge must keep suppressing its due
        // date). 400 days reaches a yearly sub's anchor plus the widest coverage window with
        // slack, without rescanning the whole table on every home load (GOL-86). Merchant +
        // amount matching stays in memory — never in a #Predicate (Decimal there SIGSEGVs).
        let lookback = cal.date(byAdding: .day, value: -400, to: now) ?? .distantPast
        let rows = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.kindRaw == expenseRaw && $0.date >= lookback }))
        let grouped = Dictionary(grouping: rows) {
            "\(MerchantNormalizer.normalize($0.merchantName))|\($0.currencyCode)"
        }

        var pending: [PendingSubscriptionCharge] = []
        for sub in representative.values {
            let groupKey = "\(sub.normalizedMerchant)|\(sub.currencyCode)"
            guard let merchantRows = grouped[groupKey] else { continue }
            let evidence = merchantRows.filter {
                !$0.isArchived
                    && SubscriptionSettlementPlanner.isBillingEvidence(amount: $0.amount,
                                                                       subscriptionAmount: sub.amount)
            }
            // Anchor = freshest billing evidence; the earliest bounds the backward grid walk so
            // backfill can never invent dues from before the subscription's known history.
            guard let anchor = evidence.max(by: { $0.date < $1.date }),
                  let earliest = evidence.min(by: { $0.date < $1.date }) else { continue }
            let coverage = TimeInterval(SubscriptionSettlementPlanner.coverageWindowDays(for: sub.cadence)) * 86_400
            for dueDate in SubscriptionSettlementPlanner.dueCharges(
                anchor: anchor.date, notBefore: earliest.date, cadence: sub.cadence, now: now, calendar: cal) {
                let isCovered = merchantRows.contains {
                    abs($0.date.timeIntervalSince(dueDate)) <= coverage
                }
                guard !isCovered else { continue }
                // The anchor's REAL merchant string (not displayName): logging the ghost with it
                // keeps MerchantNormalizer equality with future statement rows so imports merge.
                pending.append(PendingSubscriptionCharge(
                    matchKey: sub.matchKey, displayName: sub.displayName,
                    merchantName: anchor.merchantName ?? sub.displayName,
                    amount: sub.amount, currencyCode: sub.currencyCode, dueDate: dueDate))
            }
        }
        return pending.sorted { $0.dueDate < $1.dueDate }
    }
}
