public enum ExpenseSource: String, Sendable, Codable, CaseIterable {
    case manual
    case imported
    case crypto
    case automatic   // captured hands-free (e.g. the Apple Pay Transaction automation)
}
