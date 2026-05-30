import SwiftUI
import GoldengoData

public struct RootView: View {
    private let store: IngestionStore
    public init(store: IngestionStore) { self.store = store }

    public var body: some View {
        TabView {
            QuickAddView(model: QuickAddModel(store: store))
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
            RecentExpensesView(model: RecentExpensesModel(store: store))
                .tabItem { Label("Recent", systemImage: "list.bullet") }
        }
    }
}
