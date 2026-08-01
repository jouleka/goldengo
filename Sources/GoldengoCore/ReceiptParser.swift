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
    /// Best-effort purchasable rows. These stay suggestions: the review screen lets the user
    /// rename, recategorize, remove, or ignore them before any split reaches reporting.
    public let items: [ParsedReceiptItem]
    public init(amount: Decimal?, merchant: String?, date: Date?, items: [ParsedReceiptItem] = []) {
        self.amount = amount; self.merchant = merchant; self.date = date; self.items = items
    }
}

public struct ParsedReceiptItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let amount: Decimal

    public init(id: String = UUID().uuidString, name: String, amount: Decimal) {
        self.id = id; self.name = name; self.amount = amount
    }
}

/// Pure heuristic parser: OCR lines → (amount, merchant, date). Deterministic and unit-tested;
/// every result is a *suggestion* the user reviews.
public enum ReceiptParser {
    public static func parse(_ lines: [RecognizedLine], currency: CurrencyCode) -> ParsedReceipt {
        let total = extractAmount(lines, currency: currency)
        return ParsedReceipt(amount: total,
                             merchant: extractMerchant(lines),
                             date: extractDate(lines),
                             items: extractItems(lines, currency: currency, total: total))
    }

    // MARK: Line items

    /// Conservative trailing-price extraction for the common `ITEM NAME   1,250` receipt shape.
    /// It intentionally ignores totals, tax/payment rows, dates, codes, and lines without a useful
    /// text label. A partial result is still valuable: the review UI adds any unmatched remainder
    /// as one editable row rather than pretending OCR found the whole basket.
    static func extractItems(_ lines: [RecognizedLine], currency: CurrencyCode,
                             total: Decimal?) -> [ParsedReceiptItem] {
        let ignored = ["TOTAL", "TOTALI", "SUBTOTAL", "NENTOTAL", "NËNTOTAL", "TVSH", "TAX",
                       "VAT", "CASH", "CARD", "VISA", "MASTERCARD", "CHANGE", "BALANCE",
                       "SHUMA", "VLERA", "AMOUNT DUE", "THANK", "FALEMINDERIT"]
        let merchant = extractMerchant(lines)?.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                                        locale: .current).uppercased()
        var result: [ParsedReceiptItem] = []

        for line in lines.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            let raw = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                         locale: .current).uppercased()
            guard !raw.isEmpty, normalized != merchant, dateString(in: raw) == nil,
                  !ignored.contains(where: { normalized.contains($0) }) else { continue }
            guard let match = trailingAmountMatch(in: raw),
                  let amount = parseAmount(match.token, fractionDigits: currency.fractionDigits),
                  amount > 0 else { continue }
            let name = String(raw[..<match.range.lowerBound])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            guard name.count >= 2, name.contains(where: \.isLetter) else { continue }
            // A single line above the receipt total cannot exceed it; rejecting it removes most
            // phone/id/quantity artifacts without blocking partial baskets.
            if let total, amount > total { continue }
            result.append(ParsedReceiptItem(name: name, amount: amount))
        }
        return result
    }

    private static func trailingAmountMatch(in text: String) -> (token: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d[\d.,]*\d|\d)\s*(?:ALL|LEK|L|EUR|€|USD|\$)?\s*$"#,
                                                   options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text) else { return nil }
        return (String(text[tokenRange]), fullRange)
    }

    // MARK: Amount

    /// Word-boundary so "Subtotal"/"Nëntotal" are NOT mistaken for "Total". Longer keyword first.
    private static let totalKeywordRegex = try? NSRegularExpression(
        pattern: #"\b(TOTALI|TOTAL|AMOUNT DUE|SHUMA|VLERA)\b"#, options: [.caseInsensitive])

    /// A labeled total may legitimately be large (a 7-figure lek total), so the over-long-digit-run
    /// guard is relaxed on keyword lines; the unlabeled fallback keeps the tighter limit to reject
    /// footer ids/phone numbers. Both still block 11+ digit runs (barcodes/long codes).
    private static let keywordMaxDigitRun = 10
    private static let fallbackMaxDigitRun = 7

    static func extractAmount(_ lines: [RecognizedLine], currency: CurrencyCode) -> Decimal? {
        let digits = currency.fractionDigits
        // 1) Total-keyword lines; among them the bottom-most (the final total sits near the bottom).
        let keywordLines = lines
            .filter { hasTotalKeyword($0.text) && !amounts(in: $0.text, digits: digits, maxDigitRun: keywordMaxDigitRun).isEmpty }
            .sorted { $0.boundingBox.midY < $1.boundingBox.midY }
        if let best = keywordLines.first {
            return amounts(in: best.text, digits: digits, maxDigitRun: keywordMaxDigitRun).max()
        }
        // 2) Fallback: the largest amount in the lower half of the receipt.
        let lowerHalf = lines.filter { $0.boundingBox.midY < 0.5 }
        return lowerHalf.flatMap { amounts(in: $0.text, digits: digits, maxDigitRun: fallbackMaxDigitRun) }.max()
    }

    static func hasTotalKeyword(_ text: String) -> Bool {
        guard let re = totalKeywordRegex else { return false }
        return re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static let amountTokenRegex = try? NSRegularExpression(pattern: #"\d[\d.,]*\d|\d"#)

    /// Every parseable money amount in a string. Currency symbols/letters are ignored; tokens that
    /// are clearly NOT prices are rejected so they can't win the `.max()` fallback:
    ///  - any date-shaped substring (dot/slash/dash/ISO) is blanked BEFORE tokenizing, so a date's
    ///    individual parts (e.g. the "2025" in "30/05/2025", which a per-token check misses because
    ///    the slash splits the run) can't leak in as a digit run, and
    ///  - over-long digit runs (tax ids / phone numbers / codes) above `maxDigitRun`.
    static func amounts(in text: String, digits: Int, maxDigitRun: Int) -> [Decimal] {
        guard let re = amountTokenRegex else { return [] }
        let ns = blankingDates(text) as NSString
        return re.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).compactMap { m -> Decimal? in
            let token = ns.substring(with: m.range)
            if token.filter(\.isNumber).count > maxDigitRun { return nil }
            return parseAmount(token, fractionDigits: digits)
        }
    }

    /// Replace every date-shaped substring with equal-length spaces, so date digits never survive as
    /// amount tokens. Spaces (not removal) keep other token ranges intact.
    static func blankingDates(_ text: String) -> String {
        guard let re = dateRegex else { return text }
        let ns = text as NSString
        let result = NSMutableString(string: text)
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            result.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
        }
        return result as String
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

    private static let dateRegex = try? NSRegularExpression(pattern: #"\d{1,4}[./-]\d{1,2}[./-]\d{1,4}"#)

    /// The first date-shaped substring in a line, or nil.
    static func dateString(in text: String) -> String? {
        guard let re = dateRegex else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
}
