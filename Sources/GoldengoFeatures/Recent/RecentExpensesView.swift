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
    private let planModel: MoneyPlanModel
    @Binding private var showPlan: Bool
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
    public init(model: RecentExpensesModel,
                historyModel: HistoryModel,
                showHistory: Binding<Bool> = .constant(false),
                spendingModel: CategoryBreakdownModel,
                showSpending: Binding<Bool> = .constant(false),
                planModel: MoneyPlanModel,
                showPlan: Binding<Bool> = .constant(false),
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
        self.planModel = planModel
        self._showPlan = showPlan
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
                // 1. A quiet page header. Less common utilities live behind one menu; Settings stays
                // visible because it is the action people are most likely to look for here.
                headerRow.goldengoCardRow()

                if model.loadFailed { errorBanner.goldengoCardRow() }

                // 2. Home answers the most immediate question first: what happened today. Wallet
                // and month totals remain visible as supporting context, not competing headlines.
                todayHeroCard.goldengoCardRow()

                // 3. The one forward-looking decision Home needs. Reporting remains in the More
                // menu; tapping this opens the focused planning layer.
                planBriefCard.goldengoCardRow()

                // 4. Everything that can be completed in one tap is collected in one place.
                if !model.pendingCharges.isEmpty || !model.ghosts.isEmpty {
                    quickLogHeader.goldengoCardRow(top: 22, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.pendingCharges) { p in dueRow(p) }
                    ForEach(model.ghosts) { g in ghostRow(g) }
                }

                // 5. Recent — this month, grouped by day; "See all" opens the full History browser.
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
            .navigationDestination(isPresented: $showPlan) { MoneyPlanView(model: planModel) }
            .onChange(of: showPlan) { _, shown in
                if !shown {
                    barHidden = false
                    Task { await planModel.load(); await model.load() }
                }
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
                    onSave: { amt, cur, m, n, c, d, pin, context, splits, kind in
                        Task { await model.update(snap, amount: amt, currency: cur, merchant: m, note: n,
                                                  categoryName: c, date: d, fundedBySourceID: pin,
                                                  contextName: context, splits: splits, kind: kind) }
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: GoldengoTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.largeTitle.weight(.medium))
                    .fontDesign(.serif)
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
            Spacer()
            HStack(spacing: 6) {
                Menu {
                    Button { showSpending = true } label: {
                        Label("Spending breakdown", systemImage: "chart.pie.fill")
                    }
                    Button(action: onOpenSubscriptions) {
                        Label("Subscriptions", systemImage: "repeat")
                    }
                    Button(action: onOpenImport) {
                        Label("Import statement", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    circleIcon("ellipsis", label: "More")
                }
                circleIconButton("gearshape", label: "Settings", action: onOpenSettings)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func circleIconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circleIcon(systemName, label: label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func circleIcon(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(GoldengoTheme.inkMuted)
            .frame(width: 40, height: 40)
            .background(Color.goldengoField)
            .clipShape(Circle())
            .accessibilityLabel(label)
    }

    // MARK: - Today hero

    private var todayHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("SPENT TODAY")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(GoldengoTheme.inkMuted)
                Spacer()
                currencyMenu
            }

            GoldengoAmountText(model.todayTotalText, role: .hero)
                .padding(.top, GoldengoTheme.Spacing.s)

            Divider()
                .overlay(GoldengoTheme.hairline)
                .padding(.vertical, 18)

            HStack(spacing: GoldengoTheme.Spacing.m) {
                supportingMetric(title: "This month", value: model.monthTotalText())
                Divider().overlay(GoldengoTheme.hairline).frame(height: 34)
                supportingMetric(
                    title: "In your pocket",
                    value: model.hasWallet ? model.pocketHeroText : "Not set"
                )
            }
        }
        .goldengoCard(padding: 22)
    }

    private func supportingMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(GoldengoTheme.inkMuted)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Spending insight

    private var planBriefCard: some View {
        Button { showPlan = true } label: {
            if planModel.isPeriodConfigured { configuredPlanBrief }
            else { setupPlanBrief }
        }
        .buttonStyle(.plain)
        .goldengoCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint(planModel.isPeriodConfigured
                           ? "Double tap to open your plan"
                           : "Double tap to set your spending period")
    }

    private var configuredPlanBrief: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("SAFE TO SPEND", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.bold)).tracking(0.5)
                        .foregroundStyle(GoldengoTheme.income)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(planModel.safePerDayText)
                            .font(.title.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("/ day").font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold)).foregroundStyle(GoldengoTheme.inkMuted)
                    .padding(.top, 10)
            }
            Text(planBriefCaption)
                .font(.subheadline.weight(.medium)).foregroundStyle(GoldengoTheme.inkMuted)
            Divider().overlay(GoldengoTheme.hairline)
            HStack(spacing: 18) {
                planBriefMetric(icon: "tray.full.fill", value: planModel.reviewCount,
                                label: "to review", tint: planModel.reviewCount > 0 ? GoldengoTheme.accent : GoldengoTheme.income)
                planBriefMetric(icon: "calendar", value: planModel.upcomingCount,
                                label: "upcoming", tint: Color(hex: "#4D88C7"))
                Spacer()
                Text("Open plan").font(.subheadline.weight(.semibold)).foregroundStyle(GoldengoTheme.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private var setupPlanBrief: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(GoldengoTheme.accent)
                .frame(width: 46, height: 46)
                .background(GoldengoTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("SET YOUR SPENDING PERIOD")
                    .font(.caption.weight(.bold)).tracking(0.5)
                    .foregroundStyle(GoldengoTheme.accent)
                Text("Give your daily allowance a real amount and end date")
                    .font(.headline)
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .contentShape(Rectangle())
    }

    private var planBriefCaption: String {
        guard let safe = planModel.snapshot?.safe else { return "Checking balances, goals, and what is coming next" }
        return "through \(safe.horizonDate.formatted(.dateTime.day().month(.abbreviated))), after goals and planned payments"
    }

    private func planBriefMetric(icon: String, value: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            Text("\(value) \(label)").font(.caption.weight(.semibold)).foregroundStyle(GoldengoTheme.inkMuted)
        }
    }

    /// A single readable insight and a color strip replace the old three-row mini report. The whole
    /// surface remains one tap, leading to the interactive Spending view.
    private var spendingInsightCard: some View {
        Button {
            showSpending = true
        } label: {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.m) {
                HStack(spacing: GoldengoTheme.Spacing.m) {
                    Image(systemName: model.hasOverBudgetCategory ? "exclamationmark.triangle.fill" : "chart.pie.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.hasOverBudgetCategory ? GoldengoTheme.danger : GoldengoTheme.accent)
                        .frame(width: 42, height: 42)
                        .background((model.hasOverBudgetCategory ? GoldengoTheme.danger : GoldengoTheme.accent).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.hasOverBudgetCategory ? "Spending needs attention" : "Where your money went")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text(spendingInsightText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }

                spendingColorStrip
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .goldengoCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spendingCardAccessibilityLabel)
        .accessibilityHint("Double tap to explore spending")
    }

    private var spendingInsightText: String {
        guard let first = model.spendingCardRows.first else { return "No activity yet this month" }
        let amount = Money(amount: first.spent, currency: model.spendingCardCurrency).formatted()
        return "\(first.name) leads at \(amount)"
    }

    @ViewBuilder
    private var spendingColorStrip: some View {
        if model.spendingCardRows.isEmpty {
            Capsule().fill(Color.goldengoField).frame(height: 6)
        } else {
            GeometryReader { geo in
                let rows = model.spendingCardRows
                let total = rows.reduce(Decimal.zero) { $0 + max($1.spent, 0) }
                let available = max(0, geo.size.width - CGFloat(max(rows.count - 1, 0)) * 4)
                HStack(spacing: 4) {
                    ForEach(rows) { row in
                        let share = total > 0
                            ? (row.spent as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue
                            : 0
                        Capsule()
                            .fill(Color(hex: row.colorHex))
                            .frame(width: max(6, available * share))
                    }
                }
            }
            .frame(height: 6)
        }
    }

    private var quickLogHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                GoldengoSerifSectionHeader("Quick log")
                Text("Tap once to add")
                    .font(.system(size: 12.5))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
            Spacer()
            Text("\(model.pendingCharges.count + model.ghosts.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GoldengoTheme.accent)
                .frame(minWidth: 26, minHeight: 26)
                .background(GoldengoTheme.accent.opacity(0.12))
                .clipShape(Circle())
        }
    }

    /// "Spending, tap to see all categories" plus a per-row readout, so VoiceOver users get the same
    /// information sighted users see without landing on individual un-tappable sub-elements.
    private var spendingCardAccessibilityLabel: String {
        guard !model.spendingCardRows.isEmpty else { return "Where your money went, no spending yet this month" }
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

    private var currencyMenu: some View {
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
            HStack(spacing: 5) {
                Text(model.currency.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(GoldengoTheme.inkMuted)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.goldengoField)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel("Display currency, \(model.currency.rawValue)")
    }

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

    /// A clear one-tap action: icon + due amount/date + an explicit add affordance.
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
                isDraft: false,
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

    /// A clear one-tap action for a learned daily usual; the context menu remains an optional
    /// precision path for changing the suggested amount before logging it.
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
                isDraft: false,
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
