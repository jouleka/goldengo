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
    private let onSave: (_ amount: Decimal, _ currency: CurrencyCode, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date, _ fundedBySourceID: String?, _ contextName: String?, _ splits: [TransactionSplit], _ kind: TransactionKind) -> Void
    private let onDelete: () -> Void

    @State private var amountText: String
    @State private var kind: TransactionKind
    @State private var currency: CurrencyCode
    @State private var merchant: String
    @State private var note: String
    @State private var category: String?
    @State private var date: Date
    @State private var fundedBySourceID: String?
    @State private var contextName: String?
    @State private var splits: [TransactionSplit]
    @State private var showSplitEditor = false
    @State private var showDeleteConfirm = false
    @State private var showCurrencyPicker = false
    /// Selectable currencies, decoded once on appear (the currency Menu reads it in body).
    @State private var selectableCurrencies: [CurrencyCode] = []

    /// Base quick categories, shared with QuickAdd; the snapshot's current category is appended
    /// (if not already present) so editing never silently drops an existing assignment.
    private static let baseCategories = SpendingCategoryCatalog.quickChoices

    public init(snapshot: ExpenseSnapshot,
                fundingSources: [FundingSourceOption] = [],
                onSave: @escaping (_ amount: Decimal, _ currency: CurrencyCode, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date, _ fundedBySourceID: String?, _ contextName: String?, _ splits: [TransactionSplit], _ kind: TransactionKind) -> Void,
                onDelete: @escaping () -> Void) {
        self.snapshot = snapshot
        self.fundingSources = fundingSources
        self.onSave = onSave
        self.onDelete = onDelete
        _amountText = State(initialValue: NSDecimalNumber(decimal: snapshot.amount).stringValue)
        _kind = State(initialValue: snapshot.kind)
        _currency = State(initialValue: CurrencyCode(snapshot.currencyCode))
        _merchant = State(initialValue: snapshot.merchantName ?? "")
        _note = State(initialValue: snapshot.note ?? "")
        _category = State(initialValue: snapshot.categoryName)
        _date = State(initialValue: snapshot.date)
        _fundedBySourceID = State(initialValue: snapshot.fundedBySourceID)
        _contextName = State(initialValue: snapshot.contextName)
        _splits = State(initialValue: snapshot.splits)
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

    private var planningIsValid: Bool {
        guard !splits.isEmpty else { return true }
        guard let amount = parsedAmount else { return false }
        return splits.count >= 2
            && splits.allSatisfy { $0.amount > 0 && !$0.categoryName.isEmpty }
            && splits.reduce(Decimal.zero) { $0 + $1.amount } == amount
    }

    public var body: some View {
        NavigationStack {
            Form {
                amountSection
                if kindIsEditable { transactionTypeSection }
                merchantSection
                noteSection
                if kind == .expense || kind == .refund { categorySection }
                if kind == .expense || kind == .refund { planningSection }
                if (kind == .expense || kind == .refund) && !fundingSources.isEmpty {
                    paidFromSection
                }
                dateSection
                deleteSection
            }
            .tint(GoldengoTheme.accent)
            .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
            .navigationTitle("Edit transaction")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsedAmount == nil || !planningIsValid)
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
            .sheet(isPresented: $showSplitEditor) {
                SplitEditorSheet(splits: $splits, total: parsedAmount ?? 0, currency: currency)
                    .presentationDetents([.large])
            }
            .onChange(of: kind) { _, newKind in
                if newKind != .expense { splits = [] }
            }
        }
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section { HStack(spacing: GoldengoTheme.Spacing.s) {
            currencyMenu
            TextField("0", text: $amountText)
                .font(.title3.weight(.medium).monospacedDigit())
#if canImport(UIKit)
                .keyboardType(.decimalPad)
#endif
        } } header: { GoldengoSerifSectionHeader("Amount") }
    }

    private var kindIsEditable: Bool {
        snapshot.kind == .expense || snapshot.kind == .income || snapshot.kind == .refund
    }

    private var transactionTypeSection: some View {
        Section {
            Picker("Type", selection: $kind) {
                Text("Purchase").tag(TransactionKind.expense)
                Text("Income").tag(TransactionKind.income)
                Text("Refund").tag(TransactionKind.refund)
            }
            .pickerStyle(.segmented)
        } header: { GoldengoSerifSectionHeader("Transaction type") }
          footer: {
              if kind == .refund {
                  Text("Refunds reduce spending in their category and never count as earned income.")
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
            .foregroundStyle(GoldengoTheme.inkMuted)
        }
    }

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }

    private var availableCurrencies: [CurrencyCode] { selectableCurrencies }

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == currency.rawValue }) {
            list.insert(currency, at: 0)   // keep the expense's own currency reachable
        }
        return list
    }

    private var merchantSection: some View {
        Section { TextField("Merchant (optional)", text: $merchant) } header: { GoldengoSerifSectionHeader("Merchant") }
    }

    private var noteSection: some View {
        Section { TextField("Note (optional)", text: $note) } header: { GoldengoSerifSectionHeader("Note") }
    }

    private var categorySection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    ForEach(categories, id: \.self) { cat in
                        SelectableChip(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat),
                                       isSelected: category == cat) {
                            category = (category == cat) ? nil : cat
                        }
                    }
                    SpendingCategoryMenu(selectedCategory: category) { category = $0 }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.s, leading: GoldengoTheme.Spacing.m,
                                      bottom: GoldengoTheme.Spacing.s, trailing: GoldengoTheme.Spacing.m))
        } header: { GoldengoSerifSectionHeader("Category") }
    }

    /// GOL-89/95: choose which money this expense draws from. "Wallet — cash" drains the wallet
    /// ledger (the default for hand-logged spends, where a nil pin already MEANS wallet); a source
    /// chip pins it bank-paid. "Automatic" (FIFO) only appears for imported/auto rows, where a nil
    /// pin genuinely means oldest-money-first — showing it on manual rows would lie (v2 review).
    private var isManualRow: Bool { snapshot.source == .manual }
    private var walletSelected: Bool {
        fundedBySourceID == FundingPin.wallet || (isManualRow && fundedBySourceID == nil)
    }

    private var paidFromSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    paidFromChip(label: "Wallet — cash", dot: nil, selected: walletSelected) {
                        // Explicit pin (not nil): the intent survives any future default change.
                        fundedBySourceID = FundingPin.wallet
                    }
                    if !isManualRow {
                        paidFromChip(label: "Automatic", dot: nil,
                                     selected: fundedBySourceID == nil) {
                            fundedBySourceID = nil
                        }
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
            GoldengoSerifSectionHeader(kind == .refund ? "Returned to" : "Paid from")
        } footer: {
            if kind == .refund {
                Text("Choose where the returned money landed so your available balance stays accurate.")
            } else {
                Text(isManualRow
                     ? "Cash drains your wallet. Pick a source to mark this bank-paid instead."
                     : "Automatic uses your oldest money first. Wallet marks it paid in cash.")
            }
        }
    }

    private func paidFromChip(label: String, dot: Color?, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(label).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.vertical, 8)
            .foregroundStyle(GoldengoTheme.inkPrimary)
            .background(selected ? GoldengoTheme.accentSoft : Color.goldengoField)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected ? GoldengoTheme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var dateSection: some View {
        Section {
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
    }

    private var planningSection: some View {
        Section {
            ContextPicker(selection: $contextName)
                .padding(.vertical, 4)
            if kind == .expense { Button { showSplitEditor = true } label: {
                HStack {
                    Label("Split purchase", systemImage: "rectangle.split.2x1")
                    Spacer()
                    Text(splits.isEmpty ? "Not split" : "\(splits.count) categories")
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }
            }
            .disabled(parsedAmount == nil)
            }
        } header: { GoldengoSerifSectionHeader("Reporting") }
          footer: {
              Text(planningIsValid
                   ? "Context says who or why. A split changes reports, not the wallet payment."
                   : "Update the split so its categories add up to the new amount.")
                  .foregroundStyle(planningIsValid ? GoldengoTheme.inkMuted : GoldengoTheme.danger)
          }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete transaction", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let amount = parsedAmount, planningIsValid else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(amount, currency, trimmedMerchant.isEmpty ? nil : trimmedMerchant,
               trimmedNote.isEmpty ? nil : trimmedNote, category, date, fundedBySourceID,
               contextName, kind == .expense ? splits : [], kind)
        dismiss()
    }
}
