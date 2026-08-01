import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

private enum PlanDestination: String, Identifiable {
    case review, upcoming, goals, investments, insights
    var id: String { rawValue }
}

public struct MoneyPlanView: View {
    @Environment(\.dismiss) private var dismiss
    private let model: MoneyPlanModel
    @State private var destination: PlanDestination?
    @State private var showPerDay = false
    @State private var showMath = false
    @State private var showPurchaseCheck = false
    @State private var showPeriodSetup = false

    public init(model: MoneyPlanModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PlanPageHeader(title: "Plan", subtitle: "Make the next decision clearly") { dismiss() }
                safeCard
                purchaseCheckCard
                actionGrid
                if let stories = model.snapshot?.stories, !stories.isEmpty {
                    storyPreview(stories)
                }
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.bottom, 36)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .refreshable { await model.load() }
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .review: ReviewInboxView(model: model)
            case .upcoming: UpcomingMoneyView(model: model)
            case .goals: GoalsView(model: model)
            case .investments: InvestmentsView(model: model)
            case .insights: MoneyInsightsView(model: model)
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $showPurchaseCheck) {
            PurchaseCheckSheet(model: model).presentationDetents([.large])
        }
        .sheet(isPresented: $showPeriodSetup) {
            SpendingPeriodSetupView(model: model)
        }
        .alert("Couldn't update your plan", isPresented: Binding(
            get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } }
        )) { Button("OK") { model.errorText = nil } } message: { Text(model.errorText ?? "") }
#if canImport(UIKit)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    private var purchaseCheckCard: some View {
        Button { showPurchaseCheck = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "cart.badge.questionmark")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(GoldengoTheme.accent)
                    .frame(width: 44, height: 44).background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Can I afford this?").font(.system(size: 16, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("Preview a purchase without changing anything")
                        .font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(GoldengoTheme.inkMuted)
            }.goldengoCard(padding: 15)
        }.buttonStyle(.plain)
    }

    private var safeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("SAFE TO SPEND", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(GoldengoTheme.income)
                Spacer()
                Button(model.isPeriodConfigured ? "Edit" : "Set period") {
                    showPeriodSetup = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldengoTheme.accent)
                Picker("View", selection: $showPerDay) {
                    Text("Total").tag(false)
                    Text("Daily").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 128)
            }

            GoldengoAmountText(showPerDay ? model.safePerDayText : model.safeTotalText, role: .hero)
                .padding(.top, 16)
                .contentTransition(.numericText())
            Text(safeCaption)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkMuted)
                .padding(.top, 5)

            if model.periodNeedsRenewal {
                Button("This period ended · Start the next one") { showPeriodSetup = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldengoTheme.danger)
                    .padding(.top, 10)
            }

            Button {
                withAnimation(.snappy) { showMath.toggle() }
            } label: {
                HStack {
                    Text(showMath ? "Hide calculation" : "How this is calculated")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showMath ? 180 : 0))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GoldengoTheme.accent)
                .padding(.top, 18)
            }
            .buttonStyle(.plain)

            if showMath, let safe = model.snapshot?.safe {
                Divider().overlay(GoldengoTheme.hairline).padding(.vertical, 14)
                if safe.fundingMode == .fixedAmount, let starting = safe.startingAmount {
                    calculationRow("Period starting amount", starting)
                    calculationRow("Spent since period start", -safe.spentSinceStart)
                }
                calculationRow(safe.fundingMode == .fixedAmount ? "Available after activity" : "Available now",
                               safe.available)
                calculationRow("Reserved for goals", -safe.reservedForGoals)
                calculationRow("Upcoming before then", -safe.upcomingCommitments)
            }
        }
        .goldengoCard(padding: 22)
    }

    private var safeCaption: String {
        guard let safe = model.snapshot?.safe else { return "Checking your real balances and commitments…" }
        let date = safe.horizonDate.formatted(.dateTime.day().month(.abbreviated))
        guard safe.isPeriodConfigured else {
            return "Temporary estimate through \(date). Set a period to make this date yours."
        }
        return showPerDay ? "per day for \(safe.dayCount) days, through \(date)" : "available through \(date) after plans and commitments"
    }

    private func calculationRow(_ title: String, _ amount: Decimal) -> some View {
        HStack {
            Text(title).foregroundStyle(GoldengoTheme.inkMuted)
            Spacer()
            Text(Money(amount: amount, currency: model.currency).formatted())
                .monospacedDigit()
                .foregroundStyle(amount < 0 ? GoldengoTheme.inkMuted : GoldengoTheme.inkPrimary)
        }
        .font(.system(size: 13.5, weight: .medium))
        .padding(.vertical, 4)
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR MONEY")
                .font(.system(size: 12, weight: .bold)).tracking(0.6)
                .foregroundStyle(GoldengoTheme.inkMuted)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                planTile(.review, title: "Review", detail: reviewDetail,
                         icon: "tray.full.fill", color: model.reviewCount > 0 ? GoldengoTheme.accent : GoldengoTheme.income,
                         badge: model.reviewCount > 0 ? "\(model.reviewCount)" : nil)
                planTile(.upcoming, title: "Upcoming", detail: upcomingDetail,
                         icon: "calendar", color: Color(hex: "#4D88C7"))
                planTile(.goals, title: "Goals", detail: goalsDetail,
                         icon: "target", color: Color(hex: "#A46191"))
                planTile(.investments, title: "Investments", detail: investmentsDetail,
                         icon: "chart.line.uptrend.xyaxis", color: GoldengoTheme.income)
            }
        }
    }

    private func planTile(_ target: PlanDestination, title: String, detail: String,
                          icon: String, color: Color, badge: String? = nil) -> some View {
        Button { destination = target } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 38, height: 38)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                    if let badge {
                        Text(badge).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.goldengoBackground)
                            .frame(minWidth: 22, minHeight: 22).background(GoldengoTheme.accent).clipShape(Circle())
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16).frame(minHeight: 142, alignment: .top)
            .background(Color.goldengoSurface)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card).strokeBorder(GoldengoTheme.hairline) }
        }
        .buttonStyle(.plain)
    }

    private var reviewDetail: String { model.reviewCount == 0 ? "Everything is clear" : "\(model.reviewCount) items need a decision" }
    private var upcomingDetail: String {
        guard let next = model.snapshot?.upcoming.first(where: { $0.kind != .goal }) else { return "Nothing planned yet" }
        return "\(next.title) · \(next.date.formatted(.dateTime.day().month(.abbreviated)))"
    }
    private var goalsDetail: String {
        let count = model.snapshot?.goals.count ?? 0
        return count == 0 ? "Plan future expenses" : "\(count) active \(count == 1 ? "goal" : "goals")"
    }
    private var investmentsDetail: String {
        let count = model.snapshot?.investments.count ?? 0
        return count == 0 ? "Track wealth separately" : "\(count) \(count == 1 ? "account" : "accounts")"
    }

    private func storyPreview(_ stories: [MoneyStory]) -> some View {
        Button { destination = .insights } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("THIS MONTH").font(.system(size: 12, weight: .bold)).tracking(0.6)
                    Spacer()
                    Text("See insights").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(GoldengoTheme.accent)
                }
                .foregroundStyle(GoldengoTheme.inkMuted)
                if let first = stories.first {
                    HStack(spacing: 13) {
                        Image(systemName: first.icon).foregroundStyle(Color(hex: first.colorHex))
                            .frame(width: 38, height: 38).background(Color(hex: first.colorHex).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(first.title).font(.system(size: 15.5, weight: .semibold))
                            Text(first.detail).font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }
            }
            .goldengoCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Purchase decision

private struct PurchaseCheckSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var amount = ""
    @State private var name = ""
    @State private var date = Date.now
    @State private var category = "Shopping"
    @State private var showCategories = false
    @FocusState private var amountFocused: Bool

    private var amountValue: Decimal { Decimal(string: amount) ?? 0 }
    private var impact: PurchaseImpactSnapshot? { model.purchaseImpact(amount: amountValue, date: date) }
    private var canAct: Bool {
        amountValue > 0 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    amountCard
                    if amountValue > 0 { impactCard }
                    detailsCard
                    actionButtons
                }
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Check a purchase")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showCategories) {
                SpendingCategoryPicker(selectedCategory: category) { category = $0 }.presentationDetents([.large])
            }
        }
        .tint(GoldengoTheme.accent)
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            GoldengoSectionLabel("PURCHASE PRICE")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.currency.symbol).font(.system(size: 25, weight: .semibold)).foregroundStyle(GoldengoTheme.inkMuted)
                TextField("0", text: $amount)
                    .focused($amountFocused)
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
            }
            Text("This is only a preview. Nothing moves until you choose an action.")
                .font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
        }.goldengoCard(padding: 18)
    }

    @ViewBuilder private var impactCard: some View {
        if let impact {
            let color = fitColor(impact.fit)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: fitIcon(impact.fit)).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color).frame(width: 42, height: 42).background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fitTitle(impact.fit)).font(.system(size: 17, weight: .semibold))
                        Text(fitDetail(impact)).font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }
                Divider().overlay(GoldengoTheme.hairline)
                impactRow("Safe now", impact.safeBefore)
                impactRow("This purchase", -impact.amount)
                impactRow("Safe after", impact.safeAfter, emphasized: true)
                if impact.fit == .notYet {
                    Text("Short by \(Money(amount: impact.shortfall, currency: model.currency).formatted()) without touching money reserved for goals or upcoming bills.")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(GoldengoTheme.danger)
                }
            }.goldengoCard(padding: 18)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "pencil").foregroundStyle(GoldengoTheme.accent).frame(width: 24)
                TextField("What are you thinking of buying?", text: $name)
                    .font(.system(size: 15, weight: .medium))
            }
            Divider().overlay(GoldengoTheme.hairline).padding(.vertical, 13)
            HStack(spacing: 12) {
                Image(systemName: "calendar").foregroundStyle(GoldengoTheme.accent).frame(width: 24)
                DatePicker("When", selection: $date, in: Date.now..., displayedComponents: .date)
            }
            Divider().overlay(GoldengoTheme.hairline).padding(.vertical, 13)
            Button { showCategories = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: GoldengoCategoryIcon.symbol(for: category)).foregroundStyle(GoldengoTheme.accent).frame(width: 24)
                    Text(category).foregroundStyle(GoldengoTheme.inkPrimary)
                    Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(GoldengoTheme.inkMuted)
                }
            }.buttonStyle(.plain)
        }.font(.system(size: 15, weight: .medium)).goldengoCard(padding: 16)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await model.planPurchase(name: clean, amount: amountValue, category: category, date: date); dismiss() }
            } label: {
                Label("Add to upcoming", systemImage: "calendar.badge.plus")
                    .font(.system(size: 15.5, weight: .bold)).foregroundStyle(Color.goldengoBackground)
                    .frame(maxWidth: .infinity, minHeight: 50).background(GoldengoTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain).disabled(!canAct).opacity(canAct ? 1 : 0.45)
            Button {
                let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await model.logPurchaseNow(name: clean, amount: amountValue, category: category); dismiss() }
            } label: {
                Text("I bought it—log now").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                    .frame(maxWidth: .infinity, minHeight: 46).background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).disabled(!canAct).opacity(canAct ? 1 : 0.45)
        }
    }

    private func impactRow(_ title: String, _ value: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(emphasized ? GoldengoTheme.inkPrimary : GoldengoTheme.inkMuted)
            Spacer()
            Text(Money(amount: value, currency: model.currency).formatted()).monospacedDigit()
                .fontWeight(emphasized ? .bold : .medium)
        }.font(.system(size: 13.5))
    }
    private func fitTitle(_ fit: PurchaseFit) -> String {
        switch fit { case .comfortable: return "Fits comfortably"; case .fits: return "It fits"; case .tight: return "It fits, but gets tight"; case .notYet: return "Not safely yet" }
    }
    private func fitDetail(_ impact: PurchaseImpactSnapshot) -> String {
        if !impact.isInsideCurrentHorizon { return "This date is beyond the current forecast, so the preview uses today’s plan." }
        return "You would have \(Money(amount: impact.safeAfter, currency: model.currency).formatted()) left, or \(Money(amount: impact.perDayAfter, currency: model.currency).formatted()) per day."
    }
    private func fitIcon(_ fit: PurchaseFit) -> String {
        switch fit { case .comfortable: return "checkmark.seal.fill"; case .fits: return "checkmark.circle.fill"; case .tight: return "exclamationmark.circle.fill"; case .notYet: return "pause.circle.fill" }
    }
    private func fitColor(_ fit: PurchaseFit) -> Color {
        switch fit { case .comfortable, .fits: return GoldengoTheme.income; case .tight: return GoldengoTheme.accent; case .notYet: return GoldengoTheme.danger }
    }
}

// MARK: - Review

private struct ReviewInboxView: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var categorizing: ReviewIssue?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanPageHeader(title: "Review", subtitle: "One decision at a time") { dismiss() }
                if model.reviewCount == 0 { PlanEmptyState(icon: "checkmark.circle.fill", title: "All clear", detail: "Nothing needs your attention right now.") }
                else {
                    ForEach(model.snapshot?.reviewIssues ?? []) { issue in issueCard(issue) }
                }
            }.padding(.horizontal, GoldengoTheme.Spacing.m).padding(.bottom, 36)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .sheet(item: $categorizing) { issue in
            SpendingCategoryPicker(selectedCategory: nil, merchantName: issue.merchantName) { category, remember in
                Task { await model.assign(issue, category: category, rememberMerchant: remember) }
            }
            .presentationDetents([.large])
        }
        .refreshable { await model.load() }
#if canImport(UIKit)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    private func issueCard(_ issue: ReviewIssue) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: issueIcon(issue.kind)).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(issueColor(issue.kind)).frame(width: 40, height: 40)
                    .background(issueColor(issue.kind).opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                    Text(issue.detail).font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                }
                Spacer()
                if let amount = issue.amount, let code = issue.currencyCode {
                    Text(Money(amount: amount, currency: CurrencyCode(code)).formatted())
                        .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
            }
            HStack(spacing: 10) {
                switch issue.kind {
                case .uncategorized:
                    reviewButton("Choose category", primary: true) { categorizing = issue }
                    reviewButton("Leave as Other", primary: false) { Task { await model.accept(issue) } }
                case .unusual:
                    reviewButton("Looks right", primary: true) { Task { await model.accept(issue) } }
                case .subscription:
                    reviewButton("Yes, recurring", primary: true) { Task { await model.confirmSubscription(issue) } }
                    reviewButton("Not recurring", primary: false) { Task { await model.dismissSubscription(issue) } }
                }
            }
        }
        .goldengoCard()
    }

    private func reviewButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(primary ? Color.goldengoBackground : GoldengoTheme.inkPrimary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(primary ? GoldengoTheme.accent : Color.goldengoField)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func issueIcon(_ kind: ReviewIssueKind) -> String {
        switch kind { case .uncategorized: return "tag.fill"; case .unusual: return "waveform.path.ecg"; case .subscription: return "repeat" }
    }
    private func issueColor(_ kind: ReviewIssueKind) -> Color {
        switch kind { case .uncategorized: return GoldengoTheme.accent; case .unusual: return GoldengoTheme.danger; case .subscription: return Color(hex: "#4D88C7") }
    }
}

// MARK: - Upcoming

private struct UpcomingMoneyView: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanPageHeader(title: "Upcoming", subtitle: "The next 60 days") { dismiss() }
                Button { showAdd = true } label: { PlanAddRow(title: "Plan a payment", icon: "calendar.badge.plus") }
                    .buttonStyle(.plain)
                let items = model.snapshot?.upcoming ?? []
                if items.isEmpty { PlanEmptyState(icon: "calendar", title: "Nothing planned", detail: "Add rent, bills, insurance, or anything future you should see coming.") }
                else { ForEach(items) { upcomingCard($0) } }
            }.padding(.horizontal, GoldengoTheme.Spacing.m).padding(.bottom, 36)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .sheet(isPresented: $showAdd) { AddCommitmentSheet(model: model) }
        .refreshable { await model.load() }
#if canImport(UIKit)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    private func upcomingCard(_ item: UpcomingMoneyItem) -> some View {
        HStack(spacing: 13) {
            VStack(spacing: 1) {
                Text(item.date.formatted(.dateTime.day())).font(.system(size: 18, weight: .bold)).monospacedDigit()
                Text(item.date.formatted(.dateTime.month(.abbreviated))).font(.system(size: 10, weight: .bold)).textCase(.uppercase)
            }
            .foregroundStyle(kindColor(item.kind)).frame(width: 44, height: 48)
            .background(kindColor(item.kind).opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 15.5, weight: .semibold))
                Text(kindTitle(item.kind)).font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(Money(amount: item.amount, currency: CurrencyCode(item.currencyCode)).formatted())
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                if item.canLog {
                    Button("Log") { Task { await model.logUpcoming(item) } }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(GoldengoTheme.accent)
                }
            }
            if item.kind == .bill || item.kind == .income {
                Menu {
                    Button("Remove plan", role: .destructive) {
                        Task { await model.archiveCommitment(id: item.sourceID) }
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(GoldengoTheme.inkMuted)
                        .frame(width: 28, height: 36)
                }
            }
        }
        .goldengoCard()
    }
    private func kindTitle(_ kind: UpcomingMoneyKind) -> String {
        switch kind { case .bill: return "Planned payment"; case .subscription: return "Subscription"; case .income: return "Expected income"; case .goal: return "Goal due" }
    }
    private func kindColor(_ kind: UpcomingMoneyKind) -> Color {
        switch kind { case .bill: return GoldengoTheme.accent; case .subscription: return Color(hex: "#4D88C7"); case .income: return GoldengoTheme.income; case .goal: return Color(hex: "#A46191") }
    }
}

// MARK: - Goals

private struct GoalsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var showAdd = false
    @State private var updating: GoalSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanPageHeader(title: "Goals", subtitle: "Put future expenses aside") { dismiss() }
                Button { showAdd = true } label: { PlanAddRow(title: "Create a goal", icon: "plus.circle.fill") }.buttonStyle(.plain)
                let goals = model.snapshot?.goals ?? []
                if goals.isEmpty { PlanEmptyState(icon: "target", title: "Plan something meaningful", detail: "Car maintenance, a trip, insurance, or an emergency buffer.") }
                else { ForEach(goals) { goalCard($0) } }
            }.padding(.horizontal, GoldengoTheme.Spacing.m).padding(.bottom, 36)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .sheet(isPresented: $showAdd) { AddGoalSheet(model: model) }
        .sheet(item: $updating) { UpdateGoalSheet(model: model, goal: $0) }
        .refreshable { await model.load() }
#if canImport(UIKit)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    private func goalCard(_ goal: GoalSnapshot) -> some View {
        Button { updating = goal } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: goal.icon).foregroundStyle(Color(hex: goal.colorHex))
                        .frame(width: 40, height: 40).background(Color(hex: goal.colorHex).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name).font(.system(size: 16, weight: .semibold))
                        if let due = goal.dueDate { Text("By \(due.formatted(.dateTime.day().month(.abbreviated).year()))").font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted) }
                    }
                    Spacer()
                    Text("\(Int(goal.progress * 100))%").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: goal.colorHex))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.goldengoField)
                        Capsule().fill(Color(hex: goal.colorHex)).frame(width: geo.size.width * goal.progress)
                    }
                }.frame(height: 7)
                HStack {
                    Text(Money(amount: goal.savedAmount, currency: CurrencyCode(goal.currencyCode)).formatted())
                    Spacer()
                    Text("of \(Money(amount: goal.targetAmount, currency: CurrencyCode(goal.currencyCode)).formatted())")
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(GoldengoTheme.inkMuted)
            }.goldengoCard()
        }.buttonStyle(.plain)
    }
}

// MARK: - Investments

private struct InvestmentsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var showAdd = false
    @State private var actingOn: InvestmentSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanPageHeader(title: "Investments", subtitle: "Wealth, kept out of spending") { dismiss() }
                Button { showAdd = true } label: { PlanAddRow(title: "Add investment account", icon: "plus.circle.fill") }.buttonStyle(.plain)
                let accounts = model.snapshot?.investments ?? []
                if accounts.isEmpty { PlanEmptyState(icon: "chart.line.uptrend.xyaxis", title: "Track wealth honestly", detail: "Start with manual values and contributions. Market pricing can wait.") }
                else { ForEach(accounts) { investmentCard($0) } }
            }.padding(.horizontal, GoldengoTheme.Spacing.m).padding(.bottom, 36)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .sheet(isPresented: $showAdd) { AddInvestmentSheet(model: model) }
        .sheet(item: $actingOn) { InvestmentActionSheet(model: model, account: $0) }
        .refreshable { await model.load() }
#if canImport(UIKit)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    private func investmentCard(_ account: InvestmentSnapshot) -> some View {
        Button { actingOn = account } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(GoldengoTheme.sourceColor(account.colorIndex)).frame(width: 42, height: 42)
                        .background(GoldengoTheme.sourceColor(account.colorIndex).opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).font(.system(size: 16, weight: .semibold))
                        Text(account.kindName).font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(GoldengoTheme.inkMuted)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Money(amount: account.currentValue, currency: CurrencyCode(account.currencyCode)).formatted())
                        .font(.system(size: 25, weight: .semibold)).monospacedDigit()
                    Spacer()
                    Text(gainText(account)).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(account.gain >= 0 ? GoldengoTheme.income : GoldengoTheme.danger)
                }
                Text("Contributed \(Money(amount: account.contributed, currency: CurrencyCode(account.currencyCode)).formatted())")
                    .font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
            }.goldengoCard()
        }.buttonStyle(.plain)
    }
    private func gainText(_ account: InvestmentSnapshot) -> String {
        guard account.contributed > 0 else { return "Value updated" }
        return (account.gain >= 0 ? "+" : "")
            + Money(amount: account.gain, currency: CurrencyCode(account.currencyCode)).formatted()
    }
}

// MARK: - Insights

private struct MoneyInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanPageHeader(title: "This month", subtitle: "The useful version of your numbers") { dismiss() }
                let stories = model.snapshot?.stories ?? []
                if stories.isEmpty { PlanEmptyState(icon: "sparkles", title: "Your story is forming", detail: "A few more transactions will make meaningful comparisons possible.") }
                else { ForEach(stories) { storyCard($0) } }
            }.padding(.horizontal, GoldengoTheme.Spacing.m).padding(.bottom, 36)
        }.background(Color.goldengoBackground.ignoresSafeArea())
#if canImport(UIKit)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }
    private func storyCard(_ story: MoneyStory) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: story.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: story.colorHex))
                .frame(width: 42, height: 42).background(Color(hex: story.colorHex).opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(story.title).font(.system(size: 16, weight: .semibold))
                Text(story.detail).font(.system(size: 13)).foregroundStyle(GoldengoTheme.inkMuted)
            }
        }.goldengoCard()
    }
}

// MARK: - Shared chrome

private struct PlanPageHeader: View {
    let title: String; let subtitle: String; let close: () -> Void
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 30, weight: .medium, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(GoldengoTheme.inkMuted)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(GoldengoTheme.inkPrimary)
                    .frame(width: 40, height: 40).background(Color.goldengoField).clipShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel("Close")
        }.padding(.top, 14).padding(.bottom, 4)
    }
}

private struct PlanEmptyState: View {
    let icon: String; let title: String; let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(GoldengoTheme.accent)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(GoldengoTheme.inkMuted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 24).goldengoCard()
    }
}

private struct PlanAddRow: View {
    let title: String; let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(GoldengoTheme.accent)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
            Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(GoldengoTheme.inkMuted)
        }.goldengoCard()
    }
}

// MARK: - Forms

private struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var name = ""; @State private var target = ""; @State private var saved = ""
    @State private var hasDate = true; @State private var dueDate = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    var body: some View { planForm(title: "New goal", saveEnabled: !name.isEmpty && (Decimal(string: target) ?? 0) > 0) {
        TextField("Goal name", text: $name); TextField("Target amount", text: $target).decimalKeyboard()
        TextField("Already saved", text: $saved).decimalKeyboard()
        Toggle("Target date", isOn: $hasDate).tint(GoldengoTheme.accent)
        if hasDate { DatePicker("Due", selection: $dueDate, in: Date.now..., displayedComponents: .date) }
    } save: { Task { await model.addGoal(name: name, target: Decimal(string: target) ?? 0, saved: Decimal(string: saved) ?? 0, dueDate: hasDate ? dueDate : nil); dismiss() } } }
}

private struct UpdateGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel; let goal: GoalSnapshot
    @State private var amount: String
    init(model: MoneyPlanModel, goal: GoalSnapshot) { self.model = model; self.goal = goal; _amount = State(initialValue: NSDecimalNumber(decimal: goal.savedAmount).stringValue) }
    var body: some View { planForm(title: goal.name, saveEnabled: (Decimal(string: amount) ?? -1) >= 0) {
        Text("How much is reserved for this goal now?").font(.system(size: 13)).foregroundStyle(GoldengoTheme.inkMuted)
        TextField("Saved amount", text: $amount).decimalKeyboard()
        Button("Delete goal", role: .destructive) { Task { await model.archiveGoal(id: goal.id); dismiss() } }
    } save: { Task { await model.setGoalSaved(id: goal.id, amount: Decimal(string: amount) ?? 0); dismiss() } } }
}

private struct AddCommitmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var name = ""; @State private var amount = ""; @State private var category = "Bills"
    @State private var date = Date.now; @State private var cadence: PlanCadence = .monthly; @State private var context: String?
    @State private var kind: UpcomingMoneyKind = .bill
    @State private var showCategory = false
    var body: some View { planForm(title: "Plan payment", saveEnabled: !name.isEmpty && (Decimal(string: amount) ?? 0) > 0) {
        TextField("Name", text: $name); TextField("Amount", text: $amount).decimalKeyboard()
        Picker("Type", selection: $kind) {
            Text("Payment").tag(UpcomingMoneyKind.bill)
            Text("Income").tag(UpcomingMoneyKind.income)
        }.pickerStyle(.segmented)
        DatePicker("Next date", selection: $date, displayedComponents: .date)
        Picker("Repeats", selection: $cadence) { ForEach(PlanCadence.allCases) { Text($0.title).tag($0) } }
        if kind == .bill {
            Button("Category: \(category)") { showCategory = true }.foregroundStyle(GoldengoTheme.accent)
            ContextPicker(selection: $context)
        }
    } save: { Task { await model.addCommitment(name: name, amount: Decimal(string: amount) ?? 0, category: category, dueDate: date, cadence: cadence, context: context, kind: kind); dismiss() } }
    .sheet(isPresented: $showCategory) { SpendingCategoryPicker(selectedCategory: category) { category = $0 }.presentationDetents([.large]) } }
}

private struct AddInvestmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel
    @State private var name = ""; @State private var kind = "Brokerage"; @State private var value = ""
    var body: some View { planForm(title: "Investment account", saveEnabled: !name.isEmpty) {
        TextField("Account name", text: $name)
        Picker("Type", selection: $kind) { ForEach(["Brokerage", "Crypto", "Retirement", "Property", "Other"], id: \.self) { Text($0) } }
        TextField("Current value", text: $value).decimalKeyboard()
    } save: { Task { await model.addInvestment(name: name, kind: kind, value: Decimal(string: value) ?? 0); dismiss() } } }
}

private struct InvestmentActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: MoneyPlanModel; let account: InvestmentSnapshot
    @State private var value = ""; @State private var contribution = ""
    var body: some View { planForm(title: account.name, saveEnabled: (Decimal(string: value) ?? 0) > 0 || (Decimal(string: contribution) ?? 0) > 0) {
        Text("Update either field. Contributions are logged as investments and remain outside ordinary spending.")
            .font(.system(size: 13)).foregroundStyle(GoldengoTheme.inkMuted)
        TextField("New current value", text: $value).decimalKeyboard()
        TextField("Add contribution", text: $contribution).decimalKeyboard()
        Button("Stop tracking account", role: .destructive) {
            Task { await model.archiveInvestment(id: account.id); dismiss() }
        }
    } save: { Task { if let v = Decimal(string: value), v > 0 { await model.setInvestmentValue(id: account.id, value: v) }; if let c = Decimal(string: contribution), c > 0 { await model.addContribution(accountID: account.id, amount: c) }; dismiss() } } }
}

@MainActor
private func planForm<Content: View>(title: String, saveEnabled: Bool,
                                     @ViewBuilder content: () -> Content, save: @escaping () -> Void) -> some View {
    NavigationStack {
        Form { content() }
            .scrollContentBackground(.hidden).background(Color.goldengoBackground)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DismissButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!saveEnabled).fontWeight(.semibold) }
            }
    }.tint(GoldengoTheme.accent)
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Cancel") { dismiss() } }
}

struct ContextPicker: View {
    @Binding var selection: String?
    @State private var custom = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context").font(.system(size: 12, weight: .semibold)).foregroundStyle(GoldengoTheme.inkMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    contextChip(nil, title: "None", icon: "minus")
                    ForEach(SpendingContextCatalog.defaults) { option in contextChip(option.name, title: option.name, icon: option.icon) }
                }
            }
            TextField("Or name a trip or project", text: $custom)
                .onSubmit { let clean = custom.trimmingCharacters(in: .whitespacesAndNewlines); selection = clean.isEmpty ? nil : clean }
        }
    }
    private func contextChip(_ value: String?, title: String, icon: String) -> some View {
        Button { selection = value } label: {
            Label(title, systemImage: icon).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selection == value ? Color.goldengoBackground : GoldengoTheme.inkPrimary)
                .padding(.horizontal, 12).frame(height: 36)
                .background(selection == value ? GoldengoTheme.accent : Color.goldengoField).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder func decimalKeyboard() -> some View {
#if os(iOS)
        self.keyboardType(.decimalPad)
#else
        self
#endif
    }
}
