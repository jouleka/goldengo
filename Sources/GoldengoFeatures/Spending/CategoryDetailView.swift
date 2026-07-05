import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// A category's month expenses, its monthly-cap editor, and — for "Other" — a way to assign a real
/// category to each uncategorized expense. Pushed from `CategoryBreakdownView` when a row is tapped.
public struct CategoryDetailView: View {
    private let model: CategoryDetailModel
    private let currency: CurrencyCode
    /// Called when THIS category's cap just transitioned from no-cap to capped. The caller
    /// (`CategoryBreakdownView`, via `BudgetNotificationPermission.askOnce`) holds the actual
    /// app-wide once-ever gate, so this view doesn't need to know whether any other category was
    /// capped before — it stays UI-only/testable by inspection (the `UNUserNotificationCenter` call
    /// itself lives in `LocalNotificationScheduler`).
    private let onFirstCapSet: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which field owns the soft keyboard — one enum so any other tap can dismiss it
    /// (tap-outside rule; never a keyboard "Done" toolbar).
    private enum Field { case cap, newCategory }
    @FocusState private var focusedField: Field?

    @State private var editingCap = false
    @State private var capText = ""
    @State private var assigning: ExpenseSnapshot?

    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var eyebrowSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var emptyTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var emptySubSize: CGFloat = 13

    public init(model: CategoryDetailModel, currency: CurrencyCode, onFirstCapSet: @escaping () -> Void = {}) {
        self.model = model
        self.currency = currency
        self.onFirstCapSet = onFirstCapSet
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                capCard
                    .padding(.top, GoldengoTheme.Spacing.l)
                expensesSection
                    .padding(.top, GoldengoTheme.Spacing.l)
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.top, 8)
            .padding(.bottom, GoldengoTheme.Spacing.xl)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        // Tap anywhere outside a field clears focus — the house rule for keyboard dismissal.
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
#if canImport(UIKit)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .task { await model.load() }
        .sheet(item: $assigning) { snapshot in
            CategorizeExpenseView(
                expense: snapshot,
                existingCategoryNames: model.existingCategoryNames,
                onAssign: { name in Task { await model.assignCategory(name, toExpenseWithKey: snapshot.dedupeKey) } }
            )
        }
    }

    // MARK: - Top bar (chromeless back + serif title, matches HistoryView's pattern)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { dismiss() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Text("Spending").font(.system(size: 15))
                }
                .foregroundStyle(GoldengoTheme.inkMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
            Text(model.categoryName)
                .font(.system(size: titleSize, weight: .medium, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text(model.monthTitle)
                .font(.system(size: eyebrowSize, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .padding(.top, 4)
    }

    // MARK: - Monthly cap card

    @ViewBuilder
    private var capCard: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.s) {
            GoldengoSectionLabel("Monthly cap")
            if editingCap {
                capEditor
            } else {
                capSummaryRow
            }
        }
        .goldengoCard()
    }

    // Not `.accessibilityElement(children: .combine)`: this row contains a real interactive Button
    // (Edit / Set a monthly cap), and combining would swallow its button semantics into one static
    // label — VoiceOver users would lose the ability to activate it directly.
    private var capSummaryRow: some View {
        HStack(spacing: GoldengoTheme.Spacing.s) {
            if let cap = model.cap {
                GoldengoAmountText(Money(amount: cap, currency: currency).formatted(), role: .row)
                    .accessibilityLabel("Cap, \(Money(amount: cap, currency: currency).formatted())")
                Spacer(minLength: GoldengoTheme.Spacing.s)
                Button("Edit") { beginEditingCap() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GoldengoTheme.accent)
                    .accessibilityHint("Edit the monthly cap")
            } else {
                Text("No cap set")
                    .font(.system(size: 15))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                Spacer(minLength: GoldengoTheme.Spacing.s)
                Button("Set a monthly cap") { beginEditingCap() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GoldengoTheme.accent)
            }
        }
    }

    private var capEditor: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.s) {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                Text(currency.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                TextField("Amount", text: $capText)
#if canImport(UIKit)
                    .keyboardType(.decimalPad)
#endif
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .focused($focusedField, equals: .cap)
                    .submitLabel(.done)
                    .onSubmit { commitCap() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.goldengoField)
                    .clipShape(Capsule())
            }
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Button("Cancel") {
                    focusedField = nil
                    editingCap = false
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkMuted)

                if model.cap != nil {
                    Button("Clear cap") {
                        capText = ""
                        commitCap()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GoldengoTheme.danger)
                }

                Spacer(minLength: 0)

                Button("Save") { commitCap() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .disabled(!canSaveCap)
            }
        }
        .onAppear {
            capText = model.cap.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            focusedField = .cap
        }
    }

    private func beginEditingCap() {
        withAnimation(reduceMotion ? nil : GoldengoMotion.quick) { editingCap = true }
    }

    /// Parsed amount, or nil when the field isn't a positive number — mirrors `EditExpenseView`'s
    /// `parsedAmount`. Note: an EMPTY trimmed field also parses to nil here, but that case is
    /// handled separately in `commitCap` (empty means "clear the cap", not "invalid").
    private var parsedCap: Decimal? {
        let trimmed = capText.trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: trimmed), value > 0 else { return nil }
        return value
    }

    /// Save is only blocked when the field is non-empty but doesn't parse — an empty field is a
    /// valid "clear the cap" action, unlike `EditExpenseView` where an empty amount is never valid.
    private var canSaveCap: Bool {
        capText.trimmingCharacters(in: .whitespaces).isEmpty || parsedCap != nil
    }

    /// Empty clears the cap; a non-empty value only commits if it parses to a positive `Decimal` —
    /// otherwise the input is REJECTED (never silently wipes an existing cap on a typo). Saves,
    /// reloads, dismisses the keyboard via clearing focus (never a keyboard toolbar), and fires the
    /// one-time permission ask on the FIRST cap this category (or any) transitions to from no-cap.
    private func commitCap() {
        let trimmed = capText.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty || parsedCap != nil else { return }   // invalid, non-empty: reject
        let parsed = parsedCap
        focusedField = nil
        withAnimation(reduceMotion ? nil : GoldengoMotion.quick) { editingCap = false }
        Task {
            let wasFirstCap = await model.setCap(parsed)
            if wasFirstCap { onFirstCapSet() }
        }
    }

    // MARK: - Expenses list

    private var expensesSection: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.s) {
            GoldengoSectionLabel("Expenses")
            if model.expenses.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.expenses.enumerated()), id: \.element.dedupeKey) { index, expense in
                        if index > 0 {
                            Divider().overlay(GoldengoTheme.hairline)
                        }
                        expenseRow(expense)
                    }
                }
                .goldengoCard()
            }
        }
    }

    @ViewBuilder
    private func expenseRow(_ expense: ExpenseSnapshot) -> some View {
        if model.isOther {
            Button { assigning = expense } label: {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    expenseHomeRow(expense)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double tap to assign a category")
        } else {
            expenseHomeRow(expense)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundStyle(GoldengoTheme.inkMuted)
            Text("Nothing here")
                .font(.system(size: emptyTitleSize, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text("No spending in this category this month.")
                .font(.system(size: emptySubSize))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .goldengoCard()
    }
}
