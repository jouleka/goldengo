import Foundation
import GoldengoCore

public enum StatementRowMapper {
    /// Maps one parsed CSV row to a NormalizedTransaction, or nil if the row is a header /
    /// has an unparseable date or amount. Negative amount → expense (abs); positive → income.
    public static func map(row: [String], using m: ColumnMapping) -> NormalizedTransaction? {
        func field(_ i: Int?) -> String? {
            guard let i, i >= 0, i < row.count else { return nil }
            return row[i].trimmingCharacters(in: .whitespaces)
        }
        guard let dateStr = field(m.dateIndex), let amountStr = field(m.amountIndex),
              let date = Self.date(dateStr, format: m.dateFormat),
              let signed = Self.decimal(amountStr, decimal: m.decimalSeparator, grouping: m.groupingSeparator)
        else { return nil }

        let isExpense = signed < 0
        let amount = abs(signed)
        let merchant = field(m.merchantIndex)
        let ext = field(m.externalIDIndex)
        return NormalizedTransaction(
            externalID: (ext?.isEmpty == false) ? ext : nil,
            amount: amount, currency: m.currency, date: date,
            rawMerchant: (merchant?.isEmpty == false) ? merchant : nil,
            kind: isExpense ? .expense : .income, accountRef: "statement")
    }

    static func date(_ s: String, format: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f.date(from: s)
    }

    static func decimal(_ s: String, decimal: String, grouping: String) -> Decimal? {
        var t = s.replacingOccurrences(of: grouping, with: "")
        t = t.replacingOccurrences(of: decimal, with: ".")
        t = t.replacingOccurrences(of: " ", with: "")
        return Decimal(string: t)
    }
}
