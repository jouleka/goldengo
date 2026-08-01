import Foundation

/// The economic purpose of money leaving the user's accounts. Investments still drain a wallet,
/// but they build an asset and therefore must not be presented as ordinary consumption.
public enum MoneyPurpose: String, Sendable, Codable, CaseIterable, Hashable {
    case essential
    case lifestyle
    case wealth
    case waste
    case other

    public var title: String {
        switch self {
        case .essential: return "Essentials"
        case .lifestyle: return "Lifestyle"
        case .wealth: return "Investing"
        case .waste: return "Waste & risk"
        case .other: return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .essential: return "house.fill"
        case .lifestyle: return "sparkles"
        case .wealth: return "chart.line.uptrend.xyaxis"
        case .waste: return "exclamationmark.triangle.fill"
        case .other: return "square.grid.2x2"
        }
    }

    public var colorHex: String {
        switch self {
        case .essential: return "#3F7D78"
        case .lifestyle: return "#9A6AA2"
        case .wealth: return "#3F7C58"
        case .waste: return "#B75D4A"
        case .other: return "#7D7468"
        }
    }
}

public struct SpendingSubcategory: Sendable, Hashable, Identifiable {
    public let name: String
    public let purpose: MoneyPurpose
    public let aliases: [String]
    public var id: String { name }

    public init(_ name: String, purpose: MoneyPurpose, aliases: [String] = []) {
        self.name = name
        self.purpose = purpose
        self.aliases = aliases
    }
}

public struct SpendingCategoryGroup: Sendable, Hashable, Identifiable {
    public let name: String
    public let icon: String
    public let colorHex: String
    public let defaultPurpose: MoneyPurpose
    public let subcategories: [SpendingSubcategory]
    public var id: String { name }

    public init(name: String, icon: String, colorHex: String, defaultPurpose: MoneyPurpose,
                subcategories: [SpendingSubcategory]) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.defaultPurpose = defaultPurpose
        self.subcategories = subcategories
    }
}

public struct SpendingCategoryClassification: Sendable, Hashable {
    public let groupName: String
    public let subcategoryName: String?
    public let purpose: MoneyPurpose
    public let icon: String
    public let colorHex: String
    public let isKnown: Bool

    public init(groupName: String, subcategoryName: String?, purpose: MoneyPurpose,
                icon: String, colorHex: String, isKnown: Bool) {
        self.groupName = groupName
        self.subcategoryName = subcategoryName
        self.purpose = purpose
        self.icon = icon
        self.colorHex = colorHex
        self.isKnown = isKnown
    }
}

/// One canonical taxonomy used by logging, editing, receipt review, and spending analysis.
/// Existing free-text categories remain valid: known aliases are classified into a parent and a
/// purpose, while unknown names receive a stable custom color instead of collapsing into one blue.
public enum SpendingCategoryCatalog {
    public static let groups: [SpendingCategoryGroup] = [
        SpendingCategoryGroup(
            name: "Housing", icon: "house.fill", colorHex: "#B86F52", defaultPurpose: .essential,
            subcategories: [
                .init("Rent & mortgage", purpose: .essential, aliases: ["rent", "mortgage", "rent house"]),
                .init("Utilities", purpose: .essential, aliases: ["utility", "electricity", "water", "gas"]),
                .init("Home maintenance", purpose: .essential, aliases: ["home repair", "house repair"]),
                .init("Household", purpose: .essential, aliases: ["house", "home", "house stuff", "furniture", "furnishings"]),
            ]),
        SpendingCategoryGroup(
            name: "Food & drink", icon: "fork.knife", colorHex: "#D18B36", defaultPurpose: .essential,
            subcategories: [
                .init("Groceries", purpose: .essential, aliases: ["grocery", "supermarket"]),
                .init("Dining out", purpose: .lifestyle, aliases: ["food", "restaurant", "takeaway", "delivery"]),
                .init("Coffee", purpose: .lifestyle, aliases: ["cafe", "café"]),
            ]),
        SpendingCategoryGroup(
            name: "Transport", icon: "car.fill", colorHex: "#4D78A8", defaultPurpose: .essential,
            subcategories: [
                .init("Fuel", purpose: .essential, aliases: ["petrol", "gasoline"]),
                .init("Public transport", purpose: .essential, aliases: ["bus", "train", "metro"]),
                .init("Taxi & rideshare", purpose: .lifestyle, aliases: ["taxi", "uber", "rideshare"]),
                .init("Car maintenance", purpose: .essential, aliases: ["car repair", "vehicle maintenance", "mechanic"]),
                .init("Parking", purpose: .essential, aliases: ["parking fee"]),
            ]),
        SpendingCategoryGroup(
            name: "Health", icon: "cross.case.fill", colorHex: "#3E8C88", defaultPurpose: .essential,
            subcategories: [
                .init("Healthcare", purpose: .essential, aliases: ["doctor", "medical", "dentist"]),
                .init("Pharmacy", purpose: .essential, aliases: ["medicine", "medication"]),
                .init("Fitness", purpose: .lifestyle, aliases: ["gym", "sport"]),
            ]),
        SpendingCategoryGroup(
            name: "Bills", icon: "doc.text.fill", colorHex: "#6D7296", defaultPurpose: .essential,
            subcategories: [
                .init("Phone & internet", purpose: .essential, aliases: ["phone", "internet", "mobile"]),
                .init("Insurance", purpose: .essential),
                .init("Subscriptions", purpose: .lifestyle, aliases: ["subscription"]),
                .init("Taxes & fees", purpose: .essential, aliases: ["tax", "bank fee", "fees"]),
            ]),
        SpendingCategoryGroup(
            name: "Family & growth", icon: "person.2.fill", colorHex: "#8B6F9F", defaultPurpose: .essential,
            subcategories: [
                .init("Education", purpose: .essential, aliases: ["school", "course", "books"]),
                .init("Childcare", purpose: .essential, aliases: ["children", "kids"]),
                .init("Pets", purpose: .essential, aliases: ["pet", "vet"]),
                .init("Gifts", purpose: .lifestyle, aliases: ["gift"]),
                .init("Personal care", purpose: .lifestyle, aliases: ["haircut", "beauty"]),
            ]),
        SpendingCategoryGroup(
            name: "Lifestyle", icon: "sparkles", colorHex: "#A2608D", defaultPurpose: .lifestyle,
            subcategories: [
                .init("Entertainment", purpose: .lifestyle, aliases: ["cinema", "games", "gaming"]),
                .init("Shopping", purpose: .lifestyle, aliases: ["clothes", "clothing"]),
                .init("Travel", purpose: .lifestyle, aliases: ["holiday", "vacation", "hotel"]),
                .init("Hobbies", purpose: .lifestyle, aliases: ["hobby", "tools"]),
            ]),
        SpendingCategoryGroup(
            name: "Investments", icon: "chart.line.uptrend.xyaxis", colorHex: "#3E8060", defaultPurpose: .wealth,
            subcategories: [
                .init("General investing", purpose: .wealth, aliases: ["investment", "investments", "investing"]),
                .init("Savings", purpose: .wealth, aliases: ["saving", "savings deposit"]),
                .init("Stocks & funds", purpose: .wealth, aliases: ["stock", "stocks", "etf", "fund", "funds"]),
                .init("Crypto", purpose: .wealth, aliases: ["bitcoin", "cryptocurrency"]),
                .init("Retirement", purpose: .wealth, aliases: ["pension"]),
                .init("Business investment", purpose: .wealth, aliases: ["business investing"]),
            ]),
        SpendingCategoryGroup(
            name: "Waste & risk", icon: "exclamationmark.triangle.fill", colorHex: "#B65746", defaultPurpose: .waste,
            subcategories: [
                .init("Gambling", purpose: .waste, aliases: ["bet", "betting", "casino", "lottery"]),
                .init("Tobacco & vape", purpose: .waste, aliases: ["cigarette", "cigarettes", "tobacco", "vape", "vaping"]),
                .init("Impulse spending", purpose: .waste, aliases: ["impulse", "impulse purchase"]),
                .init("Fines & penalties", purpose: .waste, aliases: ["fine", "penalty"]),
                .init("General waste", purpose: .waste, aliases: ["waste", "money wasting", "wasted money"]),
            ]),
        SpendingCategoryGroup(
            name: "Other", icon: "square.grid.2x2", colorHex: "#81786C", defaultPurpose: .other,
            subcategories: [.init("Other", purpose: .other, aliases: ["uncategorized", "unknown"])]),
    ]

    /// A balanced first row for fast logging. The full hierarchy remains available through the
    /// category browser in every entry/edit flow.
    public static let quickChoices = [
        "Groceries", "Dining out", "Rent & mortgage", "Utilities", "Fuel",
        "Car maintenance", "Shopping", "General investing", "Gambling", "Other",
    ]

    public static func classify(_ rawName: String?) -> SpendingCategoryClassification {
        let displayName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = normalize(displayName)

        for group in groups {
            if normalize(group.name) == key {
                return SpendingCategoryClassification(groupName: group.name, subcategoryName: nil,
                                                       purpose: group.defaultPurpose, icon: group.icon,
                                                       colorHex: group.colorHex, isKnown: true)
            }
            for subcategory in group.subcategories {
                let candidates = [subcategory.name] + subcategory.aliases
                if candidates.contains(where: { normalize($0) == key }) {
                    return SpendingCategoryClassification(groupName: group.name,
                                                           subcategoryName: subcategory.name,
                                                           purpose: subcategory.purpose, icon: group.icon,
                                                           colorHex: group.colorHex, isKnown: true)
                }
            }
        }

        let fallbackName = displayName.isEmpty ? "Other" : "Custom"
        return SpendingCategoryClassification(groupName: fallbackName,
                                               subcategoryName: displayName.isEmpty ? "Other" : displayName,
                                               purpose: .other, icon: "tag.fill",
                                               colorHex: stableCustomColor(for: key), isKnown: false)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    private static func stableCustomColor(for value: String) -> String {
        let palette = ["#5F7895", "#7A6A9A", "#4F817A", "#9B704D", "#8A6573", "#657A4E"]
        let hash = value.utf8.reduce(UInt64(5_381)) { (($0 << 5) &+ $0) &+ UInt64($1) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
