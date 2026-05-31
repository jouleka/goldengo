import Foundation
import GoldengoCore

/// Orchestrates CSV and PDF statement imports.
/// CSV → StatementProfile.detectMapping → StatementRowMapper
/// PDF text → PDFParserRegistry → BankStatementParser
public enum StatementImporter {
    public static func transactions(fromCSV text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        var rows = CSVParser.parse(text)
        guard let header = rows.first,
              let mapping = StatementProfile.detectMapping(header: header, currency: currency)
        else { return [] }
        rows.removeFirst()
        return rows.compactMap { StatementRowMapper.map(row: $0, using: mapping) }
    }

    public static func transactions(fromPDFText text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        guard let parser = PDFParserRegistry.parser(for: text) else { return [] }
        return parser.parse(text, currency: currency)
    }
}
