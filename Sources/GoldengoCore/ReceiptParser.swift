import Foundation
import CoreGraphics

/// One OCR text line with its normalized position (origin bottom-left, so larger y = higher up).
public struct RecognizedLine: Sendable, Equatable {
    public let text: String
    public let boundingBox: CGRect
    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Best-effort fields pulled from a receipt. Any field may be nil — the user confirms before saving.
public struct ParsedReceipt: Sendable, Equatable {
    public let amount: Decimal?
    public let merchant: String?
    public let date: Date?
    public init(amount: Decimal?, merchant: String?, date: Date?) {
        self.amount = amount; self.merchant = merchant; self.date = date
    }
}

/// Pure heuristic parser: OCR lines → (amount, merchant, date). Deterministic and unit-tested;
/// every result is a *suggestion* the user reviews.
public enum ReceiptParser {
    public static func parse(_ lines: [RecognizedLine], currency: CurrencyCode) -> ParsedReceipt {
        ParsedReceipt(amount: extractAmount(lines, currency: currency),
                      merchant: extractMerchant(lines),
                      date: extractDate(lines))
    }

    // MARK: Amount

    /// Word-boundary so "Subtotal"/"Nëntotal" are NOT mistaken for "Total". Longer keyword first.
    private static let totalKeywordRegex = try? NSRegularExpression(
        pattern: #"\b(TOTALI|TOTAL|AMOUNT DUE|SHUMA|VLERA)\b"#, options: [.caseInsensitive])

    static func extractAmount(_ lines: [RecognizedLine], currency: CurrencyCode) -> Decimal? {
        let digits = currency.fractionDigits
        // 1) Total-keyword lines; among them the bottom-most (the final total sits near the bottom).
        let keywordLines = lines
            .filter { hasTotalKeyword($0.text) && !amounts(in: $0.text, digits: digits).isEmpty }
            .sorted { $0.boundingBox.midY < $1.boundingBox.midY }
        if let best = keywordLines.first {
            return amounts(in: best.text, digits: digits).max()
        }
        // 2) Fallback: the largest amount in the lower half of the receipt.
        let lowerHalf = lines.filter { $0.boundingBox.midY < 0.5 }
        return lowerHalf.flatMap { amounts(in: $0.text, digits: digits) }.max()
    }

    static func hasTotalKeyword(_ text: String) -> Bool {
        guard let re = totalKeywordRegex else { return false }
        return re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Every parseable money amount in a string. Currency symbols/letters are ignored; tokens that
    /// are clearly NOT prices are rejected so they can't win the `.max()` fallback:
    ///  - date-shaped tokens (e.g. "30.05.2025" would collapse to 30052025), and
    ///  - over-long digit runs (tax ids / phone numbers / codes — a receipt total isn't 8+ digits).
    static func amounts(in text: String, digits: Int) -> [Decimal] {
        guard let re = try? NSRegularExpression(pattern: #"\d[\d.,]*\d|\d"#) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m -> Decimal? in
            let token = ns.substring(with: m.range)
            if dateString(in: token) != nil { return nil }
            if token.filter(\.isNumber).count > 7 { return nil }
            return parseAmount(token, fractionDigits: digits)
        }
    }

    /// Parse one numeric token to Decimal, resolving `,`/`.` as decimal vs. thousands separators.
    static func parseAmount(_ raw: String, fractionDigits: Int) -> Decimal? {
        let filtered = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard filtered.contains(where: \.isNumber) else { return nil }
        if fractionDigits == 0 {
            return Decimal(string: String(filtered.filter(\.isNumber)))
        }
        if let lastSep = filtered.lastIndex(where: { $0 == "." || $0 == "," }) {
            let after = filtered[filtered.index(after: lastSep)...].filter(\.isNumber)
            if after.count >= 1 && after.count <= fractionDigits {
                let intPart = filtered[..<lastSep].filter(\.isNumber)
                return Decimal(string: "\(intPart).\(after)")
            }
        }
        return Decimal(string: String(filtered.filter(\.isNumber)))   // all separators are grouping
    }

    // MARK: Merchant

    static func extractMerchant(_ lines: [RecognizedLine]) -> String? {
        let topFirst = lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        for line in topFirst {
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2 else { continue }
            if isMostlyNumeric(t) { continue }
            if dateString(in: t) != nil { continue }
            return t
        }
        return nil
    }

    private static func isMostlyNumeric(_ s: String) -> Bool {
        s.filter(\.isNumber).count > s.filter(\.isLetter).count
    }

    // MARK: Date

    private static let dateFormats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy"]

    static func extractDate(_ lines: [RecognizedLine], now: Date = .now) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        let twoYearsAgo = cal.date(byAdding: .year, value: -2, to: now) ?? now
        for line in lines {
            guard let token = dateString(in: line.text) else { continue }
            for fmt in dateFormats {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(identifier: "UTC")
                df.dateFormat = fmt
                if let d = df.date(from: token), d <= now, d >= twoYearsAgo { return d }
            }
        }
        return nil
    }

    /// The first date-shaped substring in a line, or nil.
    static func dateString(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\d{1,4}[./-]\d{1,2}[./-]\d{1,4}"#) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
}
