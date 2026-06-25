import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData

/// Add income sheet (income.jsx): serif "Money in" title, amount + tappable currency symbol,
/// "Cash in hand" vs "Into a source" segmented choice, suggestion chips, gold Add button.
/// Preserves `cashInHand`/`addIncome`, the strict amount check, currency picker nav.
public struct AddIncomeView: View {
    @State private var model: SourcesModel
    let existingSources: [String]
    let onDone: () -> Void

    @State private var amountString = ""
    @State private var sourceName = ""
    @State private var currencyCode: String
    @State private var cashInHand = true        // income.jsx `intoSource` = !cashInHand defaults false (cash-first)
    @State private var showCurrencyPicker = false

    private static let suggestions = ["Remittance", "Pay", "ATM", "Cash gift", "Refund"]

    public init(model: SourcesModel, existingSources: [String], currency: CurrencyCode, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.existingSources = existingSources
        _currencyCode = State(initialValue: currency.rawValue)
        self.onDone = onDone
    }

    private var amount: Decimal { Decimal(string: amountString) ?? 0 }

    /// Truncate a typed amount string to a currency's fraction-digit count (drops the "." entirely
    /// for a zero-decimal currency). Pure, so it's unit-tested. Truncates (never rounds) — it's
    /// re-fitting in-progress input, not computing a value.
    static func refitAmount(_ s: String, toFractionDigits digits: Int) -> String {
        guard let dot = s.firstIndex(of: ".") else { return s }
        if digits == 0 { return String(s[..<dot]) }
        let frac = s[s.index(after: dot)...]
        guard frac.count > digits else { return s }
        return String(s[..<dot]) + "." + frac.prefix(digits)
    }

    private var allowsDecimal: Bool { CurrencyCode(currencyCode).fractionDigits > 0 }
    private var keys: [String] { ["1", "2", "3", "4", "5", "6", "7", "8", "9", allowsDecimal ? "." : "", "0", "⌫"] }
    private func tapKey(_ k: String) {
        switch k {
        case "⌫": if !amountString.isEmpty { amountString.removeLast() }
        case ".": if allowsDecimal, !amountString.contains(".") { amountString = amountString.isEmpty ? "0." : amountString + "." }
        default:
            if let dot = amountString.firstIndex(of: "."),
               amountString.distance(from: amountString.index(after: dot), to: amountString.endIndex) >= CurrencyCode(currencyCode).fractionDigits { return }
            amountString = (amountString == "0") ? k : amountString + k
        }
    }

    /// income.jsx: canSave = value > 0 && (!intoSource || name)
    /// "Into a source" requires a name; "Cash in hand" does not.
    private var canSave: Bool {
        amount > 0 && (cashInHand || !sourceName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }

    /// The formatted amount string for display (income.jsx line 28).
    private var displayAmount: String {
        let sym = CurrencyCode(currencyCode).symbol
        return sym + (amountString.isEmpty ? "0" : amountString)
    }

    /// All suggestion chips: existing source names + the static list, deduped (existing-names first).
    private var chips: [String] {
        let existingSet = Set(existingSources)
        let extras = Self.suggestions.filter { !existingSet.contains($0) }
        return existingSources + extras
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Drag handle (income.jsx line 38-39) ──────────────────────────────
                RoundedRectangle(cornerRadius: 3)
                    .fill(GoldengoTheme.hairline)
                    .frame(width: 38, height: 5)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                // ── Serif "Money in" title + amount + currency (income.jsx lines 46-54) ──
                VStack(spacing: 0) {
                    Text("Money in")
                        .font(.system(size: 22, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .padding(.bottom, 14)

                    // currency symbol (tappable) + amount
                    HStack(alignment: .bottom, spacing: 6) {
                        Button {
                            showCurrencyPicker = true
                        } label: {
                            HStack(alignment: .bottom, spacing: 2) {
                                Text(CurrencyCode(currencyCode).symbol)
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(GoldengoTheme.inkMuted)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(GoldengoTheme.inkMuted)
                                    .padding(.bottom, 5)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(displayAmount)
                            .font(.system(size: 48, weight: .semibold).monospacedDigit())
                            .tracking(-2)
                            .foregroundStyle(amountString.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.income)
                            .contentTransition(.numericText())
                            .animation(.easeIn(duration: 0.14), value: amountString)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)

                // ── Cash in hand / Into a source toggle (income.jsx lines 57-67) ───
                HStack(spacing: 0) {
                    ForEach([("Cash in hand", true), ("Into a source", false)], id: \.0) { label, isCash in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                cashInHand = isCash
                                // Cash-in-hand has no name field, so a source name picked in the other
                                // mode must not ride along as the cash origin label (it should be "Cash").
                                if isCash { sourceName = "" }
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .foregroundStyle(cashInHand == isCash ? GoldengoTheme.inkPrimary : GoldengoTheme.inkMuted)
                                .background(cashInHand == isCash ? Color.goldengoSurface : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.goldengoField)
                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                .padding(.horizontal, 22)
                .padding(.top, 22)

                // ── Suggestion chips for source name (income.jsx lines 68-74) ──────
                // Shown when "Into a source" is selected (!cashInHand).
                if !cashInHand {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.self) { s in
                                SelectableChip(s, isSelected: sourceName == s) {
                                    sourceName = (sourceName == s) ? "" : s
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 2)
                    }
                    .padding(.top, 12)
                }

                Spacer(minLength: GoldengoTheme.Spacing.s)

                // ── Amount keypad (income.jsx .gg-key grid) — the amount-entry control ──
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                    ForEach(keys, id: \.self) { k in
                        if k.isEmpty {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 54)
                        } else {
                            Button { tapKey(k) } label: {
                                Group {
                                    if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
                                }
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(GoldengoTheme.inkPrimary)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(Color.goldengoField)
                                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                // ── GoldButton Add income (income.jsx line 85) ───────────────────
                GoldButton("Add income", isEnabled: canSave) {
                    Task {
                        await model.addIncome(
                            amount: amount,
                            currency: CurrencyCode(currencyCode),
                            sourceName: cashInHand
                                ? (sourceName.trimmingCharacters(in: .whitespaces).isEmpty ? "Cash" : sourceName)
                                : sourceName,
                            intoWallet: cashInHand
                        )
                        onDone()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, max(GoldengoTheme.Spacing.l, 34))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.goldengoBackground.ignoresSafeArea())
            // Switching to a zero-decimal currency (e.g. ALL) must re-fit an already-typed fractional
            // amount, or "12.50" would be logged as a fractional lek value the keypad can no longer edit.
            .onChange(of: currencyCode) { _, newCode in
                amountString = Self.refitAmount(amountString, toFractionDigits: CurrencyCode(newCode).fractionDigits)
            }
            // Currency picker sheet (income.jsx CcyMini popup)
            .navigationDestination(isPresented: $showCurrencyPicker) {
                CurrencyPickerView(available: availableCurrencies, selectedCode: $currencyCode)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden) // we draw our own
    }
}
