import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

public struct SubscriptionsView: View {
    @State private var model: SubscriptionsModel
    public init(model: SubscriptionsModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
                if model.rows.isEmpty {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView(
                            "No subscriptions detected",
                            systemImage: "repeat.circle",
                            description: Text("Import statements or log expenses, then pull to refresh."))
                    } else {
                        Text("No subscriptions detected yet.").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.rows) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.displayName).font(.headline)
                                if s.isConfirmed {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                }
                                Spacer()
                                Text(model.amountCadenceText(s)).font(.subheadline.bold())
                            }
                            Text(model.nextChargeText(s)).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text("\(s.occurrenceCount)×").font(.caption2)
                                if s.hadTrial { Label("trial", systemImage: "gift").font(.caption2) }
                                if s.isVariableAmount { Label("variable", systemImage: "waveform").font(.caption2) }
                                Spacer()
                                Text("\(Int((s.confidence * 100).rounded()))%")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .accessibilityLabel("\(Int((s.confidence * 100).rounded()))% confidence")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Not a subscription", role: .destructive) { Task { await model.dismiss(s) } }
                            if !s.isConfirmed {
                                Button("Confirm") { Task { await model.confirm(s) } }.tint(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Subscriptions")
            .refreshable { await model.load() }
            .onAppear { Task { await model.load() } }
        }
    }
}
