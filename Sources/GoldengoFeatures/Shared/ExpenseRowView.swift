import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

// Shared expense-row layout, used by both the Home "Recent" list and the History browser so the two
// stay visually identical. Pure layout (no instance state) — extracted from RecentExpensesView.

/// Reusable row layout matching home.jsx's Row: tile + title/sub column + right content.
/// gap=14, padding 9×4, title 15.5/medium ink, sub 12.5 ink-muted.
@ViewBuilder
func homeRow(
    icon: String,
    title: String,
    sub: String,
    recurring: Bool = false,
    fundedBy: String? = nil,
    fundedByColorIndex: Int? = nil,
    isDraft: Bool = false,
    accentRight: Bool = false,
    rightContent: AnyView? = nil
) -> some View {
    HStack(alignment: .center, spacing: 14) {
        GoldengoIconTile(icon)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .lineLimit(1)
                if recurring {
                    Image(systemName: "repeat")
                        .font(.system(size: 13))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .accessibilityLabel("Recurring")
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Text(sub)
                    .font(.system(size: 12.5))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                if let fb = fundedBy, let idx = fundedByColorIndex {
                    // funded-by pill: field capsule, colored dot, name — matches home.jsx
                    HStack(spacing: 5) {
                        Circle()
                            .fill(GoldengoTheme.sourceColor(idx))
                            .frame(width: 6, height: 6)
                        Text(fb)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.goldengoField)
                    .clipShape(Capsule())
                }
            }
        }
        Spacer(minLength: 0)
        if accentRight {
            Image(systemName: "plus.circle")
                .font(.system(size: 24))
                .foregroundStyle(GoldengoTheme.accent)
        } else if let rv = rightContent {
            rv
        }
    }
    .padding(.vertical, 9)
    // No horizontal padding: the row's leading/trailing come from the list row insets (Spacing.m),
    // so the icon, day-header text, and amount all share one 16pt screen margin — no 4pt drift.
    .opacity(isDraft ? 0.72 : 1)
}

/// The inner label of a collapsible day/month section header: title · count on the left, a chevron
/// that rotates to signal fold state on the right. Shared by Home's Recent list and the History
/// browser so the two read identically. Wrap it in a Button (toggling collapse) at each call site.
@ViewBuilder
func collapsibleGroupHeaderLabel(title: String, count: Int, collapsed: Bool) -> some View {
    HStack(spacing: 7) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GoldengoTheme.inkMuted)
        Text("·  \(count)")
            .font(.system(size: 13))
            .foregroundStyle(GoldengoTheme.inkMuted.opacity(0.7))
        Spacer(minLength: 0)
        Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GoldengoTheme.inkMuted)
            .rotationEffect(.degrees(collapsed ? -90 : 0))
    }
    .padding(.top, 16)
    .padding(.bottom, 7)
    .contentShape(Rectangle())
}

/// A recent/history expense row: category icon, title, category (or "→ wallet"), and the signed,
/// kind-coloured amount on the right.
func expenseHomeRow(_ r: ExpenseSnapshot) -> some View {
    let amountStr = Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted()
    let amountView: AnyView
    switch r.kind {
    case .income:
        amountView = AnyView(GoldengoAmountText("+" + amountStr, role: .row, color: GoldengoTheme.income))
    // Muted like transfers: money that MOVED, not money spent or earned.
    case .transfer, .lent:
        amountView = AnyView(GoldengoAmountText(amountStr, role: .row, color: GoldengoTheme.inkMuted))
    case .repayment:
        amountView = AnyView(GoldengoAmountText("+" + amountStr, role: .row, color: GoldengoTheme.income))
    default:
        amountView = AnyView(GoldengoAmountText(amountStr, role: .row))
    }

    let subText: String
    switch r.kind {
    case .transfer:  subText = "→ wallet"
    case .lent:      subText = "lent · owed to you"
    case .repayment: subText = "paid back"
    default:         subText = r.categoryName ?? "Other"
    }

    let icon: String
    switch r.kind {
    case .lent:      icon = "person"
    case .repayment: icon = "arrow.uturn.left"
    default:         icon = GoldengoCategoryIcon.symbol(for: r.categoryName)
    }

    return homeRow(
        icon: icon,
        title: r.displayTitle,
        sub: subText,
        recurring: r.subscriptionName != nil,
        fundedBy: r.fundedBy,
        fundedByColorIndex: r.fundedByColorIndex,
        isDraft: false,
        accentRight: false,
        rightContent: amountView
    )
}
