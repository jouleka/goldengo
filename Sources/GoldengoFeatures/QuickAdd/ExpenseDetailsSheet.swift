import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Optional metadata is intentionally kept off the primary expense canvas. This sheet gives it a
/// calm, conventional form without making the fast amount/category path feel unfinished.
struct ExpenseDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var merchant: String
    @Binding var note: String
    @Binding var date: Date
    @Binding var contextName: String?
    @Binding var splits: [TransactionSplit]
    let total: Decimal
    let currency: CurrencyCode

    @State private var showSplitEditor = false

    @FocusState private var focusedField: Field?
    private enum Field { case merchant, note }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Optional details")
                            .font(.custom("Georgia", size: 24).weight(.medium))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("Add context only when it helps future you.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }

                    VStack(spacing: 0) {
                        detailField(
                            title: "Merchant",
                            placeholder: "Where did you spend?",
                            text: $merchant,
                            field: .merchant,
                            icon: "storefront"
                        )

                        Divider().overlay(GoldengoTheme.hairline)

                        detailField(
                            title: "Note",
                            placeholder: "Anything worth remembering?",
                            text: $note,
                            field: .note,
                            icon: "note.text"
                        )

                        Divider().overlay(GoldengoTheme.hairline)

                        HStack(spacing: 13) {
                            detailIcon("calendar")
                            Text("Date")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(GoldengoTheme.inkPrimary)
                            Spacer()
                            DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                                .labelsHidden()
                                .tint(GoldengoTheme.accent)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 58)
                    }
                    .background(Color.goldengoSurface)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                            .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ContextPicker(selection: $contextName)

                        Divider().overlay(GoldengoTheme.hairline)

                        Button { showSplitEditor = true } label: {
                            HStack(spacing: 13) {
                                detailIcon("rectangle.split.2x1")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Split purchase")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(GoldengoTheme.inkPrimary)
                                    Text(splitCaption)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(GoldengoTheme.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(GoldengoTheme.inkMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color.goldengoSurface)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                            .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
                    }
                }
                .padding(GoldengoTheme.Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showSplitEditor) {
                SplitEditorSheet(splits: $splits, total: total, currency: currency)
                    .presentationDetents([.large])
            }
        }
    }

    private var splitCaption: String {
        guard total > 0 else { return "Enter an amount first" }
        guard !splits.isEmpty else { return "Divide one payment across categories" }
        return "\(splits.count) categories · \(Money(amount: total, currency: currency).formatted())"
    }

    private func detailField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        icon: String
    ) -> some View {
        HStack(spacing: 13) {
            detailIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                TextField(placeholder, text: text)
                    .focused($focusedField, equals: field)
                    .submitLabel(field == .merchant ? .next : .done)
                    .onSubmit {
                        focusedField = field == .merchant ? .note : nil
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
    }

    private func detailIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(GoldengoTheme.accent)
            .frame(width: 32, height: 32)
            .background(GoldengoTheme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SplitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var splits: [TransactionSplit]
    let total: Decimal
    let currency: CurrencyCode

    @State private var drafts: [TransactionSplit]
    @State private var categoryIndex: Int?

    init(splits: Binding<[TransactionSplit]>, total: Decimal, currency: CurrencyCode) {
        _splits = splits
        self.total = total
        self.currency = currency
        let initial = splits.wrappedValue.isEmpty
            ? [TransactionSplit(amount: 0, categoryName: ""), TransactionSplit(amount: 0, categoryName: "")]
            : splits.wrappedValue
        _drafts = State(initialValue: initial)
    }

    private var allocated: Decimal { drafts.reduce(Decimal.zero) { $0 + $1.amount } }
    private var remaining: Decimal { total - allocated }
    private var isValid: Bool {
        total > 0 && remaining == 0
            && drafts.count >= 2
            && drafts.allSatisfy { $0.amount > 0 && !$0.categoryName.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Split this purchase")
                            .font(.custom("Georgia", size: 25).weight(.medium))
                        Text("The payment stays whole. Only your spending report is divided.")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(drafts.indices), id: \.self) { index in
                            splitRow(index)
                            if index != drafts.indices.last { Divider().overlay(GoldengoTheme.hairline) }
                        }
                    }
                    .background(Color.goldengoSurface)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))

                    HStack {
                        Button { drafts.append(.init(amount: 0, categoryName: "")) } label: {
                            Label("Add category", systemImage: "plus")
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(remaining == 0 ? "Fully allocated" : "Remaining")
                                .foregroundStyle(remaining == 0 ? GoldengoTheme.income : GoldengoTheme.inkMuted)
                            Text(Money(amount: remaining, currency: currency).formatted())
                                .monospacedDigit().foregroundStyle(GoldengoTheme.inkPrimary)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(14)
                    .background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))

                    if !splits.isEmpty {
                        Button(role: .destructive) { splits = []; dismiss() } label: {
                            Text("Remove split").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(GoldengoTheme.Spacing.m)
            }
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Split purchase")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { splits = drafts; dismiss() }
                        .fontWeight(.semibold).disabled(!isValid)
                }
            }
            .sheet(isPresented: Binding(get: { categoryIndex != nil }, set: { if !$0 { categoryIndex = nil } })) {
                SpendingCategoryPicker(selectedCategory: categoryIndex.flatMap { drafts.indices.contains($0) ? drafts[$0].categoryName : nil }) { category in
                    if let index = categoryIndex, drafts.indices.contains(index) { drafts[index].categoryName = category }
                    categoryIndex = nil
                }
                .presentationDetents([.large])
            }
        }
    }

    private func splitRow(_ index: Int) -> some View {
        HStack(spacing: 10) {
            Button { categoryIndex = index } label: {
                HStack(spacing: 8) {
                    Image(systemName: drafts[index].categoryName.isEmpty ? "tag" : SpendingCategoryCatalog.classify(drafts[index].categoryName).icon)
                    Text(drafts[index].categoryName.isEmpty ? "Choose" : drafts[index].categoryName).lineLimit(1)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(drafts[index].categoryName.isEmpty ? GoldengoTheme.accent : GoldengoTheme.inkPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            TextField("0", value: $drafts[index].amount, format: .number)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 86)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif

            if drafts.count > 2 {
                Button { drafts.remove(at: index) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(GoldengoTheme.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
    }
}
