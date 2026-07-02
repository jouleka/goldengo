import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// Declare a subscription directly — no charge history needed. Creates a confirmed, tracked
/// record; the charge itself is never fabricated (it surfaces as a one-tap ghost when due).
struct AddSubscriptionView: View {
    @State var model: SubscriptionsModel
    @State private var name = ""
    @State private var amountText = ""
    @State private var currencyCode = SharedSummary().readPreferredCurrency().rawValue
    @State private var cadence: SubscriptionCadence = .monthly
    @State private var nextCharge = Date.now
    @State private var busy = false
    @State private var showCurrencyPicker = false
    @State private var selectableCurrencies: [CurrencyCode] = []
    @Environment(\.dismiss) private var dismiss

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
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func cadenceLabel(_ c: SubscriptionCadence) -> String {
        switch c {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    // The serif title IS the name field (same idiom as the source edit sheet).
                    TextField("Netflix, iCloud, rent…", text: $name)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("Goldengo reminds you before it charges and offers the expense with one tap when it's due — nothing is logged by itself.")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
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

                HStack(spacing: 8) {
                    ForEach(SubscriptionCadence.allCases, id: \.rawValue) { c in
                        SelectableChip(cadenceLabel(c), isSelected: cadence == c) { cadence = c }
                    }
                }

                DatePicker("Next charge", selection: $nextCharge, displayedComponents: .date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .tint(GoldengoTheme.accent)

                GoldButton("Track subscription", isEnabled: canSave) {
                    guard let amount = typedAmount else { return }
                    busy = true
                    GoldengoHaptics.spendLanded()
                    Task {
                        await model.addManual(name: name, amount: amount,
                                              currency: CurrencyCode(currencyCode),
                                              cadence: cadence, nextChargeDate: nextCharge)
                        dismiss()
                    }
                }
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .goldengoDismissKeyboard()
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(available: selectableCurrencies, selectedCode: $currencyCode)
            }
        }
        .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
    }

    // One-tap popular currencies, "More…" behind it (same idiom as QuickAdd/AddIncome).
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
