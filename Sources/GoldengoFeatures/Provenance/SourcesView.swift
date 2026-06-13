import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData

/// Each named source as a draining pool, plus an Unaccounted row and an "Add income" entry.
public struct SourcesView: View {
    @State private var model: SourcesModel
    @State private var showAddIncome = false
    @State private var showCount = false
    @State private var walletAutoAdjust = false   // GOL-98: widget tap lands ON the Adjust screen
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    /// Consume the one-shot widget deep-link flag: open the wallet sheet straight at Adjust.
    private func consumePendingWalletAdjust() {
        guard model.pendingWalletAdjust else { return }
        model.pendingWalletAdjust = false
        walletAutoAdjust = true
        showCount = true
    }

    /// Where a widget tap lands (GOL-98 review): the wallet's own composition decides — ALL
    /// when tracked, else the sole tracked currency; nil (the wallet list) when empty or
    /// ambiguous, so a tap can never open a numpad for a currency the user doesn't carry.
    private func walletAdjustTarget() -> CurrencyCode? {
        let codes = model.wallet.map(\.currencyCode)
        if codes.contains(CurrencyCode.all.rawValue) { return .all }
        if codes.count == 1, let only = codes.first { return CurrencyCode(only) }
        return nil
    }

    public var body: some View {
        NavigationStack {
            List {
                if model.loadFailed {
                    HStack(spacing: GoldengoTheme.Spacing.s) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Couldn't load your money. Pull to refresh.")
                    }
                    .font(.subheadline).foregroundStyle(GoldengoTheme.danger)
                    .listRowBackground(Color.clear)
                }
                // The wallet (GOL-95 v2): per-currency cash, money moving through. Tap to adjust.
                Button { showCount = true } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("In your wallet", systemImage: "wallet.bifold")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if !model.wallet.isEmpty {
                                Text(model.wallet.map {
                                    "~" + Money(amount: $0.expectedNow,
                                                currency: CurrencyCode($0.currencyCode)).formatted()
                                }.joined(separator: " · "))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(GoldengoTheme.inkPrimary)
                            }
                        }
                        Text(model.wallet.isEmpty
                             ? "Tap to set what's in your pocket."
                             : "Tap to adjust — cash spends drain this, not your sources.")
                            .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)

                ForEach(model.snapshot?.sources ?? []) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(model.color(b)).frame(width: 9, height: 9)
                            Text(b.name).font(.subheadline.weight(.semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                            Spacer()
                            GoldengoAmountText(model.remainingText(b), role: .row)
                        }
                        DrainingPoolBar(fraction: model.fraction(b), tint: model.color(b))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(b.name), \(model.remainingText(b)) left, \(Int((model.fraction(b) * 100).rounded()))% remaining")
                }
                if let unaccounted = model.unaccountedText() {
                    HStack {
                        Label("Unaccounted", systemImage: "questionmark.circle")
                            .font(.subheadline).foregroundStyle(GoldengoTheme.inkMuted)
                        Spacer()
                        Text(unaccounted).font(.subheadline.weight(.medium)).foregroundStyle(GoldengoTheme.inkMuted)
                    }
                    .listRowBackground(Color.clear)
                }

                // In-list empty state (not an .overlay — it must never cover the wallet card).
                if (model.snapshot?.sources.isEmpty ?? true) && model.unaccountedText() == nil {
                    ContentUnavailableView("No sources yet", systemImage: "tray",
                        description: Text("Add where your money came from — a remittance, a cash withdrawal, your pay."))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await model.load() }
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddIncome = true } label: { Label("Add income", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showAddIncome, onDismiss: { Task { await model.load() } }) {
                AddIncomeView(model: model,
                              existingSources: (model.snapshot?.sources ?? []).map(\.name),
                              currency: model.currency, onDone: { showAddIncome = false })
            }
            .sheet(isPresented: $showCount, onDismiss: {
                walletAutoAdjust = false
                Task { await model.load() }
            }) {
                WalletView(model: model, autoOpenAdjust: walletAutoAdjust ? walletAdjustTarget() : nil)
            }
            .task { await model.load(); consumePendingWalletAdjust() }
            // A tap can arrive while this tab is already live (warm open, or the wallet sheet
            // itself is up) — observe the flag, don't wait for scene phases (GOL-98 review).
            .onChange(of: model.pendingWalletAdjust) { _, on in if on { consumePendingWalletAdjust() } }
        }
    }
}
