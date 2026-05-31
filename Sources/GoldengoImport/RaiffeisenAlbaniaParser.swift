import Foundation
import GoldengoCore

/// Best-effort line parser for Raiffeisen Albania PDF statements.
/// PDFKit yields flat text (not clean columns), so this is approximate.
/// Tested against the synthetic fixture; real-world accuracy improves with more samples.
public struct RaiffeisenAlbaniaParser: BankStatementParser {
    public let id = "raiffeisen-al-pdf"
    public init() {}

    private static let skipPhrases = [
        "balanca", "numri i veprimeve", "limit overdraft", "ledger balance",
        "dispo balance", "nxjerrje llogarie", "data e transaksionit"
    ]
    private static let datePattern = #"\d{2}/\d{2}/\d{2}"#
    private static let numPattern  = #"-?[\d,]+\.\d{2}"#

    // A transaction line: <txnDate> <description...> <valueDate> <amount> <balance>
    // Using a lazy (.+?) to capture the description between two dates.
    private static let lineRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(\d{2}/\d{2}/\d{2})\s+(.+?)\s+(\d{2}/\d{2}/\d{2})\s+(-?[\d,]+\.\d{2})\s+(-?[\d,]+\.\d{2})$"#
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

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // Skip summary / header rows
            if Self.skipPhrases.contains(where: { line.lowercased().contains($0) }) { continue }

            let range = NSRange(line.startIndex..., in: line)
            guard let m = re.firstMatch(in: line, range: range),
                  let dateRange = Range(m.range(at: 1), in: line),
                  let descRange = Range(m.range(at: 2), in: line),
                  let amtRange  = Range(m.range(at: 4), in: line)
            else { continue }

            guard let date = df.date(from: String(line[dateRange])),
                  let amt  = Self.decimal(String(line[amtRange]))
            else { continue }

            let kind: TransactionKind = amt < 0 ? .expense : .income
            let merchant = String(line[descRange]).trimmingCharacters(in: .whitespaces)
            out.append(NormalizedTransaction(
                externalID: nil,
                amount: abs(amt),
                currency: currency,
                date: date,
                rawMerchant: merchant.isEmpty ? nil : merchant,
                kind: kind,
                accountRef: "statement"))
        }
        return out
    }

    private static func decimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ""))
    }
}
