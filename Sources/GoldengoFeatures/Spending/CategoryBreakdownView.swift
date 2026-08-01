import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// A calm monthly overview: one summary, one purpose strip, then category cards. The screen keeps
/// every drill-in and budget affordance while avoiding duplicate group/leaf labels and dashboard
/// tiles that repeat the chart.
public struct CategoryBreakdownView: View {
    private let model: CategoryBreakdownModel

    @ScaledMetric(relativeTo: .headline) private var monthLabelSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var rowTextSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var percentTextSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var budgetCaptionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var affordanceSize: CGFloat = 12.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private struct DetailRoute: Identifiable, Hashable {
        let row: CategoryBreakdownRow
        let startsCategorizing: Bool
        var id: String { "\(row.id):\(startsCategorizing)" }
    }

    @State private var selectedRoute: DetailRoute?
    @State private var showingChartExplorer = false

    public init(model: CategoryBreakdownModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            screenHeader
            monthStepper
                .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let breakdown = model.breakdown, !breakdown.rows.isEmpty {
                        overviewCard(breakdown)

                        GoldengoSectionLabel("Categories")
                            .padding(.horizontal, 2)

                        categoryCards
                    } else {
                        emptyCard
                            .padding(.top, 22)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, GoldengoTheme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.top, 12)
        .background(Color.goldengoBackground.ignoresSafeArea())
        .task { await model.load() }
#if canImport(UIKit)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .navigationDestination(item: $selectedRoute) { route in
            if let detailModel = model.detailModel(for: route.row) {
                CategoryDetailView(
                    model: detailModel,
                    currency: CurrencyCode(model.breakdown?.currencyCode ?? model.currency.rawValue),
                    startsCategorizing: route.startsCategorizing,
                    onFirstCapSet: { Task { await BudgetNotificationPermission.askOnce() } }
                )
            }
        }
        .onChange(of: selectedRoute) { _, newValue in
            if newValue == nil { Task { await model.load() } }
        }
        .sheet(isPresented: $showingChartExplorer) {
            if let breakdown = model.breakdown {
                SpendingChartExplorer(breakdown: breakdown)
            }
        }
    }

    // MARK: - Header and month

    private var screenHeader: some View {
        ZStack {
            Text("Spending")
                .font(.custom("Georgia", size: 21).weight(.medium))
                .foregroundStyle(GoldengoTheme.inkPrimary)

            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.goldengoField)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close spending")
            }
        }
    }

    private var monthStepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", enabled: true, label: "Previous month") {
                Task { await model.step(-1) }
            }
            Spacer()
            Text(model.monthTitle)
                .font(.system(size: monthLabelSize, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .contentTransition(.opacity)
            Spacer()
            stepButton("chevron.right", enabled: !model.isCurrentMonth, label: "Next month") {
                Task { await model.step(1) }
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 42)
        .background(Color.goldengoField)
        .clipShape(Capsule())
    }

    private func stepButton(_ icon: String, enabled: Bool, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .frame(width: 38, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.22)
        .accessibilityLabel(label)
    }

    // MARK: - Overview

    private func overviewCard(_ breakdown: CategoryBreakdown) -> some View {
        let currency = CurrencyCode(breakdown.currencyCode)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SPENT")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(GoldengoTheme.inkMuted)

                    Text(Money(amount: breakdown.spendingTotal, currency: currency).formatted())
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)
                        .foregroundStyle(GoldengoTheme.inkPrimary)

                    if breakdown.investedTotal > 0 {
                        Label(
                            "\(Money(amount: breakdown.investedTotal, currency: currency).amountText()) invested",
                            systemImage: MoneyPurpose.wealth.icon
                        )
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(hex: MoneyPurpose.wealth.colorHex))
                    } else {
                        Text("No investments this month")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }

                Spacer(minLength: 0)

                Button { showingChartExplorer = true } label: {
                    VStack(spacing: 5) {
                        SpendingDonut(
                            rows: breakdown.rows,
                            total: breakdown.total,
                            currencyCode: breakdown.currencyCode,
                            showsCenterTotal: false
                        )
                        .frame(width: 116, height: 116)
                        .accessibilityHidden(true)

                        Label("Explore", systemImage: "hand.tap.fill")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(GoldengoTheme.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Explore spending chart")
                .accessibilityHint("Opens an interactive chart with category and purpose views")
            }

            purposeStrip(breakdown)
        }
        .padding(16)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
        }
    }

    private struct PurposeSlice: Identifiable {
        let purpose: MoneyPurpose
        let amount: Decimal
        var id: MoneyPurpose { purpose }
        var title: String {
            switch purpose {
            case .essential: return "Essential"
            case .lifestyle: return "Lifestyle"
            case .wealth: return "Invested"
            case .waste: return "Risk"
            case .other: return "Other"
            }
        }
    }

    private func slices(for breakdown: CategoryBreakdown) -> [PurposeSlice] {
        [
            PurposeSlice(purpose: .essential, amount: breakdown.essentialTotal),
            PurposeSlice(purpose: .lifestyle, amount: breakdown.lifestyleTotal),
            PurposeSlice(purpose: .wealth, amount: breakdown.investedTotal),
            PurposeSlice(purpose: .waste, amount: breakdown.wasteTotal),
            PurposeSlice(purpose: .other, amount: breakdown.otherTotal),
        ]
        .filter { $0.amount > 0 }
    }

    private func purposeStrip(_ breakdown: CategoryBreakdown) -> some View {
        let items = slices(for: breakdown)
        let total = max((breakdown.total as NSDecimalNumber).doubleValue, 1)

        return VStack(spacing: 9) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let amount = (item.amount as NSDecimalNumber).doubleValue
                        Rectangle()
                            .fill(Color(hex: item.purpose.colorHex))
                            .frame(width: geometry.size.width * amount / total)
                            .offset(x: geometry.size.width * precedingFraction(index, in: items, total: total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Spacer(minLength: 2) }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: item.purpose.colorHex))
                            .frame(width: 6, height: 6)
                        Text("\(item.title) \(percentage(item.amount, total: total))%")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func precedingFraction(_ index: Int, in items: [PurposeSlice], total: Double) -> CGFloat {
        guard index > 0 else { return 0 }
        let preceding = items[..<index].reduce(0.0) { partial, item in
            partial + (item.amount as NSDecimalNumber).doubleValue
        }
        return CGFloat(preceding / total)
    }

    private func percentage(_ amount: Decimal, total: Double) -> Int {
        Int((((amount as NSDecimalNumber).doubleValue / total) * 100).rounded())
    }

    // MARK: - Category cards

    private struct RowGroup: Identifiable {
        let name: String
        let icon: String
        let colorHex: String
        let purposeTitle: String
        let purposeColorHex: String
        let spent: Decimal
        let share: Double
        let rows: [CategoryBreakdownRow]
        var id: String { name }
    }

    private var groupedRows: [RowGroup] {
        let rows = model.breakdown?.rows ?? []
        let total = max(((model.breakdown?.total ?? 0) as NSDecimalNumber).doubleValue, 1)

        return Dictionary(grouping: rows, by: \.groupName)
            .map { name, groupRows in
                let purposes = Set(groupRows.map(\.purpose))
                let singlePurpose = purposes.count == 1 ? purposes.first : nil
                let spent = groupRows.reduce(Decimal(0)) { $0 + $1.spent }
                return RowGroup(
                    name: name,
                    icon: groupRows.first?.icon ?? "tag",
                    colorHex: groupRows.first?.colorHex ?? "#81786C",
                    purposeTitle: singlePurpose?.title ?? "Mixed use",
                    purposeColorHex: singlePurpose?.colorHex ?? MoneyPurpose.other.colorHex,
                    spent: spent,
                    share: (spent as NSDecimalNumber).doubleValue / total,
                    rows: groupRows.sorted { $0.spent > $1.spent }
                )
            }
            .sorted { $0.spent > $1.spent }
    }

    private var categoryCards: some View {
        LazyVStack(spacing: 10) {
            ForEach(groupedRows) { group in
                groupCard(group)
            }
        }
    }

    @ViewBuilder
    private func groupCard(_ group: RowGroup) -> some View {
        if let row = group.rows.first, group.rows.count == 1 {
            Button { openDetail(row) } label: {
                VStack(alignment: .leading, spacing: 11) {
                    groupHeader(group, displayName: row.name, showsChevron: true)
                    groupShareBar(group)
                    budgetAffordance(for: row, currency: displayCurrency)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.goldengoSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: row, currency: displayCurrency))
            .accessibilityHint(row.groupName == "Other"
                               ? "Double tap to start categorizing these transactions"
                               : "Double tap to see this category's expenses")
        } else {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 11) {
                    groupHeader(group, displayName: group.name, showsChevron: false)
                    groupShareBar(group)
                }
                .padding(14)

                Divider()
                    .overlay(GoldengoTheme.hairline)
                    .padding(.leading, 61)

                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                            .overlay(GoldengoTheme.hairline)
                            .padding(.leading, 45)
                    }
                    categoryRow(row)
                }
            }
            .background(Color.goldengoSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
            }
        }
    }

    private func groupHeader(_ group: RowGroup, displayName: String, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: group.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: group.colorHex))
                .frame(width: 36, height: 36)
                .background(Color(hex: group.colorHex).opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .lineLimit(1)
                Text(group.purposeTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(hex: group.purposeColorHex))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money(amount: group.spent, currency: displayCurrency).amountText())
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                Text("\(Int((group.share * 100).rounded()))%")
                    .font(.system(size: percentTextSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GoldengoTheme.inkMuted.opacity(0.75))
            }
        }
    }

    private func groupShareBar(_ group: RowGroup) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.goldengoField)
                Capsule()
                    .fill(Color(hex: group.colorHex))
                    .frame(width: geometry.size.width * min(max(group.share, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func categoryRow(_ row: CategoryBreakdownRow) -> some View {
        Button { openDetail(row) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(Color(hex: row.purpose.colorHex))
                        .frame(width: 7, height: 7)
                    Text(row.name)
                        .font(.system(size: rowTextSize, weight: .medium))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Money(amount: row.spent, currency: displayCurrency).amountText())
                        .font(.system(size: rowTextSize, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("\(Int((row.share * 100).rounded()))%")
                        .font(.system(size: percentTextSize))
                        .monospacedDigit()
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .frame(minWidth: 30, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GoldengoTheme.inkMuted.opacity(0.7))
                }
                budgetAffordance(for: row, currency: displayCurrency)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: row, currency: displayCurrency))
        .accessibilityHint(row.groupName == "Other"
                           ? "Double tap to start categorizing these transactions"
                           : "Double tap to see this category's expenses")
    }

    private func openDetail(_ row: CategoryBreakdownRow) {
        selectedRoute = DetailRoute(row: row, startsCategorizing: row.groupName == "Other")
    }

    private var displayCurrency: CurrencyCode {
        CurrencyCode(model.breakdown?.currencyCode ?? model.currency.rawValue)
    }

    // MARK: - Budgets and semantics

    @ViewBuilder
    private func budgetAffordance(for row: CategoryBreakdownRow, currency: CurrencyCode) -> some View {
        if row.name == "Other" {
            Label("Categorize transactions", systemImage: "wand.and.stars")
                .font(.system(size: affordanceSize, weight: .semibold))
                .foregroundStyle(GoldengoTheme.accent)
        } else if let budget = row.budget {
            budgetBar(for: row, budget: budget, currency: currency)
        } else if row.purpose == .wealth {
            Label("Investment contribution", systemImage: row.purpose.icon)
                .font(.system(size: affordanceSize, weight: .semibold))
                .foregroundStyle(Color(hex: row.purpose.colorHex))
        } else if row.purpose == .waste {
            Label("Flagged as waste & risk", systemImage: row.purpose.icon)
                .font(.system(size: affordanceSize, weight: .semibold))
                .foregroundStyle(Color(hex: row.purpose.colorHex))
        }
    }

    private func budgetBar(for row: CategoryBreakdownRow, budget: Decimal, currency: CurrencyCode) -> some View {
        let spentDouble = (row.spent as NSDecimalNumber).doubleValue
        let budgetDouble = (budget as NSDecimalNumber).doubleValue
        let fraction = budgetDouble > 0 ? min(1.0, spentDouble / budgetDouble) : 0
        let tint = budgetLevelColor(row.level)
        let caption: String = {
            if row.level == .over {
                return "over by \(Money(amount: row.spent - budget, currency: currency).amountText())"
            }
            return "\(Money(amount: budget - row.spent, currency: currency).amountText()) left"
        }()

        return HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.goldengoField)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * fraction)
                        .animation(reduceMotion ? nil : GoldengoMotion.standard, value: fraction)
                }
            }
            .frame(height: 5)
            Text(caption)
                .font(.system(size: budgetCaptionSize, weight: .semibold))
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

    private func accessibilityLabel(for row: CategoryBreakdownRow, currency: CurrencyCode) -> String {
        let base = "\(row.name), \(Money(amount: row.spent, currency: currency).formatted()), \(Int((row.share * 100).rounded())) percent"
        guard let budget = row.budget else { return base }
        if row.level == .over {
            return "\(base), over by \(Money(amount: row.spent - budget, currency: currency).formatted())"
        }
        return "\(base), \(Money(amount: budget - row.spent, currency: currency).formatted()) left"
    }

    private var emptyCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "chart.pie")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkMuted)
            Text("Nothing spent")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text("This month has no spending yet.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
    }
}
