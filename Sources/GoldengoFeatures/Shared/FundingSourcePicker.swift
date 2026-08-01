import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// A focused funding-source picker. The Quick Add screen shows only the current choice; balances
/// live here where they can be compared without competing with the amount keypad.
struct FundingSourcePicker: View {
    @Environment(\.dismiss) private var dismiss

    let sources: [SourceBalance]
    let selectedSourceID: String?
    let onSelect: (String?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    sourceRow(nil)
                    ForEach(sources) { source in
                        sourceRow(source)
                    }
                }
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.vertical, 14)
            }
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Paid from")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sourceRow(_ source: SourceBalance?) -> some View {
        let isSelected = selectedSourceID == source?.id

        return Button {
            onSelect(source?.id)
            dismiss()
        } label: {
            HStack(spacing: 13) {
                Group {
                    if let source {
                        Circle()
                            .fill(GoldengoTheme.sourceColor(source.colorIndex))
                            .frame(width: 13, height: 13)
                    } else {
                        Image(systemName: "wallet.bifold.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GoldengoTheme.accent)
                    }
                }
                .frame(width: 34, height: 34)
                .background(isSelected ? GoldengoTheme.accentSoft : Color.goldengoField)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(source?.name ?? "Wallet — cash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.inkPrimary)

                    if let source {
                        Text("\(remaining(source)) available")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    } else {
                        Text("Pay with cash in your wallet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GoldengoTheme.inkMuted)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(isSelected ? GoldengoTheme.accentSoft : Color.goldengoSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? GoldengoTheme.accentLine : GoldengoTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func remaining(_ source: SourceBalance) -> String {
        Money(amount: source.remaining, currency: CurrencyCode(source.currencyCode)).formatted()
    }
}
