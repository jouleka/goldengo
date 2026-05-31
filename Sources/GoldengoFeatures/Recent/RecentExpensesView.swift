import SwiftUI
import GoldengoCore
import GoldengoDesignSystem

public struct RecentExpensesView: View {
    @State private var model: RecentExpensesModel
    public init(model: RecentExpensesModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
                Section("Today") { Text(model.todayTotalText).font(.title2.bold()) }
                Section("Recent") {
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
            .navigationTitle("Goldengo")
            .task { await model.load() }
        }
    }
}
