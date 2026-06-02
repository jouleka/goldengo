import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

public struct SubscriptionsView: View {
    /// Owned by `RootView` (so detection can be re-run on tab-return / after an import); observed
    /// here via @Observable.
    private let model: SubscriptionsModel
    /// The just-dismissed subscription, surfaced in an Undo toast until it auto-dismisses or is undone.
    @State private var recentlyDismissed: SubscriptionSnapshot?
    @State private var undoDeadline: Date?
    private let undoWindow: TimeInterval = 4
    public init(model: SubscriptionsModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            List {
                if model.rows.isEmpty && model.dismissedRows.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions detected",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Import statements or log expenses, then pull to refresh."))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    if !model.rows.isEmpty {
                        Text("Auto-detected from your recurring charges — swipe a row to confirm or mark “Not a subscription.” Deleting a single expense won't remove one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.s, leading: GoldengoTheme.Spacing.m,
                                                      bottom: GoldengoTheme.Spacing.s, trailing: GoldengoTheme.Spacing.m))
                        ForEach(model.rows) { s in
                            row(s)
                                .subscriptionRowStyle()
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Not a subscription", role: .destructive) { dismissWithUndo(s) }
                                    if !s.isConfirmed {
                                        Button("Confirm") { Task { await model.confirm(s) } }.tint(.green)
                                    }
                                }
                        }
                    }
                    if !model.dismissedRows.isEmpty {
                        Section {
                            ForEach(model.dismissedRows) { s in
                                row(s)
                                    .opacity(0.6)
                                    .subscriptionRowStyle()
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button { Task { await model.unDismiss(s) } } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }
                                        .tint(.green)
                                    }
                            }
                        } header: {
                            Text("Dismissed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Subscriptions")
            .refreshable { await model.load() }
            // First-load net (covers cold-launch straight to this tab via a deep link, which a
            // selectedTab onChange can miss). Re-entry refresh is driven by RootView's onChange;
            // load()'s `isLoading` guard makes any overlap a no-op.
            .task { await model.load() }
            .overlay(alignment: .bottom) {
                if let s = recentlyDismissed {
                    GoldengoToast("\(s.displayName) dismissed", icon: "xmark.circle.fill",
                                  iconTint: .secondary, actionTitle: "Undo") { undoDismiss(s) }
                        .padding(.horizontal, GoldengoTheme.Spacing.l)
                        .padding(.bottom, GoldengoTheme.Spacing.m)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task(id: recentlyDismissed?.id) {
                guard recentlyDismissed != nil, let deadline = undoDeadline else { return }
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { recentlyDismissed = nil; return }
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { recentlyDismissed = nil }
            }
        }
    }

    /// Dismiss now, then surface an Undo toast. The subscription also drops into the "Dismissed"
    /// section below, so it's restorable either way.
    private func dismissWithUndo(_ s: SubscriptionSnapshot) {
        Task {
            await model.dismiss(s)
            undoDeadline = Date().addingTimeInterval(undoWindow)
            withAnimation(.snappy) { recentlyDismissed = s }
        }
    }

    private func undoDismiss(_ s: SubscriptionSnapshot) {
        Task {
            await model.unDismiss(s)
            withAnimation(.snappy) { recentlyDismissed = nil }
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

private extension View {
    /// Shared list-row chrome for subscription rows: clear background, no separators, card margins.
    func subscriptionRowStyle() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                      bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
    }
}
