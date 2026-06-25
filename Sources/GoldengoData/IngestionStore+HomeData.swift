import Foundation
import SwiftData
import GoldengoCore

/// Everything the Home dashboard needs in one call. Sendable value snapshot.
public struct HomeData: Sendable {
    public let rows: [ExpenseSnapshot]      // recent 50 (both kinds), expense rows carry fundedBy
    public let todayTotal: Decimal          // displayCurrency
    public let summary: DashboardSummary
    public let ghosts: [RhythmGhost]
    /// Named sources for the edit sheet's "Paid from" chips (GOL-89) — rides the source fetch
    /// homeData already does for funding labels, so the picker costs no extra round-trip.
    public let sources: [FundingSourceOption]
    /// Due-but-unlogged subscription charges for the one-tap "Due" ghost section (GOL-92).
    public let pending: [PendingSubscriptionCharge]
    /// Read-only per-currency wallet snapshot for the Home "In your pocket" hero (UI rewrite).
    /// Rides the home fetch; Home never writes wallet state.
    public let pocket: [PocketLine]

    public init(rows: [ExpenseSnapshot], todayTotal: Decimal, summary: DashboardSummary,
                ghosts: [RhythmGhost], sources: [FundingSourceOption], pending: [PendingSubscriptionCharge],
                pocket: [PocketLine] = []) {
        self.rows = rows; self.todayTotal = todayTotal; self.summary = summary
        self.ghosts = ghosts; self.sources = sources; self.pending = pending
        self.pocket = pocket
    }
}

extension IngestionStore {
    /// One fetch of all non-archived expense records drives recent-50 / today total / month summary /
    /// rhythm ghosts / funding labels in memory (replacing those four separate reader calls + their
    /// redundant scans). The pocket (per-currency wallet) and pending-subscription sections still do
    /// their own small, self-contained fetches — pocket reads WalletCounts and pending needs archived
    /// rows that `all` deliberately excludes. Funding labels use the SharedSummary preferred currency
    /// (matching `recentExpenses`); the totals use `displayCurrency`. The FIFO allocation is cached.
    public func homeData(in displayCurrency: CurrencyCode = .all, rates: RateTable,
                         now: Date = .now, topCategoryLimit: Int = 4) throws -> HomeData {
        let expenseRaw = TransactionKind.expense.rawValue

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.relationshipKeyPathsForPrefetching = [\.category, \.subscription, \.provenanceSource]
        let all = try modelContext.fetch(fd)
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))

        // Provenance funding labels — preferred currency, via the cached allocation.
        let (inflows, outflows) = buildAllocatorInputs(from: all)
        let alloc = allocateCached(inflows: inflows, outflows: outflows, rates: rates,
                                   displayCurrency: SharedSummary().readPreferredCurrency())
        let tags = fundingLabelMap(alloc: alloc, sources: sources)

        // Recent 50 (both kinds, already date-desc); attach the funding tag to expense rows.
        let rows: [ExpenseSnapshot] = all.prefix(50).map { r in
            var snap = makeSnapshot(r)
            if r.kindRaw == expenseRaw {
                // GOL-95 v2: cash-funded spends drain the wallet, not a source pool — chip
                // says so directly (the FIFO tags only cover bank-funded rows now).
                let cashFunded = r.fundedBySourceID == FundingPin.wallet
                    || (r.fundedBySourceID == nil && r.sourceRaw == ExpenseSource.manual.rawValue)
                if cashFunded {
                    snap.fundedBy = "Wallet"
                } else {
                    snap.fundedBy = tags[r.dedupeKey]?.label
                    snap.fundedByColorIndex = tags[r.dedupeKey]?.colorIndex
                }
            }
            return snap
        }

        // Today total (displayCurrency).
        let startOfToday = Calendar.current.startOfDay(for: now)
        let todayMonies = all
            .filter { $0.kindRaw == expenseRaw && $0.date >= startOfToday }
            .map { Money(amount: $0.amount, currency: CurrencyCode($0.currencyCode)) }
        let todayTotal = CurrencyConverter(table: rates).sum(todayMonies, to: displayCurrency)

        // Month summary (displayCurrency) from a month-filtered slice of the same array.
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let monthRecords = all.filter { $0.kindRaw == expenseRaw && $0.date >= monthStart }
        let summary = try makeDashboardSummary(monthRecords: monthRecords, in: displayCurrency,
                                               rates: rates, topCategoryLimit: topCategoryLimit)

        // Ghosts — best-effort so a rhythm failure never blanks the dashboard (matches load()'s try?).
        let ghosts = (try? rhythmGhosts(from: all.filter { $0.kindRaw == expenseRaw }, now: now)) ?? []

        // Pending subscription dues (GOL-92) — same best-effort stance. Self-contained fetch:
        // its tombstone-aware coverage needs archived rows, which `all` deliberately excludes.
        let pending = (try? pendingSubscriptionCharges(now: now)) ?? []

        let options = sources
            .map { FundingSourceOption(id: $0.id, name: $0.name, colorIndex: $0.colorIndex) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let pocket = (try? pocketSnapshot(now: now)) ?? []

        return HomeData(rows: rows, todayTotal: todayTotal, summary: summary, ghosts: ghosts,
                        sources: options, pending: pending, pocket: pocket)
    }
}
