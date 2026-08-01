import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// A calm confirmation surface: total first, then the two likely corrections, then optional
/// line-item intelligence. OCR never saves silently and advanced splitting never blocks the
/// ordinary one-category path.
public struct ReceiptReviewView: View {
    @State private var model: ReceiptScanModel
    let onDone: () -> Void
    @FocusState private var focusedField: Field?
    @State private var categoryTarget: CategoryTarget?

    private enum Field: Hashable { case amount, merchant }
    private struct CategoryTarget: Identifiable {
        let id = UUID()
        let itemID: String?
    }

    public init(model: ReceiptScanModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    amountCard
                    detailsCard
                    categoryCard
                    itemsCard
                }
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Review receipt")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!model.canSave)
                }
            }
            .sheet(item: $categoryTarget) { target in
                SpendingCategoryPicker(selectedCategory: selectedCategory(for: target)) { category in
                    if let itemID = target.itemID,
                       let index = model.items.firstIndex(where: { $0.id == itemID }) {
                        model.items[index].categoryName = category
                    } else {
                        model.selectedCategory = category
                    }
                }
                .presentationDetents([.large])
            }
            .alert("Couldn’t save the receipt", isPresented: Binding(
                get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } }
            )) { Button("OK") { model.errorText = nil } } message: { Text(model.errorText ?? "") }
        }
        .tint(GoldengoTheme.accent)
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            GoldengoSectionLabel("TOTAL")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.currency.symbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                TextField("0", text: $model.amountString)
                    .focused($focusedField, equals: .amount)
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
            }
            if model.amountWasUnreadable {
                Label("The total was unclear—enter it before saving.", systemImage: "viewfinder.circle")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GoldengoTheme.accent)
            } else {
                Text("Check the number once; everything else is optional.")
                    .font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
        .goldengoCard(padding: 18)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "storefront").foregroundStyle(GoldengoTheme.accent).frame(width: 24)
                TextField("Merchant", text: $model.merchant)
                    .focused($focusedField, equals: .merchant)
                    .font(.system(size: 15.5, weight: .medium))
            }
            Divider().overlay(GoldengoTheme.hairline).padding(.vertical, 13)
            HStack(spacing: 12) {
                Image(systemName: "calendar").foregroundStyle(GoldengoTheme.accent).frame(width: 24)
                DatePicker("Purchase date", selection: Binding(get: { model.date ?? .now }, set: { model.date = $0 }),
                           displayedComponents: .date)
                    .font(.system(size: 15.5, weight: .medium))
            }
        }
        .goldengoCard(padding: 16)
    }

    private var categoryCard: some View {
        Button { categoryTarget = CategoryTarget(itemID: nil) } label: {
            HStack(spacing: 13) {
                let category = model.selectedCategory ?? "Choose category"
                Image(systemName: model.selectedCategory.map(GoldengoCategoryIcon.symbol(for:)) ?? "tag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Overall category").font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                    Text(category).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(GoldengoTheme.inkMuted)
            }
            .goldengoCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Split by item").font(.system(size: 16, weight: .semibold))
                    Text(itemCaption).font(.system(size: 12.5)).foregroundStyle(splitCaptionColor)
                }
                Spacer()
                Toggle("Split by item", isOn: $model.useItemSplits).labelsHidden().tint(GoldengoTheme.accent)
            }

            if model.useItemSplits {
                Divider().overlay(GoldengoTheme.hairline)
                ForEach($model.items) { $item in
                    receiptItemRow(item: $item)
                    if item.id != model.items.last?.id { Divider().overlay(GoldengoTheme.hairline) }
                }
                Button { model.addItem() } label: {
                    Label("Add missing item", systemImage: "plus.circle.fill")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(GoldengoTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .goldengoCard(padding: 16)
    }

    private func receiptItemRow(item: Binding<ReceiptItemDraft>) -> some View {
        let value = item.wrappedValue
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                TextField("Item", text: item.name)
                    .font(.system(size: 14.5, weight: .medium)).lineLimit(1)
                Text(model.currency.symbol).font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                TextField("0", text: item.amountString)
                    .multilineTextAlignment(.trailing).frame(width: 74)
                    .font(.system(size: 14.5, weight: .semibold).monospacedDigit())
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                Button { model.removeItem(id: value.id) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(GoldengoTheme.inkMuted)
                }.buttonStyle(.plain).accessibilityLabel("Remove \(value.name)")
            }
            Button { categoryTarget = CategoryTarget(itemID: value.id) } label: {
                Label(value.categoryName, systemImage: GoldengoCategoryIcon.symbol(for: value.categoryName))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Color.goldengoField).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private var itemCaption: String {
        if model.items.isEmpty { return "No lines detected—add only if this was a mixed purchase." }
        if model.itemTotal > model.amountDecimal { return "Items exceed the receipt total. Check the amounts." }
        if model.itemRemainder > 0 {
            return "\(model.items.count) found · \(Money(amount: model.itemRemainder, currency: model.currency).formatted()) remains in the overall category"
        }
        return "\(model.items.count) found · totals match"
    }
    private var splitCaptionColor: Color { model.itemSplitsAreValid ? GoldengoTheme.inkMuted : GoldengoTheme.danger }

    private func selectedCategory(for target: CategoryTarget) -> String? {
        guard let itemID = target.itemID else { return model.selectedCategory }
        return model.items.first(where: { $0.id == itemID })?.categoryName
    }

    private func save() {
        focusedField = nil
        GoldengoHaptics.spendLanded()
        Task { if await model.save() { onDone() } }
    }
}
