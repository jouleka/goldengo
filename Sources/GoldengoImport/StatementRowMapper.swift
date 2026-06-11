import Foundation
import GoldengoCore

public enum StatementRowMapper {
    /// Maps one parsed CSV row to a NormalizedTransaction, or nil if the row is a header /
    /// has an unparseable date or amount. Handles both signed-amount and debit/credit columns.
    public static func map(row: [String], using m: ColumnMapping) -> NormalizedTransaction? {
        func field(_ i: Int?) -> String? {
            guard let i, i >= 0, i < row.count else { return nil }
            return row[i].trimmingCharacters(in: .whitespaces)
        }
        guard let dateStr = field(m.dateIndex),
              let date = Self.date(dateStr, formats: m.dateFormats)
        else { return nil }

        let amount: Decimal
        let kind: TransactionKind
        switch m.amount {
        case .signed(let i):
            guard let s = field(i),
                  let v = Self.decimal(s, decimal: m.decimalSeparator, grouping: m.groupingSeparator)
            else { return nil }
            kind = v < 0 ? .expense : .income; amount = abs(v)
        case .debitCredit(let di, let ci):
            let d = field(di).flatMap { Self.decimal($0, decimal: m.decimalSeparator, grouping: m.groupingSeparator) }
            let c = field(ci).flatMap { Self.decimal($0, decimal: m.decimalSeparator, grouping: m.groupingSeparator) }
            if let d, d != 0 { kind = .expense; amount = abs(d) }
            else if let c, c != 0 { kind = .income; amount = abs(c) }
            else { return nil }
        }

        let merchant = field(m.merchantIndex)
        var kindFinal = kind
        if kindFinal == .expense,
           ATMKeywords.isWithdrawal(merchant, keywords: m.atmKeywords,
                                    exclusions: m.atmExclusionKeywords) {
            kindFinal = .transfer   // money moved to the wallet, not spend (GOL-95)
        }
        let ext = field(m.externalIDIndex)
        return NormalizedTransaction(
            externalID: (ext?.isEmpty == false) ? ext : nil,
            amount: amount, currency: m.currency, date: date,
            rawMerchant: (merchant?.isEmpty == false) ? merchant : nil,
            kind: kindFinal, accountRef: "statement")
    }

    static func date(_ s: String, formats: [String]) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func decimal(_ s: String, decimal: String, grouping: String) -> Decimal? {
        var t = s.replacingOccurrences(of: grouping, with: "")
        t = t.replacingOccurrences(of: decimal, with: ".")
        t = t.replacingOccurrences(of: " ", with: "")
        return Decimal(string: t)
    }
}
