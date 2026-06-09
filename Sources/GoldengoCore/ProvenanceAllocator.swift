import Foundation

/// Pure, deterministic FIFO drawdown: spends draw from the oldest non-depleted inflow lot first,
/// converting currencies via `CurrencyConverter`. Value-in/value-out — no SwiftData, fully testable.
public enum ProvenanceAllocator {
    public struct Inflow: Sendable, Equatable {
        public let id: String; public let sourceID: String
        public let amount: Decimal; public let currency: CurrencyCode; public let date: Date
        public init(id: String, sourceID: String, amount: Decimal, currency: CurrencyCode, date: Date) {
            self.id = id; self.sourceID = sourceID; self.amount = amount; self.currency = currency; self.date = date
        }
    }
    public struct Outflow: Sendable, Equatable {
        public let id: String; public let amount: Decimal; public let currency: CurrencyCode; public let date: Date
        public init(id: String, amount: Decimal, currency: CurrencyCode, date: Date) {
            self.id = id; self.amount = amount; self.currency = currency; self.date = date
        }
    }
    public struct FundingSegment: Sendable, Equatable {
        public let sourceID: String; public let amount: Decimal   // in the SOURCE's currency
        public init(sourceID: String, amount: Decimal) { self.sourceID = sourceID; self.amount = amount }
    }
    public struct Allocation: Sendable, Equatable {
        public let remainingBySource: [String: Decimal]            // source currency, >= 0
        public let fundingByOutflow: [String: [FundingSegment]]
        public let totalUnaccounted: Decimal                       // in displayCurrency
    }

    public static func allocate(inflows: [Inflow], outflows: [Outflow],
                                rates: RateTable, displayCurrency: CurrencyCode) -> Allocation {
        let conv = CurrencyConverter(table: rates)
        let lots = inflows.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        var remaining: [String: Decimal] = [:]                     // by inflow.id
        for lot in lots { remaining[lot.id, default: 0] += lot.amount }

        var fundingByOutflow: [String: [FundingSegment]] = [:]
        var unaccounted: Decimal = 0

        for out in outflows.sorted(by: { ($0.date, $0.id) < ($1.date, $1.id) }) {
            var need = out.amount                                  // remaining need, in out.currency
            var segs: [FundingSegment] = []
            // Only lots received on/before the spend can fund it — money from the future can't fund the past.
            for lot in lots where need > 0 && lot.date <= out.date {
                let lotRem = remaining[lot.id] ?? 0
                if lotRem <= 0 { continue }
                guard let lotRemInOut = try? conv.convert(lotRem, from: lot.currency, to: out.currency) else { continue }
                let takenInOut = min(need, lotRemInOut)
                // If this lot is fully consumed, zero it exactly (avoid reconversion rounding drift).
                let fullyConsumes = takenInOut >= lotRemInOut
                let takenInLot = fullyConsumes ? lotRem
                    : ((try? conv.convert(takenInOut, from: out.currency, to: lot.currency)) ?? 0)
                remaining[lot.id] = lotRem - takenInLot
                need -= takenInOut
                segs.append(FundingSegment(sourceID: lot.sourceID, amount: takenInLot))
            }
            if need > 0 {
                unaccounted += (try? conv.convert(need, from: out.currency, to: displayCurrency)) ?? need
            }
            if !segs.isEmpty { fundingByOutflow[out.id] = merge(segs) }
        }

        var remainingBySource: [String: Decimal] = [:]
        for lot in lots { remainingBySource[lot.sourceID, default: 0] += (remaining[lot.id] ?? 0) }
        return Allocation(remainingBySource: remainingBySource,
                          fundingByOutflow: fundingByOutflow, totalUnaccounted: unaccounted)
    }

    /// Combine segments that hit the same source (an outflow can span two lots of one source).
    private static func merge(_ segs: [FundingSegment]) -> [FundingSegment] {
        var order: [String] = []
        var sums: [String: Decimal] = [:]
        for s in segs {
            if sums[s.sourceID] == nil { order.append(s.sourceID) }
            sums[s.sourceID, default: 0] += s.amount
        }
        return order.map { FundingSegment(sourceID: $0, amount: sums[$0] ?? 0) }
    }
}
