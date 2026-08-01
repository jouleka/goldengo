import SwiftUI
import Charts
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// A donut chart of category shares with the period total centered inside the ring. Pure
/// presentation — no interaction, no animation added (Charts' own minimal data-driven transition
/// is left as-is; we never layer a spin/grow effect on top).
struct SpendingDonut: View {
    let rows: [CategoryBreakdownRow]
    let total: Decimal
    let currencyCode: String
    var showsCenterTotal = true

    private struct Segment: Identifiable {
        let name: String
        let spent: Decimal
        let colorHex: String
        var id: String { name }
    }

    /// The chart shows parent categories, not every free-text leaf. This keeps adjacent slices
    /// meaningfully different and prevents five legacy blue categories from looking identical.
    private var segments: [Segment] {
        Dictionary(grouping: rows, by: \.groupName)
            .map { name, rows in
                Segment(name: name,
                        spent: rows.reduce(Decimal(0)) { $0 + $1.spent },
                        colorHex: rows.first?.colorHex ?? "#81786C")
            }
            .sorted { $0.spent > $1.spent }
    }

    var body: some View {
        Chart(segments) { segment in
            SectorMark(
                angle: .value("spent", (segment.spent as NSDecimalNumber).doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .foregroundStyle(Color(hex: segment.colorHex))
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            if showsCenterTotal { centerTotal }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(centerTotalAccessibilityLabel)
    }

    private var centerTotal: some View {
        // `.row` (not `.title`) — the ring's inner hole is ~100pt across at this chart size, and the
        // formatted total ("ALL 84,200") needs to fit without clipping into the sectors.
        VStack(spacing: 2) {
            GoldengoAmountText(
                Money(amount: total, currency: CurrencyCode(currencyCode)).formatted(),
                role: .row
            )
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            Text("money out")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .frame(width: 96)
    }

    private var centerTotalAccessibilityLabel: String {
        "Total money out, \(Money(amount: total, currency: CurrencyCode(currencyCode)).formatted())"
    }
}
