import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

public struct RecentExpensesView: View {
    /// Owned by `RootView` (so it can refresh on tab-return / import); observed here via @Observable.
    private let model: RecentExpensesModel
    @State private var editing: ExpenseSnapshot?
    /// The just-deleted expense, surfaced in the Undo toast until it auto-dismisses or is undone.
    @State private var recentlyDeleted: ExpenseSnapshot?
    /// When the current Undo toast should auto-dismiss. A wall-clock deadline (not a fixed sleep) so
    /// leaving and returning to the Home tab can't reset the countdown.
    @State private var undoDeadline: Date?
    /// How long the Undo toast stays before auto-dismissing.
    private let undoWindow: TimeInterval = 4
    private let onAdd: () -> Void
    private let onOpenImport: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenSubscriptions: () -> Void
    private let onChangeCurrency: (CurrencyCode) -> Void
    @State private var showCurrencyPicker = false
    @State private var adjusting: RhythmGhost?
    @State private var adjustAmount = ""

    public init(model: RecentExpensesModel,
                onAdd: @escaping () -> Void = {},
                onOpenImport: @escaping () -> Void = {},
                onOpenSettings: @escaping () -> Void = {},
                onOpenSubscriptions: @escaping () -> Void = {},
                onChangeCurrency: @escaping (CurrencyCode) -> Void = { _ in }) {
        self.model = model
        self.onAdd = onAdd
        self.onOpenImport = onOpenImport
        self.onOpenSettings = onOpenSettings
        self.onOpenSubscriptions = onOpenSubscriptions
        self.onChangeCurrency = onChangeCurrency
    }

    public var body: some View {
        NavigationStack {
            // A real `List` (not ScrollView+LazyVStack) so the recent rows get native, scroll-safe
            // `.swipeActions`. A custom per-row DragGesture fought the ScrollView's scrolling; the
            // system's List owns scrolling and swipe together, so they never conflict. The dashboard
            // cards ride on clear, separator-less rows to keep their existing card look.
            List {
                if model.loadFailed { errorBanner.goldengoCardRow() }
                homeHeader.goldengoCardRow()
                if model.subscriptionsText() != nil { subscriptionsCard.goldengoCardRow() }
                if let s = model.summary, !s.topCategories.isEmpty { categoriesCard(s).goldengoCardRow() }

                if !model.pendingCharges.isEmpty {
                    // Subscription dues outrank habit guesses: a detected billing schedule is
                    // near-certain, so the "Due" section sits above "Today's usuals" (GOL-92).
                    GoldengoSerifSectionHeader("Upcoming")
                        .goldengoCardRow(top: GoldengoTheme.Spacing.m, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.pendingCharges) { p in dueRow(p) }
                }

                if !model.ghosts.isEmpty {
                    GoldengoSerifSectionHeader("Today's usuals")
                        .goldengoCardRow(top: GoldengoTheme.Spacing.m, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.ghosts) { g in ghostRow(g) }
                }

                GoldengoSerifSectionHeader("Recent")
                    .goldengoCardRow(top: GoldengoTheme.Spacing.m, bottom: GoldengoTheme.Spacing.xs)
                if model.rows.isEmpty {
                    ContentUnavailableView("No expenses yet", systemImage: "tray",
                                           description: Text("Tap Add to log your first."))
                        .frame(maxWidth: .infinity)
                        .goldengoCardRow()
                } else {
                    ForEach(model.rows, id: \.dedupeKey) { r in recentRow(r) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Goldengo")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { onOpenImport() } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import statement")
                    Button { onOpenSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .refreshable { await model.load() }
            .alert("Adjust amount", isPresented: Binding(get: { adjusting != nil },
                                                         set: { if !$0 { adjusting = nil } }),
                   presenting: adjusting) { g in
                TextField("Amount", text: $adjustAmount)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                Button("Add") {
                    let amt = Decimal(string: adjustAmount) ?? g.amount
                    GoldengoHaptics.spendLanded()
                    Task { await model.confirm(g, amount: amt) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { g in
                Text("How much for \(g.displayName) today?")
            }
            .sheet(item: $editing) { snap in
                EditExpenseView(
                    snapshot: snap,
                    fundingSources: model.fundingSources,
                    onSave: { amt, cur, m, n, c, d, pin in
                        Task { await model.update(snap, amount: amt, currency: cur, merchant: m, note: n,
                                                  categoryName: c, date: d, fundedBySourceID: pin) }
                    },
                    onDelete: { deleteWithUndo(snap) }
                )
            }
            .overlay(alignment: .bottom) {
                if let snap = recentlyDeleted {
                    undoToast(snap)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Auto-dismiss the toast on a wall-clock deadline so leaving and returning to the Home
            // tab doesn't restart the countdown. Keying on the deleted row restarts it for a new
            // delete and cancels it the moment Undo clears recentlyDeleted.
            .task(id: recentlyDeleted?.dedupeKey) {
                guard recentlyDeleted != nil, let deadline = undoDeadline else { return }
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { recentlyDeleted = nil; return } // already elapsed off-screen
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { recentlyDeleted = nil }
            }
        }
    }

    // MARK: - Recent row (native swipe)

    /// One recent expense as a List row: full-row tap opens edit, native swipe reveals Edit (right) /
    /// Delete (left). Delete soft-deletes immediately with an Undo toast — no confirmation dialog.
    private func recentRow(_ r: ExpenseSnapshot) -> some View {
        // A Button (not .onTapGesture) so VoiceOver gets an activatable, isButton row and the tap
        // participates in the List's normal touch arbitration. The card is inside the label so the
        // whole card is the tap target (full-row tap → edit).
        Button { editing = r } label: {
            expenseRow(r)
                .goldengoCard(padding: GoldengoTheme.Spacing.m)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                  bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { deleteWithUndo(r) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { editing = r } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(GoldengoTheme.accent)
        }
    }

    // MARK: - Delete + Undo

    /// Soft-delete immediately (the row collapses away), then surface the Undo toast. No modal —
    /// the delete is reversible, which is friendlier than a pre-confirmation dialog. The toast holds
    /// a single most-recent deletion: a second delete replaces it (the earlier row stays deleted,
    /// re-addable) — standard "latest action" undo, safe because the soft-delete loses nothing.
    private func deleteWithUndo(_ snapshot: ExpenseSnapshot) {
        Task {
            await model.delete(snapshot)
            undoDeadline = Date().addingTimeInterval(undoWindow)
            withAnimation(.snappy) { recentlyDeleted = snapshot }
        }
    }

    private func undoDelete(_ snapshot: ExpenseSnapshot) {
        Task {
            await model.restore(snapshot)
            withAnimation(.snappy) { recentlyDeleted = nil }
        }
    }

    /// Slim, on-brand toast that floats clear of the tab bar after a delete.
    private func undoToast(_ snapshot: ExpenseSnapshot) -> some View {
        GoldengoToast(
            "\(snapshot.displayTitle) deleted",
            icon: "trash.fill",
            iconTint: GoldengoTheme.danger,
            actionTitle: "Undo",
            action: { undoDelete(snapshot) }
        )
        .padding(.horizontal, GoldengoTheme.Spacing.l)
        .padding(.bottom, GoldengoTheme.Spacing.m)
    }

    // MARK: - Cards

    private var errorBanner: some View {
        Label("Couldn't load your expenses. Pull to refresh.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .goldengoCard()
    }

    // MARK: - Display currency

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }
    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }
    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == model.currency.rawValue }) {
            list.insert(model.currency, at: 0)
        }
        return list
    }

    private var currencyMenuControl: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button {
                    onChangeCurrency(c)
                } label: {
                    if c.rawValue == model.currency.rawValue {
                        Label(menuLabel(c), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(c))
                    }
                }
            }
            Divider()
            Button { showCurrencyPicker = true } label: {
                Label("More currencies…", systemImage: "ellipsis.circle")
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.currency.symbol).font(.system(size: 26, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(GoldengoTheme.accent)
            .contentShape(Rectangle())
        }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Goldengo").font(.system(.title3, design: .serif)).foregroundStyle(GoldengoTheme.accent)
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, GoldengoTheme.Spacing.m)
                        .padding(.vertical, GoldengoTheme.Spacing.s)
                        .background(GoldengoTheme.accent)
                        .foregroundStyle(GoldengoTheme.onAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.xs) {
                GoldengoSectionLabel("In your pocket")
                if model.hasWallet {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        currencyMenuControl
                        GoldengoAmountText(model.pocketHeroText, role: .hero)
                    }
                    Text(model.pocketCaptionText).font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } else {
                    Text("Set your wallet to begin").font(.subheadline).foregroundStyle(GoldengoTheme.inkMuted)
                }
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.xs) {
                    GoldengoSerifSectionHeader("This month")
                    GoldengoAmountText(model.monthAmountText(), role: .title)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: GoldengoTheme.Spacing.xs) {
                    Text("Today").font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                    GoldengoAmountText(model.todayTotalText, role: .row)
                }
            }
            if let asOf = model.ratesAsOf {
                Text("Rates as of \(asOf.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .goldengoCard(padding: GoldengoTheme.Spacing.l)
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(
                    available: availableCurrencies,
                    selectedCode: Binding(
                        get: { model.currency.rawValue },
                        set: { onChangeCurrency(CurrencyCode($0)) }
                    )
                )
            }
        }
    }

    private var subscriptionsCard: some View {
        Button(action: onOpenSubscriptions) {
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscriptions").font(.subheadline.weight(.semibold))
                    if let subs = model.subscriptionsText() {
                        Text(subs).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .goldengoCard()
        }
        .buttonStyle(.plain)
    }

    private func categoriesCard(_ s: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.m) {
            GoldengoSerifSectionHeader("Top categories")
            ForEach(s.topCategories) { c in
                VStack(spacing: 6) {
                    HStack {
                        Label(c.name, systemImage: GoldengoCategoryIcon.symbol(for: c.name))
                            .font(.subheadline)
                            .labelStyle(.titleAndIcon)
                        Spacer()
                        Text(model.categoryTotalText(c.total))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    categoryBar(fraction: model.categoryFraction(c.total))
                }
            }
        }
        .goldengoCard(padding: GoldengoTheme.Spacing.l)
    }

    private func categoryBar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.goldengoField)
                Capsule().fill(GoldengoTheme.accent)
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }

    /// A due-but-unlogged subscription charge (GOL-92) — tap to log it at its due date. Same ghost
    /// grammar as the rhythm rows (draft opacity, plus-circle), but the chip carries the `repeat`
    /// symbol users already know as the subscription marker, and the caption leads with the date.
    private func dueRow(_ p: PendingSubscriptionCharge) -> some View {
        Button { GoldengoHaptics.spendLanded(); Task { await model.logPending(p) } } label: {
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Image(systemName: "repeat")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).font(.subheadline.weight(.medium))
                    Text(Money(amount: p.amount, currency: CurrencyCode(p.currencyCode)).formatted()
                         + " · " + p.dueDate.formatted(.dateTime.day().month(.abbreviated))
                         + " · tap to add")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(GoldengoTheme.accent)
            }
            .padding(.vertical, 4)
            .opacity(0.7)   // reads as a draft
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                  bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.displayName), due \(p.dueDate.formatted(.dateTime.day().month(.wide))), \(Money(amount: p.amount, currency: CurrencyCode(p.currencyCode)).formatted()). Double tap to log.")
    }

    /// A pre-drafted daily "usual" — tap to log at the median (today); long-press → Adjust amount.
    private func ghostRow(_ g: RhythmGhost) -> some View {
        Button { GoldengoHaptics.spendLanded(); Task { await model.confirm(g) } } label: {
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Image(systemName: GoldengoCategoryIcon.symbol(for: g.categoryName))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.displayName).font(.subheadline.weight(.medium))
                    Text("~" + Money(amount: g.amount, currency: CurrencyCode(g.currencyCode)).formatted() + " · tap to add")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(GoldengoTheme.accent)
            }
            .padding(.vertical, 4)
            .opacity(0.7)   // reads as a draft
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                  bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
        .contextMenu {
            Button("Adjust amount…") { adjustAmount = ""; adjusting = g }
        }
    }

    private func expenseRow(_ r: ExpenseSnapshot) -> some View {
        HStack(spacing: GoldengoTheme.Spacing.m) {
            Image(systemName: GoldengoCategoryIcon.symbol(for: r.categoryName))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.goldengoField)
                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(r.displayTitle)
                        .font(.subheadline.weight(.medium))
                    if r.subscriptionName != nil {
                        Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("Recurring")
                    }
                    if r.source == .automatic {
                        // Auto-captured (e.g. the Apple Pay automation) vs hand-added — a quiet marker
                        // so you can tell at a glance which rows Goldengo logged for you.
                        Image(systemName: "creditcard").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("Auto-logged")
                    }
                }
                Text(r.kind == .transfer ? "→ wallet" : (r.categoryName ?? "Other"))
                    .font(.caption).foregroundStyle(.secondary)
                if let fundedBy = r.fundedBy {
                    // Quiet funding chip: the source's palette-color dot (matching its Sources-tab
                    // bar) + "from <source>", in a soft capsule — calm, glanceable, no iconography.
                    HStack(spacing: 5) {
                        Circle()
                            .fill(GoldengoTheme.sourceColor(r.fundedByColorIndex ?? 0))
                            .frame(width: 6, height: 6)
                        Text("from \(fundedBy)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, GoldengoTheme.Spacing.s)
                    .padding(.vertical, 3)
                    .background(Color.goldengoField)
                    .clipShape(Capsule())
                    .padding(.top, 1)
                }
            }
            Spacer()
            if r.kind == .transfer {
                GoldengoAmountText(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted(),
                                   role: .row, color: GoldengoTheme.inkMuted)
            } else if r.kind == .income {
                GoldengoAmountText("+" + Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted(),
                                   role: .row, color: .green)
            } else {
                GoldengoAmountText(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted(),
                                   role: .row)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension View {
    /// A dashboard card on a clear, separator-less `List` row with consistent margins, so the List
    /// provides native scrolling while the cards keep their custom look.
    func goldengoCardRow(top: CGFloat = GoldengoTheme.Spacing.s,
                         bottom: CGFloat = GoldengoTheme.Spacing.s) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: GoldengoTheme.Spacing.m,
                                      bottom: bottom, trailing: GoldengoTheme.Spacing.m))
    }
}
