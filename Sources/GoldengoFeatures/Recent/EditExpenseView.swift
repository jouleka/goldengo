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
    /// Named sources for the "Paid from" picker (GOL-89); empty hides the section.
    private let fundingSources: [FundingSourceOption]
    private let onSave: (_ amount: Decimal, _ currency: CurrencyCode, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date, _ fundedBySourceID: String?) -> Void
    private let onDelete: () -> Void

    @State private var amountText: String
    @State private var currency: CurrencyCode
    @State private var merchant: String
    @State private var note: String
    @State private var category: String?
    @State private var date: Date
    @State private var fundedBySourceID: String?
    @State private var showDeleteConfirm = false
    @State private var showCurrencyPicker = false

    /// Base quick categories, shared with QuickAdd; the snapshot's current category is appended
    /// (if not already present) so editing never silently drops an existing assignment.
    private static let baseCategories = ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping"]

    public init(snapshot: ExpenseSnapshot,
                fundingSources: [FundingSourceOption] = [],
                onSave: @escaping (_ amount: Decimal, _ currency: CurrencyCode, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date, _ fundedBySourceID: String?) -> Void,
                onDelete: @escaping () -> Void) {
        self.snapshot = snapshot
        self.fundingSources = fundingSources
        self.onSave = onSave
        self.onDelete = onDelete
        _amountText = State(initialValue: NSDecimalNumber(decimal: snapshot.amount).stringValue)
        _currency = State(initialValue: CurrencyCode(snapshot.currencyCode))
        _merchant = State(initialValue: snapshot.merchantName ?? "")
        _note = State(initialValue: snapshot.note ?? "")
        _category = State(initialValue: snapshot.categoryName)
        _date = State(initialValue: snapshot.date)
        _fundedBySourceID = State(initialValue: snapshot.fundedBySourceID)
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
                if snapshot.kind == .expense && !fundingSources.isEmpty {
                    paidFromSection
                }
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
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    CurrencyPickerView(
                        available: availableCurrencies,
                        selectedCode: Binding(
                            get: { currency.rawValue },
                            set: { currency = CurrencyCode($0) }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section("Amount") {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                currencyMenu
                TextField("0", text: $amountText)
                    .font(.title3.weight(.medium))
#if canImport(UIKit)
                    .keyboardType(.decimalPad)
#endif
            }
        }
    }

    /// Tap the currency to change it — popular currencies inline, "More…" opens the full picker.
    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button {
                    currency = c
                } label: {
                    if c.rawValue == currency.rawValue {
                        Label(menuLabel(c), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(c))
                    }
                }
            }
            Divider()
            Button { showCurrencyPicker = true } label: {
                Label("More currencies…", systemImage: "ellipsis.circle")
            }
        } label: {
            HStack(spacing: 2) {
                Text(currency.symbol).font(.title3.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(.secondary)
        }
    }

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }

    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == currency.rawValue }) {
            list.insert(currency, at: 0)   // keep the expense's own currency reachable
        }
        return list
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

    /// GOL-89: choose which money pool this expense draws from — "Automatic" (FIFO) or a pinned
    /// source. Chips mirror the category-chip pattern; each source chip carries its palette dot.
    private var paidFromSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    paidFromChip(label: "Automatic", dot: nil, selected: fundedBySourceID == nil) {
                        fundedBySourceID = nil
                    }
                    ForEach(fundingSources) { s in
                        paidFromChip(label: s.name, dot: GoldengoTheme.sourceColor(s.colorIndex),
                                     selected: fundedBySourceID == s.id) {
                            fundedBySourceID = s.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.s, leading: GoldengoTheme.Spacing.m,
                                      bottom: GoldengoTheme.Spacing.s, trailing: GoldengoTheme.Spacing.m))
        } header: {
            Text("Paid from")
        } footer: {
            Text("Automatic uses your oldest money first. Pick a source to say exactly where this came from.")
        }
    }

    private func paidFromChip(label: String, dot: Color?, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                Text(label).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.vertical, 10)
            .background(selected ? GoldengoTheme.accent : Color.goldengoField)
            .foregroundStyle(selected ? .black : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
        onSave(amount, currency, trimmedMerchant.isEmpty ? nil : trimmedMerchant,
               trimmedNote.isEmpty ? nil : trimmedNote, category, date, fundedBySourceID)
        dismiss()
    }
}
