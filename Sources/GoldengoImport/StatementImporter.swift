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
        return rows.compactMap { row in
            // Skip non-transaction rows (opening/closing balance, totals) — the PDF path already
            // does this; the CSV path silently didn't, so a summary row with a date + amount leaked
            // in as a phantom transaction that distorted totals.
            let joined = row.joined(separator: " ").lowercased()
            if mapping.skipRowKeywords.contains(where: { !$0.isEmpty && joined.contains($0) }) { return nil }
            return StatementRowMapper.map(row: row, using: mapping)
        }
    }

    public static func transactions(fromPDFText text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        guard let parser = PDFParserRegistry.parser(for: text) else { return [] }
        return parser.parse(text, currency: currency)
    }
}
