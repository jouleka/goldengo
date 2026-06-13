import SwiftUI

/// A selectable pill (category / paid-from). Selected = gold-soft wash + 1px gold hairline + gold
/// label (gold used sparingly, never a solid fill behind the chip — D4); unselected = quiet field
/// fill + ink label. Shared by Add and Receipt (and later Edit).
public struct SelectableChip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? GoldengoTheme.accent : GoldengoTheme.inkPrimary)
            .background(isSelected ? GoldengoTheme.accentSoft : Color.goldengoField)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? GoldengoTheme.accent : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
