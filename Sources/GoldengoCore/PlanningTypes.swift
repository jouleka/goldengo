import Foundation

/// A transaction's category answers "what was bought"; context answers "for whom or why".
/// Context deliberately stays a separate dimension so categories never grow variants such as
/// "Business food", "Holiday food", and "Normal food".
public enum SpendingContextCatalog {
    public struct Option: Sendable, Hashable, Identifiable {
        public let name: String
        public let icon: String
        public let colorHex: String
        public var id: String { name }

        public init(name: String, icon: String, colorHex: String) {
            self.name = name; self.icon = icon; self.colorHex = colorHex
        }
    }

    public static let defaults: [Option] = [
        .init(name: "Personal", icon: "person.fill", colorHex: "#8B7FA8"),
        .init(name: "Business", icon: "briefcase.fill", colorHex: "#4D88C7"),
        .init(name: "Household", icon: "house.fill", colorHex: "#3E8F83"),
        .init(name: "Family", icon: "person.2.fill", colorHex: "#B46B7A"),
        .init(name: "Travel", icon: "airplane", colorHex: "#C99135"),
    ]

    public static func option(named name: String?) -> Option? {
        guard let name, !name.isEmpty else { return nil }
        if let known = defaults.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return known
        }
        return .init(name: name, icon: "tag.fill", colorHex: stableColor(for: name))
    }

    private static func stableColor(for text: String) -> String {
        let palette = ["#6677A8", "#3E8F83", "#A46191", "#C99135", "#B75D49", "#73825C"]
        let value = text.lowercased().unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(value) % palette.count]
    }
}

public struct TransactionSplit: Sendable, Hashable, Identifiable {
    public var id: String
    public var amount: Decimal
    public var categoryName: String

    public init(id: String = UUID().uuidString, amount: Decimal, categoryName: String) {
        self.id = id; self.amount = amount; self.categoryName = categoryName
    }
}

public enum PlanCadence: String, Sendable, CaseIterable, Codable, Identifiable {
    case once, weekly, monthly, yearly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .once: return "Once"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    public func advance(_ date: Date, by periods: Int = 1, calendar: Calendar = .current) -> Date {
        switch self {
        case .once: return date
        case .weekly: return calendar.date(byAdding: .day, value: periods * 7, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: periods, to: date) ?? date
        case .yearly: return calendar.date(byAdding: .year, value: periods, to: date) ?? date
        }
    }
}

/// How a spending period advances after its end date.
public enum SpendingPeriodCadence: String, Sendable, CaseIterable, Codable, Identifiable {
    case once, weekly, biweekly, monthly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .once: return "One period"
        case .weekly: return "Every week"
        case .biweekly: return "Every two weeks"
        case .monthly: return "Every month"
        }
    }

    public func advance(_ date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .once: return date
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}

/// Where the period's available-now number comes from.
public enum SpendingPeriodFundingMode: String, Sendable, CaseIterable, Codable, Identifiable {
    case liveBalances, fixedAmount
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .liveBalances: return "Wallet + sources"
        case .fixedAmount: return "A fixed amount"
        }
    }
}

public enum InvestmentEntryKind: String, Sendable, CaseIterable, Codable {
    case contribution, withdrawal, valuation
}

public enum ReviewIssueKind: String, Sendable, Hashable {
    case uncategorized, unusual, subscription
}

public enum UpcomingMoneyKind: String, Sendable, Hashable {
    case bill, subscription, income, goal
}

public enum PlanningValidationError: LocalizedError, Sendable {
    case invalidSplits
    public var errorDescription: String? {
        switch self {
        case .invalidSplits: return "Split amounts must be positive and add up to the transaction total."
        }
    }
}

public enum SpendingPeriodValidationError: LocalizedError, Sendable {
    case endBeforeStart, invalidStartingAmount
    public var errorDescription: String? {
        switch self {
        case .endBeforeStart: return "The period end must be on or after its start."
        case .invalidStartingAmount: return "Enter an amount greater than zero."
        }
    }
}
