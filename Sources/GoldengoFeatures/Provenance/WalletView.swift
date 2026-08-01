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
    @State private var selectedCurrency: CurrencyCode?
    @State private var showCurrencyPicker = false
    @State private var currencySelection = ""
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
    private func label(for code: String) -> String {
        if code == "ALL" { return "Lek (ALL)" }
        let name = Locale.current.localizedString(forCurrencyCode: code)
        return name.map { "\($0) (\(code))" } ?? code
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Physical cash only")
                            .font(.system(size: 23, design: .serif))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("Count what you carry. Cash expenses update the matching currency automatically.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if model.wallet.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wallet.bifold")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(GoldengoTheme.accent)
                            Text("No cash tracked")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(GoldengoTheme.inkPrimary)
                            Text("Choose a currency and enter the cash you have right now.")
                                .font(.system(size: 13))
                                .foregroundStyle(GoldengoTheme.inkMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .goldengoCard(padding: 16)
                    } else {
                        ForEach(model.wallet) { line in
                            cashCard(line)
                        }
                    }

                    if !untracked.isEmpty {
                        Button {
                            currencySelection = ""
                            showCurrencyPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(GoldengoTheme.accent)
                                    .frame(width: 38, height: 38)
                                    .background(GoldengoTheme.accentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.wallet.isEmpty ? "Start tracking cash" : "Track another currency")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(GoldengoTheme.inkPrimary)
                                    Text("Search once, then count it")
                                        .font(.system(size: 12))
                                        .foregroundStyle(GoldengoTheme.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(GoldengoTheme.inkMuted)
                            }
                            .padding(14)
                            .goldengoCard(padding: 0)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Removing a cash wallet stops tracking that currency; it does not delete past expenses.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .padding(.horizontal, 4)
                }
                .padding(GoldengoTheme.Spacing.m)
                .padding(.bottom, GoldengoTheme.Spacing.l)
            }
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Cash wallets")
            .walletInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(item: $selectedCurrency) { currency in
                AdjustWalletView(model: model, currency: currency, closeSheet: { dismiss() })
            }
            .onAppear {
                selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
                if let autoOpenAdjust { selectedCurrency = autoOpenAdjust }
            }
            .onChange(of: autoOpenAdjust) { _, target in
                if let target { selectedCurrency = target }
            }
            .sheet(isPresented: $showCurrencyPicker, onDismiss: {
                guard !currencySelection.isEmpty else { return }
                selectedCurrency = CurrencyCode(currencySelection)
            }) {
                NavigationStack {
                    CurrencyPickerView(available: untracked, selectedCode: $currencySelection)
                }
            }
        }
    }

    private func cashCard(_ line: WalletBalance) -> some View {
        let currency = CurrencyCode(line.currencyCode)
        return Button { selectedCurrency = currency } label: {
            HStack(spacing: 13) {
                Text(currency.symbol)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(label(for: line.currencyCode))
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("Counted " + SourcesModel.compactDay(line.baselineDate))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    GoldengoAmountText(Money(amount: line.expectedNow, currency: currency).formatted(), role: .row)
                    Text("Count again")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.accent)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
            .padding(16)
            .goldengoCard(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Set one currency's real balance (wallet.jsx AdjustSheet). Type the total or use the
/// denomination counter (DisclosureGroup + steppers) — both set the same number.
/// No ceremony on save: one result line, then dismiss. Lower than expected auto-logs Unaccounted.
struct AdjustWalletView: View {
    @State var model: SourcesModel
    let currency: CurrencyCode
    let closeSheet: () -> Void
    @State private var amountText = ""
    @State private var showCounter = false
    @State private var tally = DenominationTally()
    @State private var resultLine: String?
    @State private var busy = false
    @FocusState private var focused: Bool

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
        guard let exp = expected, let typed = typedAmount else { return nil }
        let g = typed - exp
        return abs(g) > (currency == .all ? 0 : Decimal(string: "0.001")!) ? g : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("How much cash is there?")
                            .font(.system(size: 23, design: .serif))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("Enter the real amount. We will reconcile it with the expected balance.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let expected {
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(GoldengoTheme.inkMuted)
                                .frame(width: 38, height: 38)
                                .background(Color.goldengoField)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("EXPECTED NOW")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .tracking(0.55)
                                    .foregroundStyle(GoldengoTheme.inkMuted)
                                GoldengoAmountText(Money(amount: expected, currency: currency).formatted(), role: .row)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .goldengoCard(padding: 0)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(currency.symbol)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                        TextField("0", text: $amountText)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                            .focused($focused)
                            .font(.system(size: 42, weight: .semibold).monospacedDigit())
                            .tracking(-1)
                            .foregroundStyle(amountText.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.inkPrimary)
                            .minimumScaleFactor(0.65)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 92)
                    .background(Color.goldengoSurface)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                            .strokeBorder(focused ? GoldengoTheme.accentLine : GoldengoTheme.hairline,
                                          lineWidth: focused ? 1.5 : 1)
                    }

                    reconciliationHint

                    if hasDenominationTable {
                        counterDisclosure
                    }

                    if let resultLine {
                        Text(resultLine)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(GoldengoTheme.danger)
                            .padding(.horizontal, 4)
                    }

                    if expected != nil {
                        Button(role: .destructive) {
                            Task {
                                await model.removeWalletCurrency(currency)
                                closeSheet()
                            }
                        } label: {
                            Text("Stop tracking \(currency.rawValue) cash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(GoldengoTheme.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(GoldengoTheme.Spacing.m)
                .padding(.bottom, 12)
            }

            GoldButton("Save cash count", isEnabled: !busy && typedAmount != nil) {
                save()
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.top, 10)
            .padding(.bottom, GoldengoTheme.Spacing.m)
            .background(Color.goldengoBackground)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .navigationTitle("Count \(currency.rawValue) cash")
        .walletInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { closeSheet() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .accessibilityLabel("Close cash count")
            }
        }
        .goldengoDismissKeyboard()
        .onAppear {
            // Prefill what the user can SEE (display-rounded) — a raw FX/flow residue like
            // "117623.632489346" is unreadable and re-saves as a junk correction.
            if amountText.isEmpty, let expected, expected > 0 {
                amountText = "\(Money(amount: expected, currency: currency).roundedAmount())"
            }
        }
    }

    @ViewBuilder
    private var reconciliationHint: some View {
        if let typedAmount, let expected {
            let difference = typedAmount - expected
            HStack(spacing: 10) {
                Image(systemName: gap == nil ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(gap == nil ? GoldengoTheme.income : GoldengoTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap == nil ? "Matches the expected balance" : "This count will reconcile the wallet")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    if difference < 0 {
                        Text(Money(amount: -difference, currency: currency).formatted()
                             + " short · marked as Needs review")
                            .font(.system(size: 11.5))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    } else if difference > 0 {
                        Text(Money(amount: difference, currency: currency).formatted()
                             + " over · added as a cash correction")
                            .font(.system(size: 11.5))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((gap == nil ? GoldengoTheme.income : GoldengoTheme.accent).opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private var counterDisclosure: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { showCounter.toggle() }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "banknote")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Count notes and coins")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("Optional · builds the total for you")
                            .font(.system(size: 11.5))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .rotationEffect(.degrees(showCounter ? 180 : 0))
                }
                .padding(15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCounter {
                Rectangle().fill(GoldengoTheme.hairline).frame(height: 1)
                VStack(spacing: 2) {
                    ForEach(Denominations.notes(for: currency) + Denominations.coins(for: currency),
                            id: \.self) { d in
                        HStack {
                            Text("\(d)")
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .frame(width: 76, alignment: .leading)
                            Spacer()
                            Stepper(value: Binding(
                                get: { tally.counts[d] ?? 0 },
                                set: {
                                    tally.counts[d] = $0 > 0 ? $0 : nil
                                    amountText = "\(tally.total)"
                                }), in: 0...200) {
                                Text("\(tally.counts[d] ?? 0)")
                                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .goldengoCard(padding: 0)
    }

    private func save() {
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
                    + " was marked Needs review. You can inspect it in Recent."
                busy = false
            } else {
                closeSheet()
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func walletInlineNavigationTitle() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}
