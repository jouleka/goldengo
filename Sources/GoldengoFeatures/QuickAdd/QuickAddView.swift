import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData
#if canImport(UIKit)
import UIKit
#endif

public struct QuickAddView: View {
    @State private var model: QuickAddModel
    @State private var showAdded = false
    @State private var showCurrencyPicker = false
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
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", model.allowsDecimal ? "." : "", "0", "⌫"]
    }

    public var body: some View {
        // Stacked layout — padding mirrors quickadd.jsx StackedLayout: 14px top, 22px h, 34px bottom
        VStack(spacing: 0) {
            amountBlock
                .padding(.top, 8)               // paddingTop: 8 on AmountBlock wrapper

            categoryChips
                .padding(.top, 22)              // marginTop: 22

            if !model.sourceBalances.isEmpty {
                paidFromRow
                    .padding(.top, 16)          // marginTop: 16
            }

            Spacer(minLength: 0)                // flex: 1

            keypad
                .padding(.top, 16)             // marginTop: 16

#if os(iOS)
            scanReceiptButton
                .padding(.top, 10)             // marginTop: 10
#endif

            addButton
                .padding(.top, 8)              // marginTop: 8
        }
        .padding(.top, 14)                      // outer container top: 14px
        .padding(.horizontal, 22)               // outer container h: 22px
        .padding(.bottom, 34)                   // outer container bottom: 34px
        .background(Color.goldengoBackground.ignoresSafeArea())
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
        .task { await model.loadSources() }
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
        VStack(spacing: 0) {
            Text("New expense")
                .font(.custom("Georgia", size: 19).weight(.medium))   // gg-serif-title at 19px
                .foregroundStyle(GoldengoTheme.inkMuted)
                .padding(.bottom, 14)                                  // marginBottom: 14

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                currencyMenu
                heroAmount
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .multilineTextAlignment(.center)
    }

    // Dynamic size: base 50pt (JSX big=false), shrinks for strings longer than 7 chars
    private var heroFontSize: CGFloat {
        let base: CGFloat = 50
        let len = displayAmountBody.count
        guard len > 7 else { return base }
        return max(30, (base * 7 / CGFloat(len)).rounded())
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
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(model.currency.symbol)
                    .font(.system(size: 30, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.top, 6)              // marginTop: 6 on the chevron in JSX
            }
            .foregroundStyle(GoldengoTheme.inkMuted)
            .contentShape(Rectangle())
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

    // MARK: - Category chips
    // Matches Chips in quickadd.jsx: horizontal scroll, gap: 9, SelectableChip (= .gg-chip)

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(model.quickCategories, id: \.self) { cat in
                    SelectableChip(
                        cat,
                        systemImage: GoldengoCategoryIcon.symbol(for: cat),
                        isSelected: model.selectedCategory == cat
                    ) {
                        model.selectedCategory = model.selectedCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.vertical, 2)              // padding: '2px 0'
        }
    }

    // MARK: - Paid from
    // Matches PaidFrom in quickadd.jsx: gg-eyebrow label + pill menu on goldengoField

    private var paidFromRow: some View {
        HStack {
            GoldengoSectionLabel("Paid from")   // .gg-eyebrow: 12px/600/uppercase/0.6 tracking/ink-muted
            Spacer()
            paidFromMenu
        }
    }

    private var selectedSource: SourceBalance? {
        model.sourceBalances.first { $0.id == model.selectedSourceID }
    }

    private var paidFromMenu: some View {
        Menu {
            Button { model.selectedSourceID = nil } label: {
                if model.selectedSourceID == nil {
                    Label("Wallet — cash", systemImage: "checkmark")
                } else {
                    Text("Wallet — cash")
                }
            }
            ForEach(model.sourceBalances) { s in
                Button { model.selectedSourceID = s.id } label: {
                    let label = "\(s.name)  ·  \(sourceRemaining(s)) left"
                    if model.selectedSourceID == s.id {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            // pill: goldengoField bg, gap: 8, padding: '8px 14px', borderRadius: 9999
            HStack(spacing: 8) {
                if let s = selectedSource {
                    Circle()
                        .fill(GoldengoTheme.sourceColor(s.colorIndex))
                        .frame(width: 9, height: 9)
                    Text(s.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                } else {
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 16))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    Text("Wallet — cash")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.goldengoField)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .animation(.snappy, value: model.selectedSourceID)
    }

    private func sourceRemaining(_ s: SourceBalance) -> String {
        Money(amount: s.remaining, currency: CurrencyCode(s.currencyCode)).formatted()
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
                if k.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: keyHeight)
                } else {
                    Button { tap(k) } label: {
                        Group {
                            if k == "⌫" {
                                Image(systemName: "delete.left")
                                    .font(.system(size: 26))
                            } else {
                                Text(k)
                                    .font(.system(size: 26, weight: .medium))
                            }
                        }
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                        .frame(maxWidth: .infinity, minHeight: keyHeight)
                        .background(Color.goldengoField)
                        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(KeypadButtonStyle())
                }
            }
        }
    }

    private func tap(_ k: String) { k == "⌫" ? model.backspace() : model.tap(k) }

    // MARK: - Scan receipt
    // Matches ScanBtn in quickadd.jsx: accent color, "doc.viewfinder", 15px/600, minHeight: 40

#if os(iOS)
    @ViewBuilder private var scanReceiptButton: some View {
        if DocumentScannerView.isSupported {
            Button { showScanner = true } label: {
                Label("Scan receipt", systemImage: "doc.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .padding(.vertical, 6)          // padding: '6px 0'
            }
            .buttonStyle(.plain)
        }
    }
#endif

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
