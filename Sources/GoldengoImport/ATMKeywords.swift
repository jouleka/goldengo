import Foundation

/// Detects ATM-withdrawal rows in statement descriptions (GOL-95). Word-boundary aware so a
/// merchant like "Atmosfera" never matches the keyword "atm", and EXCLUSION-first so a fee row
/// ("KOMISION TERHEQJE ATM") is never mistaken for money entering the wallet — a fee is spend.
public enum ATMKeywords {
    public static func isWithdrawal(_ description: String?, keywords: [String], exclusions: [String]) -> Bool {
        guard let description else { return false }
        let folded = " " + fold(description) + " "
        guard !exclusions.contains(where: { matches(folded, keyword: $0) }) else { return false }
        return keywords.contains { matches(folded, keyword: $0) }
    }

    private static func matches(_ foldedPadded: String, keyword: String) -> Bool {
        let k = fold(keyword)
        guard !k.isEmpty else { return false }
        // Keyword must sit between word boundaries (multi-word keywords match as phrases):
        // "ATM-REF" matches "atm"; "Atmosfera" must not.
        return foldedPadded.range(of: "(^|[^\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: k)
                                    + "($|[^\\p{L}\\p{N}])",
                                  options: .regularExpression) != nil
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sq_AL"))
    }
}
