import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData

/// Minimal income capture: amount, currency (so a EUR remittance can be logged), source name
/// with suggestions, date.
public struct AddIncomeView: View {
    @State private var model: SourcesModel
    let existingSources: [String]
    let onDone: () -> Void
    @State private var amountString = ""
    @State private var sourceName = ""
    @State private var currencyCode: String
    @State private var date = Date.now
    @State private var cashInHand = false   // GOL-95 v2: the money is physically in the wallet
    @FocusState private var amountFocused: Bool

    public init(model: SourcesModel, existingSources: [String], currency: CurrencyCode, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.existingSources = existingSources
        _currencyCode = State(initialValue: currency.rawValue)
        self.onDone = onDone
    }

    private var amount: Decimal { Decimal(string: amountString) ?? 0 }
    private var canSave: Bool { amount > 0 && !sourceName.trimmingCharacters(in: .whitespaces).isEmpty }

    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }
    private var currencyLabel: String {
        let c = CurrencyCode(currencyCode)
        let n = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol) · \(n)"
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0", text: $amountString)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                        .focused($amountFocused)
                        .font(.title2.weight(.semibold).monospacedDigit())
                } header: { GoldengoSerifSectionHeader("Amount") }
                Section {
                    NavigationLink {
                        CurrencyPickerView(available: availableCurrencies, selectedCode: $currencyCode)
                    } label: {
                        LabeledContent("Currency", value: currencyLabel)
                    }
                } header: { GoldengoSerifSectionHeader("Currency") }
                Section {
                    TextField("Source (e.g. Sister, Freelance)", text: $sourceName)
                    if !existingSources.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: GoldengoTheme.Spacing.s) {
                                ForEach(existingSources, id: \.self) { s in
                                    Button(s) { sourceName = s }
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(GoldengoTheme.inkPrimary)
                                        .padding(.horizontal, GoldengoTheme.Spacing.m).padding(.vertical, 6)
                                        .background(Color.goldengoField).clipShape(Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: { GoldengoSerifSectionHeader("From") }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: { GoldengoSerifSectionHeader("Date") }
                Section {
                    Toggle("Cash in hand", isOn: $cashInHand)
                    Text(cashInHand
                         ? "Goes straight into your wallet — the name is kept as where it came from."
                         : "Lands in the bank as a named source; reach it via an ATM withdrawal.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                }
            }
            .navigationTitle("Add income")
            .tint(GoldengoTheme.accent)
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        amountFocused = false
                        Task {
                            await model.addIncome(amount: amount, currency: CurrencyCode(currencyCode),
                                                  sourceName: sourceName, intoWallet: cashInHand)
                            onDone()
                        }
                    }.disabled(!canSave)
                }
            }
        }
    }
}
