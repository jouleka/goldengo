import SwiftUI
import Charts
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// A large, interactive companion to the compact overview donut. The user can switch between the
/// concrete category view and the economic-purpose view, then tap either a slice or a list row to
/// inspect its amount and share without leaving Spending.
struct SpendingChartExplorer: View {
    private enum Lens: String, CaseIterable, Identifiable {
        case categories = "Categories"
        case purpose = "Purpose"
        var id: String { rawValue }
    }

    private struct Segment: Identifiable {
        let name: String
        let amount: Decimal
        let colorHex: String
        var id: String { name }
    }

    let breakdown: CategoryBreakdown

    @Environment(\.dismiss) private var dismiss
    @State private var lens: Lens = .categories
    @State private var selectedName: String?

    private var currency: CurrencyCode { CurrencyCode(breakdown.currencyCode) }

    private var segments: [Segment] {
        switch lens {
        case .categories:
            return Dictionary(grouping: breakdown.rows, by: \.groupName)
                .map { name, rows in
                    Segment(
                        name: name,
                        amount: rows.reduce(Decimal(0)) { $0 + $1.spent },
                        colorHex: rows.first?.colorHex ?? MoneyPurpose.other.colorHex
                    )
                }
                .sorted { $0.amount > $1.amount }
        case .purpose:
            return [
                Segment(name: MoneyPurpose.essential.title, amount: breakdown.essentialTotal,
                        colorHex: MoneyPurpose.essential.colorHex),
                Segment(name: MoneyPurpose.lifestyle.title, amount: breakdown.lifestyleTotal,
                        colorHex: MoneyPurpose.lifestyle.colorHex),
                Segment(name: MoneyPurpose.wealth.title, amount: breakdown.investedTotal,
                        colorHex: MoneyPurpose.wealth.colorHex),
                Segment(name: MoneyPurpose.waste.title, amount: breakdown.wasteTotal,
                        colorHex: MoneyPurpose.waste.colorHex),
                Segment(name: MoneyPurpose.other.title, amount: breakdown.otherTotal,
                        colorHex: MoneyPurpose.other.colorHex),
            ]
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
        }
    }

    private var activeSegment: Segment? {
        guard let selectedName else { return nil }
        return segments.first { $0.name == selectedName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    lensControl
                    interactiveChart
                    segmentList
                }
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.top, 12)
                .padding(.bottom, GoldengoTheme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Where your money went")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: lens) { _, _ in clearSelection() }
    }

    private var lensControl: some View {
        HStack(spacing: 5) {
            ForEach(Lens.allCases) { option in
                Button {
                    withAnimation(GoldengoMotion.quick) { lens = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(lens == option ? GoldengoTheme.inkPrimary : GoldengoTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(lens == option ? Color.goldengoSurface : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(lens == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.goldengoField)
        .clipShape(Capsule())
    }

    private var interactiveChart: some View {
        VStack(spacing: 14) {
            Chart(segments) { segment in
                SectorMark(
                    angle: .value("Money out", value(of: segment)),
                    innerRadius: .ratio(0.58),
                    angularInset: 2
                )
                .foregroundStyle(Color(hex: segment.colorHex))
                .cornerRadius(5)
                .opacity(activeSegment == nil || activeSegment?.id == segment.id ? 1 : 0.34)
            }
            .chartLegend(.hidden)
            .chartBackground { _ in chartCenter }
            // `chartAngleSelection` uses a drag-style recognizer. Inside this vertical ScrollView,
            // iOS waits to decide whether the finger is scrolling, which makes a slice feel like it
            // needs a long press. A spatial tap resolves on finger-up and maps that point to the
            // donut angle directly, so every slice changes with one ordinary tap.
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { tap in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    selectSector(at: tap.location, in: geometry[plotFrame])
                                }
                        )
                }
            }
            .frame(height: 270)
            .animation(GoldengoMotion.quick, value: selectedName)
            .accessibilityLabel(chartAccessibilityLabel)

            if activeSegment != nil {
                Button("Show total") { clearSelection() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
            } else {
                Label("Tap a slice or a row to inspect it", systemImage: "hand.tap")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
        .padding(16)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
        }
    }

    private var chartCenter: some View {
        VStack(spacing: 3) {
            Text(activeSegment?.name ?? "Money out")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkMuted)
                .lineLimit(1)
            Text(Money(amount: activeSegment?.amount ?? breakdown.total, currency: currency).amountText())
                .font(.system(size: 21, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            if let segment = activeSegment {
                Text("\(percentage(of: segment))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: segment.colorHex))
            }
        }
        .frame(width: 122)
    }

    private var segmentList: some View {
        VStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 { Divider().overlay(GoldengoTheme.hairline) }
                Button { toggle(segment) } label: {
                    VStack(spacing: 9) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: segment.colorHex))
                                .frame(width: 10, height: 10)
                            Text(segment.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(GoldengoTheme.inkPrimary)
                            Spacer(minLength: 8)
                            Text(Money(amount: segment.amount, currency: currency).amountText())
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(GoldengoTheme.inkPrimary)
                            Text("\(percentage(of: segment))%")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(GoldengoTheme.inkMuted)
                                .frame(width: 34, alignment: .trailing)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.goldengoField)
                                Capsule()
                                    .fill(Color(hex: segment.colorHex))
                                    .frame(width: geometry.size.width * share(of: segment))
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(activeSegment == nil || activeSegment?.id == segment.id ? 1 : 0.48)
                .accessibilityLabel("\(segment.name), \(Money(amount: segment.amount, currency: currency).formatted()), \(percentage(of: segment)) percent")
            }
        }
        .padding(.horizontal, 14)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
        }
    }

    private func value(of segment: Segment) -> Double {
        (segment.amount as NSDecimalNumber).doubleValue
    }

    private func share(of segment: Segment) -> Double {
        let total = max((breakdown.total as NSDecimalNumber).doubleValue, 1)
        return min(max(value(of: segment) / total, 0), 1)
    }

    private func percentage(of segment: Segment) -> Int {
        Int((share(of: segment) * 100).rounded())
    }

    private func segment(at angle: Double) -> Segment? {
        var upperBound = 0.0
        for segment in segments {
            upperBound += value(of: segment)
            if angle <= upperBound { return segment }
        }
        return segments.last
    }

    private func selectSector(at location: CGPoint, in plotFrame: CGRect) {
        let center = CGPoint(x: plotFrame.midX, y: plotFrame.midY)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        let outerRadius = min(plotFrame.width, plotFrame.height) / 2

        guard distance <= outerRadius * 1.08 else { return }
        guard distance >= outerRadius * 0.46 else {
            clearSelection()
            return
        }

        // SectorMark starts at twelve o'clock and advances clockwise. `atan2(dx, -dy)` gives the
        // same orientation, then the fraction of a full turn maps onto the chart's cumulative sum.
        var radians = atan2(dx, -dy)
        if radians < 0 { radians += 2 * .pi }
        let total = segments.reduce(0.0) { $0 + value(of: $1) }
        guard total > 0, let tapped = segment(at: radians / (2 * .pi) * total) else { return }

        withAnimation(GoldengoMotion.quick) {
            selectedName = tapped.name
        }
    }

    private func toggle(_ segment: Segment) {
        withAnimation(GoldengoMotion.quick) {
            selectedName = selectedName == segment.name ? nil : segment.name
        }
    }

    private func clearSelection() {
        selectedName = nil
    }

    private var chartAccessibilityLabel: String {
        if let activeSegment {
            return "\(activeSegment.name), \(Money(amount: activeSegment.amount, currency: currency).formatted()), \(percentage(of: activeSegment)) percent"
        }
        return "Interactive spending chart, total \(Money(amount: breakdown.total, currency: currency).formatted())"
    }
}
