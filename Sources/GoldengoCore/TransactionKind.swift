public enum TransactionKind: String, Sendable, Codable, CaseIterable {
    case expense
    case income
    case transfer
    /// Money handed to a person — left the pocket/source for real, but it's a CLAIM, not
    /// spending. Every consumer opts in explicitly: wallet/allocator drain it like a cash
    /// spend; spend totals and the subscription detector exclude it (they filter .expense).
    case lent
    /// A lent claim coming home (v1: cash back into the wallet). Not income earned.
    case repayment
}
