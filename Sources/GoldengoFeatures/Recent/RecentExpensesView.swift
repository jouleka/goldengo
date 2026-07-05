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
    /// The History browser pushed from the "See all" affordance. Owned by `RootView` so it survives
    /// tab switches and shares the store.
    private let historyModel: HistoryModel
    /// Bound to `RootView` so the custom tab bar can hide while History is pushed (it's a ZStack
    /// sibling of the content, not a real tab bar that a push would cover).
    @Binding private var showHistory: Bool
    /// The full Spending breakdown pushed from the compact Spending card. Owned by `RootView`, same
    /// reason as `historyModel`.
    private let spendingModel: CategoryBreakdownModel
    /// Bound to `RootView` — same purpose as `showHistory`, for the Spending push.
    @Binding private var showSpending: Bool
    /// Bound to `RootView` — set true while scrolling down so the floating pill slides away.
    @Binding private var barHidden: Bool
    @State private var showCurrencyPicker = false
    @State private var adjusting: RhythmGhost?
    @State private var adjustAmount = ""
    /// Selectable currencies, decoded once on appear — not re-read from UserDefaults + re-decoded on
    /// every body pass (the currency Menu/picker read it directly in body).
    @State private var selectableCurrencies: [CurrencyCode] = []
    /// Folded day sections in the Recent list, keyed by start-of-day. Expanded by default (absent =
    /// expanded). Keyed by date — not list index — so a fold survives the frequent `model.load()`
    /// reloads (tab return, foreground, after an add/edit/delete). Session-only; not persisted.
    @State private var collapsedDays: Set<Date> = []
    /// Drives the Spending card's budget-bar fill animation (matches `CategoryBreakdownView`'s own).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: RecentExpensesModel,
                historyModel: HistoryModel,
                showHistory: Binding<Bool> = .constant(false),
                spendingModel: CategoryBreakdownModel,
                showSpending: Binding<Bool> = .constant(false),
                barHidden: Binding<Bool> = .constant(false),
                onOpenImport: @escaping () -> Void = {},
                onOpenSettings: @escaping () -> Void = {},
                onOpenSubscriptions: @escaping () -> Void = {},
                onChangeCurrency: @escaping (CurrencyCode) -> Void = { _ in }) {
        self.model = model
        self.historyModel = historyModel
        self._showHistory = showHistory
        self.spendingModel = spendingModel
        self._showSpending = showSpending
        self._barHidden = barHidden
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

                // 3. Spending — compact top-categories preview; taps through to the full breakdown.
                spendingHeaderRow
                    .goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                spendingCard.goldengoCardRow()

                // 4. Upcoming (pending subscription charges).
                if !model.pendingCharges.isEmpty {
                    GoldengoSerifSectionHeader("Upcoming")
                        .goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.pendingCharges) { p in dueRow(p) }
                }

                // 5. Today's usuals (rhythm ghosts).
                if !model.ghosts.isEmpty {
                    GoldengoSerifSectionHeader("Today's usuals")
                        .goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.ghosts) { g in ghostRow(g) }
                }

                // 6. Recent — this month, grouped by day; "See all" opens the full History browser.
                HStack(alignment: .firstTextBaseline) {
                    GoldengoSerifSectionHeader("Recent")
                    Spacer()
                    Button { showHistory = true } label: {
                        HStack(spacing: 2) {
                            Text("See all").font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(GoldengoTheme.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all expenses")
                }
                .goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                if model.rows.isEmpty {
                    emptyRecentCard.goldengoCardRow()
                } else {
                    ForEach(RecentExpensesModel.dayGroups(from: model.rows, now: .now)) { group in
                        Section {
                            if !collapsedDays.contains(group.id) {
                                ForEach(group.rows, id: \.dedupeKey) { r in recentRow(r) }
                            }
                        } header: {
                            dayHeader(group)
                        }
                        .textCase(nil)   // SwiftUI uppercases plain-list headers by default; our labels are cased.
                    }
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
            // Clear the floating tab bar + raised Add button so the last rows aren't tucked behind it.
            // Lives on the list (not the RootView wrapper) so pushed History — which hides the bar —
            // doesn't inherit a big empty bottom gap.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
            .modifier(HideBarOnScroll(hidden: $barHidden))   // slide the pill away while scrolling down
            .navigationDestination(isPresented: $showHistory) { HistoryView(model: historyModel) }
            // Popping back from History fires no tab/sheet transition, so reload Home here — an edit or
            // delete made in History to a current-month row must show on Home without a manual refresh.
            .onChange(of: showHistory) { _, shown in
                if !shown { barHidden = false; Task { await model.load() } }
            }
            .navigationDestination(isPresented: $showSpending) { CategoryBreakdownView(model: spendingModel) }
            // Popping back from the full breakdown may have changed a cap — reload so the card's rows
            // and over-budget dot reflect it without a manual refresh.
            .onChange(of: showSpending) { _, shown in
                if !shown { barHidden = false; Task { await model.load() } }
            }
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

    // MARK: - Spending card

    /// "Spending" title + an over-budget dot when any category this month is over its cap. No
    /// trailing button here (unlike Recent's header) — the whole card below is the single tap target,
    /// so a second tappable control in the header would compete with it.
    private var spendingHeaderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: GoldengoTheme.Spacing.s) {
            GoldengoSerifSectionHeader("Spending")
            if model.hasOverBudgetCategory {
                Circle()
                    .fill(GoldengoTheme.danger)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)   // conveyed in the card's own accessibility label instead
            }
            Spacer()
        }
    }

    /// Compact preview of the top 3 categories this month; taps through to the full breakdown.
    /// Empty state: a quiet line, matching Recent's `emptyRecentCard` tone (no icon here — this is a
    /// secondary card, not the primary empty state).
    private var spendingCard: some View {
        Button {
            showSpending = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if model.spendingCardRows.isEmpty {
                    Text("No spending yet this month")
                        .font(.system(size: 14))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .padding(.vertical, GoldengoTheme.Spacing.xs)
                } else {
                    ForEach(Array(model.spendingCardRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().overlay(GoldengoTheme.hairline)
                        }
                        spendingCardRow(row)
                    }
                }
                Divider().overlay(GoldengoTheme.hairline)
                    .padding(.top, GoldengoTheme.Spacing.xs)
                HStack(spacing: 2) {
                    Spacer()
                    Text("See all").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(GoldengoTheme.accent)
                .padding(.top, GoldengoTheme.Spacing.s)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .goldengoCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spendingCardAccessibilityLabel)
        .accessibilityHint("Double tap to see all categories")
    }

    /// One compact row: color dot + name + amount, and — for capped categories — the same thin
    /// budget bar used on the full breakdown screen (green ok / gold near / terracotta over).
    private func spendingCardRow(_ row: CategoryBreakdownRow) -> some View {
        let amountText = Money(amount: row.spent, currency: model.spendingCardCurrency).amountText()
        return VStack(alignment: .leading, spacing: row.budget != nil ? GoldengoTheme.Spacing.xs : 0) {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                Circle()
                    .fill(Color(hex: row.colorHex))
                    .frame(width: 10, height: 10)
                Text(row.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .lineLimit(1)
                Spacer(minLength: GoldengoTheme.Spacing.s)
                Text(amountText)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(GoldengoTheme.inkPrimary)
            }
            if let budget = row.budget {
                spendingCardBudgetBar(spent: row.spent, budget: budget, level: row.level)
                    .padding(.leading, 10 + GoldengoTheme.Spacing.s)   // align under the name, past the dot
            }
        }
        .padding(.vertical, GoldengoTheme.Spacing.s)
    }

    /// The same thin progress bar as `CategoryBreakdownView.budgetBar`, without its trailing caption
    /// (the compact card has no room for "over by …" / "… left" text alongside three rows).
    private func spendingCardBudgetBar(spent: Decimal, budget: Decimal, level: BudgetLevel) -> some View {
        let spentDouble = (spent as NSDecimalNumber).doubleValue
        let budgetDouble = (budget as NSDecimalNumber).doubleValue
        let fraction = budgetDouble > 0 ? min(1.0, spentDouble / budgetDouble) : 0
        let tint = spendingBudgetLevelColor(level)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.goldengoField)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint)
                    .frame(width: geo.size.width * fraction)
                    .animation(reduceMotion ? nil : GoldengoMotion.standard, value: fraction)
            }
        }
        .frame(height: 6)
    }

    private func spendingBudgetLevelColor(_ level: BudgetLevel) -> Color {
        switch level {
        case .ok: return GoldengoTheme.income
        case .near: return GoldengoTheme.accent
        case .over: return GoldengoTheme.danger
        case .noBudget: return GoldengoTheme.inkMuted
        }
    }

    /// "Spending, tap to see all categories" plus a per-row readout, so VoiceOver users get the same
    /// information sighted users see without landing on individual un-tappable sub-elements.
    private var spendingCardAccessibilityLabel: String {
        guard !model.spendingCardRows.isEmpty else { return "Spending, no spending yet this month" }
        let rows = model.spendingCardRows.map { row -> String in
            let amount = Money(amount: row.spent, currency: model.spendingCardCurrency).formatted()
            guard let budget = row.budget else { return "\(row.name), \(amount)" }
            switch row.level {
            case .over:
                let over = Money(amount: row.spent - budget, currency: model.spendingCardCurrency).formatted()
                return "\(row.name), \(amount), over by \(over)"
            default:
                let remaining = Money(amount: budget - row.spent, currency: model.spendingCardCurrency).formatted()
                return "\(row.name), \(amount), \(remaining) left"
            }
        }.joined(separator: "; ")
        let overBudgetNote = model.hasOverBudgetCategory ? ", over budget" : ""
        return "Spending\(overBudgetNote), tap to see all categories: \(rows)"
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

    // MARK: - Day header (collapsible, sticky)

    /// A quiet, sub-level header for one calendar day in Recent. The whole row toggles the day's fold
    /// state; the chevron rotates to signal it. A row count rides along so a folded day still says
    /// what's inside. Sits on an opaque canvas row so the pinned (sticky) header stays legible as
    /// rows scroll beneath it.
    private func dayHeader(_ group: DayGroup) -> some View {
        let collapsed = collapsedDays.contains(group.id)
        return Button {
            withAnimation(.snappy) {
                if collapsed { collapsedDays.remove(group.id) } else { collapsedDays.insert(group.id) }
            }
        } label: {
            collapsibleGroupHeaderLabel(title: group.title, count: group.rows.count, collapsed: collapsed)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.goldengoBackground)   // opaque so the pinned header occludes rows beneath it
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: GoldengoTheme.Spacing.m,
                                  bottom: 0, trailing: GoldengoTheme.Spacing.m))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title), \(group.rows.count) \(group.rows.count == 1 ? "expense" : "expenses"), \(collapsed ? "collapsed" : "expanded")")
        .accessibilityHint("Double tap to \(collapsed ? "expand" : "collapse")")
    }

    // Shared row layout (`homeRow` / `expenseHomeRow`) lives in Shared/ExpenseRowView.swift so the
    // History browser renders identical rows.

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

/// Drives the floating pill's hide-on-scroll: hidden while scrolling DOWN, revealed when scrolling UP
/// or near the top. Uses the iOS 18 scroll-geometry API; on iOS 17 the pill simply stays put.
private struct HideBarOnScroll: ViewModifier {
    @Binding var hidden: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { oldY, newY in
                if newY < 40 {                                  // near the top — always show
                    if hidden { hidden = false }
                } else if newY > oldY + 6 {                     // a deliberate downward scroll — hide
                    if !hidden { hidden = true }
                } else if newY < oldY - 4 {                     // any upward scroll — reveal eagerly
                    if hidden { hidden = false }
                }
            }
        } else {
            content
        }
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
