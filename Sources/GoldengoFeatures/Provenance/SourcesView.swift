import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Each named source as a draining pool, plus an Unaccounted row and an "Add income" entry.
public struct SourcesView: View {
    @State private var model: SourcesModel
    @State private var showAddIncome = false
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
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
            }
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Sources")
            .overlay {
                if (model.snapshot?.sources.isEmpty ?? true) && model.unaccountedText() == nil {
                    ContentUnavailableView("No sources yet", systemImage: "tray",
                        description: Text("Add where your money came from — a remittance, a cash withdrawal, your pay."))
                }
            }
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
            .task { await model.load() }
        }
    }
}
