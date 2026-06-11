import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The wallet (GOL-95 v2): per-currency cash lines. Tap a line, type what's actually in your
/// pocket, Save — five seconds. The denomination grid is an optional helper that fills the same
/// number. Lower than expected auto-logs one visible "Unaccounted" entry; higher just is.
public struct WalletView: View {
    @State private var model: SourcesModel
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    /// Currencies offered for a first line, beyond what already exists.
    private var addable: [CurrencyCode] {
        [CurrencyCode.all, .eur, CurrencyCode("USD")]
            .filter { c in !model.wallet.contains { $0.currencyCode == c.rawValue } }
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(model.wallet) { line in
                    NavigationLink {
                        AdjustWalletView(model: model, currency: CurrencyCode(line.currencyCode))
                    } label: {
                        HStack {
                            Text(line.currencyCode).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("~" + Money(amount: line.expectedNow,
                                             currency: CurrencyCode(line.currencyCode)).formatted())
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if !addable.isEmpty {
                    Section {
                        ForEach(addable, id: \.rawValue) { c in
                            NavigationLink {
                                AdjustWalletView(model: model, currency: c)
                            } label: {
                                Label("Track \(c.rawValue) cash", systemImage: "plus.circle")
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
    private var typedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
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

                if let resultLine {
                    Text(resultLine).font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    guard !busy, let total = typedAmount, total >= 0 else { return }
                    busy = true
                    focused = false
                    GoldengoHaptics.spendLanded()
                    Task {
                        let outcome = await model.setWalletBalance(
                            total, currency: currency, tally: showCounter ? tally : nil)
                        if let gap = outcome?.unaccountedLogged {
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
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { focused = false }     // tap-outside dismissal (no keyboard toolbar)
        .onAppear {
            if amountText.isEmpty, let expected, expected > 0 { amountText = "\(expected)" }
        }
    }
}
