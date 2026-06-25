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
    @State private var importFile: ImportFile?            // a statement shared into the app (Share / Open in)
    @State private var reEntryPrompt: ReEntryPrompt?      // welcome-back soft-landing after a gap
    @State private var ritualSheet: RitualSheet?          // daily check-in (GOL-85), opt-in
    @Environment(\.scenePhase) private var scenePhase
    // Owned here (not inline in the tab) so Home can be refreshed when the user returns to it or
    // finishes an import — otherwise newly added/imported expenses don't appear until a manual reload.
    @State private var recentModel: RecentExpensesModel
    @State private var subsModel: SubscriptionsModel
    @State private var quickAddModel: QuickAddModel
    @State private var sourcesModel: SourcesModel
    public init(store: IngestionStore) {
        self.store = store
        let preferred = SharedSummary().readPreferredCurrency()
        _recentModel = State(initialValue: RecentExpensesModel(store: store, currency: preferred))
        _subsModel = State(initialValue: SubscriptionsModel(store: store))
        _quickAddModel = State(initialValue: QuickAddModel(store: store, currency: preferred))
        _sourcesModel = State(initialValue: SourcesModel(store: store, currency: preferred))
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

    // MARK: — Custom bottom bar (matches chrome.jsx TabBar exactly)

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 5:
            SourcesView(model: sourcesModel)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 86) }
        default:
            RecentExpensesView(
                model: recentModel,
                onOpenImport: { showImport = true },
                onOpenSettings: { showSettings = true },
                onOpenSubscriptions: { showSubscriptions = true },
                onChangeCurrency: { code in
                    SharedSummary().setPreferredCurrency(code)
                    quickAddModel.currency = code
                    recentModel.currency = code
                    sourcesModel.currency = code   // keep the Wallet tab on the just-chosen display currency
                    Task { await recentModel.load() }
                    // Re-render the widget's cached today-total string in the new currency (it stores a
                    // pre-formatted, currency-bearing string), else the lock screen keeps the old one.
                    Task { try? await store.refreshSharedSummaries() }
                }
            )
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 64) }
        }
    }

    private var goldengoTabBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Home tab button
            Button {
                selectedTab = 1
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "house")
                        .font(.system(size: 25, weight: selectedTab == 1 ? .semibold : .regular))
                    Text("Home")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(selectedTab == 1 ? GoldengoTheme.accent : GoldengoTheme.inkMuted)
                .frame(width: 84)
            }
            .buttonStyle(.plain)

            Spacer()

            // Center Add FAB — raised above the bar (marginTop: -22 → offset y: -18)
            AddFAB { showAdd = true }
                .offset(y: -18)

            Spacer()

            // Wallet tab button
            Button {
                selectedTab = 5
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 25, weight: selectedTab == 5 ? .semibold : .regular))
                    Text("Wallet")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(selectedTab == 5 ? GoldengoTheme.accent : GoldengoTheme.inkMuted)
                .frame(width: 84)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 34)
        .padding(.top, 12)
        .padding(.bottom, 24)
        // A bit translucent: a frosted blur (content softly blurs behind it) warmed with the canvas tint,
        // so the bar reads light/airy like the design yet the Home/Wallet labels stay legible.
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.goldengoBackground.opacity(0.32))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            contentView
            goldengoTabBar
        }
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
            // Recompose the widget summaries so an update/install (or any pre-fix edit) never
            // leaves the lock screen asserting a stale or missing pocket claim (GOL-98 review).
            try? await store.refreshSharedSummaries()
        }
        .onChange(of: selectedTab) { _, newTab in
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
