import SwiftUI
import GoldengoData
import GoldengoDesignSystem

public struct RootView: View {
    private let store: IngestionStore
    @State private var selectedTab: Int = 1            // Home dashboard is the orienting landing screen.
    @State private var showSettings = false
    @State private var showImport = false
    @Environment(\.scenePhase) private var scenePhase
    public init(store: IngestionStore) { self.store = store }

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
            QuickAddView(model: QuickAddModel(store: store))
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(0)
            RecentExpensesView(
                model: RecentExpensesModel(store: store),
                onAdd: { selectedTab = 0 },
                onOpenImport: { showImport = true },
                onOpenSettings: { showSettings = true },
                onOpenSubscriptions: { selectedTab = 4 }
            )
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(1)
            SubscriptionsView(model: SubscriptionsModel(store: store))
                .tabItem { Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath") }
                .tag(4)
        }
        .tint(GoldengoTheme.accent)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showImport) { ImportView(model: ImportModel(store: store)) }
        .onAppear { applyPendingTab() }
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
