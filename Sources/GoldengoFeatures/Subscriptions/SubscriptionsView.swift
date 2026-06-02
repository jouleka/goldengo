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
                    ContentUnavailableView(
                        "No subscriptions detected",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Import statements or log expenses, then pull to refresh."))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Text("Auto-detected from your recurring charges — swipe a row to confirm or mark “Not a subscription.” Deleting a single expense won't remove one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.s, leading: GoldengoTheme.Spacing.m,
                                                  bottom: GoldengoTheme.Spacing.s, trailing: GoldengoTheme.Spacing.m))
                    ForEach(model.rows) { s in
                        row(s)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                                      bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Not a subscription", role: .destructive) { Task { await model.dismiss(s) } }
                                if !s.isConfirmed {
                                    Button("Confirm") { Task { await model.confirm(s) } }.tint(.green)
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Subscriptions")
            .refreshable { await model.load() }
            .onAppear { Task { await model.load() } }
        }
    }

    private func row(_ s: SubscriptionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.s) {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                Text(s.displayName).font(.headline)
                if s.isConfirmed {
                    Image(systemName: "checkmark.seal.fill").font(.subheadline).foregroundStyle(.green)
                }
                Spacer()
                Text(model.amountCadenceText(s)).font(.subheadline.weight(.semibold))
            }
            Text(model.nextChargeText(s)).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: GoldengoTheme.Spacing.s) {
                metaTag("\(s.occurrenceCount)× seen", systemImage: "number")
                if s.hadTrial { metaTag("trial", systemImage: "gift") }
                if s.isVariableAmount { metaTag("variable", systemImage: "waveform") }
                Spacer()
                Text("\(Int((s.confidence * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, GoldengoTheme.Spacing.s)
                    .padding(.vertical, 3)
                    .background(GoldengoTheme.accentSoft)
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                    .accessibilityLabel("\(Int((s.confidence * 100).rounded()))% confidence")
            }
        }
        .goldengoCard()
    }

    private func metaTag(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
