import SwiftUI
import GoldengoDesignSystem

/// One revealable swipe action (Edit / Delete) for `SwipeableRow`.
struct SwipeAction {
    let label: String
    let systemImage: String
    let tint: Color
    let foreground: Color
    let handler: () -> Void

    /// Gold Edit action, revealed by swiping right. Mirrors the dashboard's Add button (gold on black).
    static func edit(_ handler: @escaping () -> Void) -> SwipeAction {
        SwipeAction(label: "Edit", systemImage: "pencil",
                    tint: GoldengoTheme.accent, foreground: .black, handler: handler)
    }

    /// Red Delete action, revealed by swiping left.
    static func delete(_ handler: @escaping () -> Void) -> SwipeAction {
        SwipeAction(label: "Delete", systemImage: "trash",
                    tint: GoldengoTheme.danger, foreground: .white, handler: handler)
    }
}

/// A row that reveals a swipe action on each edge — swipe right for `leading` (Edit), left for
/// `trailing` (Delete) — while keeping a full-row tap (`onTap`).
///
/// Built for the Home recent list, which is a `ScrollView { LazyVStack { … } }` rather than a `List`,
/// so native `.swipeActions` is unavailable. The horizontal `DragGesture` is direction-locked to
/// predominantly-horizontal movement and attached as a low-priority `.gesture`, so SwiftUI's scroll
/// arbitration keeps vertical scrolling intact: the ScrollView claims vertical drags and this gesture
/// only engages on horizontal ones (using `.simultaneousGesture` here made the row compete with every
/// scroll touch and could stall the list). Release behaviour (snap closed / rest open / commit) is
/// decided by the pure `SwipeResolver`.
struct SwipeableRow<Content: View>: View {
    private let id: String
    @Binding private var openRowID: String?
    private let leading: SwipeAction?
    private let trailing: SwipeAction?
    private let onTap: () -> Void
    private let content: Content

    /// - Parameters:
    ///   - id: Stable identity for this row.
    ///   - openRowID: Shared "which row is currently open" binding — opening one row closes any
    ///     other, mirroring how a `List`'s native swipe actions behave.
    init(id: String,
         openRowID: Binding<String?>,
         leading: SwipeAction? = nil,
         trailing: SwipeAction? = nil,
         onTap: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.id = id
        self._openRowID = openRowID
        self.leading = leading
        self.trailing = trailing
        self.onTap = onTap
        self.content = content()
    }

    /// Width of a revealed action button (the rounded pill behind the row).
    private let buttonWidth: CGFloat = 60
    /// Margin floating each action button in from the row's edges (top/bottom/outer/inner).
    private let actionInset: CGFloat = GoldengoTheme.Spacing.s
    /// Spring used for every snap so opening, closing, and committing feel identical.
    private let snap = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// How far the content rests open to fully reveal a button (button + its inner & outer margins).
    private var restOpen: CGFloat { buttonWidth + 2 * actionInset }

    /// Live horizontal displacement of the content (positive = revealing Edit, negative = Delete).
    @State private var offset: CGFloat = 0
    /// The settled displacement the row rests at (0, +restOpen, or -restOpen).
    @State private var restOffset: CGFloat = 0
    /// Per-gesture axis decision: nil until decided, true = horizontal (ours), false = vertical (scroll).
    @State private var horizontalDrag: Bool?

    private var openThreshold: CGFloat { restOpen * 0.55 }
    /// Fixed full-swipe commit distance. Deliberately NOT measured per-row: a `GeometryReader` in each
    /// row's background interfered with the enclosing `ScrollView`'s scrolling and got worse as rows
    /// piled up. A constant works fine — fast flicks still commit via the velocity (predictedEnd) path.
    private var commitThreshold: CGFloat { restOpen * 2.4 }

    var body: some View {
        ZStack {
            actionsLayer
            contentLayer
        }
        .clipped()
        .onChange(of: openRowID) { _, newValue in
            // Another row opened — close this one so only one is ever open.
            if newValue != id, restOffset != 0 { settle(0) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if let leading { Button(leading.label) { leading.handler() } }
            if let trailing { Button(trailing.label) { trailing.handler() } }
        }
    }

    // MARK: - Layers

    private var actionsLayer: some View {
        HStack(spacing: 0) {
            if let leading { actionButton(leading) }
            Spacer(minLength: 0)
            if let trailing { actionButton(trailing) }
        }
        .padding(actionInset)
    }

    private var contentLayer: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.goldengoSurface)
            .contentShape(Rectangle())
            .offset(x: offset)
            .gesture(dragGesture)
            .onTapGesture { handleTap() }
    }

    /// A rounded, floating action button revealed as the content slides off it. Tapping it (when
    /// revealed) fires the action.
    private func actionButton(_ action: SwipeAction) -> some View {
        Button { trigger(action) } label: {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage).font(.subheadline.weight(.semibold))
                Text(action.label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(action.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(action.tint, in: RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: buttonWidth)
        .accessibilityHidden(true) // exposed via the row's accessibilityActions instead
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if horizontalDrag == nil {
                    horizontalDrag = abs(value.translation.width) > abs(value.translation.height)
                }
                guard horizontalDrag == true else { return }
                offset = resisted(restOffset + value.translation.width)
            }
            .onEnded { value in
                defer { horizontalDrag = nil }
                guard horizontalDrag == true else { return }
                let total = restOffset + value.translation.width
                let predicted = restOffset + value.predictedEndTranslation.width
                switch SwipeResolver.outcome(translation: total, predictedEnd: predicted,
                                             openThreshold: openThreshold, commitThreshold: commitThreshold,
                                             hasLeading: leading != nil, hasTrailing: trailing != nil) {
                case .closed:         settle(0)
                case .openLeading:    settle(restOpen)
                case .openTrailing:   settle(-restOpen)
                case .commitLeading:  if let leading { trigger(leading) } else { settle(0) }
                case .commitTrailing: if let trailing { trigger(trailing) } else { settle(0) }
                }
            }
    }

    // MARK: - State transitions

    private func handleTap() {
        if restOffset != 0 { settle(0) } else { onTap() }
    }

    private func trigger(_ action: SwipeAction) {
        settle(0)
        action.handler()
    }

    private func settle(_ to: CGFloat) {
        restOffset = to
        withAnimation(snap) { offset = to }
        // Keep the shared open-row tracking in sync: claim it when opening, release it when closing.
        // (When another row claimed it, `openRowID` already points elsewhere, so we don't clobber it.)
        if to != 0 {
            openRowID = id
        } else if openRowID == id {
            openRowID = nil
        }
    }

    /// Follows the finger up to `restOpen`, then adds resistance — including against swiping
    /// toward an edge that has no action — so the row feels elastic instead of free-sliding.
    private func resisted(_ x: CGFloat) -> CGFloat {
        if (x > 0 && leading == nil) || (x < 0 && trailing == nil) { return x * 0.15 }
        guard abs(x) > restOpen else { return x }
        let over = abs(x) - restOpen
        let damped = restOpen + over * 0.55
        return x < 0 ? -damped : damped
    }
}
