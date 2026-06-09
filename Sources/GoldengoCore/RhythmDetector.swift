import Foundation

/// One active daily-recurring spend pattern, "due today". Pure value type.
public struct RhythmPattern: Sendable, Equatable, Identifiable {
    public let id: String                 // "<normalizedMerchant>|<currencyCode>"
    public let displayName: String
    public let normalizedMerchant: String
    public let amount: Decimal             // median of recent positive amounts
    public let currency: CurrencyCode
    public let occurrenceCount: Int        // distinct recent days
    public let lastSeen: Date
    public let confidence: Double          // 0...1
    public init(id: String, displayName: String, normalizedMerchant: String, amount: Decimal,
                currency: CurrencyCode, occurrenceCount: Int, lastSeen: Date, confidence: Double) {
        self.id = id; self.displayName = displayName; self.normalizedMerchant = normalizedMerchant
        self.amount = amount; self.currency = currency; self.occurrenceCount = occurrenceCount
        self.lastSeen = lastSeen; self.confidence = confidence
    }
}

/// Pure, on-device DAILY rhythm detection — separate from `SubscriptionDetector` (which floors at
/// weekly). Conservative on purpose: a wrong daily ghost erodes trust.
public enum RhythmDetector {
    public struct Options: Sendable {
        public var windowDays: Int
        public var minOccurrences: Int
        public var maxGap: Int
        public var activeWithinDays: Int
        public var minConfidence: Double
        public var now: Date
        public init(windowDays: Int = 21, minOccurrences: Int = 6, maxGap: Int = 2,
                    activeWithinDays: Int = 2, minConfidence: Double = 0.6, now: Date = .now) {
            self.windowDays = windowDays; self.minOccurrences = minOccurrences; self.maxGap = maxGap
            self.activeWithinDays = activeWithinDays; self.minConfidence = minConfidence; self.now = now
        }
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    public static func detect(_ occurrences: [TransactionOccurrence], options: Options = .init()) -> [RhythmPattern] {
        let windowStart = calendar.date(byAdding: .day, value: -options.windowDays, to: options.now) ?? options.now
        var groups: [String: [TransactionOccurrence]] = [:]
        for o in occurrences where o.date >= windowStart {
            let norm = MerchantNormalizer.normalize(o.merchant)
            guard !norm.isEmpty else { continue }
            groups["\(norm)|\(o.currency.rawValue)", default: []].append(o)
        }
        return groups.compactMap { pattern(key: $0.key, raw: $0.value, options: options) }
            .sorted { $0.confidence > $1.confidence }
    }

    private static func pattern(key: String, raw: [TransactionOccurrence], options: Options) -> RhythmPattern? {
        let norm = MerchantNormalizer.normalize(raw.first?.merchant)
        guard !norm.isEmpty else { return nil }
        let currency = raw.first!.currency
        // Collapse same UTC day to one (keep the larger amount) — daily means one per day.
        var byDay: [Date: TransactionOccurrence] = [:]
        for o in raw {
            let d = calendar.startOfDay(for: o.date)
            if let e = byDay[d] { if o.amount > e.amount { byDay[d] = o } } else { byDay[d] = o }
        }
        let series = byDay.values.sorted { $0.date < $1.date }
        guard series.count >= options.minOccurrences else { return nil }

        let lastSeen = series.last!.date
        guard let activeCutoff = calendar.date(byAdding: .day, value: -options.activeWithinDays, to: options.now),
              lastSeen >= activeCutoff else { return nil }

        var gaps: [Int] = []
        for i in 1..<series.count {
            gaps.append(calendar.dateComponents([.day], from: series[i - 1].date, to: series[i].date).day ?? 0)
        }
        guard !gaps.isEmpty else { return nil }   // defensive: never index an empty gap array
        let sortedGaps = gaps.sorted()
        guard sortedGaps[sortedGaps.count / 2] == 1 else { return nil }            // daily median
        guard gaps.filter({ $0 <= options.maxGap }).count >= max(1, gaps.count * 2 / 3) else { return nil }

        let positive = series.map(\.amount).filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        let amount = positive[positive.count / 2]

        let gd = gaps.map(Double.init)
        let mean = gd.reduce(0, +) / Double(gd.count)
        let variance = gd.reduce(0) { $0 + pow($1 - mean, 2) } / Double(gd.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1
        let regularity = max(0, 1 - cv)
        let occWeight = min(1.0, Double(series.count) / 8.0)
        let confidence = min(1, max(0, 0.6 * regularity + 0.4 * occWeight))
        guard confidence >= options.minConfidence else { return nil }

        let displayName = series.reversed().compactMap { $0.merchant?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? norm
        return RhythmPattern(id: key, displayName: displayName, normalizedMerchant: norm, amount: amount,
                             currency: currency, occurrenceCount: series.count, lastSeen: lastSeen, confidence: confidence)
    }
}
