import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// A sheet to edit (or delete) a single expense. Presented via `.sheet(item:)` from the Home
/// recent list. Mirrors the QuickAdd design language — gold accent, grouped surfaces, rounded
/// chips — but uses a `Form` since it's a focused modal rather than the dashboard.
public struct EditExpenseView: View {
    @Environment(\.dismiss) private var dismiss

    private let snapshot: ExpenseSnapshot
    private let currency: CurrencyCode
    private let onSave: (_ amount: Decimal, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date) -> Void
    private let onDelete: () -> Void

    @State private var amountText: String
    @State private var merchant: String
    @State private var note: String
    @State private var category: String?
    @State private var date: Date
    @State private var showDeleteConfirm = false

    /// Base quick categories, shared with QuickAdd; the snapshot's current category is appended
    /// (if not already present) so editing never silently drops an existing assignment.
    private static let baseCategories = ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping"]

    public init(snapshot: ExpenseSnapshot,
                currency: CurrencyCode,
                onSave: @escaping (_ amount: Decimal, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date) -> Void,
                onDelete: @escaping () -> Void) {
        self.snapshot = snapshot
        self.currency = currency
        self.onSave = onSave
        self.onDelete = onDelete
        _amountText = State(initialValue: NSDecimalNumber(decimal: snapshot.amount).stringValue)
        _merchant = State(initialValue: snapshot.merchantName ?? "")
        _note = State(initialValue: snapshot.note ?? "")
        _category = State(initialValue: snapshot.categoryName)
        _date = State(initialValue: snapshot.date)
    }

    private var categories: [String] {
        guard let current = snapshot.categoryName, !Self.baseCategories.contains(current) else {
            return Self.baseCategories
        }
        return Self.baseCategories + [current]
    }

    /// Parsed amount, or nil when the field isn't a positive number — drives Save enablement.
    private var parsedAmount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: trimmed), value > 0 else { return nil }
        return value
    }

    public var body: some View {
        NavigationStack {
            Form {
                amountSection
                merchantSection
                noteSection
                categorySection
                dateSection
                deleteSection
            }
            .navigationTitle("Edit expense")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsedAmount == nil)
                }
            }
            .alert("Delete this expense?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section("Amount") {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                Text(currency.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("0", text: $amountText)
                    .font(.title3.weight(.medium))
#if canImport(UIKit)
                    .keyboardType(.decimalPad)
#endif
            }
        }
    }

    private var merchantSection: some View {
        Section("Merchant") {
            TextField("Merchant (optional)", text: $merchant)
        }
    }

    private var noteSection: some View {
        Section("Note") {
            TextField("Note (optional)", text: $note)
        }
    }

    private var categorySection: some View {
        Section("Category") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    ForEach(categories, id: \.self) { cat in
                        let selected = category == cat
                        Button {
                            category = selected ? nil : cat
                        } label: {
                            Label(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, GoldengoTheme.Spacing.m)
                                .padding(.vertical, 10)
                                .background(selected ? GoldengoTheme.accent : Color.goldengoField)
                                .foregroundStyle(selected ? .black : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.s, leading: GoldengoTheme.Spacing.m,
                                      bottom: GoldengoTheme.Spacing.s, trailing: GoldengoTheme.Spacing.m))
        }
    }

    private var dateSection: some View {
        Section {
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete expense", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let amount = parsedAmount else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(amount, trimmedMerchant.isEmpty ? nil : trimmedMerchant,
               trimmedNote.isEmpty ? nil : trimmedNote, category, date)
        dismiss()
    }
}
