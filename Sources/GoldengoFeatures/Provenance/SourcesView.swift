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
    @State private var adjustSource: SourceBalance?   // tapped source → edit name/amount sheet
    @State private var deleteCandidate: SourceBalance?   // swipe-Delete → confirm alert
    @State private var showDeleteConfirm = false
    @State private var showLend = false               // "Lend" pill → LendView sheet
    @State private var adjustLoan: LoanBalance?       // tapped claim → payback/forgive sheet
    @State private var deleteLoanCandidate: LoanBalance?   // swipe-Delete on a claim
    @State private var showDeleteLoanConfirm = false
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
        // A real `List` (not ScrollView+VStack) so the source cards get native, scroll-safe
        // `.swipeActions` — the same trade RecentExpensesView made (a custom DragGesture fights
        // the scroll; the system List owns scrolling and swipe together).
        List {
            Group {
                headerRow
                walletCard
                Text("Cash spends drain this — not your sources. Reconcile by feel.")
                    .font(.system(size: 12))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                    .padding(.horizontal, GoldengoTheme.Spacing.m)
                    .padding(.top, 8)
            }
            .plainRow()

            // ── Owed to you: money that left but is still yours ──────────────────
            if !model.loans.isEmpty {
                GoldengoSerifSectionHeader("Owed to you")
                    .padding(.horizontal, GoldengoTheme.Spacing.m)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                    .plainRow()
                ForEach(model.loans) { loan in
                    loanCard(loan)
                        .plainRow(top: 6, horizontal: GoldengoTheme.Spacing.m, bottom: 6)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteLoanCandidate = loan
                                showDeleteLoanConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { adjustLoan = loan } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(GoldengoTheme.accent)
                        }
                }
            }

            GoldengoSerifSectionHeader("Sources")
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.top, 26)
                .padding(.bottom, 12)
                .plainRow()

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
                .plainRow(horizontal: GoldengoTheme.Spacing.m)
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
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.vertical, 26)
                .goldengoCard()
                .plainRow(horizontal: GoldengoTheme.Spacing.m)
            } else {
                ForEach(model.snapshot?.sources ?? []) { b in
                    sourceCard(b)
                        .plainRow(top: 6, horizontal: GoldengoTheme.Spacing.m, bottom: 6)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteCandidate = b
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { adjustSource = b } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(GoldengoTheme.accent)
                        }
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
                    .plainRow(top: 6, horizontal: GoldengoTheme.Spacing.m, bottom: 6)
                }
            }

            Color.clear.frame(height: GoldengoTheme.Spacing.xl)
                .plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.goldengoBackground.ignoresSafeArea())
        .refreshable { await model.load() }
        .alert("Delete \(deleteCandidate?.name ?? "source")?", isPresented: $showDeleteConfirm,
               presenting: deleteCandidate) { b in
            Button("Delete", role: .destructive) {
                Task { await model.deleteSource(b) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its income history archives with it. Logged expenses stay.")
        }
        .sheet(isPresented: $showAddIncome, onDismiss: { Task { await model.load() } }) {
            AddIncomeView(model: model,
                          existingSources: (model.snapshot?.sources ?? []).map(\.name),
                          currency: model.currency, onDone: { showAddIncome = false })
        }
        .sheet(item: $adjustSource) { b in
            AdjustSourceView(model: model, source: b)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLend, onDismiss: { Task { await model.load() } }) {
            LendView(model: model, onDone: { showLend = false })
        }
        .sheet(item: $adjustLoan) { loan in
            AdjustLoanView(model: model, loan: loan)
                .presentationDetents([.medium, .large])
        }
        .alert("Delete \(deleteLoanCandidate?.personName ?? "this claim")?",
               isPresented: $showDeleteLoanConfirm, presenting: deleteLoanCandidate) { loan in
            Button("Delete", role: .destructive) {
                Task { await model.deleteLoan(loan) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The claim and its lend/payback history archive together.")
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

    // ── serif "Wallet" title + Income pill (wallet.jsx line 18-27) ──────────
    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Wallet")
                .font(.system(size: 32, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Spacer()
            Button { showLend = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                    Text("Lend")
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
            .padding(.leading, 8)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // ── "In your wallet" card (wallet.jsx lines 30-59) ───────────────────
    private var walletCard: some View {
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
        .padding(.horizontal, GoldengoTheme.Spacing.m)
    }

    // ── Source card: color dot + name + remaining amount + draining bar ──────
    // Tappable → the edit name/amount sheet (swipe left deletes, swipe right also edits).
    @ViewBuilder
    private func sourceCard(_ b: SourceBalance) -> some View {
        Button { adjustSource = b } label: {
            sourceCardBody(b)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sourceCardBody(_ b: SourceBalance) -> some View {
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

    // ── Loan card: color dot + person + amount owed + since date ─────────────
    // Tappable → the payback/forgive sheet (swipe left deletes, swipe right edits).
    @ViewBuilder
    private func loanCard(_ loan: LoanBalance) -> some View {
        Button { adjustLoan = loan } label: {
            HStack {
                HStack(spacing: 9) {
                    Circle()
                        .fill(GoldengoTheme.sourceColor(loan.colorIndex))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loan.personName)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(GoldengoTheme.inkPrimary)
                        Text("since " + Self.sinceFormatter.string(from: loan.sinceDate))
                            .font(.system(size: 12))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }
                Spacer()
                GoldengoAmountText(
                    Money(amount: loan.remaining, currency: CurrencyCode(loan.currencyCode)).formatted(),
                    role: .row
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .goldengoCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let sinceFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private func walletLabel(_ code: String) -> String {
        if code == "ALL" { return "Lek (ALL)" }
        let name = Locale.current.localizedString(forCurrencyCode: code)
        return name.map { "\($0) (\(code))" } ?? code
    }
}

private extension View {
    /// A clear, separator-less `List` row so the converted screen keeps its ScrollView-era look;
    /// the blocks' own paddings stay authoritative (insets only where a block relied on an outer
    /// horizontal padding).
    func plainRow(top: CGFloat = 0, horizontal: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: horizontal,
                                      bottom: bottom, trailing: horizontal))
    }
}

/// Edit one source: rename it and/or set what's actually left (mirrors AdjustWalletView's
/// honesty rules — higher → the gap arrives as income; lower → one visible Unaccounted entry
/// pinned to the pool), or delete the source entirely.
struct AdjustSourceView: View {
    @State var model: SourcesModel
    let source: SourceBalance
    @State private var nameText = ""
    @State private var amountText = ""
    @State private var busy = false
    @State private var showDeleteConfirm = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var currency: CurrencyCode { CurrencyCode(source.currencyCode) }

    /// What the user can SEE as the balance — comparisons and the prefill use this, so typing
    /// the displayed number back is a no-op (never a junk sub-unit correction).
    private var displayedRemaining: Decimal {
        Money(amount: source.remaining, currency: currency).roundedAmount()
    }

    /// STRICT parse (same rule as AdjustWalletView): whole string must be a plain
    /// non-negative amount. Grouped formats reject.
    private var typedAmount: Decimal? {
        let cleaned = amountText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard cleaned.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: cleaned)
    }

    /// Gap between what's typed and what the books say is left — shown as the hint.
    private var gap: Decimal? {
        guard let typed = typedAmount else { return nil }
        let g = typed - displayedRemaining
        return g == 0 ? nil : g
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    // The serif title IS the name field — tap it to rename.
                    TextField("Source name", text: $nameText)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("The books say " + Money(amount: source.remaining, currency: currency).formatted()
                         + " is left. Set what's real.")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }

                TextField("0", text: $amountText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .focused($focused)
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, GoldengoTheme.Spacing.s)
                    .foregroundStyle(amountText.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.inkPrimary)

                if let g = gap {
                    Text(g < 0
                         ? Money(amount: -g, currency: currency).formatted() + " less than the books → logged as Unaccounted"
                         : Money(amount: g, currency: currency).formatted() + " more than the books → added as income")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                GoldButton("Save", isEnabled: !busy && typedAmount != nil
                           && !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    guard !busy, let total = typedAmount else { return }
                    busy = true
                    focused = false
                    GoldengoHaptics.spendLanded()
                    Task {
                        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, trimmed != source.name {
                            await model.renameSource(source, to: trimmed)
                        }
                        if total != displayedRemaining {
                            await model.setSourceRemaining(total, source: source)
                        }
                        dismiss()
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete source", systemImage: "trash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(busy)
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .goldengoDismissKeyboard()
        .alert("Delete \(source.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                busy = true
                Task {
                    await model.deleteSource(source)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its income history archives with it. Logged expenses stay.")
        }
        .onAppear {
            if nameText.isEmpty { nameText = source.name }
            if amountText.isEmpty { amountText = "\(displayedRemaining)" }
        }
    }
}
