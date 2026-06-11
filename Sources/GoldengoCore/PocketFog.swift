import Foundation

/// Pure pocket-claim confidence math (GOL-98). The store owns record selection; this owns
/// the honesty band: how blurry the claim is after N cash-silent days, capped so the claim
/// always stays falsifiable from memory (assassin guard: an absurd ±N reads as broken).
public enum PocketFog {
    public enum Confidence: Equatable, Sendable {
        case even                      // reconciled or books moving with the hands
        case fogged(width: Decimal)    // honest ± band
        case lost                      // past ~one wallet of drift — plain words, no number
    }

    /// Median daily cash outflow, floored — thin or tiny history must not make fog crawl.
    public static func typicalCashDay(dailyOutflows: [Decimal], floor: Decimal) -> Decimal {
        guard !dailyOutflows.isEmpty else { return floor }
        let sorted = dailyOutflows.sorted()
        return max(sorted[sorted.count / 2], floor)
    }

    public static func confidence(silentDays: Int, typicalCashDay: Decimal,
                                  walletTotal: Decimal) -> Confidence {
        guard silentDays > 0, typicalCashDay > 0 else { return .even }
        guard walletTotal > 0 else { return .lost }
        let width = typicalCashDay * Decimal(silentDays)
        return width >= walletTotal ? .lost : .fogged(width: width)
    }
}

/// Pre-rendered widget content (GOL-98) — the widget process reads ONLY this from the App
/// Group; all formatting and privacy variants are composed app-side (the today-total pattern).
public struct PocketPayload: Codable, Equatable, Sendable {
    public var revealedInline: String
    public var hiddenInline: String
    public var revealedLines: [String]
    public var hiddenLines: [String]
    public var hasWallet: Bool
    public init(revealedInline: String, hiddenInline: String,
                revealedLines: [String], hiddenLines: [String], hasWallet: Bool) {
        self.revealedInline = revealedInline; self.hiddenInline = hiddenInline
        self.revealedLines = revealedLines; self.hiddenLines = hiddenLines; self.hasWallet = hasWallet
    }
}
