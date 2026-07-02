import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// Lend money to a person — the cash leaves the wallet (or a pinned source) for real, but
/// it becomes a CLAIM on the Wallet tab, never spending. Idiom shared with AddIncomeView.
struct LendView: View {
    @State var model: SourcesModel
    let onDone: () -> Void

    @State private var personName = ""
    @State private var amountText = ""
    @State private var currencyCode: String
    @State private var fundedBySourceID: String?   // nil = Wallet — cash
    @State private var date = Date.now
    @State private var busy = false
    @State private var showCurrencyPicker = false
    @State private var selectableCurrencies: [CurrencyCode] = []
    @FocusState private var nameFocused: Bool

    init(model: SourcesModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        _currencyCode = State(initialValue: model.currency.rawValue)
        self.onDone = onDone
    }

    /// STRICT parse (same rule as AdjustWalletView): whole string is a plain positive amount.
    private var typedAmount: Decimal? {
        let cleaned = amountText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard cleaned.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: cleaned)
    }
    private var canSave: Bool {
        !busy && (typedAmount ?? 0) > 0
            && !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    // The serif title IS the person field (same idiom as the other sheets).
                    TextField("Who's borrowing?", text: $personName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFocused = false }
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("It leaves your money for real, but it's not spending — it sits under “Owed to you” until it comes home.")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Existing debtors as one-tap chips (lending more to the same person).
                if !model.loans.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.loans) { loan in
                                SelectableChip(loan.personName, isSelected: personName == loan.personName) {
                                    personName = (personName == loan.personName) ? "" : loan.personName
                                    nameFocused = false
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    currencyMenu
                    TextField("0", text: $amountText)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                        .font(.system(size: 40, weight: .semibold).monospacedDigit())
                        .tracking(-1)
                        .foregroundStyle(amountText.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.inkPrimary)
                }

                // From: Wallet — cash by default, or a named source (QuickAdd's Paid-from idiom).
                HStack {
                    GoldengoSectionLabel("From")
                    Spacer()
                    fromMenu
                }

                HStack {
                    GoldengoSectionLabel("When")
                    Spacer()
                    DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                        .tint(GoldengoTheme.accent)
                }

                GoldButton("Lend it", isEnabled: canSave) {
                    guard let amount = typedAmount else { return }
                    busy = true
                    GoldengoHaptics.spendLanded()
                    Task {
                        await model.lend(amount: amount, currency: CurrencyCode(currencyCode),
                                         personName: personName, fundedBySourceID: fundedBySourceID,
                                         date: date)
                        onDone()
                    }
                }
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .goldengoDismissKeyboard()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(available: selectableCurrencies, selectedCode: $currencyCode)
            }
        }
        .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
    }

    private var selectedSource: SourceBalance? {
        (model.snapshot?.sources ?? []).first { $0.id == fundedBySourceID }
    }

    private var fromMenu: some View {
        Menu {
            Button { fundedBySourceID = nil } label: {
                if fundedBySourceID == nil {
                    Label("Wallet — cash", systemImage: "checkmark")
                } else {
                    Text("Wallet — cash")
                }
            }
            ForEach(model.snapshot?.sources ?? []) { s in
                Button { fundedBySourceID = s.id } label: {
                    let label = "\(s.name)  ·  \(model.remainingText(s)) left"
                    if fundedBySourceID == s.id {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let s = selectedSource {
                    Circle()
                        .fill(model.color(s))
                        .frame(width: 9, height: 9)
                    Text(s.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                } else {
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 16))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    Text("Wallet — cash")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.goldengoField)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .animation(.snappy, value: fundedBySourceID)
    }

    // One-tap popular currencies, "More…" behind it (same idiom as the sibling sheets).
    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button { currencyCode = c.rawValue } label: {
                    let label = "\(c.symbol)  \(Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue)"
                    if c.rawValue == currencyCode { Label(label, systemImage: "checkmark") }
                    else { Text(label) }
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

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(selectableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == currencyCode }) {
            list.insert(CurrencyCode(currencyCode), at: 0)
        }
        return list
    }
}
