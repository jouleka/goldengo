import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The Count (GOL-95): tap the notes actually in your hand. Steppers only — no keyboard.
/// After save, the same sheet shows the drift moment: keep the gap as street money, or let it go.
public struct WalletCountView: View {
    @State private var model: SourcesModel
    @State private var tally = DenominationTally()
    @State private var outcome: WalletCountOutcome?
    @Environment(\.dismiss) private var dismiss
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                if let outcome {
                    driftMoment(outcome)
                } else {
                    countGrid
                }
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
    }

    private var countGrid: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
            Text("Count your wallet").font(.title2.weight(.bold))
            Text(Money(amount: tally.total, currency: .all).formatted())
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.numericText())
                .animation(.snappy, value: tally.total)
            ForEach(Denominations.lekNotes + Denominations.lekCoins, id: \.self) { d in
                denominationRow(d)
            }
            Button {
                GoldengoHaptics.spendLanded()
                Task { outcome = await model.countWallet(tally) }
            } label: {
                Text("Save count").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
            }
            .background(GoldengoTheme.accent).foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
            .disabled(tally.total == 0)
        }
    }

    private func denominationRow(_ d: Int) -> some View {
        HStack {
            Text("\(d)").font(.headline.monospacedDigit())
                .frame(width: 76, alignment: .leading)
            Spacer()
            Stepper(value: Binding(get: { tally.counts[d] ?? 0 },
                                   set: { tally.counts[d] = $0 > 0 ? $0 : nil }),
                    in: 0...200) {
                Text("\(tally.counts[d] ?? 0)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func driftMoment(_ o: WalletCountOutcome) -> some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
            if let drift = o.drift, drift < 0 {
                Text("Counted " + Money(amount: o.countedTotal, currency: .all).formatted())
                    .font(.title3.weight(.semibold))
                Text(Money(amount: -drift, currency: .all).formatted()
                     + " slipped by since the last count — keep it as street money?")
                    .font(.body).foregroundStyle(.secondary)
                Button {
                    GoldengoHaptics.spendLanded()
                    Task { await model.keepDrift(-drift); dismiss() }
                } label: {
                    Text("Keep it").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                }
                .background(GoldengoTheme.accent).foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                Button("Let it go") { dismiss() }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                if let drift = o.drift, drift > 0 {
                    Text("Your wallet is " + Money(amount: drift, currency: .all).formatted()
                         + " ahead of the books — baseline updated.")
                        .font(.body).foregroundStyle(.secondary)
                } else {
                    Text("Books and pocket agree. Nice.")
                        .font(.body).foregroundStyle(.secondary)
                }
                Button(action: { dismiss() }) {
                    Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                }
                .background(GoldengoTheme.accent).foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
            }
        }
    }
}
