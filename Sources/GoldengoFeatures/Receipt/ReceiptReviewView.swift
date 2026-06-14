import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Pre-filled confirm sheet for a scanned receipt. The user verifies/edits, then saves.
public struct ReceiptReviewView: View {
    @State private var model: ReceiptScanModel
    let onDone: () -> Void
    @FocusState private var amountFocused: Bool
    @FocusState private var merchantFocused: Bool

    public init(model: ReceiptScanModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onDone = onDone
    }

    private let categories = ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping", "Other"]

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(model.currency.symbol).foregroundStyle(GoldengoTheme.inkMuted)
                        TextField("0", text: $model.amountString)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                            .focused($amountFocused)
                            .font(.title2.weight(.semibold).monospacedDigit())
                    }
                    if model.amountWasUnreadable {
                        Text("Couldn't read the total — enter it.")
                            .font(.footnote).foregroundStyle(GoldengoTheme.inkMuted)
                    }
                } header: {
                    GoldengoSerifSectionHeader("Amount")
                }
                Section {
                    TextField("Merchant", text: $model.merchant)
                        .focused($merchantFocused)
                } header: {
                    GoldengoSerifSectionHeader("Merchant")
                }
                Section {
                    DatePicker("Date",
                               selection: Binding(get: { model.date ?? .now },
                                                  set: { model.date = $0 }),
                               displayedComponents: .date)
                } header: {
                    GoldengoSerifSectionHeader("Date")
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: GoldengoTheme.Spacing.s) {
                            ForEach(categories, id: \.self) { cat in
                                SelectableChip(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat),
                                               isSelected: model.selectedCategory == cat) {
                                    model.selectedCategory = (model.selectedCategory == cat) ? nil : cat
                                }
                            }
                        }
                    }
                } header: {
                    GoldengoSerifSectionHeader("Category")
                }
            }
            .tint(GoldengoTheme.accent)
            .navigationTitle("Review receipt")
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = false; merchantFocused = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        amountFocused = false; merchantFocused = false
                        GoldengoHaptics.spendLanded()
                        Task { await model.save(); onDone() }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
    }
}
