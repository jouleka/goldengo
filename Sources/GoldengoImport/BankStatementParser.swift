import Foundation
import GoldengoCore

/// Protocol implemented by each bank-specific PDF parser.
public protocol BankStatementParser: Sendable {
    var id: String { get }
    /// Returns true if this parser recognises the given extracted PDF text.
    func canParse(_ text: String) -> Bool
    /// Parses transactions from extracted PDF text.
    func parse(_ text: String, currency: CurrencyCode) -> [NormalizedTransaction]
}

/// Registry of all known PDF bank parsers. First match wins.
public enum PDFParserRegistry {
    public static let parsers: [any BankStatementParser] = [RaiffeisenAlbaniaParser()]
    public static func parser(for text: String) -> (any BankStatementParser)? {
        parsers.first { $0.canParse(text) }
    }
}
