import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The History browser: a fixed Day/Week/Month/Year toggle + period stepper on top, then the
/// selected period's expenses grouped and collapsible (by day; by month for Year). Pushed from Home.
public struct HistoryView: View {
    private let model: HistoryModel
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ExpenseSnapshot?
    /// Single-slot undo (mirrors Home): a second delete before the toast expires commits the first.
    /// Acceptable because deletes are soft/reversible in the store — the toast is a convenience, not
    /// the only recovery path.
    @State private var recentlyDeleted: ExpenseSnapshot?
    @State private var undoDeadline: Date?
    private let undoWindow: TimeInterval = 4
    /// Folded sections, keyed by start-of-day/month. Expanded by default; session-only.
    @State private var collapsedGroups: Set<Date> = []

    public init(model: HistoryModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            scalePicker
            periodStepper
            summary
            periodList
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
#if canImport(UIKit)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .task { await model.appear() }
        .sheet(item: $editing) { snap in
            EditExpenseView(
                snapshot: snap,
                fundingSources: [],   // source-pinning picker is Home-only in v1 (hidden when empty)
                onSave: { amt, cur, m, n, c, d, pin in
                    Task { await model.update(snap, amount: amt, currency: cur, merchant: m, note: n,
                                              categoryName: c, date: d, fundedBySourceID: pin) }
                },
                onDelete: { deleteWithUndo(snap) }
            )
        }
        .overlay(alignment: .bottom) {
            if let snap = recentlyDeleted {
                undoToast(snap)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: recentlyDeleted?.dedupeKey) {
            guard recentlyDeleted != nil, let deadline = undoDeadline else { return }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { recentlyDeleted = nil; return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { recentlyDeleted = nil }
        }
    }

    // MARK: - Top bar (chromeless back + title)

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Text("Home").font(.system(size: 15))
                }
                .foregroundStyle(GoldengoTheme.inkMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .overlay {
            Text("History")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Scale toggle (Day / Week / Month / Year)

    private var scalePicker: some View {
        HStack(spacing: 0) {
            ForEach(PeriodScale.allCases) { s in
                let selected = model.scale == s
                Button { Task { await model.setScale(s) } } label: {
                    Text(s.title)
                        .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? GoldengoTheme.onAccent : GoldengoTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selected { RoundedRectangle(cornerRadius: 9).fill(GoldengoTheme.accent) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.goldengoField))
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .animation(.snappy, value: model.scale)
    }

    // MARK: - Period stepper (‹ label ›)

    private var periodStepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", enabled: true) { Task { await model.stepBackward() } }
            Spacer()
            Text(model.periodLabel)
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .contentTransition(.opacity)
            Spacer()
            stepButton("chevron.right", enabled: model.canStepForward) { Task { await model.stepForward() } }
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.top, 16)
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel(icon == "chevron.left" ? "Previous period" : "Next period")
    }

    // MARK: - Summary (spent + count)

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SPENT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(GoldengoTheme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                GoldengoAmountText(model.totalSpentText, role: .title)
                if model.expenseCount > 0 {
                    Text("· \(model.expenseCount) \(model.expenseCount == 1 ? "expense" : "expenses")")
                        .font(.system(size: 13))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - The grouped, collapsible list

    private var periodList: some View {
        List {
            if model.loadFailed {
                Label("Couldn't load this period. Pull to refresh.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .goldengoHistoryRow()
            }
            if model.rows.isEmpty && !model.loadFailed {
                emptyCard.goldengoHistoryRow()
            } else {
                ForEach(model.groups) { group in
                    Section {
                        if !collapsedGroups.contains(group.id) {
                            ForEach(group.rows, id: \.dedupeKey) { r in historyRow(r) }
                        }
                    } header: {
                        groupHeader(group)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.goldengoBackground)
        .refreshable { await model.load() }
        // No bottom inset here: the parent Home tab already reserves it, and the custom tab bar is
        // hidden while History is pushed — adding another would double the bottom gap.
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 26))
                .foregroundStyle(GoldengoTheme.inkMuted)
            Text("Nothing here")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text("No spending in this period.")
                .font(.system(size: 13))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func groupHeader(_ group: DayGroup) -> some View {
        let collapsed = collapsedGroups.contains(group.id)
        return Button {
            withAnimation(.snappy) {
                if collapsed { collapsedGroups.remove(group.id) } else { collapsedGroups.insert(group.id) }
            }
        } label: {
            collapsibleGroupHeaderLabel(title: group.title, count: group.rows.count, collapsed: collapsed)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.goldengoBackground)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: GoldengoTheme.Spacing.m, bottom: 0, trailing: GoldengoTheme.Spacing.m))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title), \(group.rows.count) \(group.rows.count == 1 ? "expense" : "expenses"), \(collapsed ? "collapsed" : "expanded")")
        .accessibilityHint("Double tap to \(collapsed ? "expand" : "collapse")")
    }

    private func historyRow(_ r: ExpenseSnapshot) -> some View {
        Button { editing = r } label: {
            expenseHomeRow(r).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                  bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { deleteWithUndo(r) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { editing = r } label: { Label("Edit", systemImage: "pencil") }
                .tint(GoldengoTheme.accent)
        }
    }

    // MARK: - Delete + Undo (mirrors Home)

    private func deleteWithUndo(_ snapshot: ExpenseSnapshot) {
        Task {
            await model.delete(snapshot)
            undoDeadline = Date().addingTimeInterval(undoWindow)
            withAnimation(.snappy) { recentlyDeleted = snapshot }
        }
    }

    private func undoToast(_ snapshot: ExpenseSnapshot) -> some View {
        GoldengoToast(
            "\(snapshot.displayTitle) deleted",
            icon: "trash.fill",
            iconTint: GoldengoTheme.danger,
            actionTitle: "Undo",
            action: {
                Task {
                    await model.restore(snapshot)
                    withAnimation(.snappy) { recentlyDeleted = nil }
                }
            }
        )
        .padding(.horizontal, GoldengoTheme.Spacing.l)
        .padding(.bottom, GoldengoTheme.Spacing.m)
    }
}

private extension View {
    func goldengoHistoryRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.s, leading: GoldengoTheme.Spacing.m,
                                      bottom: GoldengoTheme.Spacing.s, trailing: GoldengoTheme.Spacing.m))
    }
}
