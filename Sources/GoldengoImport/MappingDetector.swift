import Foundation
import GoldengoCore

public enum MappingDetector {
    public static func detect(header: [String], currency: CurrencyCode) -> ColumnMapping? {
        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func firstIndex(_ keys: [String]) -> Int? {
            lower.firstIndex { h in keys.contains { h.contains($0) } }
        }
        guard let dateIdx = firstIndex(["date", "data", "datë"]),
              let amtIdx = firstIndex(["amount", "vlera", "shuma", "debit"]),
              let descIdx = firstIndex(["description", "details", "merchant", "përshkrim", "narrative"])
        else { return nil }
        let idIdx = firstIndex(["reference", "ref", "id", "transaction"])
        return ColumnMapping(dateIndex: dateIdx, amountIndex: amtIdx, merchantIndex: descIdx,
                             externalIDIndex: idIdx, dateFormat: "dd.MM.yyyy",
                             decimalSeparator: ",", groupingSeparator: ".", currency: currency)
    }
}
