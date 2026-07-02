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
    @State private var showAdd = false   // ＋ / empty-state CTA → Add-subscription sheet
    @Environment(\.dismiss) private var dismiss
    public init(model: SubscriptionsModel) { self.model = model }

    /// Detected-but-unverified candidates (the user is asked to confirm or dismiss these).
    private var needsReview: [SubscriptionSnapshot] { model.rows.filter { !$0.isConfirmed } }
    /// Subscriptions the user has confirmed they want to track.
    private var tracked: [SubscriptionSnapshot] { model.rows.filter { $0.isConfirmed } }

    public var body: some View {
        NavigationStack {
            List {
                if needsReview.isEmpty && tracked.isEmpty && model.dismissedRows.isEmpty {
                    ContentUnavailableView {
                        Label("No subscriptions yet", systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text("Add one yourself, or import statements — when the same charge repeats, Goldengo lists it here.")
                    } actions: {
                        Button("Add a subscription") { showAdd = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldengoTheme.accent)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    if !needsReview.isEmpty {
                        Section {
                            ForEach(needsReview) { s in
                                row(s)
                                    .subscriptionRowStyle()
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("Not a subscription", role: .destructive) { dismissWithUndo(s) }
                                        Button("Confirm") { Task { await model.confirm(s) } }.tint(.green)
                                    }
                            }
                        } header: {
                            sectionHeader("Needs your review",
                                          hint: "Charges that look like they repeat. Swipe a row → “Confirm” it’s a subscription, or “Not a subscription.”")
                        }
                    }
                    if !tracked.isEmpty {
                        Section {
                            ForEach(tracked) { s in
                                row(s)
                                    .subscriptionRowStyle()
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("Not a subscription", role: .destructive) { dismissWithUndo(s) }
                                    }
                            }
                        } header: {
                            sectionHeader("Tracked", hint: "Subscriptions you’ve confirmed. Swipe to stop tracking.")
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
                            sectionHeader("Dismissed", hint: "You marked these “not a subscription.” Swipe to restore.")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Subscriptions")
            // An explicit close is required here: the list's pull-to-refresh captures the
            // downward drag that would otherwise swipe-dismiss the sheet.
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add subscription")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddSubscriptionView(model: model)
                    .presentationDetents([.medium, .large])
            }
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
                Spacer()
                Text(model.amountCadenceText(s)).font(.subheadline.weight(.semibold))
            }
            Text(chargedSummary(s)).font(.caption).foregroundStyle(.secondary)
            if hasTags(s) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    if !s.isConfirmed && s.confidence < 0.5 { metaTag("Not sure yet", systemImage: "questionmark.circle") }
                    if s.hadTrial { metaTag("Free trial", systemImage: "gift") }
                    if s.isVariableAmount { metaTag("Amount varies", systemImage: "waveform") }
                    Spacer()
                }
            }
        }
        .goldengoCard()
    }

    /// Plain-language summary, e.g. "Charged 3 times · Next: Jun 15, 2026" — replaces the old
    /// "N× seen" jargon and the raw confidence %.
    private func chargedSummary(_ s: SubscriptionSnapshot) -> String {
        switch s.occurrenceCount {
        case 0:  return "No recent charges"
        case 1:  return "Charged once · \(model.nextChargeText(s))"
        default: return "Charged \(s.occurrenceCount) times · \(model.nextChargeText(s))"
        }
    }

    private func hasTags(_ s: SubscriptionSnapshot) -> Bool {
        (!s.isConfirmed && s.confidence < 0.5) || s.hadTrial || s.isVariableAmount
    }

    private func sectionHeader(_ title: String, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .padding(.vertical, 2)
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
