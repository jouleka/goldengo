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
    @State private var walletAdjustCurrency: CurrencyCode?   // non-nil skips the list and opens this cash count
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
        walletAdjustCurrency = walletAdjustTarget()
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
            headerRow
                .plainRow()

            walletCard
                .plainRow(horizontal: GoldengoTheme.Spacing.m)

            quickActions
                .plainRow(top: 12, horizontal: GoldengoTheme.Spacing.m)

            if let unaccounted = model.unaccountedText() {
                unaccountedCard(unaccounted)
                    .plainRow(top: 12, horizontal: GoldengoTheme.Spacing.m)
            }

            sectionHeading("Money sources", subtitle: "What your non-cash money came from")
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
            } else if model.snapshot?.sources.isEmpty ?? true {
                VStack(spacing: 10) {
                    Image(systemName: "banknote")
                        .font(.system(size: 26))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    Text("No sources yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("Add income to remember where money came from and what is still available.")
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

            }

            // Money that left the wallet but is still an asset is visually separate from sources.
            if !model.loans.isEmpty {
                sectionHeading("Owed to you", subtitle: "Open claims and expected paybacks")
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

            Color.clear.frame(height: 108)
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
            walletAdjustCurrency = nil
            Task { await model.load() }
        }) {
            WalletView(model: model, autoOpenAdjust: walletAdjustCurrency)
        }
        .task { await model.load(); consumePendingWalletAdjust() }
        // A tap can arrive while this tab is already live (warm open) — observe the flag.
        .onChange(of: model.pendingWalletAdjust) { _, on in if on { consumePendingWalletAdjust() } }
    }

    // MARK: - Header and cash overview

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Wallet")
                .font(.system(size: 32, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text("Cash, sources, and money owed to you")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("CASH ON HAND")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.65)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                    Text(model.wallet.isEmpty ? "Not tracked yet" : cashCaption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }

                Spacer()

                Button("Manage") { openWalletManager() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
            }

            if model.wallet.isEmpty {
                Text("Set what you are physically carrying. Cash expenses will reduce it automatically.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Money(amount: model.walletTotal(), currency: model.currency).formatted())
                    .font(.system(size: 31, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if model.wallet.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.wallet) { line in
                                Button { openCashCount(CurrencyCode(line.currencyCode)) } label: {
                                    HStack(spacing: 6) {
                                        Text(line.currencyCode)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(GoldengoTheme.inkMuted)
                                        Text(Money(amount: line.expectedNow,
                                                   currency: CurrencyCode(line.currencyCode)).amountText())
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(GoldengoTheme.inkPrimary)
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(Color.goldengoField)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
        }
    }

    private var cashCaption: String {
        guard let newest = model.wallet.map(\.baselineDate).max() else { return "Live estimate" }
        let count = model.wallet.count
        let currencies = count == 1 ? walletLabel(model.wallet[0].currencyCode) : "\(count) currencies"
        return "\(currencies) · counted \(SourcesModel.compactDay(newest))"
    }

    private var quickActions: some View {
        HStack(spacing: 9) {
            quickAction("Income", icon: "tray.and.arrow.down.fill") { showAddIncome = true }
            quickAction("Count cash", icon: "banknote.fill") { openCashCount(walletAdjustTarget()) }
            quickAction("Lend", icon: "arrow.up.right") { showLend = true }
        }
    }

    private func quickAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.accent)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(Color.goldengoSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func unaccountedCard(_ amount: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GoldengoTheme.danger)
                .frame(width: 36, height: 36)
                .background(GoldengoTheme.danger.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Needs review")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                Text("Money that could not be matched to a source")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }

            Spacer(minLength: 8)
            Text(amount)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(GoldengoTheme.danger)
        }
        .padding(14)
        .background(GoldengoTheme.danger.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(GoldengoTheme.danger.opacity(0.24), lineWidth: 1)
        }
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 23, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Text(subtitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    private func openCashCount(_ currency: CurrencyCode?) {
        walletAdjustCurrency = currency
        showCount = true
    }

    private func openWalletManager() {
        walletAdjustCurrency = nil
        showCount = true
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.color(b))
                    .frame(width: 40, height: 40)
                    .background(model.color(b).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(b.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("Money source · \(b.currencyCode)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    GoldengoAmountText(model.remainingText(b), role: .row)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }
            }

            DrainingPoolBar(fraction: model.fraction(b), tint: model.color(b))

            Text("\(Int((model.fraction(b) * 100).rounded()))% left of "
                 + Money(amount: b.totalInflow,
                         currency: CurrencyCode(b.currencyCode)).formatted())
                .font(.system(size: 12))
                .foregroundStyle(GoldengoTheme.inkMuted)
        }
        .padding(16)
        .goldengoCard(padding: 0)
    }

    // ── Loan card: color dot + person + amount owed + since date ─────────────
    // Tappable → the payback/forgive sheet (swipe left deletes, swipe right edits).
    // Same skeleton as a source card — title row (dot + name … amount), then ONE muted
    // full-width meta line: "since 25 Jun · 🔔 25 Jul" (the bell IS the word "nudge";
    // the sheet spells the promise out in a sentence).
    @ViewBuilder
    private func loanCard(_ loan: LoanBalance) -> some View {
        Button { adjustLoan = loan } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.sourceColor(loan.colorIndex))
                    .frame(width: 40, height: 40)
                    .background(GoldengoTheme.sourceColor(loan.colorIndex).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(loan.personName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    HStack(spacing: 4) {
                        Text("Since " + SourcesModel.compactDay(loan.sinceDate))
                        if let nudge = model.nextNudgeDateText(loan) {
                            Text("·")
                            Image(systemName: "bell.fill")
                                .font(.system(size: 9))
                            Text(nudge)
                        } else {
                            Text("· no reminder")
                        }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(GoldengoTheme.inkMuted)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    GoldengoAmountText(
                        Money(amount: loan.remaining, currency: CurrencyCode(loan.currencyCode)).formatted(),
                        role: .row
                    )
                    HStack(spacing: 4) {
                        Text("Open")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }
            }
            .padding(16)
            .goldengoCard(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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
