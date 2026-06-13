import SwiftUI

/// Full-width primary call-to-action. Gold fill + `onAccent` label when enabled; quiet `field`
/// fill + muted label when disabled. The single primary button across Add/Save/Done CTAs.
public struct GoldButton: View {
    public enum Fill: Equatable, Sendable { case accent, field }
    public enum LabelTint: Equatable, Sendable { case onAccent, muted }

    /// Pure state→fill mapping (testable).
    public static func fill(isEnabled: Bool) -> Fill { isEnabled ? .accent : .field }
    /// Pure state→label-tint mapping (testable).
    public static func labelTint(isEnabled: Bool) -> LabelTint { isEnabled ? .onAccent : .muted }

    private let title: String
    private let systemImage: String?
    private let isEnabled: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GoldengoTheme.Spacing.m)
        }
        .buttonStyle(.plain)
        .background(fillColor)
        .foregroundStyle(labelColor)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
        .disabled(!isEnabled)
    }

    private var fillColor: Color {
        Self.fill(isEnabled: isEnabled) == .accent ? GoldengoTheme.accent : Color.goldengoField
    }
    private var labelColor: Color {
        Self.labelTint(isEnabled: isEnabled) == .onAccent ? GoldengoTheme.onAccent : GoldengoTheme.inkMuted
    }
}
