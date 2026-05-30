public enum TransactionKind: String, Sendable, Codable, CaseIterable {
    case expense
    case income
    case transfer
}
