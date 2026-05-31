import Foundation
import GoldengoCore

/// Best-effort line parser for Raiffeisen Albania PDF statements.
/// PDFKit yields flat text (not clean columns), so this is approximate.
/// Tested against the synthetic fixture; real-world accuracy improves with more samples.
public struct RaiffeisenAlbaniaParser: BankStatementParser {
    public let id = "raiffeisen-al-pdf"
    public init() {}

    private static let datePattern = #"\d{2}/\d{2}/\d{2}"#
    private static let numPattern  = #"-?[\d,]+\.\d{2}"#

    // A transaction line: <txnDate> [description...] <valueDate> <amount> <balance>.
    // The description (group 2) is OPTIONAL: real statements have rows — e.g. fixed-commission
    // debits ("Komision Fiks") and some credits — where the description sits on a separate line,
    // leaving just <txnDate> <valueDate> <amount> <balance>. Without the optional group those
    // rows were silently dropped.
    private static let lineRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(\d{2}/\d{2}/\d{2})\s+(?:(.+?)\s+)?(\d{2}/\d{2}/\d{2})\s+(-?[\d,]+\.\d{2})\s+(-?[\d,]+\.\d{2})$"#
    )

    public func canParse(_ text: String) -> Bool {
        let l = text.lowercased()
        return l.contains("nxjerrje llogarie") ||
               (l.contains("debi") && l.contains("kredi") && l.contains("pershkrimi"))
    }

    public func parse(_ text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        guard let re = Self.lineRegex else { return [] }
        var out: [NormalizedTransaction] = []
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "dd/MM/yy"

        let skipKeywords = StatementProfile.raiffeisenAlbania.skipRowKeywords
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Guard against absurdly long lines that cause regex backtracking
            guard trimmed.count <= 400 else { continue }
            // Collapse whitespace runs to single spaces to reduce backtracking
            let line = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            // Skip summary / header rows
            if skipKeywords.contains(where: { line.lowercased().contains($0) }) { continue }

            let range = NSRange(line.startIndex..., in: line)
            guard let m = re.firstMatch(in: line, range: range),
                  let dateRange = Range(m.range(at: 1), in: line),
                  let amtRange  = Range(m.range(at: 4), in: line)
            else { continue }

            guard let date = df.date(from: String(line[dateRange])),
                  let amt  = Self.decimal(String(line[amtRange]))
            else { continue }

            // Description (group 2) is optional — absent when it's on a separate line.
            let merchant = Range(m.range(at: 2), in: line)
                .map { String(line[$0]).trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }

            let kind: TransactionKind = amt < 0 ? .expense : .income
            out.append(NormalizedTransaction(
                externalID: nil,
                amount: abs(amt),
                currency: currency,
                date: date,
                rawMerchant: merchant,
                kind: kind,
                accountRef: "statement"))
        }
        return out
    }

    private static func decimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ""))
    }
}
