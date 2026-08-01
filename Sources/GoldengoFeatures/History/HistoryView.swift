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
    @State private var showFilters = false

    public init(model: HistoryModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            searchBar
            if model.isSearchMode {
                searchSummary
                searchList
            } else {
                scalePicker
                periodStepper
                summary
                periodList
            }
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
#if canImport(UIKit)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .task { await model.appear() }
        .task(id: model.searchText) {
            guard model.isSearchMode else { model.clearSearch(); return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await model.search()
        }
        .sheet(isPresented: $showFilters) {
            HistoryFilterSheet(model: model).presentationDetents([.large])
        }
        .sheet(item: $editing) { snap in
            EditExpenseView(
                snapshot: snap,
                fundingSources: [],   // source-pinning picker is Home-only in v1 (hidden when empty)
                onSave: { amt, cur, m, n, c, d, pin, context, splits, kind in
                    Task { await model.update(snap, amount: amt, currency: cur, merchant: m, note: n,
                                              categoryName: c, date: d, fundedBySourceID: pin,
                                              contextName: context, splits: splits, kind: kind) }
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

    // MARK: - Search

    private var searchBar: some View {
        @Bindable var bindableModel = model
        return HStack(spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(GoldengoTheme.inkMuted)
                TextField("Find merchant, category, note or amount", text: $bindableModel.searchText)
                    .font(.system(size: 14.5, weight: .medium))
                    .submitLabel(.search)
                    .onSubmit { Task { await model.search() } }
                if !model.searchText.isEmpty {
                    Button { model.searchText = ""; Task { await model.search() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(GoldengoTheme.inkMuted)
                    }.buttonStyle(.plain).accessibilityLabel("Clear search text")
                }
            }
            .padding(.horizontal, 13).frame(height: 44)
            .background(Color.goldengoField).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            Button {
                Task { await model.prepareSearchFacets(); showFilters = true }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(model.activeFilterCount > 0 ? Color.goldengoBackground : GoldengoTheme.inkPrimary)
                        .frame(width: 44, height: 44)
                        .background(model.activeFilterCount > 0 ? GoldengoTheme.accent : Color.goldengoField)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    if model.activeFilterCount > 0 {
                        Text("\(model.activeFilterCount)").font(.system(size: 9, weight: .bold)).foregroundStyle(GoldengoTheme.accent)
                            .frame(width: 18, height: 18).background(Color.goldengoBackground).clipShape(Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            }.buttonStyle(.plain).accessibilityLabel("Filter transactions")
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.bottom, 12)
    }

    private var searchSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.searchRows.count) \(model.searchRows.count == 1 ? "result" : "results")")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                Text("Across your full history").font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
            }
            Spacer()
            Button("Clear") { model.clearSearch() }.font(.system(size: 13.5, weight: .semibold)).foregroundStyle(GoldengoTheme.accent)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m).padding(.bottom, 6)
    }

    private var searchList: some View {
        List {
            if model.searchFailed {
                Label("Couldn’t search right now. Tap to retry.", systemImage: "exclamationmark.triangle.fill")
                    .onTapGesture { Task { await model.search() } }.goldengoHistoryRow()
            } else if model.searchRows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 25)).foregroundStyle(GoldengoTheme.inkMuted)
                    Text("No matching transactions").font(.system(size: 15, weight: .semibold))
                    Text("Try fewer filters or a different word.").font(.system(size: 13)).foregroundStyle(GoldengoTheme.inkMuted)
                }.frame(maxWidth: .infinity).padding(.vertical, 34).goldengoHistoryRow()
            } else {
                ForEach(model.searchGroups) { group in
                    Section {
                        ForEach(group.rows, id: \.dedupeKey) { historyRow($0) }
                    } header: { collapsibleGroupHeaderLabel(title: group.title, count: group.rows.count, collapsed: false) }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Color.goldengoBackground)
        .refreshable { await model.search() }
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

private struct HistoryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: HistoryModel
    @State private var criteria: TransactionSearchCriteria
    @State private var dateRange: DateRangeChoice
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var minimum: String
    @State private var maximum: String
    @State private var showCategories = false

    private enum DateRangeChoice: String, CaseIterable, Identifiable {
        case any, thirtyDays, thisYear, custom
        var id: String { rawValue }
        var title: String {
            switch self { case .any: return "Any time"; case .thirtyDays: return "30 days"; case .thisYear: return "This year"; case .custom: return "Custom" }
        }
    }

    init(model: HistoryModel) {
        self.model = model
        let current = model.searchFilters
        _criteria = State(initialValue: current)
        let hasDates = current.startDate != nil || current.endDate != nil
        _dateRange = State(initialValue: hasDates ? .custom : .any)
        _startDate = State(initialValue: current.startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now)
        _endDate = State(initialValue: current.endDate ?? .now)
        _minimum = State(initialValue: current.minimumAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _maximum = State(initialValue: current.maximumAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $criteria.scope) {
                        ForEach(TransactionSearchScope.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                } header: { GoldengoSerifSectionHeader("Money movement") }

                Section {
                    Button { showCategories = true } label: {
                        filterSelectionRow(icon: "tag.fill", title: "Category", value: criteria.categoryName ?? "Any")
                    }
                    if criteria.categoryName != nil { Button("Clear category") { criteria.categoryName = nil }.foregroundStyle(GoldengoTheme.accent) }
                } header: { GoldengoSerifSectionHeader("Category") }

                if !contextOptions.isEmpty {
                    Section {
                        chipScroller(options: contextOptions, selection: $criteria.contextName)
                    } header: { GoldengoSerifSectionHeader("Context") }
                }

                if !model.searchFacets.fundingNames.isEmpty {
                    Section {
                        chipScroller(options: model.searchFacets.fundingNames, selection: $criteria.fundingName)
                    } header: { GoldengoSerifSectionHeader("Paid from") }
                }

                Section {
                    Picker("Date range", selection: $dateRange) {
                        ForEach(DateRangeChoice.allCases) { Text($0.title).tag($0) }
                    }
                    if dateRange == .custom {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                        DatePicker("Through", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: { GoldengoSerifSectionHeader("When") }

                Section {
                    HStack {
                        TextField("Minimum", text: $minimum).historyDecimalKeyboard()
                        Text("to").foregroundStyle(GoldengoTheme.inkMuted)
                        TextField("Maximum", text: $maximum).historyDecimalKeyboard()
                    }
                    Text("Amounts use each transaction’s original currency.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Amount") }

                Section {
                    Button("Reset all filters", role: .destructive) { reset() }.frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden).background(Color.goldengoBackground)
            .navigationTitle("Filter history")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showCategories) {
                SpendingCategoryPicker(selectedCategory: criteria.categoryName) { criteria.categoryName = $0 }
                    .presentationDetents([.large])
            }
        }.tint(GoldengoTheme.accent)
    }

    private var contextOptions: [String] {
        let names = SpendingContextCatalog.defaults.map(\.name) + model.searchFacets.contexts
        return Array(Set(names)).sorted()
    }

    private func filterSelectionRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(GoldengoTheme.inkPrimary)
            Spacer(); Text(value).foregroundStyle(criteria.categoryName == nil ? GoldengoTheme.inkMuted : GoldengoTheme.accent)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(GoldengoTheme.inkMuted)
        }
    }

    private func chipScroller(options: [String], selection: Binding<String?>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Any", selected: selection.wrappedValue == nil) { selection.wrappedValue = nil }
                ForEach(options, id: \.self) { option in
                    filterChip(option, selected: selection.wrappedValue == option) { selection.wrappedValue = option }
                }
            }.padding(.vertical, 2)
        }.listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.goldengoBackground : GoldengoTheme.inkPrimary)
                .padding(.horizontal, 13).frame(height: 36)
                .background(selected ? GoldengoTheme.accent : Color.goldengoField).clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    private func reset() {
        criteria = TransactionSearchCriteria(); dateRange = .any; minimum = ""; maximum = ""
    }
    private func apply() {
        switch dateRange {
        case .any: criteria.startDate = nil; criteria.endDate = nil
        case .thirtyDays:
            criteria.startDate = Calendar.current.date(byAdding: .day, value: -30, to: .now); criteria.endDate = .now
        case .thisYear:
            criteria.startDate = Calendar.current.dateInterval(of: .year, for: .now)?.start; criteria.endDate = .now
        case .custom: criteria.startDate = startDate; criteria.endDate = endDate
        }
        criteria.minimumAmount = Decimal(string: minimum.trimmingCharacters(in: .whitespacesAndNewlines))
        criteria.maximumAmount = Decimal(string: maximum.trimmingCharacters(in: .whitespacesAndNewlines))
        model.searchFilters = criteria
        Task { await model.search(); dismiss() }
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

    @ViewBuilder func historyDecimalKeyboard() -> some View {
#if os(iOS)
        self.keyboardType(.decimalPad)
#else
        self
#endif
    }
}
