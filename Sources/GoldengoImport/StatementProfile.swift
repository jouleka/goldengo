import Foundation
import GoldengoCore

public struct StatementProfile: Sendable {
    public var id: String
    public var dateFormats: [String]
    public var decimalSeparator: String
    public var groupingSeparator: String
    public var dateKeywords: [String]
    public var descriptionKeywords: [String]
    public var debitKeywords: [String]
    public var creditKeywords: [String]
    public var amountKeywords: [String]      // for single-signed-column banks
    public var idKeywords: [String]
    public var skipRowKeywords: [String]     // substrings marking non-transaction rows
    public var atmKeywords: [String] = []           // descriptions marking ATM withdrawals → .transfer (GOL-95)
    public var atmExclusionKeywords: [String] = []  // fee/commission wording that vetoes the match — a fee is spend

    public static let all: [StatementProfile] = [.raiffeisenAlbania, .generic]

    public static let raiffeisenAlbania = StatementProfile(
        id: "raiffeisen-al",
        dateFormats: ["dd/MM/yy", "dd/MM/yyyy"],
        decimalSeparator: ".", groupingSeparator: ",",
        dateKeywords: ["data e transaksionit", "datë"],
        descriptionKeywords: ["pershkrimi", "përshkrimi", "description"],
        debitKeywords: ["debi", "debit"],
        creditKeywords: ["kredi", "credit"],
        amountKeywords: [],
        idKeywords: ["referenca", "reference", "ref"],
        skipRowKeywords: ["balanca", "numri i veprimeve", "limit overdraft", "ledger balance", "dispo balance", "nxjerrje llogarie", "data e transaksionit"],
        atmKeywords: ["terheqje", "terheqja", "terheqjes", "atm", "bankomat", "bankomati", "bankomatit", "cash withdrawal"],
        atmExclusionKeywords: ["komision", "komisioni", "commission", "fee", "tarifa", "tarife", "provizion"])

    public static let generic = StatementProfile(
        id: "generic",
        dateFormats: ["yyyy-MM-dd", "dd/MM/yyyy", "dd.MM.yyyy", "MM/dd/yyyy"],
        decimalSeparator: ".", groupingSeparator: ",",
        dateKeywords: ["date", "data"],
        descriptionKeywords: ["description", "details", "merchant", "narrative", "pershkrimi"],
        debitKeywords: ["debit", "debi"],
        creditKeywords: ["credit", "kredi"],
        amountKeywords: ["amount", "value", "vlera", "shuma"],
        idKeywords: ["reference", "ref", "id", "transaction"],
        skipRowKeywords: ["opening balance", "closing balance", "balanca"],
        atmKeywords: ["atm", "cash withdrawal", "terheqje", "terheqja", "bankomat", "bankomati"],
        atmExclusionKeywords: ["komision", "komisioni", "commission", "fee", "tarifa", "tarife", "provizion"])

    /// Best-match mapping from a header row, trying each known profile in order.
    public static func detectMapping(header: [String], currency: CurrencyCode) -> ColumnMapping? {
        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func idx(_ keys: [String]) -> Int? {
            lower.firstIndex { h in keys.contains { !$0.isEmpty && h.contains($0) } }
        }
        for p in all {
            guard let date = idx(p.dateKeywords), let desc = idx(p.descriptionKeywords) else { continue }
            let style: AmountStyle
            if let d = idx(p.debitKeywords), let c = idx(p.creditKeywords) {
                style = .debitCredit(debit: d, credit: c)
            } else if let a = idx(p.amountKeywords) {
                style = .signed(index: a)
            } else {
                continue
            }
            var mapping = ColumnMapping(
                dateIndex: date, amount: style, merchantIndex: desc,
                externalIDIndex: idx(p.idKeywords),
                dateFormats: p.dateFormats,
                decimalSeparator: p.decimalSeparator,
                groupingSeparator: p.groupingSeparator,
                currency: currency)
            mapping.atmKeywords = p.atmKeywords
            mapping.atmExclusionKeywords = p.atmExclusionKeywords
            mapping.skipRowKeywords = p.skipRowKeywords
            return mapping
        }
        return nil
    }
}
