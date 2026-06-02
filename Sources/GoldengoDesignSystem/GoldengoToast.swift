import SwiftUI

/// A slim floating toast — a confirmation message that briefly appears above the content (e.g. above
/// the tab bar) with an optional trailing action. Uses `.regularMaterial` plus a hairline border and
/// a soft shadow so it reads as a distinct, elevated element against both light and dark backgrounds
/// (a plain surface fill disappeared into the dark canvas). Minimal by design — one line, one action.
public struct GoldengoToast: View {
    private let icon: String?
    private let iconTint: Color
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ message: String,
                icon: String? = nil,
                iconTint: Color = .secondary,
                actionTitle: String? = nil,
                action: (() -> Void)? = nil) {
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.actionTitle = actionTitle
        self.action = action
    }

    private var hasAction: Bool { actionTitle != nil && action != nil }

    public var body: some View {
        HStack(spacing: GoldengoTheme.Spacing.s + 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(iconTint)
            }
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if hasAction {
                Spacer(minLength: GoldengoTheme.Spacing.s)
                Button(actionTitle ?? "") { action?() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, GoldengoTheme.Spacing.l)
        .padding(.trailing, hasAction ? GoldengoTheme.Spacing.m : GoldengoTheme.Spacing.l)
        .padding(.vertical, GoldengoTheme.Spacing.s + 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}
