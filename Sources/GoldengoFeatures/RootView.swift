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

public struct RootView: View {
    private let store: IngestionStore
    @State private var selectedTab: Int = 1            // Home dashboard is the orienting landing screen.
    @State private var showSettings = false
    @State private var showImport = false
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

    /// Settings (2) and Import (3) live behind the Home toolbar as sheets rather than permanent
    /// tabs, so deep links / widget / Siri targeting them open the matching sheet instead of a tab.
    private func route(toTab tab: Int) {
        switch tab {
        case 2: showSettings = true
        case 3: showImport = true
        default: selectedTab = tab
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
        if reEntryPrompt == nil,
           let days = ReEntryPolicy.daysAway(lastSeen: summary.readLastSeen()),
           days >= ReEntryPolicy.thresholdDays {
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

    public var body: some View {
        TabView(selection: $selectedTab) {
            QuickAddView(model: quickAddModel)
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(0)
            RecentExpensesView(
                model: recentModel,
                onAdd: { selectedTab = 0 },
                onOpenImport: { showImport = true },
                onOpenSettings: { showSettings = true },
                onOpenSubscriptions: { selectedTab = 4 },
                onChangeCurrency: { code in
                    SharedSummary().setPreferredCurrency(code)
                    quickAddModel.currency = code
                    recentModel.currency = code
                    Task { await recentModel.load() }
                }
            )
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(1)
            SubscriptionsView(model: subsModel)
                .tabItem { Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath") }
                .tag(4)
            SourcesView(model: sourcesModel)
                .tabItem { Label("Sources", systemImage: "circle.grid.2x2") }
                .tag(5)
        }
        .tint(GoldengoTheme.accent)
        .sheet(isPresented: $showSettings, onDismiss: {
            // Adopt a changed preferred currency: update the new-expense default + dashboard display
            // currency, and reload Home only when it actually changed.
            let preferred = SharedSummary().readPreferredCurrency()
            let changed = recentModel.currency != preferred
            quickAddModel.currency = preferred
            recentModel.currency = preferred
            sourcesModel.currency = preferred
            if changed { Task { await recentModel.load() }; Task { await sourcesModel.load() } }
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
        }
        .onChange(of: selectedTab) { _, newTab in
            // Reload the destination tab's data on entry so adds/imports show without a manual refresh.
            if newTab == 0 { Task { await quickAddModel.loadSources() } }   // fresh "Paid from" balances (GOL-90)
            if newTab == 1 { Task { await recentModel.load() } }
            if newTab == 4 { Task { await subsModel.load() } }
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
            case .background:
                SharedSummary().setLastSeen()
            default:
                break
            }
        }
        .onOpenURL { url in
            if Self.isStatementFile(url) {
                importFile = ImportFile(url: url)            // Share-to-Goldengo: import the shared file
            } else if let tab = Self.tab(forDeepLink: url) {
                route(toTab: tab)
            }
        }
    }

    /// A shared statement arrives as a `file://` URL (vs a `goldengo://` deep link). Extracted so
    /// the routing branch is unit-testable and can't silently regress.
    public nonisolated static func isStatementFile(_ url: URL) -> Bool { url.isFileURL }

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
