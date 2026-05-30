import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class RecentExpensesModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var rows: [ExpenseSnapshot] = []
    public private(set) var todayTotalText: String = ""

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        rows = (try? await store.recentExpenses(limit: 50)) ?? []
        let total = (try? await store.todayTotal()) ?? 0
        todayTotalText = Money(amount: total, currency: currency).formatted()
    }
}
