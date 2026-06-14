import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData

/// The Wallet tab (wallet.jsx main screen): serif "Wallet" header + Income pill, per-currency
/// cash card ("In your wallet"), draining Sources pools, unaccounted row.
public struct SourcesView: View {
    @State private var model: SourcesModel
    @State private var showAddIncome = false
    @State private var showCount = false
    @State private var walletAutoAdjust = false   // GOL-98: widget tap lands ON the Adjust screen
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    /// Consume the one-shot widget deep-link flag: open the wallet sheet straight at Adjust.
    private func consumePendingWalletAdjust() {
        guard model.pendingWalletAdjust else { return }
        model.pendingWalletAdjust = false
        walletAutoAdjust = true
        showCount = true
    }

    /// Where a widget tap lands (GOL-98 review): ALL when tracked, else the sole tracked currency;
    /// nil (the wallet list) when empty or ambiguous.
    private func walletAdjustTarget() -> CurrencyCode? {
        let codes = model.wallet.map(\.currencyCode)
        if codes.contains(CurrencyCode.all.rawValue) { return .all }
        if codes.count == 1, let only = codes.first { return CurrencyCode(only) }
        return nil
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── serif "Wallet" title + Income pill (wallet.jsx line 18-27) ──────────
                HStack(alignment: .center) {
                    Text("Wallet")
                        .font(.system(size: 32, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Spacer()
                    Button { showAddIncome = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("Income")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(GoldengoTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(GoldengoTheme.accentSoft)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(GoldengoTheme.accentLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                // ── "In your wallet" card (wallet.jsx lines 30-59) ───────────────────
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "wallet.bifold")
                            .font(.system(size: 15))
                            .foregroundStyle(GoldengoTheme.accent)
                        Text("IN YOUR WALLET")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    if model.wallet.isEmpty {
                        Text("Your pocket, by currency. Tap below to set what you're actually holding.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    } else {
                        ForEach(Array(model.wallet.enumerated()), id: \.element.id) { idx, w in
                            Button { showCount = true } label: {
                                HStack {
                                    Text(walletLabel(w.currencyCode))
                                        .font(.system(size: 15.5, weight: .semibold))
                                        .foregroundStyle(GoldengoTheme.inkPrimary)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        GoldengoAmountText(
                                            "~" + Money(amount: w.expectedNow,
                                                        currency: CurrencyCode(w.currencyCode)).formatted(),
                                            role: .row
                                        )
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(GoldengoTheme.inkMuted)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) {
                                if idx > 0 {
                                    Rectangle()
                                        .fill(GoldengoTheme.hairline)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }

                    // "Track another currency" row
                    Button { showCount = true } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                            Text("Track another currency")
                                .font(.system(size: 14.5, weight: .medium))
                        }
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) {
                        Rectangle().fill(GoldengoTheme.hairline).frame(height: 1)
                    }
                }
                .goldengoCard(padding: 0)
                .padding(.horizontal, 20)

                Text("Cash spends drain this — not your sources. Reconcile by feel.")
                    .font(.system(size: 12))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)

                // ── Sources draining pools (wallet.jsx lines 65-93) ──────────────────
                GoldengoSerifSectionHeader("Sources")
                    .padding(.horizontal, 24)
                    .padding(.top, 26)
                    .padding(.bottom, 12)

                if model.loadFailed {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                        Text("Couldn't load sources")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("Pull to refresh.")
                            .font(.caption)
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(26)
                    .goldengoCard()
                    .padding(.horizontal, 20)
                } else if (model.snapshot?.sources.isEmpty ?? true) && model.unaccountedText() == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "banknote")
                            .font(.system(size: 26))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                        Text("No sources yet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("Add where money came from — a remittance, a cash withdrawal, your pay.")
                            .font(.system(size: 13))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 26)
                    .goldengoCard()
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.snapshot?.sources ?? []) { b in
                            sourceCard(b)
                        }

                        if let unaccounted = model.unaccountedText() {
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(GoldengoTheme.inkMuted)
                                    Text("Unaccounted")
                                        .font(.subheadline)
                                        .foregroundStyle(GoldengoTheme.inkMuted)
                                }
                                Spacer()
                                GoldengoAmountText(unaccounted, role: .row, color: GoldengoTheme.inkMuted)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .goldengoCard()
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: GoldengoTheme.Spacing.xl)
            }
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .refreshable { await model.load() }
        .sheet(isPresented: $showAddIncome, onDismiss: { Task { await model.load() } }) {
            AddIncomeView(model: model,
                          existingSources: (model.snapshot?.sources ?? []).map(\.name),
                          currency: model.currency, onDone: { showAddIncome = false })
        }
        .sheet(isPresented: $showCount, onDismiss: {
            walletAutoAdjust = false
            Task { await model.load() }
        }) {
            WalletView(model: model, autoOpenAdjust: walletAutoAdjust ? walletAdjustTarget() : nil)
        }
        .task { await model.load(); consumePendingWalletAdjust() }
        // A tap can arrive while this tab is already live (warm open) — observe the flag.
        .onChange(of: model.pendingWalletAdjust) { _, on in if on { consumePendingWalletAdjust() } }
    }

    // ── Source card: color dot + name + remaining amount + draining bar ──────
    @ViewBuilder
    private func sourceCard(_ b: SourceBalance) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 9) {
                    Circle()
                        .fill(model.color(b))
                        .frame(width: 10, height: 10)
                    Text(b.name)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                }
                Spacer()
                GoldengoAmountText(model.remainingText(b), role: .row)
            }
            .padding(.bottom, 12)

            DrainingPoolBar(fraction: model.fraction(b), tint: model.color(b))

            Text(model.remainingText(b) + " of " + Money(amount: b.totalInflow,
                 currency: CurrencyCode(b.currencyCode)).formatted()
                 + " left · " + "\(Int((model.fraction(b) * 100).rounded()))%")
                .font(.system(size: 12))
                .foregroundStyle(GoldengoTheme.inkMuted)
                .padding(.top, 9)
        }
        .padding(18)
        .goldengoCard(padding: 0)
    }

    private func walletLabel(_ code: String) -> String {
        if code == "ALL" { return "Lek (ALL)" }
        let name = Locale.current.localizedString(forCurrencyCode: code)
        return name.map { "\($0) (\(code))" } ?? code
    }
}
