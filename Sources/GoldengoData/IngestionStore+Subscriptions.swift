import Foundation
import SwiftData
import GoldengoCore

/// `Sendable` view of a detected/persisted subscription, safe to cross the actor boundary to the UI.
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

    /// GOL-92: logs due-but-unlogged charges for confirmed fixed-amount subscriptions as
    /// `.automatic` entries (dedupeKey `settle:<uuid>`) dated at the due date.
    ///
    /// Safety rules (spec revision after adversarial review):
    /// - The SCHEDULE anchors only on REAL billing evidence — non-archived, non-settle rows
    ///   within the detector's amount tolerance — so sweep output never feeds its own schedule
    ///   (no self-sustaining fabrication) and month-end billing days never drift across runs.
    /// - A due date COVERED by any row within ±`coverageWindowDays` — tombstones included —
    ///   is skipped, so deleting an entry (settle-made or real) is final.
    /// - An archived settle row at/after the anchor means the user rejected a guess: the sub
    ///   is MUTED until newer real evidence arrives.
    /// - Two confirmed records sharing merchant+currency (a series that changed cadence) is
    ///   ambiguous — settle neither.
    /// Returns the number of entries created.
    @discardableResult
    public func settleDueSubscriptionCharges(now: Date = .now) throws -> Int {
        let subs = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            .filter { $0.isConfirmed && !$0.isDismissed && !$0.isArchived && !$0.isVariableAmount }
        guard !subs.isEmpty else { return 0 }
        var merchantCount: [String: Int] = [:]
        for s in subs { merchantCount["\(s.normalizedMerchant)|\(s.currencyCode)", default: 0] += 1 }

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let expenseRaw = TransactionKind.expense.rawValue
        // ONE bulk fetch, tombstones INCLUDED (archived rows must keep covering their dates or
        // deletions would resurrect). Merchant + amount matching stays in memory — never in a
        // #Predicate (Decimal there SIGSEGVs at runtime).
        let rows = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.kindRaw == expenseRaw }))
        let grouped = Dictionary(grouping: rows) {
            "\(MerchantNormalizer.normalize($0.merchantName))|\($0.currencyCode)"
        }
        let settlePrefix = Self.settleKeyPrefix + ":"
        let coverage = TimeInterval(SubscriptionSettlementPlanner.coverageWindowDays) * 86_400

        var created = 0
        for sub in subs {
            let groupKey = "\(sub.normalizedMerchant)|\(sub.currencyCode)"
            guard merchantCount[groupKey] == 1, let merchantRows = grouped[groupKey] else { continue }
            guard let anchor = merchantRows
                .filter({ !$0.isArchived && !$0.dedupeKey.hasPrefix(settlePrefix)
                    && SubscriptionSettlementPlanner.isBillingEvidence(amount: $0.amount,
                                                                       subscriptionAmount: sub.amount) })
                .max(by: { $0.date < $1.date }) else { continue }
            // Deletion mutes: the user rejected a guess made at/after the last real charge.
            guard !merchantRows.contains(where: {
                $0.isArchived && $0.dedupeKey.hasPrefix(settlePrefix) && $0.date >= anchor.date
            }) else { continue }
            for dueDate in SubscriptionSettlementPlanner.dueCharges(
                lastCharge: anchor.date, cadence: sub.cadence, now: now, calendar: cal) {
                let isCovered = merchantRows.contains {
                    abs($0.date.timeIntervalSince(dueDate)) <= coverage
                }
                guard !isCovered else { continue }
                // The anchor's REAL merchant string (not displayName) keeps MerchantNormalizer
                // equality with future statement rows so the import merges, not duplicates.
                _ = try logEntry(amount: sub.amount, currency: CurrencyCode(sub.currencyCode),
                                 merchant: anchor.merchantName, note: nil, categoryName: nil,
                                 source: .automatic, keyPrefix: Self.settleKeyPrefix, date: dueDate)
                created += 1
            }
        }
        return created
    }
}
