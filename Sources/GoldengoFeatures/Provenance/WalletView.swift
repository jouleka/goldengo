import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// Per-currency wallet sheet: lists tracked currencies as tappable rows → AdjustWalletView.
/// "Track another currency" quick-adds ALL/EUR or navigates to a full picker for others.
/// GOL-98: `autoOpenAdjust` skips the list and pushes straight to the adjust screen.
public struct WalletView: View {
    @State private var model: SourcesModel
    let autoOpenAdjust: CurrencyCode?
    @State private var adjustPresented = false
    @Environment(\.dismiss) private var dismiss
    /// Selectable currencies, decoded once on appear (the "track another currency" section reads
    /// `untracked` directly in body — was re-decoding from UserDefaults on every pass).
    @State private var selectableCurrencies: [CurrencyCode] = []

    public init(model: SourcesModel, autoOpenAdjust: CurrencyCode? = nil) {
        _model = State(initialValue: model)
        self.autoOpenAdjust = autoOpenAdjust
    }

    /// Every catalog currency without a wallet line yet.
    private var untracked: [CurrencyCode] {
        selectableCurrencies.filter { c in !model.wallet.contains { $0.currencyCode == c.rawValue } }
    }
    private var quickAdds: [CurrencyCode] { untracked.filter { $0 == .all || $0 == .eur } }
    private var otherAdds: [CurrencyCode]  { untracked.filter { $0 != .all && $0 != .eur } }

    private func label(for code: String) -> String {
        if code == "ALL" { return "Lek (ALL)" }
        let name = Locale.current.localizedString(forCurrencyCode: code)
        return name.map { "\($0) (\(code))" } ?? code
    }

    public var body: some View {
        NavigationStack {
            List {
                if model.wallet.isEmpty {
                    Text("Your pocket, by currency. Start by setting what you're actually holding — cash spends drain it from there.")
                        .font(.caption).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // Tracked currencies → adjust
                ForEach(model.wallet) { line in
                    NavigationLink {
                        AdjustWalletView(model: model, currency: CurrencyCode(line.currencyCode))
                    } label: {
                        HStack {
                            Text(label(for: line.currencyCode))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            GoldengoAmountText(
                                "~" + Money(amount: line.expectedNow,
                                            currency: CurrencyCode(line.currencyCode)).formatted(),
                                role: .row
                            )
                        }
                    }
                    .listRowBackground(Color.clear)
                    // Money records stay — only the tracking line goes, so this is reversible
                    // by simply tracking the currency again (no confirmation ceremony needed).
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Remove", role: .destructive) {
                            Task { await model.removeWalletCurrency(CurrencyCode(line.currencyCode)) }
                        }
                    }
                }

                // Track another currency
                if !untracked.isEmpty {
                    Section {
                        ForEach(quickAdds, id: \.rawValue) { c in
                            NavigationLink {
                                AdjustWalletView(model: model, currency: c)
                            } label: {
                                Label("Track \(label(for: c.rawValue)) cash", systemImage: "plus.circle")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .listRowBackground(Color.clear)
                        }
                        if !otherAdds.isEmpty {
                            NavigationLink {
                                List(otherAdds, id: \.rawValue) { c in
                                    NavigationLink {
                                        AdjustWalletView(model: model, currency: c)
                                    } label: {
                                        Text(label(for: c.rawValue)).font(.subheadline)
                                    }
                                    .listRowBackground(Color.clear)
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                                .background(Color.goldengoBackground.ignoresSafeArea())
                                .navigationTitle("Which currency?")
                            } label: {
                                Label("Track another currency", systemImage: "plus.circle")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Wallet")
            // GOL-98: widget tap pushes straight to Adjust.
            .navigationDestination(isPresented: $adjustPresented) {
                AdjustWalletView(model: model, currency: autoOpenAdjust ?? .all)
            }
            .onAppear {
                selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
                if autoOpenAdjust != nil { adjustPresented = true }
            }
            .onChange(of: autoOpenAdjust) { _, target in
                if target != nil { adjustPresented = true }
            }
        }
    }
}

/// Set one currency's real balance (wallet.jsx AdjustSheet). Type the total or use the
/// denomination counter (DisclosureGroup + steppers) — both set the same number.
/// No ceremony on save: one result line, then dismiss. Lower than expected auto-logs Unaccounted.
struct AdjustWalletView: View {
    @State var model: SourcesModel
    let currency: CurrencyCode
    @State private var amountText = ""
    @State private var showCounter = false
    @State private var tally = DenominationTally()
    @State private var resultLine: String?
    @State private var busy = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var expected: Decimal? {
        model.wallet.first { $0.currencyCode == currency.rawValue }?.expectedNow
    }

    /// STRICT parse: whole string must be a plain non-negative amount. Grouped formats reject.
    private var typedAmount: Decimal? {
        let cleaned = amountText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard cleaned.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: cleaned)
    }

    private var hasDenominationTable: Bool {
        !(Denominations.notes(for: currency) + Denominations.coins(for: currency)).isEmpty
    }

    /// Gap between what's typed and what the books expect — shown as the result hint.
    private var gap: Decimal? {
        guard let exp = expected, let typed = typedAmount, typed > 0 else { return nil }
        let g = typed - exp
        return abs(g) > (currency == .all ? 0 : Decimal(string: "0.001")!) ? g : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {

                // Serif title (wallet.jsx AdjustSheet line 138-144)
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's in your wallet?")
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    if let expected {
                        Text("The books expect " + Money(amount: expected, currency: currency).formatted() + ". Count it and set what's real.")
                            .font(.caption)
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }

                // Big monospaced amount input (wallet.jsx line 147-149)
                TextField("0", text: $amountText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .focused($focused)
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, GoldengoTheme.Spacing.s)
                    .foregroundStyle(amountText.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.inkPrimary)

                // Denomination counter (wallet.jsx implied by design — DisclosureGroup + steppers)
                if hasDenominationTable {
                    counterDisclosure
                }

                // Gap hint (wallet.jsx lines 152-158)
                if let g = gap {
                    Text(g < 0
                         ? Money(amount: -g, currency: currency).formatted() + " less than expected → logged as Unaccounted"
                         : Money(amount: g, currency: currency).formatted() + " more than expected — that's fine")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                // Result line (after save)
                if let resultLine {
                    Text(resultLine).font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                }

                // GoldButton Save (wallet.jsx line 167)
                GoldButton("Save", isEnabled: !busy && typedAmount != nil) {
                    guard !busy, let total = typedAmount else { return }
                    busy = true
                    focused = false
                    GoldengoHaptics.spendLanded()
                    Task {
                        let tallyToSave = (showCounter && tally.total == total) ? tally : nil
                        let outcome = await model.setWalletBalance(total, currency: currency, tally: tallyToSave)
                        if outcome == nil {
                            resultLine = "Couldn't save — try again."
                            busy = false
                        } else if let gap = outcome?.unaccountedLogged {
                            resultLine = Money(amount: gap, currency: currency).formatted()
                                + " logged as Unaccounted — delete it in Recent if that's wrong."
                            busy = false
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .goldengoDismissKeyboard()
        .onAppear {
            // Prefill what the user can SEE (display-rounded) — a raw FX/flow residue like
            // "117623.632489346" is unreadable and re-saves as a junk correction.
            if amountText.isEmpty, let expected, expected > 0 {
                amountText = "\(Money(amount: expected, currency: currency).roundedAmount())"
            }
        }
    }

    private var counterDisclosure: some View {
        DisclosureGroup("Count the notes instead", isExpanded: $showCounter) {
            VStack(spacing: 2) {
                ForEach(Denominations.notes(for: currency) + Denominations.coins(for: currency),
                        id: \.self) { d in
                    HStack {
                        Text("\(d)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 76, alignment: .leading)
                        Spacer()
                        Stepper(value: Binding(
                            get: { tally.counts[d] ?? 0 },
                            set: { tally.counts[d] = $0 > 0 ? $0 : nil
                                   amountText = "\(tally.total)" }),
                                in: 0...200) {
                            Text("\(tally.counts[d] ?? 0)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(GoldengoTheme.inkMuted)
    }
}
