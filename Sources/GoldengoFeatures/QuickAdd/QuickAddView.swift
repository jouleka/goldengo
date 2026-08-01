import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData
#if canImport(UIKit)
import UIKit
#endif

public struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: QuickAddModel
    @State private var showAdded = false
    @State private var showCurrencyPicker = false
    @State private var showCategoryPicker = false
    @State private var showSourcePicker = false
    @State private var showDetailsSheet = false
    /// Selectable currencies, decoded once on appear (the currency Menu reads it in body).
    @State private var selectableCurrencies: [CurrencyCode] = []
#if os(iOS)
    @State private var showScanner = false
    @State private var scanModel: ReceiptScanModel?
#endif
    public init(model: QuickAddModel) { _model = State(initialValue: model) }

    // gg-key height: matches quickadd.jsx `keyH` at density "regular" = 60
    private let keyHeight: CGFloat = 60

    private var keys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", model.allowsDecimal ? "." : "C", "0", "⌫"]
    }

    public var body: some View {
        // Stacked layout — padding mirrors quickadd.jsx StackedLayout: 14px top, 22px h, 34px bottom.
        // The upper half scrolls if it must (scroll-off only when the rows outgrow the space —
        // details + category field open at once on a small screen); keypad and Add stay anchored.
        VStack(spacing: 0) {
            sheetHeader

            ScrollView {
                VStack(spacing: 0) {
                    amountBlock
                        .padding(.top, 2)

                    transactionCard
                        .padding(.top, 22)
                }
            }
            .scrollBounceBehavior(.basedOnSize)   // feels static whenever everything fits

            keypad
                .padding(.top, 16)             // marginTop: 16

            addButton
                .padding(.top, 12)
        }
        .padding(.top, 14)                      // outer container top: 14px
        .padding(.horizontal, GoldengoTheme.Spacing.m)   // app-wide 16pt content edge (matches the tabs)
        .padding(.bottom, 34)                   // outer container bottom: 34px
        .background(Color.goldengoBackground.ignoresSafeArea())
        // The text keyboard (details/category fields) overlays the numeric keypad instead of
        // compressing the sheet — otherwise the whole layout gets shoved off the top while typing.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(
                    available: availableCurrencies,
                    selectedCode: Binding(
                        get: { model.currency.rawValue },
                        set: { model.setCurrency(CurrencyCode($0)) }
                    )
                )
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            SpendingCategoryPicker(selectedCategory: model.selectedCategory) { category in
                withAnimation(.easeInOut(duration: 0.18)) {
                    model.selectedCategory = category
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSourcePicker) {
            FundingSourcePicker(
                sources: model.sourceBalances,
                selectedSourceID: model.selectedSourceID
            ) { sourceID in
                withAnimation(.easeInOut(duration: 0.18)) {
                    model.selectedSourceID = sourceID
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDetailsSheet) {
            ExpenseDetailsSheet(
                merchant: $model.merchant,
                note: $model.note,
                date: $model.date,
                contextName: $model.contextName,
                splits: $model.splits,
                total: model.amountDecimal,
                currency: model.currency
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScan: { cg in
                    showScanner = false
                    let m = ReceiptScanModel(store: model.store, currency: model.currency)
                    scanModel = m
                    Task { await m.handle(cgImage: cg) }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $scanModel) { m in
            ReceiptReviewView(model: m, onDone: { scanModel = nil })
        }
#endif
        .alert("Couldn't save", isPresented: Binding(
            get: { model.errorText != nil },
            set: { if !$0 { model.errorText = nil } }
        )) {
            Button("OK") { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
        .overlay(alignment: .top) {
            if showAdded {
                GoldengoToast("Added", icon: "checkmark.circle.fill", iconTint: GoldengoTheme.accent)
                    .padding(.top, GoldengoTheme.Spacing.m)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task { await model.loadSources(); await model.loadCategories() }
        .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
        .onChange(of: model.savedCount) { _, newCount in
            guard newCount > 0 else { return }
            GoldengoHaptics.spendLanded()
            withAnimation(.snappy) { showAdded = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                if model.savedCount == newCount { withAnimation(.snappy) { showAdded = false } }
            }
        }
    }

    // MARK: - Amount block
    // Matches AmountBlock in quickadd.jsx:
    //   serif "New expense" title at 19px/muted, then sym (30px/600/muted) + amount (hero, dynamic size)

    private var amountBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            heroAmount
            currencyMenu
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private var sheetHeader: some View {
        ZStack {
            Text("New expense")
                .font(.custom("Georgia", size: 20).weight(.medium))
                .foregroundStyle(GoldengoTheme.inkPrimary)

            HStack {
                headerLeadingAction
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.goldengoField)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close new expense")
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var headerLeadingAction: some View {
#if os(iOS)
        if DocumentScannerView.isSupported {
            Button { showScanner = true } label: {
                Label("Scan", systemImage: "doc.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(minWidth: 64, minHeight: 36)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 64, height: 36)
        }
#else
        Color.clear.frame(width: 64, height: 36)
#endif
    }

    // The amount is the only hero on the screen; everything else reads as supporting metadata.
    private var heroFontSize: CGFloat {
        let base: CGFloat = 58
        let len = displayAmountBody.count
        guard len > 7 else { return base }
        return max(32, (base * 7 / CGFloat(len)).rounded())
    }

    // The formatted body (no symbol), matching JSX formatTyped
    private var displayAmountBody: String {
        let s = model.amountString
        guard !s.isEmpty else { return "0" }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        var intPart = parts[0].isEmpty ? "0" : parts[0]
        // add thousands grouping
        if let n = Int(intPart) {
            intPart = n.formatted(.number.grouping(.automatic))
        }
        if parts.count == 2 {
            return intPart + "." + parts[1]
        }
        return intPart
    }

    private var heroAmount: some View {
        Text(displayAmountBody)
            .font(.system(size: heroFontSize, weight: .semibold))
            .monospacedDigit()
            .tracking(-2)
            .foregroundStyle(model.amountString.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.inkPrimary)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.15), value: heroFontSize)
            .animation(.easeInOut(duration: 0.2), value: model.amountString.isEmpty)
    }

    // MARK: - Currency menu
    // Matches CurrencyMenu in quickadd.jsx: sym at 30px/600/muted + chevron.down at 12px

    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button {
                    model.setCurrency(c)
                } label: {
                    if c.rawValue == model.currency.rawValue {
                        Label(menuLabel(c), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(c))
                    }
                }
            }
            Divider()
            Button {
                showCurrencyPicker = true
            } label: {
                Label("More currencies…", systemImage: "ellipsis.circle")
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.currency.rawValue)
                    .font(.system(size: 14, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(GoldengoTheme.inkMuted)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Color.goldengoField)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
    }

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }

    private var availableCurrencies: [CurrencyCode] { selectableCurrencies }

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == model.currency.rawValue }) {
            list.insert(model.currency, at: 0)
        }
        return list
    }

    // MARK: - Transaction summary

    private var transactionCard: some View {
        VStack(spacing: 0) {
            categoryRow
            cardDivider
            sourceRow
            cardDivider
            detailsRow
        }
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
        }
    }

    private var categoryRow: some View {
        let classification = SpendingCategoryCatalog.classify(model.selectedCategory)
        let iconColor = model.selectedCategory == nil ? GoldengoTheme.inkMuted : Color(hex: classification.colorHex)
        return transactionRow(
            label: "Category",
            value: model.selectedCategory ?? "Choose category",
            icon: model.selectedCategory == nil ? "tag" : classification.icon,
            iconColor: iconColor,
            action: { showCategoryPicker = true }
        )
    }

    private var sourceRow: some View {
        let source = selectedSource
        return transactionRow(
            label: "Paid from",
            value: source?.name ?? "Wallet — cash",
            icon: source == nil ? "wallet.bifold.fill" : "circle.fill",
            iconColor: source.map { GoldengoTheme.sourceColor($0.colorIndex) } ?? GoldengoTheme.accent,
            action: { showSourcePicker = true }
        )
    }

    private var detailsRow: some View {
        transactionRow(
            label: "Details",
            value: detailsSummary,
            icon: "slider.horizontal.3",
            iconColor: GoldengoTheme.inkMuted,
            action: { showDetailsSheet = true }
        )
    }

    private func transactionRow(
        label: String,
        value: String,
        icon: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 34, height: 34)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GoldengoTheme.inkMuted.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cardDivider: some View {
        Divider()
            .overlay(GoldengoTheme.hairline)
            .padding(.leading, 61)
    }

    private var selectedSource: SourceBalance? {
        model.sourceBalances.first { $0.id == model.selectedSourceID }
    }

    private var detailsSummary: String {
        let day = Calendar.current.isDateInToday(model.date)
            ? "Today"
            : model.date.formatted(date: .abbreviated, time: .omitted)
        if !model.splits.isEmpty { return "\(model.splits.count) categories · \(day)" }
        if let context = model.contextName { return "\(context) · \(day)" }
        if !model.merchant.isEmpty { return "\(model.merchant) · \(day)" }
        if !model.note.isEmpty { return "Note added · \(day)" }
        return day
    }

    // MARK: - Keypad
    // Matches Keypad in quickadd.jsx: 3-col grid, gap: 9, each key = .gg-key style
    // .gg-key: goldengoField bg, radius.control, 26px/500, height = keyHeight (60)

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3),
            spacing: 9
        ) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Button { tap(k) } label: {
                    Group {
                        if k == "⌫" {
                            Image(systemName: "delete.left")
                                .font(.system(size: 25))
                        } else {
                            Text(k)
                                .font(.system(size: k == "C" ? 20 : 26, weight: k == "C" ? .semibold : .medium))
                        }
                    }
                    .foregroundStyle(k == "C" ? GoldengoTheme.accent : GoldengoTheme.inkPrimary)
                    .frame(maxWidth: .infinity, minHeight: keyHeight)
                    .background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                }
                .buttonStyle(KeypadButtonStyle())
            }
        }
    }

    private func tap(_ k: String) {
        switch k {
        case "⌫": model.backspace()
        case "C":
            while !model.amountString.isEmpty { model.backspace() }
        default: model.tap(k)
        }
    }

    // MARK: - Add button
    // Matches .gg-btn: GoldButton full-width, "Add expense"

    private var addButton: some View {
        GoldButton("Add expense", isEnabled: model.canSave) {
            Task { await model.save() }
        }
    }
}

// MARK: - Keypad button style
// Matches .gg-key:active — scale(.94) + accent-tinted background

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.09), value: configuration.isPressed)
    }
}
