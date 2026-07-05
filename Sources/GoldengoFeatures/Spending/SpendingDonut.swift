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

    var body: some View {
        Chart(rows) { row in
            SectorMark(
                angle: .value("spent", (row.spent as NSDecimalNumber).doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .foregroundStyle(Color(hex: row.colorHex))
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            centerTotal
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
            Text("spent")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .frame(width: 96)
    }

    private var centerTotalAccessibilityLabel: String {
        "Total spent, \(Money(amount: total, currency: CurrencyCode(currencyCode)).formatted())"
    }
}
