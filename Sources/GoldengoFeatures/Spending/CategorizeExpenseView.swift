import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The "assign a category" sheet for a single "Other" expense. It keeps recent categories as fast
/// suggestions while making the full searchable taxonomy a permanent, obvious action.
struct CategorizeExpenseView: View {
    let expense: ExpenseSnapshot
    let existingCategoryNames: [String]
    let onAssign: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingAllCategories = false
    @State private var rememberMerchant = true

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                GoldengoSectionLabel("Categorize transaction")
                transactionCard

                if let merchant = expense.merchantName, !merchant.isEmpty {
                    Toggle(isOn: $rememberMerchant) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remember for \(merchant)").font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                            Text("Future transactions will use your choice.")
                                .font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                        }
                    }
                    .tint(GoldengoTheme.accent)
                    .padding(14)
                    .background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !suggestedCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        GoldengoSectionLabel("Suggested")
                        categoryChips
                    }
                }

                Button { showingAllCategories = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                        Text("Choose from all categories")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .padding(.horizontal, 15)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(GoldengoTheme.accentLine, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(GoldengoTheme.Spacing.m)
            .background(Color.goldengoBackground.ignoresSafeArea())
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAllCategories) {
                SpendingCategoryPicker(selectedCategory: nil, merchantName: expense.merchantName) { category, remember in
                    assign(category, remember: remember)
                }
            }
        }
    }

    private var transactionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(GoldengoTheme.accent)
                .frame(width: 40, height: 40)
                .background(GoldengoTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .lineLimit(1)
                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }

            Spacer(minLength: 8)

            Text(Money(amount: expense.amount, currency: CurrencyCode(expense.currencyCode)).formatted())
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(GoldengoTheme.inkPrimary)
        }
        .padding(14)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
        }
    }

    private var suggestedCategories: [String] {
        Array(existingCategoryNames
            .filter { $0.caseInsensitiveCompare("Other") != .orderedSame }
            .prefix(6))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(suggestedCategories, id: \.self) { name in
                    SelectableChip(name, systemImage: GoldengoCategoryIcon.symbol(for: name), isSelected: false) {
                        assign(name, remember: rememberMerchant)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func assign(_ name: String, remember: Bool) {
        onAssign(name, remember)
        dismiss()
    }
}
