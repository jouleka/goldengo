import SwiftUI
import GoldengoData

public struct RootView: View {
    private let store: IngestionStore
    @State private var selectedTab: Int = 0
    public init(store: IngestionStore) { self.store = store }

    public var body: some View {
        TabView(selection: $selectedTab) {
            QuickAddView(model: QuickAddModel(store: store))
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(0)
            RecentExpensesView(model: RecentExpensesModel(store: store))
                .tabItem { Label("Recent", systemImage: "list.bullet") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .onOpenURL { url in
            if let tab = Self.tab(forDeepLink: url) { selectedTab = tab }
        }
    }

    /// Maps a `goldengo://` deep link to a tab index (extracted so routing is unit-testable
    /// and can't silently regress). `quickadd` -> Add (0), `recent` -> Recent (1).
    public static func tab(forDeepLink url: URL) -> Int? {
        guard url.scheme == "goldengo" else { return nil }
        switch url.host {
        case "quickadd": return 0
        case "recent":   return 1
        case "settings": return 2
        default:         return nil
        }
    }
}
