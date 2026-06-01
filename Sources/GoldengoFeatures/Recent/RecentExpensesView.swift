import SwiftUI
import GoldengoCore
import GoldengoDesignSystem

public struct RecentExpensesView: View {
    @State private var model: RecentExpensesModel
    public init(model: RecentExpensesModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
                if model.loadFailed {
                    Section {
                        Label("Couldn't load your expenses. Pull to refresh.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Today") { Text(model.todayTotalText).font(.title2.bold()) }
                Section("Recent") {
                    if model.rows.isEmpty {
                        if #available(iOS 17.0, *) {
                            ContentUnavailableView(
                                "No expenses yet",
                                systemImage: "tray",
                                description: Text("Tap + to add your first.")
                            )
                        } else {
                            Text("No expenses yet — tap + to add your first.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(model.rows, id: \.dedupeKey) { r in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(r.merchantName ?? r.categoryName ?? "Expense")
                                    Text(r.categoryName ?? "Uncategorized").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if r.kind == .income {
                                    Text("+" + Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted())
                                        .foregroundStyle(.green)
                                } else {
                                    Text(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Goldengo")
            .refreshable { await model.load() }
            .onAppear { Task { await model.load() } }
        }
    }
}
