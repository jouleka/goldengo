import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The "Spending" breakdown screen: a month stepper, the period total, and ranked category rows.
/// Donut chart + budget progress bars land in later tasks — this is rows only.
public struct CategoryBreakdownView: View {
    private let model: CategoryBreakdownModel

    // Rest of the app's fixed-size fonts (homeRow, HistoryView, GoldengoAmountText, etc.) don't scale
    // with Dynamic Type — an existing, unexamined gap this task explicitly asks not to repeat here.
    // @ScaledMetric keeps the same base point sizes at the default text setting but grows them with
    // the user's preference, confined to this new screen only (no shared component touched).
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .headline) private var monthLabelSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var rowTextSize: CGFloat = 15.5
    @ScaledMetric(relativeTo: .footnote) private var percentTextSize: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var emptyTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var emptySubSize: CGFloat = 13

    public init(model: CategoryBreakdownModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title
                monthStepper
                    .padding(.top, GoldengoTheme.Spacing.l)
                totalText
                    .padding(.top, GoldengoTheme.Spacing.s)
                rowsCard
                    .padding(.top, GoldengoTheme.Spacing.l)
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.top, 14)
            .padding(.bottom, GoldengoTheme.Spacing.xl)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .task { await model.load() }
    }

    // MARK: - Title

    private var title: some View {
        Text("Spending")
            .font(.system(size: titleSize, weight: .medium, design: .serif))
            .foregroundStyle(GoldengoTheme.accent)
    }

    // MARK: - Month stepper (‹ month yyyy ›) — mirrors History's periodStepper

    private var monthStepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", enabled: true, label: "Previous month") {
                Task { await model.step(-1) }
            }
            Spacer()
            Text(model.monthTitle)
                .font(.system(size: monthLabelSize, weight: .medium, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .contentTransition(.opacity)
            Spacer()
            stepButton("chevron.right", enabled: !model.isCurrentMonth, label: "Next month") {
                Task { await model.step(1) }
            }
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel(label)
    }

    // MARK: - Period total

    private var totalText: some View {
        Group {
            if let breakdown = model.breakdown {
                GoldengoAmountText(
                    Money(amount: breakdown.total, currency: CurrencyCode(breakdown.currencyCode)).formatted(),
                    role: .title
                )
            } else {
                // No data yet (still loading, or the store threw) — an empty-but-stable placeholder,
                // never a crash or a stale figure from another month.
                GoldengoAmountText(Money(amount: 0, currency: model.currency).formatted(), role: .title)
            }
        }
    }

    // MARK: - Ranked rows

    private var rowsCard: some View {
        Group {
            if let rows = model.breakdown?.rows, !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().overlay(GoldengoTheme.hairline)
                        }
                        categoryRow(row)
                    }
                }
                .goldengoCard()
            } else {
                emptyCard
            }
        }
    }

    private func categoryRow(_ row: CategoryBreakdownRow) -> some View {
        let currency = CurrencyCode(model.breakdown?.currencyCode ?? model.currency.rawValue)
        let amountText = Money(amount: row.spent, currency: currency).amountText()
        let percentText = "\(Int((row.share * 100).rounded()))%"
        return HStack(spacing: GoldengoTheme.Spacing.s) {
            Circle()
                .fill(Color(hex: row.colorHex))
                .frame(width: 10, height: 10)
            Text(row.name)
                .font(.system(size: rowTextSize, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .lineLimit(1)
            Spacer(minLength: GoldengoTheme.Spacing.s)
            Text(amountText)
                .font(.system(size: rowTextSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text(percentText)
                .font(.system(size: percentTextSize))
                .monospacedDigit()
                .foregroundStyle(GoldengoTheme.inkMuted)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.vertical, GoldengoTheme.Spacing.s + 2)
        .accessibilityElement(children: .combine)
        // Spoken form includes the currency (VoiceOver reads common ISO codes/symbols by name, e.g.
        // "ALL" / "€"), matching the one existing amount-in-a-label precedent (RecentExpensesView's
        // dueRow), rather than the plain-magnitude `amountText()` used for the visible row text.
        .accessibilityLabel("\(row.name), \(Money(amount: row.spent, currency: currency).formatted()), \(Int((row.share * 100).rounded())) percent")
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.pie")
                .font(.system(size: 26))
                .foregroundStyle(GoldengoTheme.inkMuted)
            Text("Nothing here")
                .font(.system(size: emptyTitleSize, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text("No spending in this month.")
                .font(.system(size: emptySubSize))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .goldengoCard()
    }
}
