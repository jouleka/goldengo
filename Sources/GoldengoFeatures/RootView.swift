import SwiftUI
import GoldengoData
import GoldengoDesignSystem
import GoldengoCore

public struct RootView: View {
    private let store: IngestionStore
    @State private var selectedTab: Int = 1            // Home dashboard is the orienting landing screen.
    @State private var showSettings = false
    @State private var showImport = false
    @Environment(\.scenePhase) private var scenePhase
    // Owned here (not inline in the tab) so Home can be refreshed when the user returns to it or
    // finishes an import — otherwise newly added/imported expenses don't appear until a manual reload.
    @State private var recentModel: RecentExpensesModel
    @State private var subsModel: SubscriptionsModel
    @State private var quickAddModel: QuickAddModel
    public init(store: IngestionStore) {
        self.store = store
        let preferred = SharedSummary().readPreferredCurrency()
        _recentModel = State(initialValue: RecentExpensesModel(store: store, currency: preferred))
        _subsModel = State(initialValue: SubscriptionsModel(store: store))
        _quickAddModel = State(initialValue: QuickAddModel(store: store, currency: preferred))
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
                onOpenSubscriptions: { selectedTab = 4 }
            )
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(1)
            SubscriptionsView(model: subsModel)
                .tabItem { Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath") }
                .tag(4)
        }
        .tint(GoldengoTheme.accent)
        .sheet(isPresented: $showSettings, onDismiss: {
            // Adopt a changed preferred currency: update the new-expense default + dashboard display
            // currency, and reload Home only when it actually changed.
            let preferred = SharedSummary().readPreferredCurrency()
            let changed = recentModel.currency != preferred
            quickAddModel.currency = preferred
            recentModel.currency = preferred
            if changed { Task { await recentModel.load() } }
        }) { SettingsView() }
        .sheet(isPresented: $showImport, onDismiss: {
            // A statement import adds expenses AND may form new recurring patterns — refresh both.
            Task { await recentModel.load() }
            Task { await subsModel.load() }
        }) {
            ImportView(model: ImportModel(store: store))
        }
        .onAppear { applyPendingTab() }
        .task { await recentModel.load() }   // cold-launch load (Home is the landing tab)
        .onChange(of: selectedTab) { _, newTab in
            // Reload the destination tab's data on entry so adds/imports show without a manual refresh.
            if newTab == 1 { Task { await recentModel.load() } }
            if newTab == 4 { Task { await subsModel.load() } }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { applyPendingTab() }
        }
        .onOpenURL { url in
            if let tab = Self.tab(forDeepLink: url) { route(toTab: tab) }
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
