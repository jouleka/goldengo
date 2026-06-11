import Foundation

/// Detects ATM-withdrawal rows in statement descriptions (GOL-95). Word-boundary aware so a
/// merchant like "Atmosfera" never matches the keyword "atm".
public enum ATMKeywords {
    public static func isWithdrawal(_ description: String?, keywords: [String]) -> Bool {
        guard let description else { return false }
        let folded = " " + fold(description) + " "
        return keywords.contains { keyword in
            let k = fold(keyword)
            guard !k.isEmpty else { return false }
            // Keyword must sit between word boundaries (multi-word keywords match as phrases):
            // "ATM-REF" matches "atm"; "Atmosfera" must not.
            return folded.range(of: "(^|[^\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: k)
                                    + "($|[^\\p{L}\\p{N}])",
                                options: .regularExpression) != nil
        }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sq_AL"))
    }
}
