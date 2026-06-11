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
    @Environment(\.scenePhase) private var scenePhase
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    /// Consume the one-shot widget deep-link flag: open the wallet sheet straight at Adjust.
    private func consumePendingWalletAdjust() {
        let summary = SharedSummary()
        guard summary.readPendingWalletAdjust() else { return }
        summary.setPendingWalletAdjust(false)
        walletAutoAdjust = true
        showCount = true
    }

    public var body: some View {
        NavigationStack {
            List {
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
                            }
                        }
                        Text(model.wallet.isEmpty
                             ? "Tap to set what's in your pocket."
                             : "Tap to adjust — cash spends drain this, not your sources.")
                            .font(.caption).foregroundStyle(.secondary)
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
                            Text(b.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(model.remainingText(b)).font(.subheadline.weight(.medium))
                        }
                        ProgressView(value: model.fraction(b))
                            .tint(model.color(b))
                            .animation(.snappy, value: model.fraction(b))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
                if let unaccounted = model.unaccountedText() {
                    HStack {
                        Label("Unaccounted", systemImage: "questionmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(unaccounted).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
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
                WalletView(model: model, autoOpenAdjust: walletAutoAdjust ? .all : nil)
            }
            .task { await model.load(); consumePendingWalletAdjust() }
            .onChange(of: scenePhase) { _, p in if p == .active { consumePendingWalletAdjust() } }
        }
    }
}
