import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// First-run and later-edit surface for Goldengo's central contract: a known amount, through a
/// known date, with an allowance whose inputs the user can inspect.
public struct SpendingPeriodSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let model: MoneyPlanModel
    private let isOnboarding: Bool
    private let onComplete: () -> Void
    private let onDefer: () -> Void
    private let onAddExpense: () -> Void
    private let onImportStatement: () -> Void

    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 13, to: .now) ?? .now
    @State private var fundingMode = SpendingPeriodFundingMode.fixedAmount
    @State private var startingAmountText = ""
    @State private var cadence = SpendingPeriodCadence.once
    @State private var isSaving = false
    @State private var didHydrate = false
    @State private var setupSaved = false
    @FocusState private var amountFocused: Bool

    public init(model: MoneyPlanModel, isOnboarding: Bool = false,
                onComplete: @escaping () -> Void = {}, onDefer: @escaping () -> Void = {},
                onAddExpense: @escaping () -> Void = {},
                onImportStatement: @escaping () -> Void = {}) {
        self.model = model; self.isOnboarding = isOnboarding
        self.onComplete = onComplete; self.onDefer = onDefer
        self.onAddExpense = onAddExpense; self.onImportStatement = onImportStatement
    }

    private var startingAmount: Decimal? {
        let clean = startingAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(string: clean), amount > 0 else { return nil }
        return amount
    }

    private var canSave: Bool {
        endDate >= Calendar.current.startOfDay(for: startDate)
            && (fundingMode == .liveBalances || startingAmount != nil)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if setupSaved && isOnboarding {
                        completionStep
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            if isOnboarding {
                                Text("Welcome")
                                    .font(.headline)
                                    .foregroundStyle(GoldengoTheme.inkPrimary)
                                    .frame(maxWidth: .infinity)
                            }
                            introduction
                            datesCard
                            moneyCard
                            repeatCard
                            previewCard
                            saveButton
                            if isOnboarding {
                                Button("Explore first") {
                                    onDefer(); dismiss()
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldengoTheme.inkMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 2)
                            }
                        }
                    }
                }
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle(isOnboarding ? "" : "Spending period")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .tint(GoldengoTheme.accent)
        .onAppear { hydrateOnce() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(GoldengoTheme.accent)
                .frame(width: 48, height: 48)
                .background(GoldengoTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(isOnboarding ? "Make every day feel clear" : "Define the number behind your plan")
                .font(.largeTitle.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text("Tell Goldengo how much money is available for this period and when it ends. Bills and goals stay protected automatically.")
                .font(.body)
                .foregroundStyle(GoldengoTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var datesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            GoldengoSectionLabel("1 · CHOOSE THE WINDOW")
            if dynamicTypeSize.isAccessibilitySize {
                accessibleDateField("Starts", selection: $startDate)
            } else {
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
            }
            Divider().overlay(GoldengoTheme.hairline)
            if dynamicTypeSize.isAccessibilitySize {
                accessibleDateField("Ends", selection: $endDate,
                                    range: Calendar.current.startOfDay(for: startDate)...)
            } else {
                DatePicker("Ends", selection: $endDate,
                           in: Calendar.current.startOfDay(for: startDate)...,
                           displayedComponents: .date)
            }
            Text("Your daily allowance includes today and the final day.")
                .font(.footnote)
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .goldengoCard()
    }

    private var moneyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            GoldengoSectionLabel("2 · CHOOSE THE MONEY")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(SpendingPeriodFundingMode.allCases) { mode in
                        Button {
                            fundingMode = mode
                        } label: {
                            HStack {
                                Text(LocalizedStringKey(mode.title))
                                Spacer()
                                if fundingMode == mode { Image(systemName: "checkmark.circle.fill") }
                            }
                            .font(.headline)
                            .foregroundStyle(fundingMode == mode ? GoldengoTheme.accent : GoldengoTheme.inkPrimary)
                            .padding(12)
                            .background(fundingMode == mode ? GoldengoTheme.accentSoft : Color.goldengoField)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Picker("Money source", selection: $fundingMode) {
                    ForEach(SpendingPeriodFundingMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            if fundingMode == .fixedAmount {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.currency.symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    TextField("Amount before plans", text: $startingAmountText)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .focused($amountFocused)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                }
                .padding(14)
                .background(Color.goldengoField)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text("Use what is available now, before upcoming bills and money already reserved for goals.")
                    .font(.footnote)
                    .foregroundStyle(GoldengoTheme.inkMuted)
            } else {
                Text("Goldengo will use the current Wallet and named-source balances. Reconcile them whenever reality changes.")
                    .font(.footnote)
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
        .goldengoCard()
    }

    private var repeatCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GoldengoSectionLabel("3 · AFTER IT ENDS")
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    Picker("Repeat", selection: $cadence) {
                        ForEach(SpendingPeriodCadence.allCases) { option in
                            Text(LocalizedStringKey(option.title)).tag(option)
                        }
                    }
                } label: {
                    HStack {
                        Text(LocalizedStringKey(cadence.title))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.headline)
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .padding(12)
                    .background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            } else {
                Picker("Repeat", selection: $cadence) {
                    ForEach(SpendingPeriodCadence.allCases) { option in
                        Text(LocalizedStringKey(option.title)).tag(option)
                    }
                }
            }
            Text(cadence == .once
                 ? "Goldengo will ask you to start the next period."
                 : "The same window and amount move forward automatically.")
                .font(.footnote)
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .goldengoCard()
    }

    private var previewCard: some View {
        let days = max(1, 1 + (Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: startDate),
            to: Calendar.current.startOfDay(for: endDate)).day ?? 0))
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(GoldengoTheme.income)
                .frame(width: 44, height: 44)
                .background(GoldengoTheme.income.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(days) spending \(days == 1 ? "day" : "days")")
                    .font(.headline)
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                Text("Through \(endDate.formatted(.dateTime.day().month(.wide).year()))")
                    .font(.subheadline)
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
        .goldengoCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func accessibleDateField(_ title: LocalizedStringKey, selection: Binding<Date>,
                                     range: PartialRangeFrom<Date>? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let range {
                DatePicker(title, selection: selection, in: range, displayedComponents: .date)
                    .labelsHidden()
            } else {
                DatePicker(title, selection: selection, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button {
            guard !isSaving else { return }
            amountFocused = false; isSaving = true
            Task {
                let saved = await model.savePeriod(startDate: startDate, endDate: endDate,
                                                   fundingMode: fundingMode,
                                                   startingAmount: startingAmount,
                                                   cadence: cadence)
                isSaving = false
                if saved {
                    onComplete()
                    if isOnboarding { setupSaved = true }
                    else { dismiss() }
                }
            }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(GoldengoTheme.onAccent) }
                Text(isOnboarding ? "Start my period" : "Save period")
            }
            .font(.headline)
            .foregroundStyle(GoldengoTheme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(canSave ? GoldengoTheme.accent : GoldengoTheme.hairline)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave || isSaving)
    }

    private var completionStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 28)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(GoldengoTheme.income)
                .frame(width: 62, height: 62)
                .background(GoldengoTheme.income.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("Your period is ready")
                    .font(.largeTitle.weight(.medium)).fontDesign(.serif)
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                Text("Add one real transaction now, import a statement, or simply start from Home.")
                    .font(.body).foregroundStyle(GoldengoTheme.inkMuted)
            }
            VStack(spacing: 12) {
                completionButton("Add my first expense", icon: "plus.circle.fill", primary: true) {
                    onAddExpense(); dismiss()
                }
                completionButton("Import a statement", icon: "square.and.arrow.down", primary: false) {
                    onImportStatement(); dismiss()
                }
                Button("Go to Home") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completionButton(_ title: String, icon: String, primary: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(primary ? GoldengoTheme.onAccent : GoldengoTheme.inkPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(primary ? GoldengoTheme.accent : Color.goldengoSurface)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    if !primary {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(GoldengoTheme.hairline)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func hydrateOnce() {
        guard !didHydrate else { return }
        didHydrate = true
        guard let period = model.snapshot?.period else {
            fundingMode = model.snapshot?.safe.usesWallet == true ? .liveBalances : .fixedAmount
            return
        }
        startDate = period.startDate; endDate = period.endDate
        fundingMode = period.fundingMode; cadence = period.cadence
        if let amount = period.startingAmount {
            startingAmountText = NSDecimalNumber(decimal: amount).stringValue
        }
    }
}
