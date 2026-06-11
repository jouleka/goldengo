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
    @FocusState private var noteFocused: Bool
#if os(iOS)
    @State private var showScanner = false
    @State private var scanModel: ReceiptScanModel?
#endif
    public init(model: QuickAddModel) { _model = State(initialValue: model) }

    private var keys: [String] {
        // Hide the decimal key for currencies with no minor unit (e.g. lek) — it would do nothing.
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", model.allowsDecimal ? "." : "", "0", "⌫"]
    }

    public var body: some View {
        VStack(spacing: GoldengoTheme.Spacing.l) {
            amountDisplay
            noteField
            categoryChips
            paidFromRow
            Spacer(minLength: 0)
            keypad
#if os(iOS)
            scanReceiptButton
#endif
            addButton
        }
        .padding(.horizontal, GoldengoTheme.Spacing.l)
        .padding(.bottom, GoldengoTheme.Spacing.m)
        .background(
            Color.goldengoBackground
                .ignoresSafeArea()
                .onTapGesture { noteFocused = false }   // tap anywhere off the field dismisses the keyboard
        )
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
        .task { await model.loadSources() }   // populate the "Paid from" picker (hidden if no sources)
        // Fire only on a *new* save (not on returning to this tab), so the confirmation isn't replayed.
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

    // MARK: - Amount

    private var amountDisplay: some View {
        VStack(spacing: GoldengoTheme.Spacing.xs) {
            Text("New expense")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                currencyMenu
                Text(model.amountString.isEmpty ? "0" : model.amountString)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(model.amountString.isEmpty ? Color.secondary : Color.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.amountString)
            }
        }
        .padding(.top, GoldengoTheme.Spacing.xl)
    }

    // MARK: - Note

    private var noteField: some View {
        HStack(spacing: GoldengoTheme.Spacing.s) {
            Image(systemName: "pencil")
                .font(.subheadline)
                .foregroundStyle(noteFocused ? GoldengoTheme.accent : .secondary)
            TextField("Add a note (optional)", text: $model.note)
                .font(.subheadline)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
                .tint(GoldengoTheme.accent)
#if canImport(UIKit)
                .textInputAutocapitalization(.sentences)
#endif
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.vertical, 12)
        .background(Color.goldengoField)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
        .animation(.snappy, value: noteFocused)
    }

    // MARK: - Currency

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
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.currency.symbol)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
    }

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }

    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == model.currency.rawValue }) {
            list.insert(model.currency, at: 0)   // keep the current currency reachable
        }
        return list
    }

    // MARK: - Categories

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                ForEach(model.quickCategories, id: \.self) { cat in
                    let selected = model.selectedCategory == cat
                    Button {
                        model.selectedCategory = selected ? nil : cat
                    } label: {
                        Label(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, GoldengoTheme.Spacing.m)
                            .padding(.vertical, 10)
                            .background(selected ? GoldengoTheme.accent : Color.goldengoSurface)
                            .foregroundStyle(selected ? .black : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Paid from (GOL-90)

    /// Optional funding-source picker — only when the user has named sources. "Automatic" (FIFO) is
    /// the zero-tap default; choosing a source pins this expense to it.
    @ViewBuilder private var paidFromRow: some View {
        if !model.sourceBalances.isEmpty {
            HStack {
                Text("Paid from").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                paidFromMenu
            }
        }
    }

    private var selectedSource: SourceBalance? {
        model.sourceBalances.first { $0.id == model.selectedSourceID }
    }

    private var paidFromMenu: some View {
        Menu {
            // GOL-95 v2: a hand-logged spend is CASH by default — it drains the wallet.
            // Picking a source below marks it bank-paid instead (pins that source).
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
            HStack(spacing: 7) {
                if let s = selectedSource {
                    Circle().fill(GoldengoTheme.sourceColor(s.colorIndex)).frame(width: 9, height: 9)
                    Text(s.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                } else {
                    Image(systemName: "wallet.bifold").font(.caption).foregroundStyle(.secondary)
                    Text("Wallet").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
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

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GoldengoTheme.Spacing.s), count: 3),
                  spacing: GoldengoTheme.Spacing.s) {
            ForEach(keys, id: \.self) { k in
                if k.isEmpty {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 60)   // keeps 0 / ⌫ aligned
                } else {
                    Button { tap(k) } label: {
                        Group {
                            if k == "⌫" {
                                Image(systemName: "delete.left")
                            } else {
                                Text(k)
                            }
                        }
                        .font(.title2.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.goldengoField)
                        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Save

    private var addButton: some View {
        Button {
            noteFocused = false                     // drop the keyboard the moment the expense is added
            Task { await model.save() }
        } label: {
            Text("Add expense")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .background(model.canSave ? GoldengoTheme.accent : Color.goldengoField)
        .foregroundStyle(model.canSave ? .black : .secondary)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
        .disabled(!model.canSave)
        .animation(.snappy, value: model.canSave)
    }

    private func tap(_ k: String) { k == "⌫" ? model.backspace() : model.tap(k) }

#if os(iOS)
    @ViewBuilder private var scanReceiptButton: some View {
        if DocumentScannerView.isSupported {
            Button { showScanner = true } label: {
                Label("Scan receipt", systemImage: "doc.viewfinder")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoldengoTheme.accent)
        }
    }
#endif
}
