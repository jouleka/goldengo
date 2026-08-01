import Foundation
import SwiftData
import GoldengoCore

@Model
public final class ScheduledCommitmentRecord {
    public var id: String = ""
    public var name: String = ""
    public var amount: Decimal = 0
    public var currencyCode: String = "ALL"
    public var categoryName: String = "Bills"
    public var nextDueDate: Date = Date.now
    public var cadenceRaw: String = PlanCadence.monthly.rawValue
    public var kindRaw: String = UpcomingMoneyKind.bill.rawValue
    public var contextName: String?
    public var createdAt: Date = Date.now
    public var isArchived: Bool = false

    public init(id: String = UUID().uuidString, name: String = "", amount: Decimal = 0,
                currencyCode: String = "ALL", categoryName: String = "Bills",
                nextDueDate: Date = .now, cadence: PlanCadence = .monthly,
                contextName: String? = nil, kind: UpcomingMoneyKind = .bill) {
        self.id = id; self.name = name; self.amount = amount; self.currencyCode = currencyCode
        self.categoryName = categoryName; self.nextDueDate = nextDueDate
        self.cadenceRaw = cadence.rawValue; self.contextName = contextName
        self.kindRaw = kind.rawValue
    }

    public var cadence: PlanCadence { PlanCadence(rawValue: cadenceRaw) ?? .monthly }
    public var kind: UpcomingMoneyKind { UpcomingMoneyKind(rawValue: kindRaw) ?? .bill }
}
