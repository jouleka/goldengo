import SwiftUI
import GoldengoData
import GoldengoDesignSystem
import GoldengoCore

/// A statement file handed to the app via the Share Sheet / "Open in" → presented as the import
/// sheet. Identifiable so `.sheet(item:)` re-presents for each distinct shared file.
public struct ImportFile: Identifiable, Hashable {
    public let id: String
    public let url: URL
    public init(url: URL) { self.url = url; self.id = url.absoluteString }
}

/// Drives the Re-entry `.fullScreenCover(item:)` (Int? isn't Identifiable on its own).
public struct ReEntryPrompt: Identifiable { public let id = UUID(); public let days: Int }

/// Drives the ritual `.sheet(item:)` (RitualPrompt isn't Identifiable, and we need a fresh identity
/// per presentation). Only `.morning`/`.evening` are ever wrapped (never `.none`).
public struct RitualSheet: Identifiable { public let id = UUID(); public let kind: RitualPrompt }

/// Where a legacy tab index resolves under the 3-destination shell. Deep links, widget taps and
/// Siri `pendingTab` still speak in the old integer indices; this maps them to "select a tab" vs
/// "present a sheet". Pure + `Equatable` so routing can't silently regress.
public enum RootRoute: Equatable, Sendable {
    case tab(Int)          // a real bottom-bar tab: Home (1) or Wallet (5)
    case add               // present the Add sheet
    case settings          // present the Settings sheet
    case statementImport   // present the Import sheet
    case subscriptions     // go to Home and present the Subscriptions sheet
}

public struct RootView: View {
    private let store: IngestionStore
    @State private var selectedTab: Int = 1            // Home dashboard is the orienting landing screen.
    @State private var showSettings = false
    @State private var showImport = false
    @State private var showAdd = false            // center FAB → Add sheet (QuickAdd)
    @State private var showSubscriptions = false  // Home "Upcoming" → Subscriptions management sheet
    @State private var showHistory = false        // History pushed within the Home tab — hides the tab bar
    @State private var showSpending = false       // Spending breakdown pushed from Home's compact card
    @State private var barHidden = false          // hide-on-scroll: the pill slides away while scrolling down Home
    @State private var importFile: ImportFile?            // a statement shared into the app (Share / Open in)
    @State private var reEntryPrompt: ReEntryPrompt?      // welcome-back soft-landing after a gap
    @State private var ritualSheet: RitualSheet?          // daily check-in (GOL-85), opt-in
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Owned here (not inline in the tab) so Home can be refreshed when the user returns to it or
    // finishes an import — otherwise newly added/imported expenses don't appear until a manual reload.
    @State private var recentModel: RecentExpensesModel
    @State private var subsModel: SubscriptionsModel
    @State private var quickAddModel: QuickAddModel
    @State private var sourcesModel: SourcesModel
    @State private var historyModel: HistoryModel   // the "See all" period browser, pushed from Home
    @State private var spendingModel: CategoryBreakdownModel   // the full breakdown, pushed from Home's Spending card
    public init(store: IngestionStore) {
        self.store = store
        let preferred = SharedSummary().readPreferredCurrency()
        _recentModel = State(initialValue: RecentExpensesModel(store: store, currency: preferred))
        _subsModel = State(initialValue: SubscriptionsModel(store: store))
        _quickAddModel = State(initialValue: QuickAddModel(store: store, currency: preferred))
        _sourcesModel = State(initialValue: SourcesModel(store: store, currency: preferred))
        _historyModel = State(initialValue: HistoryModel(reader: store, currency: preferred))
        _spendingModel = State(initialValue: CategoryBreakdownModel(store: store, currency: preferred))
    }

    /// Applies a legacy tab index (from deep links / widget / Siri `pendingTab`) under the
    /// 3-destination shell: real tabs select, the rest present their sheet. See `route(forTab:)`.
    private func route(toTab tab: Int) {
        switch Self.route(forTab: tab) {
        case .tab(let t):       selectedTab = t
        case .add:              showAdd = true
        case .settings:         showSettings = true
        case .statementImport:  showImport = true
        case .subscriptions:    selectedTab = 1; showSubscriptions = true
        }
    }

    private func applyPendingTab() {
        let summary = SharedSummary()
        if let tab = summary.readPendingTab() {
            route(toTab: tab)
            summary.setPendingTab(nil)
        }
    }

    /// Show the soft-landing if we've been away long enough. Called from the cold-launch `.task` AND
    /// `.onChange(scenePhase) == .active` (the former is needed because onChange misses the initial
    /// cold-launch `.active`). Re-runs are safe two ways: the `reEntryPrompt == nil` guard blocks any
    /// re-present, and the unconditional `setLastSeen()` reset (load-bearing — don't remove) makes any
    /// later same-session `.active` a 0-day no-op and also seeds the baseline on first-ever launch.
    private func checkReEntry() {
        let summary = SharedSummary()
        let lastSeen = summary.readLastSeen()
        if reEntryPrompt == nil, ReEntryPolicy.shouldShow(lastSeen: lastSeen),
           let days = ReEntryPolicy.daysAway(lastSeen: lastSeen) {
            reEntryPrompt = ReEntryPrompt(days: days)
            // Re-entry takes precedence: drop any ritual sheet left open across the background gap so
            // the .fullScreenCover never stacks on a leftover .sheet (which would wedge the modal stack).
            ritualSheet = nil
        }
        summary.setLastSeen()
    }

    /// Present the daily check-in sheet if one is due. Re-entry takes precedence (if its soft-landing
    /// is showing this activation, skip the ritual). Opt-in gated. Called right after `checkReEntry()`
    /// in both the cold-launch `.task` and `.onChange(scenePhase) == .active`. The `ritualSheet == nil`
    /// guard + the once-per-day intention/reflected dates make re-presenting within a day impossible.
    private func checkRitual() {
        guard reEntryPrompt == nil, ritualSheet == nil else { return }
        let summary = SharedSummary()
        guard summary.ritualEnabled() else { return }
        let prompt = RitualPolicy.prompt(now: .now,
                                         intentionDate: summary.readIntentionDate(),
                                         reflectedDate: summary.readReflectedDate(),
                                         skippedDate: summary.readMorningSkippedDate())
        if prompt != .none { ritualSheet = RitualSheet(kind: prompt) }
    }

    /// Evaluate this month's capped categories and fire a notification for any that NEWLY escalated.
    /// This is the ONLY place `evaluateBudgetAlerts` is called — it consumes the notify-once
    /// token (mutates + persists), unlike the read-only `categoryBreakdown` the Spending card/screen
    /// use. Safe to call from both cold launch and every foreground: the dedupe means a second call
    /// before the month/level changes again just returns `[]`, so no duplicate notification.
    private func checkOverspend() {
        Task {
            let rates = ExchangeRateCache().load() ?? SeedRates.table
            let alerts = (try? await store.evaluateBudgetAlerts(asOf: .now,
                                                                 displayCurrency: recentModel.currency,
                                                                 rates: rates)) ?? []
            if !alerts.isEmpty { await OverspendNotifications.fire(alerts) }
        }
    }

    // MARK: — Custom bottom bar (matches chrome.jsx TabBar exactly)

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 5:
            SourcesView(model: sourcesModel)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }   // clear the tab bar + FAB
        default:
            RecentExpensesView(
                model: recentModel,
                historyModel: historyModel,
                showHistory: $showHistory,
                spendingModel: spendingModel,
                showSpending: $showSpending,
                barHidden: $barHidden,
                onOpenImport: { showImport = true },
                onOpenSettings: { showSettings = true },
                onOpenSubscriptions: { showSubscriptions = true },
                onChangeCurrency: { code in
                    SharedSummary().setPreferredCurrency(code)
                    quickAddModel.currency = code
                    recentModel.currency = code
                    sourcesModel.currency = code   // keep the Wallet tab on the just-chosen display currency
                    historyModel.currency = code   // and the History browser on next open
                    spendingModel.currency = code  // and the Spending breakdown on next open
                    Task { await recentModel.load() }
                    // Re-render the widget's cached today-total string in the new currency (it stores a
                    // pre-formatted, currency-bearing string), else the lock screen keeps the old one.
                    Task { try? await store.refreshSharedSummaries() }
                }
            )
            // Bottom clearance now lives on the Recent list itself (so pushed History doesn't inherit it).
        }
    }

    private func tabButton(_ icon: String, label: String, tab: Int) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: selectedTab == tab ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selectedTab == tab ? GoldengoTheme.accent : GoldengoTheme.inkMuted)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A detached, floating glass "pill": margins on the sides, a gap above the home indicator, and a
    /// soft shadow so it reads as a light control hovering over the content rather than a wall welded
    /// to the bottom. Home / + / Wallet split the pill into even thirds.
    private var goldengoTabBar: some View {
        HStack(spacing: 0) {
            tabButton("house", label: "Home", tab: 1)
            AddFAB { showAdd = true }
                .padding(.horizontal, 4)
            tabButton("wallet.bifold", label: "Wallet", tab: 5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background {
            let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.goldengoBackground.opacity(0.10)))   // warm the glass to the canvas
                .overlay(shape.strokeBorder(GoldengoTheme.hairline.opacity(0.5), lineWidth: 0.5))
                .shadow(color: Color(red: 0, green: 0, blue: 0).opacity(0.28), radius: 16, y: 7)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)   // detach from the screen edges
        .padding(.bottom, 4)                              // float just above the home indicator
        .animation(GoldengoMotion.quick, value: selectedTab)   // ease the gold tint between Home/Wallet
    }

    @ViewBuilder
    public var body: some View {
        ZStack(alignment: .bottom) {
            contentView
            // Hidden while History or Spending is pushed inside the Home tab — the custom bar is a
            // ZStack sibling (not a real tab bar), so it would otherwise float over the pushed screen
            // with live, misleading Home/Wallet/Add controls.
            if !showHistory && !showSpending {
                goldengoTabBar
                    .offset(y: barHidden ? 120 : 0)                       // hide-on-scroll: slide the pill off the bottom
                    .scaleEffect(barHidden ? 0.94 : 1, anchor: .bottom)   // a gentle shrink (GPU-cheap; not blur)
                    .opacity(barHidden ? 0 : 1)
                    .animation(reduceMotion ? nil : GoldengoMotion.standard, value: barHidden)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: showHistory)
        .animation(.snappy, value: showSpending)
        .sheet(isPresented: $showAdd, onDismiss: {
            // A logged expense should appear on Home without a manual refresh.
            Task { await recentModel.load() }
        }) {
            QuickAddView(model: quickAddModel)   // QuickAddView loads its own "Paid from" balances on .task (GOL-90)
        }
        .sheet(isPresented: $showSubscriptions, onDismiss: {
            // Confirming/dismissing a subscription can change Home's "Upcoming" section.
            Task { await recentModel.load() }
        }) {
            SubscriptionsView(model: subsModel)
                .task { await subsModel.load() }   // load on present; also re-syncs reminders (was tab 4 entry)
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            // Adopt a changed preferred currency: update the new-expense default + dashboard display
            // currency, and reload Home only when it actually changed.
            let preferred = SharedSummary().readPreferredCurrency()
            let changed = recentModel.currency != preferred
            quickAddModel.currency = preferred
            recentModel.currency = preferred
            sourcesModel.currency = preferred
            historyModel.currency = preferred
            spendingModel.currency = preferred
            if changed {
                Task { await recentModel.load() }
                Task { await sourcesModel.load() }
                // Re-publish the widget today-total in the new currency (the cached string is
                // currency-bearing; without this the lock screen keeps the old currency/symbol).
                Task { try? await store.refreshSharedSummaries() }
            }
        }) { SettingsView() }
        .sheet(isPresented: $showImport, onDismiss: {
            // A statement import adds expenses AND may form new recurring patterns — refresh both.
            Task { await recentModel.load() }
            Task { await subsModel.load() }
        }) {
            ImportView(model: ImportModel(store: store))
        }
        .sheet(item: $importFile, onDismiss: {
            // Same post-import refresh as the picker path (new expenses + possible new recurring patterns).
            Task { await recentModel.load() }
            Task { await subsModel.load() }
        }) { file in
            ImportView(model: ImportModel(store: store), autoImport: file.url)
        }
#if os(iOS)
        .fullScreenCover(item: $reEntryPrompt) { prompt in
            ReEntryView(daysAway: prompt.days) { reEntryPrompt = nil }
        }
#endif
        .sheet(item: $ritualSheet) { s in
            if s.kind == .morning {
                MorningView(onDone: { ritualSheet = nil })
            } else {
                EveningView(model: EveningModel(store: store,
                                                currency: SharedSummary().readPreferredCurrency()),
                            onDone: { ritualSheet = nil })
            }
        }
        .onAppear { applyPendingTab() }
        .task {
            checkReEntry()            // cold-launch re-entry check (onChange(scenePhase) misses the initial .active)
            checkRitual()             // then the daily check-in (Re-entry takes precedence)
            await recentModel.load()  // Home is the landing tab
            await subsModel.load()    // re-sync subscription reminders on cold launch (was tab-4 entry)
            checkOverspend()          // evaluate + fire any newly-escalated budget alerts
            // Recompose the widget summaries so an update/install (or any pre-fix edit) never
            // leaves the lock screen asserting a stale or missing pocket claim (GOL-98 review).
            try? await store.refreshSharedSummaries()
        }
        .onChange(of: selectedTab) { _, newTab in
            barHidden = false   // always reveal the pill when changing tabs
            // Reload the destination tab's data on entry so adds/imports show without a manual refresh.
            if newTab == 1 { Task { await recentModel.load() } }
            if newTab == 5 { Task { await sourcesModel.load() } }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                checkReEntry()
                checkRitual()
                applyPendingTab()
                // An expense may have been logged via the Quick-Log shortcut while we were
                // backgrounded; reload so it appears on Home without a manual pull-to-refresh.
                Task { await recentModel.load() }
                // Keep subscription reminders fresh on long-uptime foregrounds (was the tab-4 trigger).
                Task { await subsModel.load() }
                checkOverspend()   // re-evaluate on every foreground; the store's dedupe stops repeats
            case .background:
                SharedSummary().setLastSeen()
            default:
                break
            }
        }
        .onOpenURL { url in
            if Self.isStatementFile(url) {
                importFile = ImportFile(url: url)            // Share-to-Goldengo: import the shared file
            } else if url.host == "wallet" {
                sourcesModel.pendingWalletAdjust = true   // GOL-98: land on Adjust (in-memory one-shot)
                route(toTab: 5)
            } else if let tab = Self.tab(forDeepLink: url) {
                route(toTab: tab)
            }
        }
    }

    /// A shared statement arrives as a `file://` URL (vs a `goldengo://` deep link). Extracted so
    /// the routing branch is unit-testable and can't silently regress.
    public nonisolated static func isStatementFile(_ url: URL) -> Bool { url.isFileURL }

    /// Maps a legacy tab index to a `RootRoute`. Extracted (like `tab(forDeepLink:)`) so the
    /// IA can't silently regress. 0→Add sheet, 1→Home, 2→Settings, 3→Import, 4→Subscriptions, 5→Wallet.
    public nonisolated static func route(forTab tab: Int) -> RootRoute {
        switch tab {
        case 0: return .add
        case 2: return .settings
        case 3: return .statementImport
        case 4: return .subscriptions
        default: return .tab(tab)   // 1 = Home, 5 = Wallet
        }
    }

    /// Maps a `goldengo://` deep link to a tab index (extracted so routing is unit-testable
    /// and can't silently regress). `quickadd` -> Add (0), `recent`/`home` -> Home (1),
    /// `settings` -> Settings sheet (2), `import` -> Import sheet (3), `subscriptions` -> Subs (4).
    public nonisolated static func tab(forDeepLink url: URL) -> Int? {
        guard url.scheme == "goldengo" else { return nil }
        switch url.host {
        case "quickadd": return 0
        case "recent":   return 1
        case "home":     return 1
        case "settings":      return 2
        case "import":        return 3
        case "subscriptions": return 4
        default:              return nil
        }
    }
}
