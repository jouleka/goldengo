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
                monthCard.goldengoCardRow()
                if model.subscriptionsText() != nil { subscriptionsCard.goldengoCardRow() }
                if let s = model.summary, !s.topCategories.isEmpty { categoriesCard(s).goldengoCardRow() }

                GoldengoSectionLabel("Recent")
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
            .sheet(item: $editing) { snap in
                EditExpenseView(
                    snapshot: snap,
                    onSave: { amt, cur, m, n, c, d in
                        Task { await model.update(snap, amount: amt, currency: cur, merchant: m, note: n, categoryName: c, date: d) }
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

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.xs) {
                    GoldengoSectionLabel("This month")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
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
                            // Small, fixed-width currency control (gold tint signals it's tappable) so the
                            // big amount beside it keeps a real width budget and scales instead of clipping.
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(model.currency.symbol)
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .contentShape(Rectangle())
                        }
                        Text(model.monthAmountText())
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    if let asOf = model.ratesAsOf {
                        Text("Rates as of \(asOf.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, GoldengoTheme.Spacing.m)
                        .padding(.vertical, GoldengoTheme.Spacing.s)
                        .background(GoldengoTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Label("Today", systemImage: "sun.max")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.todayTotalText)
                    .font(.headline)
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
            GoldengoSectionLabel("Top categories")
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
                    }
                }
                Text(r.categoryName ?? "Other")
                    .font(.caption).foregroundStyle(.secondary)
                if let fundedBy = r.fundedBy {
                    Label("funded by \(fundedBy)", systemImage: "arrow.down.left.circle")
                        .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
            }
            Spacer()
            if r.kind == .income {
                Text("+" + Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted())
                    .font(.subheadline.weight(.medium))
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
