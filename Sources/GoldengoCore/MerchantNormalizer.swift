import Foundation

public enum MerchantNormalizer {
    /// Uppercases, collapses all whitespace (spaces, tabs, newlines), and drops purely
    /// numeric tokens (e.g. store/terminal numbers) so "Spar" and "SPAR TIRANA 4471"
    /// normalize to the same key. Returns "" for nil/empty/whitespace-only/all-numeric input.
    public static func normalize(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let upper = raw.uppercased()
        let tokens = upper.split(whereSeparator: { $0.isWhitespace })
        let kept = tokens.filter { !$0.allSatisfy(\.isNumber) }
        return kept.joined(separator: " ")
    }
}
