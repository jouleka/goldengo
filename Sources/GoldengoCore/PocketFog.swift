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

    /// Whole UTC days between movements. One helper shared by the store (composing the
    /// payload) and the widget (re-rendering it per timeline date) so the two never disagree.
    public static func silentDays(from lastMovement: Date, to now: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return max(cal.dateComponents([.day], from: lastMovement, to: now).day ?? 0, 0)
    }

    public static func confidence(silentDays: Int, typicalCashDay: Decimal,
                                  walletTotal: Decimal) -> Confidence {
        guard silentDays > 0, typicalCashDay > 0 else { return .even }
        // An exactly-zero wallet can't drain — the books are exact, not blind (review: zero
        // is knowledge; only a NEGATIVE balance proves the books wrong).
        if walletTotal == 0 { return .even }
        guard walletTotal > 0 else { return .lost }
        let width = typicalCashDay * Decimal(silentDays)
        return width >= walletTotal ? .lost : .fogged(width: width)
    }
}

/// The widget's input (GOL-98): per-currency claim DATA, published app-side at every save. The
/// widget never touches the store — it re-renders these numbers at each timeline date with the
/// same pure math, so fog keeps advancing on days the app never runs (review: a pre-rendered
/// string payload froze the claim at the last save and the machine could never confess).
public struct PocketPayload: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public var currencyCode: String
        public var expected: Decimal          // the books' claim; only saves change it
        public var typicalCashDay: Decimal    // 0 = static currency (never fogs)
        public var lastMovement: Date
        public init(currencyCode: String, expected: Decimal,
                    typicalCashDay: Decimal, lastMovement: Date) {
            self.currencyCode = currencyCode; self.expected = expected
            self.typicalCashDay = typicalCashDay; self.lastMovement = lastMovement
        }
    }
    public var lines: [Line]
    public var hasWallet: Bool
    public init(lines: [Line], hasWallet: Bool) {
        self.lines = lines; self.hasWallet = hasWallet
    }
}

/// One rendering of the claim — both privacy variants, composed at a specific date.
public struct PocketContent: Equatable, Sendable {
    public var revealedInline: String
    public var hiddenInline: String
    public var revealedLines: [String]
    public var hiddenLines: [String]
    public init(revealedInline: String, hiddenInline: String,
                revealedLines: [String], hiddenLines: [String]) {
        self.revealedInline = revealedInline; self.hiddenInline = hiddenInline
        self.revealedLines = revealedLines; self.hiddenLines = hiddenLines
    }
}

extension PocketPayload {
    /// Render the claim as it stands at `date`. Pure — the app and the widget compose from the
    /// same payload, so the lock screen can never assert something the math wouldn't.
    /// Honesty rules (review-pinned): .lost shows plain words and NO number; "~" marks .fogged
    /// only; the privacy inline speaks for the WORST currency, not the first; "since" falls
    /// back to a real date once a weekday would be ambiguous (>6 days).
    public func content(at date: Date) -> PocketContent {
        guard hasWallet, !lines.isEmpty else {
            return PocketContent(revealedInline: "Set your wallet", hiddenInline: "Set your wallet",
                                 revealedLines: [], hiddenLines: [])
        }
        struct Rendered { let name: String; let confidence: PocketFog.Confidence
                          let amount: String; let state: String }
        let rendered: [Rendered] = lines.map { l in
            let silent = PocketFog.silentDays(from: l.lastMovement, to: date)
            let confidence = PocketFog.confidence(silentDays: silent,
                                                  typicalCashDay: l.typicalCashDay,
                                                  walletTotal: l.expected)
            let since = silent < 7
                ? l.lastMovement.formatted(.dateTime.weekday(.abbreviated))
                : l.lastMovement.formatted(.dateTime.month(.abbreviated).day())
            let state: String
            switch confidence {
            case .even: state = "even since \(since)"
            case .fogged: state = "losing track since \(since)"
            case .lost: state = "lost track — tap when your wallet's out"
            }
            let money = Money(amount: l.expected, currency: CurrencyCode(l.currencyCode)).formatted()
            let name = l.currencyCode == "ALL" ? "Lek"
                : (Locale.current.localizedString(forCurrencyCode: l.currencyCode) ?? l.currencyCode)
            let amount = confidence.isFogged ? "~" + money : money
            return Rendered(name: name, confidence: confidence, amount: amount, state: state)
        }
        // The worst currency speaks for the one-line privacy claim (first wins ties — ALL leads).
        func rank(_ c: PocketFog.Confidence) -> Int {
            switch c { case .even: return 0; case .fogged: return 1; case .lost: return 2 }
        }
        let worst = rendered.dropFirst().reduce(rendered[0]) {
            rank($1.confidence) > rank($0.confidence) ? $1 : $0
        }
        let revealedInline: String
        if rendered.count == 1, rendered[0].confidence == .lost {
            revealedInline = rendered[0].state
        } else {
            revealedInline = rendered.map {
                $0.confidence == .lost ? "\($0.name) lost track" : $0.amount
            }.joined(separator: " · ")
        }
        return PocketContent(
            revealedInline: revealedInline,
            hiddenInline: worst.state,
            revealedLines: rendered.map {
                $0.confidence == .lost ? "\($0.name) — \($0.state)" : "\($0.amount) — \($0.state)"
            },
            hiddenLines: rendered.map { "\($0.name) — \($0.state)" })
    }
}

private extension PocketFog.Confidence {
    var isFogged: Bool { if case .fogged = self { return true }; return false }
}
