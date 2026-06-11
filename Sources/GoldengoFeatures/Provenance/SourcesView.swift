import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Each named source as a draining pool, plus an Unaccounted row and an "Add income" entry.
public struct SourcesView: View {
    @State private var model: SourcesModel
    @State private var showAddIncome = false
    @State private var showCount = false
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
                // The Count (GOL-95): the physical wallet as a place. Never prompted — opened.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("In your wallet", systemImage: "wallet.bifold")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let w = model.wallet {
                            Text("~" + Money(amount: w.expectedNow, currency: .all).formatted())
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    HStack {
                        if let w = model.wallet {
                            Text("Counted " + w.baselineDate.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Count your wallet to begin.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Count") { showCount = true }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered).tint(GoldengoTheme.accent)
                    }
                }
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
            .sheet(isPresented: $showCount, onDismiss: { Task { await model.load() } }) {
                WalletCountView(model: model)
            }
            .task { await model.load() }
        }
    }
}
