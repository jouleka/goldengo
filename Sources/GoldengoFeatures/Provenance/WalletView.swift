import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The wallet (GOL-95 v2): per-currency cash lines. Tap a line, type what's actually in your
/// pocket, Save — five seconds. The denomination grid is an optional helper that fills the same
/// number. Lower than expected auto-logs one visible "Unaccounted" entry; higher just is.
public struct WalletView: View {
    @State private var model: SourcesModel
    /// GOL-98: a widget tap lands straight on this currency's Adjust screen.
    let autoOpenAdjust: CurrencyCode?
    @State private var adjustPresented = false
    public init(model: SourcesModel, autoOpenAdjust: CurrencyCode? = nil) {
        _model = State(initialValue: model)
        self.autoOpenAdjust = autoOpenAdjust
    }

    /// Every catalog currency without a wallet line yet — the same catalog the Add-income and
    /// Settings pickers use (rate-table driven), not a hardcoded shortlist. The common Albanian
    /// pocket pair (lek, euro) is surfaced directly; the rest sit behind one "another currency" row.
    private var untracked: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
            .filter { c in !model.wallet.contains { $0.currencyCode == c.rawValue } }
    }
    private var quickAdds: [CurrencyCode] { untracked.filter { $0 == .all || $0 == .eur } }
    private var otherAdds: [CurrencyCode] { untracked.filter { $0 != .all && $0 != .eur } }

    /// Human label for a wallet line ("ALL" reads as the English word otherwise).
    private func label(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code)
        if code == "ALL" { return "Lek (ALL)" }
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
                ForEach(model.wallet) { line in
                    NavigationLink {
                        AdjustWalletView(model: model, currency: CurrencyCode(line.currencyCode))
                    } label: {
                        HStack {
                            Text(label(for: line.currencyCode)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("~" + Money(amount: line.expectedNow,
                                             currency: CurrencyCode(line.currencyCode)).formatted())
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .listRowBackground(Color.clear)
                }
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
            // GOL-98: a widget tap pushes straight to Adjust — the reconcile is the point.
            .navigationDestination(isPresented: $adjustPresented) {
                AdjustWalletView(model: model, currency: autoOpenAdjust ?? .all)
            }
            .onAppear { if autoOpenAdjust != nil { adjustPresented = true } }
        }
    }
}

/// Set one currency's real balance. Type it (prefilled with what the books expect) or open the
/// note counter to add it up — both feed the same number. No ceremony on save: one quiet line.
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
    /// STRICT parse: the whole string must be a plain non-negative amount (one optional decimal
    /// part). A pasted grouped amount ("10 000", "10,000") must REJECT — Decimal(string:)'s
    /// prefix-parsing would read it as 10 and auto-log a fabricated 9,990 gap (v2 review).
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                Text("What's in your wallet?").font(.title2.weight(.bold))
                if let expected {
                    Text("The books expect " + Money(amount: expected, currency: currency).formatted() + ".")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("0", text: $amountText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .focused($focused)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, GoldengoTheme.Spacing.s)

                if hasDenominationTable {
                    counterDisclosure
                }

                if let resultLine {
                    Text(resultLine).font(.caption).foregroundStyle(.secondary)
                }

                saveButton
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { focused = false }     // tap-outside dismissal (no keyboard toolbar)
        .onAppear {
            if amountText.isEmpty, let expected, expected > 0 { amountText = "\(expected)" }
        }
    }

    private var counterDisclosure: some View {
        DisclosureGroup("Count the notes instead", isExpanded: $showCounter) {
            VStack(spacing: 2) {
                ForEach(Denominations.notes(for: currency) + Denominations.coins(for: currency),
                        id: \.self) { d in
                    HStack {
                        Text("\(d)").font(.headline.monospacedDigit())
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
        .font(.caption).foregroundStyle(.secondary)
    }

    private var saveButton: some View {
        Button {
            guard !busy, let total = typedAmount else { return }
            busy = true
            focused = false
            GoldengoHaptics.spendLanded()
            Task {
                // Persist the tally only when it actually IS the saved number — the user may
                // have counted, then corrected the text by hand (review: no stale tallies).
                let tallyToSave = (showCounter && tally.total == total) ? tally : nil
                let outcome = await model.setWalletBalance(total, currency: currency, tally: tallyToSave)
                if outcome == nil {
                    // Store failure must never look like success (review finding).
                    resultLine = "Couldn't save — try again."
                    busy = false
                } else if let gap = outcome?.unaccountedLogged {
                    resultLine = Money(amount: gap, currency: currency).formatted()
                        + " logged as Unaccounted — delete it in Recent if that's wrong."
                    busy = false   // let the line be read; user leaves via Back
                } else {
                    dismiss()
                }
            }
        } label: {
            Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
        }
        .background(GoldengoTheme.accent).foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
        .disabled(busy || typedAmount == nil)
    }
}
