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
        }
        .onOpenURL { url in
            if url.scheme == "goldengo", url.host == "quickadd" {
                selectedTab = 0
            }
        }
    }
}
