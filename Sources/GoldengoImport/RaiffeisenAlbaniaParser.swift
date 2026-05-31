import Foundation
import GoldengoCore

/// Best-effort line parser for Raiffeisen Albania PDF statements.
/// PDFKit yields flat text (not clean columns), so this is approximate. It handles two layouts:
/// the whole row on one line, AND the transaction date on its own line with the
/// description / value date / amount / balance on the next line (PDFKit often splits it that way).
/// Real-world accuracy improves with more samples.
public struct RaiffeisenAlbaniaParser: BankStatementParser {
    public let id = "raiffeisen-al-pdf"
    public init() {}

    // A transaction line: <txnDate> [description...] <valueDate> <amount> <balance>.
    // Description (group 2) is OPTIONAL — some rows carry it on a separate line.
    private static let lineRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(\d{2}/\d{2}/\d{2})\s+(?:(.+?)\s+)?(\d{2}/\d{2}/\d{2})\s+(-?[\d,]+\.\d{2})\s+(-?[\d,]+\.\d{2})$"#
    )
    private static let dateOnlyRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"^\d{2}/\d{2}/\d{2}$"#)

    public func canParse(_ text: String) -> Bool {
        let l = text.lowercased()
        return l.contains("nxjerrje llogarie") ||
               (l.contains("debi") && l.contains("kredi") && l.contains("pershkrimi"))
    }

    public func parse(_ text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        guard let re = Self.lineRegex else { return [] }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "dd/MM/yy"
        let skipKeywords = StatementProfile.raiffeisenAlbania.skipRowKeywords

        // Normalize each line: collapse whitespace runs, drop empties. Crucially this also
        // strips control/zero-width junk (PDFKit appends a NUL `U+0000` to lone date lines and
        // injects U+200B/U+FEFF into tokens); these survive `.whitespaces` trimming and would
        // otherwise break the date-only match below, silently dropping the row.
        let normalized = text.split(whereSeparator: \.isNewline)
            .map { Self.normalizeLine($0) }
            .filter { !$0.isEmpty }

        // PDFKit often emits the transaction date on its OWN line; merge a lone-date line with
        // the following line (which carries description / value date / amount / balance).
        var lines: [String] = []
        var i = 0
        while i < normalized.count {
            let line = normalized[i]
            if Self.isDateOnly(line), i + 1 < normalized.count {
                lines.append(line + " " + normalized[i + 1]); i += 2
            } else {
                lines.append(line); i += 1
            }
        }

        var out: [NormalizedTransaction] = []
        for line in lines {
            guard line.count <= 400 else { continue }   // ReDoS guard
            if skipKeywords.contains(where: { line.lowercased().contains($0) }) { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let m = re.firstMatch(in: line, range: range),
                  let dateRange = Range(m.range(at: 1), in: line),
                  let amtRange  = Range(m.range(at: 4), in: line)
            else { continue }
            guard let date = df.date(from: String(line[dateRange])),
                  let amt  = Self.decimal(String(line[amtRange]))
            else { continue }
            // Description (group 2) is optional — absent when it was on a separate line.
            let merchant = Range(m.range(at: 2), in: line)
                .map { String(line[$0]).trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let kind: TransactionKind = amt < 0 ? .expense : .income
            out.append(NormalizedTransaction(
                externalID: nil, amount: abs(amt), currency: currency, date: date,
                rawMerchant: merchant, kind: kind, accountRef: "statement"))
        }
        return out
    }

    /// Collapse all whitespace into single spaces and strip control/zero-width characters.
    /// A "separator" is any Unicode whitespace scalar, any C0/C1 control char (incl. NUL),
    /// or a zero-width space/BOM (U+200B / U+FEFF). Runs collapse; leading/trailing trimmed.
    private static func normalizeLine(_ line: Substring) -> String {
        let cleaned = String.UnicodeScalarView(line.unicodeScalars.map { scalar in
            let isSeparator = scalar.properties.isWhitespace
                || scalar.value < 0x20        // C0 controls (NUL, etc.)
                || (scalar.value >= 0x7F && scalar.value <= 0x9F)  // DEL + C1 controls
                || scalar.value == 0x200B     // zero-width space
                || scalar.value == 0xFEFF     // zero-width no-break space / BOM
            return isSeparator ? " " : scalar
        })
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    private static func isDateOnly(_ s: String) -> Bool {
        guard let re = dateOnlyRegex else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func decimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ""))
    }
}
