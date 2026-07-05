import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The "Spending" breakdown screen: a month stepper, a donut chart with the period total at its
/// center, and ranked category rows with per-category budget progress bars.
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
    @ScaledMetric(relativeTo: .caption) private var budgetCaptionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var otherAffordanceSize: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The category row tapped for drill-in — pushes `CategoryDetailView`. Uses the AMBIENT
    /// `NavigationStack` (this view no longer owns one): it's entered by a push from Home's stack,
    /// same as `HistoryView`. The DEBUG preview entry wraps a stack around this view itself.
    @State private var selectedRow: CategoryBreakdownRow?

    public init(model: CategoryBreakdownModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title
                monthStepper
                    .padding(.top, GoldengoTheme.Spacing.l)
                donut
                rowsCard
                    .padding(.top, GoldengoTheme.Spacing.l)
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.top, 14)
            .padding(.bottom, GoldengoTheme.Spacing.xl)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .task { await model.load() }
#if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .navigationDestination(item: $selectedRow) { row in
            if let detailModel = model.detailModel(for: row) {
                CategoryDetailView(model: detailModel, currency: CurrencyCode(model.breakdown?.currencyCode ?? model.currency.rawValue),
                                   onFirstCapSet: { Task { await BudgetNotificationPermission.askOnce() } })
            }
        }
        // Popping back from a detail push may have changed a cap or reassigned an "Other" row —
        // reload so the row's bar/amount reflect it without a manual pull-to-refresh.
        .onChange(of: selectedRow) { _, newValue in
            if newValue == nil { Task { await model.load() } }
        }
    }

    // MARK: - Donut

    @ViewBuilder
    private var donut: some View {
        if let breakdown = model.breakdown, !breakdown.rows.isEmpty {
            SpendingDonut(rows: breakdown.rows, total: breakdown.total, currencyCode: breakdown.currencyCode)
                .frame(width: 160, height: 160)
                .frame(maxWidth: .infinity)
                .padding(.top, GoldengoTheme.Spacing.l)
        }
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
        let showsAffordance = row.name == "Other" || row.budget != nil
        return Button {
            selectedRow = row
        } label: {
            VStack(alignment: .leading, spacing: showsAffordance ? GoldengoTheme.Spacing.xs : 0) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
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
                if showsAffordance {
                    budgetAffordance(for: row, currency: currency)
                        .padding(.leading, 10 + GoldengoTheme.Spacing.s)   // align under the name, past the dot
                }
            }
            .padding(.vertical, GoldengoTheme.Spacing.s + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        // Spoken form includes the currency (VoiceOver reads common ISO codes/symbols by name, e.g.
        // "ALL" / "€"), matching the one existing amount-in-a-label precedent (RecentExpensesView's
        // dueRow), rather than the plain-magnitude `amountText()` used for the visible row text.
        .accessibilityLabel(accessibilityLabel(for: row, currency: currency, percentText: percentText))
        .accessibilityHint("Double tap to see this category's expenses")
    }

    // MARK: - Budget affordance (progress bar / caption / "Other" categorize prompt)

    @ViewBuilder
    private func budgetAffordance(for row: CategoryBreakdownRow, currency: CurrencyCode) -> some View {
        if row.name == "Other" {
            Text("Tap to categorize this spend")
                .font(.system(size: otherAffordanceSize, weight: .medium))
                .foregroundStyle(GoldengoTheme.accent)
        } else if let budget = row.budget {
            budgetBar(for: row, budget: budget, currency: currency)
        }
        // budget == nil and name != "Other": no bar, unchanged.
    }

    private func budgetBar(for row: CategoryBreakdownRow, budget: Decimal, currency: CurrencyCode) -> some View {
        let spentDouble = (row.spent as NSDecimalNumber).doubleValue
        let budgetDouble = (budget as NSDecimalNumber).doubleValue
        let fraction = budgetDouble > 0 ? min(1.0, spentDouble / budgetDouble) : 0
        let tint = budgetLevelColor(row.level)
        let caption: String = {
            if row.level == .over {
                let over = Money(amount: row.spent - budget, currency: currency).amountText()
                return "over by \(over)"
            } else {
                let remaining = Money(amount: budget - row.spent, currency: currency).amountText()
                return "\(remaining) left"
            }
        }()
        return HStack(spacing: GoldengoTheme.Spacing.s) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.goldengoField)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint)
                        .frame(width: geo.size.width * fraction)
                        .animation(reduceMotion ? nil : GoldengoMotion.standard, value: fraction)
                }
            }
            .frame(height: 6)
            Text(caption)
                .font(.system(size: budgetCaptionSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func budgetLevelColor(_ level: BudgetLevel) -> Color {
        switch level {
        case .ok: return GoldengoTheme.income
        case .near: return GoldengoTheme.accent
        case .over: return GoldengoTheme.danger
        case .noBudget: return GoldengoTheme.inkMuted
        }
    }

    private func accessibilityLabel(for row: CategoryBreakdownRow, currency: CurrencyCode, percentText: String) -> String {
        let base = "\(row.name), \(Money(amount: row.spent, currency: currency).formatted()), \(Int((row.share * 100).rounded())) percent"
        guard let budget = row.budget else { return base }
        switch row.level {
        case .over:
            let over = Money(amount: row.spent - budget, currency: currency).formatted()
            return "\(base), over by \(over)"
        default:
            let remaining = Money(amount: budget - row.spent, currency: currency).formatted()
            return "\(base), \(remaining) left"
        }
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
