import SwiftUI
import GoldengoDesignSystem
#if canImport(UIKit)
import UIKit
#endif

public struct QuickAddView: View {
    @State private var model: QuickAddModel
    @State private var showAdded = false
    public init(model: QuickAddModel) { _model = State(initialValue: model) }

    private var keys: [String] {
        // Hide the decimal key for currencies with no minor unit (e.g. lek) — it would do nothing.
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", model.allowsDecimal ? "." : "", "0", "⌫"]
    }

    public var body: some View {
        VStack(spacing: GoldengoTheme.Spacing.l) {
            amountDisplay
            categoryChips
            Spacer(minLength: 0)
            keypad
            addButton
        }
        .padding(.horizontal, GoldengoTheme.Spacing.l)
        .padding(.bottom, GoldengoTheme.Spacing.m)
        .background(Color.goldengoBackground.ignoresSafeArea())
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
        // Fire only on a *new* save (not on returning to this tab), so the confirmation isn't replayed.
        .onChange(of: model.savedCount) { _, newCount in
            guard newCount > 0 else { return }
            successHaptic()
            withAnimation(.snappy) { showAdded = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                if model.savedCount == newCount { withAnimation(.snappy) { showAdded = false } }
            }
        }
    }

    private func successHaptic() {
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }

    // MARK: - Amount

    private var amountDisplay: some View {
        VStack(spacing: GoldengoTheme.Spacing.xs) {
            Text("New expense")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.currency.symbol)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(model.amountString.isEmpty ? "0" : model.amountString)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(model.amountString.isEmpty ? Color.secondary : Color.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.amountString)
            }
        }
        .padding(.top, GoldengoTheme.Spacing.xl)
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
}
