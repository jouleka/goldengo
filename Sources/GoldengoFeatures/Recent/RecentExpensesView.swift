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
    private let onOpenImport: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenSubscriptions: () -> Void
    private let onChangeCurrency: (CurrencyCode) -> Void
    @State private var showCurrencyPicker = false
    @State private var adjusting: RhythmGhost?
    @State private var adjustAmount = ""
    /// Selectable currencies, decoded once on appear — not re-read from UserDefaults + re-decoded on
    /// every body pass (the currency Menu/picker read it directly in body).
    @State private var selectableCurrencies: [CurrencyCode] = []

    public init(model: RecentExpensesModel,
                onOpenImport: @escaping () -> Void = {},
                onOpenSettings: @escaping () -> Void = {},
                onOpenSubscriptions: @escaping () -> Void = {},
                onChangeCurrency: @escaping (CurrencyCode) -> Void = { _ in }) {
        self.model = model
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
                // 1. Header row — serif wordmark left, circular icon buttons right.
                headerRow.goldengoCardRow()

                if model.loadFailed { errorBanner.goldengoCardRow() }

                // 2. Pocket hero card.
                pocketHeroCard.goldengoCardRow()

                // 3. Upcoming (pending subscription charges).
                if !model.pendingCharges.isEmpty {
                    GoldengoSerifSectionHeader("Upcoming")
                        .goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.pendingCharges) { p in dueRow(p) }
                }

                // 4. Today's usuals (rhythm ghosts).
                if !model.ghosts.isEmpty {
                    GoldengoSerifSectionHeader("Today's usuals")
                        .goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.ghosts) { g in ghostRow(g) }
                }

                // 5. Recent.
                GoldengoSerifSectionHeader("Recent")
                    .goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                if model.rows.isEmpty {
                    emptyRecentCard.goldengoCardRow()
                } else {
                    ForEach(model.rows, id: \.dedupeKey) { r in recentRow(r) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
#endif
            .refreshable { await model.load() }
            .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
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
    }

    // MARK: - Header row

    /// Wordmark + two 36×36 plain circular icon buttons. Matches home.jsx's .gg-wordmark + iconBtn.
    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Goldengo")
                .font(.system(size: 26, weight: .medium, design: .serif))
                .foregroundStyle(GoldengoTheme.accent)
            Spacer()
            HStack(spacing: 6) {
                // In-app entry to Subscriptions management (the redesign dropped the only button;
                // it was otherwise reachable only via Siri/deeplink).
                circleIconButton("repeat", label: "Subscriptions", action: onOpenSubscriptions)
                circleIconButton("square.and.arrow.down", label: "Import statement", action: onOpenImport)
                circleIconButton("gearshape", label: "Settings", action: onOpenSettings)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func circleIconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 21))
                .foregroundStyle(GoldengoTheme.inkMuted)
                .frame(width: 36, height: 36)
                .background(Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Pocket hero card

    private var pocketHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow: 12pt, semibold, tracking 0.6, uppercase, inkMuted — matches .gg-eyebrow
            Text("IN YOUR POCKET")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(GoldengoTheme.inkMuted)

            if model.hasWallet {
                GoldengoAmountText(model.pocketHeroText, role: .hero)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                let caption = model.pocketSecondaryText.isEmpty
                    ? "cash you're carrying right now"
                    : model.pocketSecondaryText
                Text(caption)
                    .font(.system(size: 12.5))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            } else {
                Text("Set your wallet to begin.")
                    .font(.system(size: 15))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                    .padding(.top, 12)
            }

            // Hairline divider, margin 18 top/bottom — matches home.jsx hr { margin: '18px 0' }
            Divider()
                .overlay(GoldengoTheme.hairline)
                .padding(.vertical, 18)

            // Bottom row: "This month" serif 16pt + amount cycler on the left;
            //             "Today" caption 12.5 + row amount on the right.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This month")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    // Currency cycler: monthAmountText + chevron.down (mirrors home.jsx onCycleDisplay)
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
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            GoldengoAmountText(model.monthAmountText(), role: .title)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(GoldengoTheme.inkMuted)
                                .padding(.top, 4)
                        }
                        .contentShape(Rectangle())
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Today")
                        .font(.system(size: 12.5))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    GoldengoAmountText(model.todayTotalText, role: .row)
                }
            }
        }
        .goldengoCard(padding: 22)
    }

    // MARK: - Currency helpers

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }
    private var availableCurrencies: [CurrencyCode] { selectableCurrencies }
    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == model.currency.rawValue }) {
            list.insert(model.currency, at: 0)
        }
        return list
    }

    // MARK: - Empty recent state

    /// A centered card with tag icon + copy, matching home.jsx's empty-Recent card.
    private var emptyRecentCard: some View {
        VStack(spacing: 0) {
            Image(systemName: "tag")
                .font(.system(size: 26))
                .foregroundStyle(GoldengoTheme.inkMuted)
                .padding(.bottom, 10)
            Text("No expenses yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text("Tap the gold button to log your first.")
                .font(.system(size: 13))
                .foregroundStyle(GoldengoTheme.inkMuted)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .goldengoCard()
    }

    // MARK: - Due row (pending subscription charge)

    /// Matches home.jsx: GoldengoIconTile("repeat") + name + sub + plus.circle accent. Draft opacity 0.72.
    private func dueRow(_ p: PendingSubscriptionCharge) -> some View {
        Button {
            GoldengoHaptics.spendLanded()
            Task { await model.logPending(p) }
        } label: {
            homeRow(
                icon: "repeat",
                title: p.displayName,
                sub: Money(amount: p.amount, currency: CurrencyCode(p.currencyCode)).formatted()
                    + " · " + p.dueDate.formatted(.dateTime.day().month(.abbreviated))
                    + " · tap to add",
                isDraft: true,
                accentRight: true
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                  bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.displayName), due \(p.dueDate.formatted(.dateTime.day().month(.wide))), \(Money(amount: p.amount, currency: CurrencyCode(p.currencyCode)).formatted()). Double tap to log.")
    }

    // MARK: - Ghost row (today's usual)

    /// Matches home.jsx: GoldengoIconTile(category icon) + name + "~amount · tap to add" + plus.circle. Draft opacity 0.72.
    private func ghostRow(_ g: RhythmGhost) -> some View {
        Button {
            GoldengoHaptics.spendLanded()
            Task { await model.confirm(g) }
        } label: {
            homeRow(
                icon: GoldengoCategoryIcon.symbol(for: g.categoryName),
                title: g.displayName,
                sub: "~" + Money(amount: g.amount, currency: CurrencyCode(g.currencyCode)).formatted()
                    + " · tap to add",
                isDraft: true,
                accentRight: true
            )
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

    // MARK: - Recent row (native swipe)

    /// Full-row tap → edit; native trailing swipe → delete; leading swipe → edit. Matches home.jsx ExpenseRow.
    private func recentRow(_ r: ExpenseSnapshot) -> some View {
        Button { editing = r } label: {
            expenseHomeRow(r)
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

    // MARK: - Shared row layout (home.jsx Row component)

    /// Reusable row layout matching home.jsx's Row: tile + title/sub column + right content.
    /// gap=14, padding 9×4, title 15.5/medium ink, sub 12.5 ink-muted.
    private func homeRow(
        icon: String,
        title: String,
        sub: String,
        recurring: Bool = false,
        fundedBy: String? = nil,
        fundedByColorIndex: Int? = nil,
        isDraft: Bool = false,
        accentRight: Bool = false,
        rightContent: AnyView? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            GoldengoIconTile(icon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                        .lineLimit(1)
                    if recurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 13))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                            .accessibilityLabel("Recurring")
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    Text(sub)
                        .font(.system(size: 12.5))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    if let fb = fundedBy, let idx = fundedByColorIndex {
                        // funded-by pill: field capsule, colored dot, name — matches home.jsx
                        HStack(spacing: 5) {
                            Circle()
                                .fill(GoldengoTheme.sourceColor(idx))
                                .frame(width: 6, height: 6)
                            Text(fb)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GoldengoTheme.inkMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.goldengoField)
                        .clipShape(Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
            if accentRight {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(GoldengoTheme.accent)
            } else if let rv = rightContent {
                rv
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .opacity(isDraft ? 0.72 : 1)
    }

    // MARK: - Expense row (recent list)

    private func expenseHomeRow(_ r: ExpenseSnapshot) -> some View {
        let amountStr = Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted()
        let amountView: AnyView
        switch r.kind {
        case .income:
            amountView = AnyView(GoldengoAmountText("+" + amountStr, role: .row, color: GoldengoTheme.income))
        case .transfer:
            amountView = AnyView(GoldengoAmountText(amountStr, role: .row, color: GoldengoTheme.inkMuted))
        default:
            amountView = AnyView(GoldengoAmountText(amountStr, role: .row))
        }

        let subText = r.kind == .transfer ? "→ wallet" : (r.categoryName ?? "Other")

        return homeRow(
            icon: GoldengoCategoryIcon.symbol(for: r.categoryName),
            title: r.displayTitle,
            sub: subText,
            recurring: r.subscriptionName != nil,
            fundedBy: r.fundedBy,
            fundedByColorIndex: r.fundedByColorIndex,
            isDraft: false,
            accentRight: false,
            rightContent: amountView
        )
    }

    // MARK: - Delete + Undo

    /// Soft-delete immediately (the row collapses away), then surface the Undo toast. No modal —
    /// the delete is reversible, which is friendlier than a pre-confirmation dialog.
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

    // MARK: - Error banner

    private var errorBanner: some View {
        Label("Couldn't load your expenses. Pull to refresh.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .goldengoCard()
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
