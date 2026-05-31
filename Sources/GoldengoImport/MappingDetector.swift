import Foundation
import GoldengoCore

/// Thin shim kept for backward compatibility. New code should use `StatementProfile.detectMapping`.
public enum MappingDetector {
    public static func detect(header: [String], currency: CurrencyCode) -> ColumnMapping? {
        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func firstIndex(_ keys: [String]) -> Int? {
            lower.firstIndex { h in keys.contains { !$0.isEmpty && h.contains($0) } }
        }
        guard let dateIdx = firstIndex(["date", "data", "datë"]),
              let descIdx = firstIndex(["description", "details", "merchant", "përshkrim", "narrative"])
        else { return nil }
        let idIdx = firstIndex(["reference", "ref", "id", "transaction"])
        if let debitIdx = firstIndex(["debit", "debi"]), let creditIdx = firstIndex(["credit", "kredi"]) {
            return ColumnMapping(dateIndex: dateIdx, amount: .debitCredit(debit: debitIdx, credit: creditIdx),
                                 merchantIndex: descIdx, externalIDIndex: idIdx,
                                 dateFormats: ["dd.MM.yyyy", "dd/MM/yyyy", "dd/MM/yy", "yyyy-MM-dd"],
                                 decimalSeparator: ",", groupingSeparator: ".", currency: currency)
        }
        guard let amtIdx = firstIndex(["amount", "vlera", "shuma"]) else { return nil }
        return ColumnMapping(dateIndex: dateIdx, amount: .signed(index: amtIdx),
                             merchantIndex: descIdx, externalIDIndex: idIdx,
                             dateFormats: ["dd.MM.yyyy", "dd/MM/yyyy", "dd/MM/yy", "yyyy-MM-dd"],
                             decimalSeparator: ",", groupingSeparator: ".", currency: currency)
    }
}
