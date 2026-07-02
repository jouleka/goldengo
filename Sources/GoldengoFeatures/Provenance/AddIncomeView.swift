import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData

/// Add income sheet (income.jsx): serif "Money in" title, baseline-aligned currency menu +
/// hero amount, "Cash in hand" vs "Into a source" segmented choice, source chips with an
/// inline "New" name field, gold Add button. Mirrors QuickAddView's amount-block idiom
/// exactly so the two money-entry sheets read as siblings.
/// Preserves `cashInHand`/`addIncome` and the strict amount check.
public struct AddIncomeView: View {
    @State private var model: SourcesModel
    let existingSources: [String]
    let onDone: () -> Void

    @State private var amountString = ""
    @State private var sourceName = ""
    @State private var currencyCode: String
    @State private var cashInHand = true        // income.jsx `intoSource` = !cashInHand defaults false (cash-first)
    @State private var showCurrencyPicker = false
    /// "New" chip → inline name field (this is how a source is CREATED — the store
    /// find-or-creates by name on save).
    @State private var newSourceMode = false
    @State private var newSourceText = ""
    @FocusState private var newSourceFocused: Bool
    /// Selectable currencies, decoded once on appear (the currency Menu reads it in body).
    @State private var selectableCurrencies: [CurrencyCode] = []
    /// When the money arrived — defaults to now; bounded to today (future income would
    /// distort the wallet ledger and the pools before it exists).
    @State private var date = Date.now

    // gg-key height — matches QuickAddView (quickadd.jsx `keyH` at density "regular")
    private let keyHeight: CGFloat = 60

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
        newSourceFocused = false   // typing the amount ends name editing (tap-outside rule)
        switch k {
        case "⌫": if !amountString.isEmpty { amountString.removeLast() }
        case ".": if allowsDecimal, !amountString.contains(".") { amountString = amountString.isEmpty ? "0." : amountString + "." }
        default:
            if let dot = amountString.firstIndex(of: "."),
               amountString.distance(from: amountString.index(after: dot), to: amountString.endIndex) >= CurrencyCode(currencyCode).fractionDigits { return }
            amountString = (amountString == "0") ? k : amountString + k
        }
    }

    /// The name the income will be filed under: the inline field when creating, else the chip.
    private var resolvedSourceName: String {
        (newSourceMode ? newSourceText : sourceName).trimmingCharacters(in: .whitespaces)
    }

    /// income.jsx: canSave = value > 0 && (!intoSource || name)
    /// "Into a source" requires a name; "Cash in hand" does not.
    private var canSave: Bool {
        amount > 0 && (cashInHand || !resolvedSourceName.isEmpty)
    }

    private var availableCurrencies: [CurrencyCode] { selectableCurrencies }

    /// All suggestion chips: existing source names + the static list, deduped (existing-names first).
    private var chips: [String] {
        let existingSet = Set(existingSources)
        let extras = Self.suggestions.filter { !existingSet.contains($0) }
        return existingSources + extras
    }

    public var body: some View {
        // Stacked layout — same frame as QuickAddView: 14px top, app-wide 16pt sides, 34px bottom.
        VStack(spacing: 0) {
            amountBlock
                .padding(.top, 8)

            modeToggle
                .padding(.top, 22)

            if !cashInHand {
                sourceChips
                    .padding(.top, 12)
                if newSourceMode {
                    newSourceField
                        .padding(.top, 10)
                }
            }

            whenRow
                .padding(.top, 12)

            Spacer(minLength: 0)

            keypad
                .padding(.top, 16)

            GoldButton("Add income", isEnabled: canSave) {
                Task {
                    await model.addIncome(
                        amount: amount,
                        currency: CurrencyCode(currencyCode),
                        sourceName: cashInHand
                            ? (resolvedSourceName.isEmpty ? "Cash" : resolvedSourceName)
                            : resolvedSourceName,
                        intoWallet: cashInHand,
                        date: date
                    )
                    onDone()
                }
            }
            .padding(.top, GoldengoTheme.Spacing.l)   // clear gap so it never touches the keypad
        }
        .padding(.top, 14)
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.bottom, 34)
        .background(Color.goldengoBackground.ignoresSafeArea())
        // The text keyboard (new-source field) overlays the numeric keypad instead of
        // compressing the sheet — otherwise the layout gets shoved off the top while typing.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Switching to a zero-decimal currency (e.g. ALL) must re-fit an already-typed fractional
        // amount, or "12.50" would be logged as a fractional lek value the keypad can no longer edit.
        .onChange(of: currencyCode) { _, newCode in
            amountString = Self.refitAmount(amountString, toFractionDigits: CurrencyCode(newCode).fractionDigits)
        }
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(available: availableCurrencies, selectedCode: $currencyCode)
            }
        }
        .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)   // system grabber; swipe down cancels (same as QuickAdd)
    }

    // MARK: - Amount block
    // Mirrors QuickAddView's AmountBlock: serif title (Georgia 19/medium/muted), then
    // baseline-aligned currency menu + hero amount with grouping and dynamic shrink.

    private var amountBlock: some View {
        VStack(spacing: 0) {
            Text("Money in")
                .font(.custom("Georgia", size: 19).weight(.medium))
                .foregroundStyle(GoldengoTheme.inkMuted)
                .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                currencyMenu
                heroAmount
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .multilineTextAlignment(.center)
    }

    // Dynamic size: base 50pt, shrinks for strings longer than 7 chars (same rule as QuickAdd).
    private var heroFontSize: CGFloat {
        let base: CGFloat = 50
        let len = displayAmountBody.count
        guard len > 7 else { return base }
        return max(30, (base * 7 / CGFloat(len)).rounded())
    }

    // The formatted body (no symbol) with thousands grouping, matching QuickAdd's formatTyped.
    private var displayAmountBody: String {
        let s = amountString
        guard !s.isEmpty else { return "0" }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        var intPart = parts[0].isEmpty ? "0" : parts[0]
        if let n = Int(intPart) {
            intPart = n.formatted(.number.grouping(.automatic))
        }
        if parts.count == 2 {
            return intPart + "." + parts[1]
        }
        return intPart
    }

    private var heroAmount: some View {
        Text(displayAmountBody)
            .font(.system(size: heroFontSize, weight: .semibold))
            .monospacedDigit()
            .tracking(-2)
            .foregroundStyle(amountString.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.income)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.15), value: heroFontSize)
            .animation(.easeInOut(duration: 0.2), value: amountString.isEmpty)
    }

    // MARK: - Currency menu
    // Mirrors QuickAddView's CurrencyMenu: one tap for popular currencies, "More…" for the rest.

    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button { currencyCode = c.rawValue } label: {
                    if c.rawValue == currencyCode {
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
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(CurrencyCode(currencyCode).symbol)
                    .font(.system(size: 30, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.top, 6)
            }
            .foregroundStyle(GoldengoTheme.inkMuted)
            .contentShape(Rectangle())
        }
    }

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == currencyCode }) {
            list.insert(CurrencyCode(currencyCode), at: 0)
        }
        return list
    }

    // MARK: - Cash in hand / Into a source toggle (income.jsx lines 57-67)

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach([("Cash in hand", true), ("Into a source", false)], id: \.0) { label, isCash in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        cashInHand = isCash
                        // Cash-in-hand has no name field, so a source name picked in the other
                        // mode must not ride along as the cash origin label (it should be "Cash").
                        if isCash {
                            sourceName = ""
                            newSourceMode = false
                            newSourceText = ""
                        }
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(cashInHand == isCash ? GoldengoTheme.inkPrimary : GoldengoTheme.inkMuted)
                        .background(cashInHand == isCash ? Color.goldengoSurface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control - 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.goldengoField)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
    }

    // MARK: - Source chips + inline "New" name field

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "New" leads: creating a source is a first-class action, not a leftover.
                SelectableChip("New", systemImage: "plus", isSelected: newSourceMode) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        newSourceMode.toggle()
                        sourceName = ""
                        if newSourceMode { newSourceFocused = true } else { newSourceText = "" }
                    }
                }
                ForEach(chips, id: \.self) { s in
                    SelectableChip(s, isSelected: !newSourceMode && sourceName == s) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            sourceName = (sourceName == s) ? "" : s
                            newSourceMode = false
                            newSourceText = ""
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var newSourceField: some View {
        TextField("Name this source — e.g. Freelance", text: $newSourceText)
            .focused($newSourceFocused)
            .submitLabel(.done)
            .onSubmit { newSourceFocused = false }
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundStyle(GoldengoTheme.inkPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.goldengoField)
            .clipShape(Capsule())
    }

    // MARK: - When (backdating) — bounded to today.

    private var whenRow: some View {
        HStack {
            GoldengoSectionLabel("When")
            Spacer()
            DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
                .tint(GoldengoTheme.accent)
        }
    }

    // MARK: - Keypad
    // Same grid + press micro-interaction as QuickAddView (3 cols, gap 9, gg-key style).

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                if k.isEmpty {
                    Color.clear.frame(maxWidth: .infinity, minHeight: keyHeight)
                } else {
                    Button { tapKey(k) } label: {
                        Group {
                            if k == "⌫" {
                                Image(systemName: "delete.left")
                                    .font(.system(size: 26))
                            } else {
                                Text(k)
                                    .font(.system(size: 26, weight: .medium))
                            }
                        }
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                        .frame(maxWidth: .infinity, minHeight: keyHeight)
                        .background(Color.goldengoField)
                        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(KeypadButtonStyle())
                }
            }
        }
    }
}

// MARK: - Keypad button style
// Matches .gg-key:active — scale(.94) press feedback (same as QuickAddView's).

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.09), value: configuration.isPressed)
    }
}
