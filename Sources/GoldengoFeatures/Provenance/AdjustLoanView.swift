import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// One person's claim: log a payback (prefilled with the full amount — saving it closes the
/// debt), rename them, forgive the rest (becomes ONE visible "Gifts" expense — no silent
/// write-offs), or delete the claim. Idiom shared with AdjustSourceView.
struct AdjustLoanView: View {
    @State var model: SourcesModel
    let loan: LoanBalance
    @State private var nameText = ""
    @State private var amountText = ""
    @State private var busy = false
    @State private var showForgiveConfirm = false
    @State private var showDeleteConfirm = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var currency: CurrencyCode { CurrencyCode(loan.currencyCode) }

    /// STRICT parse (same rule as the sibling sheets); capped at what's owed — a payback
    /// above the debt isn't a payback (a friend's tip is income; log it as income).
    private var typedAmount: Decimal? {
        let cleaned = amountText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard cleaned.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let value = Decimal(string: cleaned), value <= loan.remaining
        else { return nil }
        return value
    }

    private var sinceText: String {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        return df.string(from: loan.sinceDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    // The serif title IS the name field — tap it to rename.
                    TextField("Name", text: $nameText)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("Owes you " + Money(amount: loan.remaining, currency: currency).formatted()
                         + " since \(sinceText). Log what came back.")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
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

                if let typed = typedAmount, typed > 0, typed < loan.remaining {
                    Text(Money(amount: loan.remaining - typed, currency: currency).formatted()
                         + " will still be owed")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                GoldButton("Log payback", isEnabled: !busy && (typedAmount ?? 0) > 0) {
                    guard !busy, let amount = typedAmount, amount > 0 else { return }
                    busy = true
                    focused = false
                    GoldengoHaptics.spendLanded()
                    Task {
                        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, trimmed != loan.personName {
                            await model.renameLoan(loan, to: trimmed)
                        }
                        await model.repayLoan(loan, amount: amount)
                        dismiss()
                    }
                }

                Button(role: .destructive) {
                    showForgiveConfirm = true
                } label: {
                    Label("Forgive the rest", systemImage: "heart")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(busy)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(busy)
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .goldengoDismissKeyboard()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert("Forgive \(loan.personName)?", isPresented: $showForgiveConfirm) {
            Button("Forgive", role: .destructive) {
                busy = true
                Task {
                    // Apply a pending rename first so the gift expense carries the right name.
                    let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, trimmed != loan.personName {
                        await model.renameLoan(loan, to: trimmed)
                    }
                    await model.forgiveLoan(loan)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("What's left becomes one visible Gifts expense — that's the moment it counts as spending.")
        }
        .alert("Delete this claim?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                busy = true
                Task {
                    await model.deleteLoan(loan)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The claim and its lend/payback history archive together.")
        }
        .onAppear {
            if nameText.isEmpty { nameText = loan.personName }
            if amountText.isEmpty {
                amountText = "\(Money(amount: loan.remaining, currency: currency).roundedAmount())"
            }
        }
    }
}
