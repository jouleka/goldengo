import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

public struct RecentExpensesView: View {
    @State private var model: RecentExpensesModel
    @State private var editing: ExpenseSnapshot?
    /// The just-deleted expense, surfaced in the Undo toast until it auto-dismisses or is undone.
    @State private var recentlyDeleted: ExpenseSnapshot?
    /// dedupeKey of the recent row currently showing its swipe actions — only one at a time.
    @State private var openRowID: String?
    private let onAdd: () -> Void
    private let onOpenImport: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenSubscriptions: () -> Void

    public init(model: RecentExpensesModel,
                onAdd: @escaping () -> Void = {},
                onOpenImport: @escaping () -> Void = {},
                onOpenSettings: @escaping () -> Void = {},
                onOpenSubscriptions: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onAdd = onAdd
        self.onOpenImport = onOpenImport
        self.onOpenSettings = onOpenSettings
        self.onOpenSubscriptions = onOpenSubscriptions
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: GoldengoTheme.Spacing.m) {
                    if model.loadFailed { errorBanner }
                    monthCard
                    if model.subscriptionsText() != nil { subscriptionsCard }
                    if let s = model.summary, !s.topCategories.isEmpty { categoriesCard(s) }
                    recentCard
                }
                .padding(GoldengoTheme.Spacing.m)
            }
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Goldengo")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { onOpenImport() } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import statement")
                    Button { onOpenSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .refreshable { await model.load() }
            .onAppear { Task { await model.load() } }
            .sheet(item: $editing) { snap in
                EditExpenseView(
                    snapshot: snap,
                    currency: model.currency,
                    onSave: { amt, m, c, d in
                        Task { await model.update(snap, amount: amt, merchant: m, categoryName: c, date: d) }
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
            // Auto-dismiss the toast ~4s after the latest delete. Keying the task on the deleted
            // row restarts the timer on a new delete and cancels it the moment Undo clears it.
            .task(id: recentlyDeleted?.dedupeKey) {
                guard recentlyDeleted != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { recentlyDeleted = nil }
            }
        }
    }

    // MARK: - Delete + Undo

    /// Soft-delete immediately (the row collapses away), then surface the Undo toast. No modal —
    /// the delete is reversible, which is friendlier than a pre-confirmation dialog. The toast holds
    /// a single most-recent deletion: a second delete replaces it (the earlier row stays deleted,
    /// re-addable) — standard "latest action" undo, safe because the soft-delete loses nothing.
    private func deleteWithUndo(_ snapshot: ExpenseSnapshot) {
        Task {
            await model.delete(snapshot)
            withAnimation(.snappy) { recentlyDeleted = snapshot }
        }
    }

    private func undoDelete(_ snapshot: ExpenseSnapshot) {
        Task {
            await model.restore(snapshot)
            withAnimation(.snappy) { recentlyDeleted = nil }
        }
    }

    /// Slim, on-brand toast that floats above the tab bar after a delete.
    private func undoToast(_ snapshot: ExpenseSnapshot) -> some View {
        HStack(spacing: GoldengoTheme.Spacing.m) {
            Image(systemName: "trash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(snapshot.merchantName ?? snapshot.categoryName ?? "Expense") deleted")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: GoldengoTheme.Spacing.m)
            Button("Undo") { undoDelete(snapshot) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GoldengoTheme.accent)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.vertical, GoldengoTheme.Spacing.s + 2)
        .background(
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous)
                .fill(Color.goldengoSurface)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        )
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.bottom, GoldengoTheme.Spacing.s)
    }

    // MARK: - Cards

    private var errorBanner: some View {
        Label("Couldn't load your expenses. Pull to refresh.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .goldengoCard()
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.xs) {
                    GoldengoSectionLabel("This month")
                    Text(model.monthTotalText())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, GoldengoTheme.Spacing.m)
                        .padding(.vertical, GoldengoTheme.Spacing.s)
                        .background(GoldengoTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Label("Today", systemImage: "sun.max")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.todayTotalText)
                    .font(.headline)
            }
        }
        .goldengoCard(padding: GoldengoTheme.Spacing.l)
    }

    private var subscriptionsCard: some View {
        Button(action: onOpenSubscriptions) {
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscriptions").font(.subheadline.weight(.semibold))
                    if let subs = model.subscriptionsText() {
                        Text(subs).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .goldengoCard()
        }
        .buttonStyle(.plain)
    }

    private func categoriesCard(_ s: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.m) {
            GoldengoSectionLabel("Top categories")
            ForEach(s.topCategories) { c in
                VStack(spacing: 6) {
                    HStack {
                        Label(c.name, systemImage: GoldengoCategoryIcon.symbol(for: c.name))
                            .font(.subheadline)
                            .labelStyle(.titleAndIcon)
                        Spacer()
                        Text(model.categoryTotalText(c.total))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    categoryBar(fraction: model.categoryFraction(c.total))
                }
            }
        }
        .goldengoCard(padding: GoldengoTheme.Spacing.l)
    }

    private func categoryBar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.goldengoField)
                Capsule().fill(GoldengoTheme.accent)
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.s) {
            GoldengoSectionLabel("Recent")
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No expenses yet",
                    systemImage: "tray",
                    description: Text("Tap Add to log your first.")
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(model.rows, id: \.dedupeKey) { r in
                    if r.dedupeKey != model.rows.first?.dedupeKey { Divider() }
                    SwipeableRow(
                        id: r.dedupeKey,
                        openRowID: $openRowID,
                        leading: .edit { editing = r },
                        trailing: .delete { deleteWithUndo(r) },
                        onTap: { editing = r }
                    ) {
                        expenseRow(r)
                    }
                }
            }
        }
        .goldengoCard(padding: GoldengoTheme.Spacing.l)
        .animation(.snappy, value: model.rows)
    }

    private func expenseRow(_ r: ExpenseSnapshot) -> some View {
        HStack(spacing: GoldengoTheme.Spacing.m) {
            Image(systemName: GoldengoCategoryIcon.symbol(for: r.categoryName))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.goldengoField)
                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(r.merchantName ?? r.categoryName ?? "Expense")
                        .font(.subheadline.weight(.medium))
                    if r.subscriptionName != nil {
                        Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(r.categoryName ?? "Uncategorized")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if r.kind == .income {
                Text("+" + Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted())
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.vertical, 4)
    }
}
