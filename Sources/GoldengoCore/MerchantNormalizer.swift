import Foundation

public enum MerchantNormalizer {
    /// Uppercases, trims, collapses whitespace, and drops trailing numeric tokens
    /// (e.g. store/terminal numbers) so "Spar" and "SPAR TIRANA 4471" normalize closer.
    public static func normalize(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let upper = raw.uppercased()
        let tokens = upper.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let kept = tokens.filter { !$0.allSatisfy(\.isNumber) }
        return kept.joined(separator: " ")
    }
}
