import SwiftUI

/// The single renderer for every monetary amount in the app: tabular figures, semibold, tight
/// tracking, and an in-place numeric transition. Takes a pre-formatted string (amounts arrive
/// already localized from `Money.formatted()`); `role` sets the size.
public struct GoldengoAmountText: View {
    public enum Role: CaseIterable, Sendable { case hero, title, row, micro }

    private let text: String
    private let role: Role
    private let color: Color?
    @ScaledMetric private var scaledPointSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ text: String, role: Role = .row, color: Color? = nil) {
        self.text = text
        self.role = role
        self.color = color
        _scaledPointSize = ScaledMetric(wrappedValue: Self.pointSize(for: role),
                                        relativeTo: Self.textStyle(for: role))
    }

    public nonisolated static func pointSize(for role: Role) -> CGFloat {
        switch role {
        case .hero:  return 52
        case .title: return 30
        case .row:   return 17
        case .micro: return 13
        }
    }

    public nonisolated static func tracking(for role: Role) -> CGFloat {
        switch role {
        case .hero:  return -1.6
        case .title: return -0.6
        case .row:   return -0.2
        case .micro: return 0
        }
    }

    private nonisolated static func textStyle(for role: Role) -> Font.TextStyle {
        switch role {
        case .hero: return .largeTitle
        case .title: return .title
        case .row: return .body
        case .micro: return .caption
        }
    }

    public var body: some View {
        Text(text)
            .font(.system(size: scaledPointSize, weight: .semibold))
            .monospacedDigit()
            .tracking(Self.tracking(for: role))
            .foregroundStyle(color ?? GoldengoTheme.inkPrimary)
            .contentTransition(.numericText())
            // Roll the digits when the value actually changes (currency switch, new total, period
            // change). Stable amounts (every list row) never trigger it, so this is free at rest.
            .animation(reduceMotion ? nil : GoldengoMotion.standard, value: text)
    }
}
