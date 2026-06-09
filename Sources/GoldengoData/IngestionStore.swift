import Foundation
import SwiftData
import GoldengoCore
#if canImport(WidgetKit)
import WidgetKit
#endif

public enum IngestOutcome: String, Sendable, Equatable { case inserted, merged }

public struct ExpenseSnapshot: Sendable, Equatable, Identifiable {
    public var dedupeKey: String
    public var amount: Decimal
    public var currencyCode: String
    public var source: ExpenseSource
    public var categoryName: String?
    public var date: Date
    public var merchantName: String?
    public var note: String?
    public var kind: TransactionKind
    public var subscriptionName: String?
    /// Short "funded by …" label from provenance FIFO (nil for expenses with no named source and for
    /// income rows). Populated by `recentExpenses`; defaults nil so other constructors are unaffected.
    public var fundedBy: String? = nil

    /// Stable identity for `.sheet(item:)` / `ForEach` — the dedupeKey uniquely identifies the row.
    public var id: String { dedupeKey }

    /// The row's primary label: lead with the most specific thing the user gave — the free-text note
    /// ("what"), then the merchant ("who"), then the category, then a generic fallback.
    public var displayTitle: String { note ?? merchantName ?? categoryName ?? "Expense" }
}

@ModelActor
public actor IngestionStore {
    // MARK: FIFO allocation cache (GOL-86)
    // Memoize the ProvenanceAllocator result. The allocation depends ONLY on the provenance inputs +
    // display currency + rate date, so we key the cache on a content fingerprint of those — it can
    // never serve stale data: any local edit/delete/add-income, a date reorder, a currency/rate
    // change, or a CloudKit remote merge changes the fingerprint and forces a recompute. Internal (not
    // private) so the cross-file +Provenance / +HomeData extensions can call allocateCached.
    struct LedgerFingerprint: Equatable {
        let currencyCode: String
        let ratesAsOf: Date
        let inflowKeys: [String]
        let outflowKeys: [String]
    }
    private var cachedAllocation: (fingerprint: LedgerFingerprint, allocation: ProvenanceAllocator.Allocation)?
    /// Test observability only: number of times the allocator actually ran (i.e. cache misses).
    private(set) var allocationComputeCount = 0

    /// Reuse the cached allocation when the inputs+currency+rate-date are identical, else recompute.
    func allocateCached(inflows: [ProvenanceAllocator.Inflow], outflows: [ProvenanceAllocator.Outflow],
                        rates: RateTable, displayCurrency: CurrencyCode) -> ProvenanceAllocator.Allocation {
        let fp = fingerprint(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: displayCurrency)
        if let cached = cachedAllocation, cached.fingerprint == fp { return cached.allocation }
        let alloc = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows,
                                                 rates: rates, displayCurrency: displayCurrency)
        cachedAllocation = (fp, alloc)
        allocationComputeCount += 1
        return alloc
    }

    /// Order-independent content fingerprint of the allocator inputs (keys sorted so a different fetch
    /// order — e.g. Home's date-desc vs Sources' unsorted — still hits the same cache entry).
    private func fingerprint(inflows: [ProvenanceAllocator.Inflow], outflows: [ProvenanceAllocator.Outflow],
                             rates: RateTable, displayCurrency: CurrencyCode) -> LedgerFingerprint {
        LedgerFingerprint(
            currencyCode: displayCurrency.rawValue,
            ratesAsOf: rates.asOf,
            inflowKeys: inflows.map { "\($0.id)|\($0.date.timeIntervalSinceReferenceDate)|\($0.amount)|\($0.currency.rawValue)|\($0.sourceID)" }.sorted(),
            outflowKeys: outflows.map { "\($0.id)|\($0.date.timeIntervalSinceReferenceDate)|\($0.amount)|\($0.currency.rawValue)" }.sorted())
    }

    /// Insert a transaction, or merge it into the existing non-archived record with the
    /// same dedupeKey. Note: with composite keys (no external id) two genuinely distinct
    /// expenses sharing day+amount+merchant+account will merge — an accepted trade-off
    /// (spec §6) for collapsing import↔import duplicates. Manual entries use a unique key
    /// (`logManual`), so they are never auto-collapsed; an imported row may also reconcile
    /// into a recent `.automatic` capture (see `reconcileImportedAgainstAutomatic`).
    public func ingest(_ tx: NormalizedTransaction, source: ExpenseSource = .imported) throws -> IngestOutcome {
        let key = tx.dedupeKey
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        if let existing = try modelContext.fetch(fd).first {
            try merge(existing, with: tx, source: source)
            return .merged
        }
        // Cross-source reconciliation: an imported statement row that is very likely the same
        // purchase as a recent hands-free (.automatic) capture merges into it rather than
        // double-counting. Conservative on purpose — see reconcileImportedAgainstAutomatic.
        if source == .imported, let auto = try reconcileImportedAgainstAutomatic(tx) {
            try merge(auto, with: tx, source: source)
            return .merged
        }
        let rec = ExpenseRecord(amount: tx.amount, currencyCode: tx.currency.rawValue,
                                date: tx.date, merchantName: tx.rawMerchant,
                                kind: tx.kind, source: source, dedupeKey: key)
        rec.category = try defaultCategory(forMerchant: tx.rawMerchant)
        modelContext.insert(rec)
        try linkToConfirmedSubscription(rec)
        try modelContext.save()
        return .inserted
    }

    /// Merge an incoming transaction into an existing record: refresh provenance/merchant but keep
    /// the first-seen amount/date/currency — an import confirming an earlier entry must not silently
    /// rewrite it. Used by both the exact-dedupeKey path and cross-source reconciliation.
    private func merge(_ existing: ExpenseRecord, with tx: NormalizedTransaction, source: ExpenseSource) throws {
        existing.sourceRaw = source.rawValue
        existing.merchantName = tx.rawMerchant ?? existing.merchantName
        existing.updatedAt = .now
        // Back-fill the merchant default category if the record still has none
        // (e.g. a manual entry made before the merchant->category mapping was learned).
        if existing.category == nil {
            existing.category = try defaultCategory(forMerchant: tx.rawMerchant)
        }
        try linkToConfirmedSubscription(existing)
        try modelContext.save()
    }

    /// Find a recent `.automatic` capture that is high-confidence the SAME purchase as an imported
    /// row, or nil. High-confidence = same currency + exact amount + same kind + exact normalized
    /// merchant (`MerchantNormalizer`, which drops numeric terminal tokens) + the swipe day within
    /// `[postingDay - 4, postingDay]` (posting follows the swipe). Returns the earliest match so a
    /// second imported row in the same statement reconciles against a different capture. Bias:
    /// anything short of this stays a separate, deletable record — never hide a real expense.
    private func reconcileImportedAgainstAutomatic(_ tx: NormalizedTransaction) throws -> ExpenseRecord? {
        let merchantNorm = MerchantNormalizer.normalize(tx.rawMerchant)
        guard !merchantNorm.isEmpty else { return nil }
        // Calendar.current (not UTC like dedupeKey): the +1-day slack on `upper` absorbs tz skew,
        // and any miss errs toward a kept duplicate — never a hidden expense.
        let cal = Calendar.current
        let postingDay = cal.startOfDay(for: tx.date)
        guard let lower = cal.date(byAdding: .day, value: -4, to: postingDay),
              let upper = cal.date(byAdding: .day, value: 1, to: postingDay) else { return nil }
        let cur = tx.currency.rawValue
        let kindRaw = tx.kind.rawValue
        let autoRaw = ExpenseSource.automatic.rawValue
        // Filter currency/kind/source/date-window in the store; match amount + merchant IN MEMORY.
        // (SwiftData/CoreData predicate translation of `Decimal` equality can crash at runtime, so
        // `amount` must NOT appear in the #Predicate.)
        let fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate {
                $0.isArchived == false && $0.sourceRaw == autoRaw && $0.kindRaw == kindRaw
                    && $0.currencyCode == cur
                    && $0.date >= lower && $0.date < upper
            },
            sortBy: [SortDescriptor(\.date, order: .forward)])
        let amt = tx.amount
        let candidates = try modelContext.fetch(fd)
        return candidates.first { $0.amount == amt && MerchantNormalizer.normalize($0.merchantName) == merchantNorm }
    }

    public func expenseCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.isArchived == false }))
    }

    public func snapshot(dedupeKey key: String) throws -> ExpenseSnapshot? {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        guard let r = try modelContext.fetch(fd).first else { return nil }
        return makeSnapshot(r)
    }

    public func recentExpenses(limit: Int = 20) throws -> [ExpenseSnapshot] {
        let labels = try fundingLabels(displayCurrency: SharedSummary().readPreferredCurrency())
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = limit
        return try modelContext.fetch(fd).map { r in
            var snap = makeSnapshot(r)
            if r.kindRaw == TransactionKind.expense.rawValue { snap.fundedBy = labels[r.dedupeKey] }
            return snap
        }
    }

    /// Sum of today's expense-kind amounts, each converted into `displayCurrency` via `rates`.
    /// (`.all` is the ISO 4217 code for the Albanian lek — the user's primary currency.)
    public func todayTotal(in displayCurrency: CurrencyCode = .all, rates: RateTable) throws -> Decimal {
        let start = Calendar.current.startOfDay(for: .now)
        let expenseRaw = TransactionKind.expense.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= start
        })
        let monies = try modelContext.fetch(fd).map {
            Money(amount: $0.amount, currency: CurrencyCode($0.currencyCode))
        }
        return CurrencyConverter(table: rates).sum(monies, to: displayCurrency)
    }

    /// Recompute the widget's today-total in the user's preferred currency and publish it.
    private func refreshSharedTodayTotal() throws {
        let display = SharedSummary().readPreferredCurrency()
        let rates = ExchangeRateCache().load() ?? SeedRates.table
        let total = try todayTotal(in: display, rates: rates)
        SharedSummary().writeTodayTotal(Money(amount: total, currency: display).formatted())
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()   // every save path (incl. the Apple Pay automation) refreshes the widget
#endif
    }

    private func makeSnapshot(_ r: ExpenseRecord) -> ExpenseSnapshot {
        ExpenseSnapshot(dedupeKey: r.dedupeKey, amount: r.amount, currencyCode: r.currencyCode,
                        source: r.source, categoryName: r.category?.name,
                        date: r.date, merchantName: r.merchantName, note: r.note, kind: r.kind,
                        subscriptionName: r.subscription?.displayName)
    }

    /// Link an expense-kind record to a CONFIRMED subscription with the same normalized merchant + currency.
    private func linkToConfirmedSubscription(_ rec: ExpenseRecord) throws {
        guard rec.kindRaw == TransactionKind.expense.rawValue else { return }
        let norm = MerchantNormalizer.normalize(rec.merchantName)
        guard !norm.isEmpty else { return }
        let confirmed = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.isConfirmed == true && $0.isDismissed == false && $0.isArchived == false }))
        if let match = confirmed.first(where: { $0.normalizedMerchant == norm && $0.currencyCode == rec.currencyCode }) {
            rec.subscription = match
        }
    }

    /// Logs a user-entered expense. Always a distinct insert (unique key) so identical
    /// same-day purchases are never collapsed. Returns the new record's dedupeKey.
    @discardableResult
    public func logManual(amount: Decimal, currency: CurrencyCode,
                          merchant: String?, note: String? = nil, categoryName: String?,
                          date: Date = .now) throws -> String {
        try logEntry(amount: amount, currency: currency, merchant: merchant, note: note,
                     categoryName: categoryName, source: .manual, keyPrefix: "manual", date: date)
    }

    /// Logs a hands-free auto-captured payment (e.g. the Apple Pay Transaction automation). Same
    /// behavior as `logManual` but tagged `.automatic` so import reconciliation can safely merge a
    /// later statement row into it, and the UI can label it "auto-logged". Always a distinct insert.
    @discardableResult
    public func logAutomatic(amount: Decimal, currency: CurrencyCode,
                             merchant: String?, categoryName: String? = nil) throws -> String {
        try logEntry(amount: amount, currency: currency, merchant: merchant, note: nil,
                     categoryName: categoryName, source: .automatic, keyPrefix: "auto")
    }

    /// Shared insert for the user-facing log paths (`logManual`, `logAutomatic`). A unique
    /// `<keyPrefix>:<uuid>` dedupeKey means these are never collapsed with each other — only an
    /// imported statement row reconciles into an `.automatic` entry (see `ingest`).
    @discardableResult
    private func logEntry(amount: Decimal, currency: CurrencyCode, merchant: String?, note: String?,
                          categoryName: String?, source: ExpenseSource, keyPrefix: String,
                          date: Date = .now) throws -> String {
        let key = "\(keyPrefix):\(UUID().uuidString)"
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: date,
                                merchantName: merchant, note: (cleanNote?.isEmpty ?? true) ? nil : cleanNote,
                                kind: .expense, source: source, dedupeKey: key)
        if let categoryName, !categoryName.isEmpty {
            rec.category = try findOrCreateCategory(named: categoryName)
        } else {
            // No explicit category and no remembered one for this merchant → a real "Other" category
            // (so it's counted, shows in Top Categories, and is re-assignable) rather than nil.
            rec.category = try defaultCategory(forMerchant: merchant) ?? findOrCreateCategory(named: "Other")
        }
        modelContext.insert(rec)
        try linkToConfirmedSubscription(rec)
        try modelContext.save()
        try refreshSharedTodayTotal()
        return key
    }

    func findOrCreateCategory(named rawName: String) throws -> CategoryRecord {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Case-insensitive reuse so free-text from Siri/Shortcuts doesn't spawn "Coffee"/"coffee".
        let all = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let c = CategoryRecord(name: name)
        modelContext.insert(c)
        return c
    }

    /// Remembered default category for a merchant (matched by normalized name), bumping
    /// its usage stats. Returns nil for empty/unknown merchants — the empty guard avoids
    /// matching a merchant row that happens to have an empty normalized name.
    public struct ImportSummary: Sendable, Equatable { public var imported: Int; public var deduped: Int }

    public func importStatement(_ transactions: [NormalizedTransaction], fileName: String) throws -> ImportSummary {
        var imported = 0, deduped = 0
        for tx in transactions {
            switch try ingest(tx, source: .imported) {
            case .inserted: imported += 1
            case .merged:   deduped += 1
            }
        }
        modelContext.insert(ImportBatch(fileName: fileName, rowCount: transactions.count,
                                        importedCount: imported, dedupedCount: deduped))
        try modelContext.save()
        try refreshSharedTodayTotal()
        return ImportSummary(imported: imported, deduped: deduped)
    }

    public func importBatchCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ImportBatch>())
    }

    private func defaultCategory(forMerchant rawMerchant: String?) throws -> CategoryRecord? {
        let norm = MerchantNormalizer.normalize(rawMerchant)
        guard !norm.isEmpty else { return nil }
        var mf = FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.normalizedName == norm })
        mf.fetchLimit = 1
        guard let merchant = try modelContext.fetch(mf).first else { return nil }
        merchant.useCount += 1
        merchant.lastUsed = .now
        return merchant.defaultCategory
    }
}
