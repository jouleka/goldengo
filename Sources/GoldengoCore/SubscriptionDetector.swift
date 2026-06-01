import Foundation

/// Pure, on-device subscription detection (spec §9). Operates over `TransactionOccurrence`
/// value types so it has zero persistence/UI dependencies and is trivially unit-testable.
public enum SubscriptionDetector {

    public struct Options: Sendable {
        /// Relative amount-spread threshold for the `isVariableAmount` flag (spec §9 "amount-tolerance
        /// flag"): when the in-series amounts span more than this fraction of the median, the candidate
        /// is flagged variable (utilities etc.). A normal price change below this stays "fixed".
        public var amountTolerance: Double
        /// "Now", used to roll the predicted next charge forward past the last observed charge.
        public var now: Date
        public init(amountTolerance: Double = 0.15, now: Date = .now) {
            self.amountTolerance = amountTolerance; self.now = now
        }
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    public static func detect(_ occurrences: [TransactionOccurrence], options: Options = .init()) -> [SubscriptionCandidate] {
        var groups: [String: [TransactionOccurrence]] = [:]
        for o in occurrences {
            let norm = MerchantNormalizer.normalize(o.merchant)
            guard !norm.isEmpty else { continue }
            groups["\(norm)|\(o.currency.rawValue)", default: []].append(o)
        }

        var candidates: [SubscriptionCandidate] = []
        for (_, raw) in groups {
            guard let c = candidate(from: raw, options: options) else { continue }
            candidates.append(c)
        }
        return candidates.sorted { $0.confidence > $1.confidence }
    }

    private static func candidate(from raw: [TransactionOccurrence], options: Options) -> SubscriptionCandidate? {
        let norm = MerchantNormalizer.normalize(raw.first?.merchant)
        guard !norm.isEmpty else { return nil }
        let currency = raw.first!.currency

        // Collapse same UTC day to one occurrence (keep the larger amount).
        var byDay: [Date: TransactionOccurrence] = [:]
        for o in raw {
            let d = calendar.startOfDay(for: o.date)
            if let existing = byDay[d] { if o.amount > existing.amount { byDay[d] = o } }
            else { byDay[d] = o }
        }
        let series = byDay.values.sorted { $0.date < $1.date }
        guard series.count >= 2 else { return nil }

        var gaps: [Int] = []
        for i in 1..<series.count {
            let g = calendar.dateComponents([.day], from: series[i - 1].date, to: series[i].date).day ?? 0
            gaps.append(g)
        }
        let sortedGaps = gaps.sorted()
        let medianGap = sortedGaps[sortedGaps.count / 2]

        guard let cadence = SubscriptionCadence.allCases.first(where: { $0.dayBand.contains(medianGap) }) else { return nil }
        let inBand = gaps.filter { cadence.dayBand.contains($0) }.count
        guard inBand >= max(1, gaps.count / 2) else { return nil }
        guard series.count >= cadence.minimumOccurrences else { return nil }

        let positive = series.map(\.amount).filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        let median = positive[positive.count / 2]
        let hadTrial = series.contains { $0.amount == 0 }
        // Variable-amount flag: compute the spread ratio in Double (avoids Decimal(Double) literal
        // imprecision) and compare against the public tolerance knob (default 15%).
        let spread = positive.last! - positive.first!
        let ratio = median > 0
            ? NSDecimalNumber(decimal: spread).doubleValue / NSDecimalNumber(decimal: median).doubleValue
            : 0
        let isVariableAmount = ratio > options.amountTolerance

        var next = cadence.advance(series.last!.date, calendar: calendar)
        while next < options.now { next = cadence.advance(next, calendar: calendar) }

        let gd = gaps.map(Double.init)
        let mean = gd.reduce(0, +) / Double(gd.count)
        let variance = gd.reduce(0) { $0 + pow($1 - mean, 2) } / Double(gd.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1
        let regularity = max(0, 1 - cv)
        let occWeight = min(1.0, Double(series.count) / 6.0)
        let confidence = min(1, max(0, 0.6 * regularity + 0.4 * occWeight))

        let displayName = series.reversed().compactMap { $0.merchant?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? norm

        return SubscriptionCandidate(
            id: "\(norm)|\(cadence.rawValue)|\(currency.rawValue)",
            displayName: displayName, normalizedMerchant: norm, amount: median, currency: currency,
            cadence: cadence, occurrenceCount: series.count,
            firstCharge: series.first!.date, lastCharge: series.last!.date,
            predictedNextCharge: next, isVariableAmount: isVariableAmount, hadTrial: hadTrial,
            confidence: confidence, memberIDs: series.map(\.id))
    }
}
