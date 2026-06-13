import SwiftUI

/// The single renderer for every monetary amount in the app: tabular figures, semibold, tight
/// tracking, and an in-place numeric transition. Takes a pre-formatted string (amounts arrive
/// already localized from `Money.formatted()`); `role` sets the size.
public struct GoldengoAmountText: View {
    public enum Role: CaseIterable { case hero, title, row, micro }

    private let text: String
    private let role: Role

    public init(_ text: String, role: Role = .row) {
        self.text = text
        self.role = role
    }

    public static func pointSize(for role: Role) -> CGFloat {
        switch role {
        case .hero:  return 44
        case .title: return 30
        case .row:   return 17
        case .micro: return 13
        }
    }

    public static func tracking(for role: Role) -> CGFloat {
        switch role {
        case .hero:  return -1.0
        case .title: return -0.5
        case .row:   return -0.2
        case .micro: return 0
        }
    }

    public var body: some View {
        Text(text)
            .font(.system(size: Self.pointSize(for: role), weight: .semibold))
            .monospacedDigit()
            .tracking(Self.tracking(for: role))
            .foregroundStyle(GoldengoTheme.inkPrimary)
            .contentTransition(.numericText())
    }
}
