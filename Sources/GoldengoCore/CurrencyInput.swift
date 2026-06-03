import Foundation

/// Pure helper for keypad amount entry. Keeps the app's "display == saved value" invariant when the
/// currency changes to one with fewer minor-unit digits.
public enum CurrencyInput {
    /// Trim a typed amount string so its fractional part fits `digits` minor-unit digits.
    public static func fit(_ amountString: String, toFractionDigits digits: Int) -> String {
        guard let dot = amountString.firstIndex(of: ".") else { return amountString }
        if digits == 0 { return String(amountString[..<dot]) }              // drop "." + all decimals
        let fracStart = amountString.index(after: dot)
        let fracCount = amountString.distance(from: fracStart, to: amountString.endIndex)
        guard fracCount > digits else { return amountString }
        return String(amountString[..<amountString.index(fracStart, offsetBy: digits)])
    }
}
