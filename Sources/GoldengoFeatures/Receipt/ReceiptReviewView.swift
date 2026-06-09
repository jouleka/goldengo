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
                Section("Amount") {
                    HStack {
                        Text(model.currency.symbol).foregroundStyle(.secondary)
                        TextField("0", text: $model.amountString)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                            .focused($amountFocused)
                            .font(.title2.weight(.semibold))
                    }
                    if model.amountWasUnreadable {
                        Text("Couldn't read the total — enter it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Merchant") {
                    TextField("Merchant", text: $model.merchant)
                        .focused($merchantFocused)
                }
                Section("Date") {
                    DatePicker("Date",
                               selection: Binding(get: { model.date ?? .now },
                                                  set: { model.date = $0 }),
                               displayedComponents: .date)
                }
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: GoldengoTheme.Spacing.s) {
                            ForEach(categories, id: \.self) { cat in
                                let selected = model.selectedCategory == cat
                                Button {
                                    model.selectedCategory = selected ? nil : cat
                                } label: {
                                    Label(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat))
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, GoldengoTheme.Spacing.m)
                                        .padding(.vertical, 8)
                                        .background(selected ? GoldengoTheme.accent : Color.goldengoSurface)
                                        .foregroundStyle(selected ? .black : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
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
