import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The evening "close the day" reflection: surfaces this morning's intention, today's usuals to
/// confirm, a calm spend recap, and a warm close. Accountability to yourself — never scolding.
public struct EveningView: View {
    @State private var model: EveningModel
    let onDone: () -> Void
    public init(model: EveningModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model); self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                Text("Close your day").font(.title.weight(.bold))

                // This morning's intention (or a gentle "no note" line).
                if let intention = model.intention {
                    VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.s) {
                        Text("This morning you said").font(.caption).foregroundStyle(.secondary)
                        Text("“\(intention)”").font(.title3.weight(.semibold))
                    }
                } else {
                    Text("No note this morning — that's fine.")
                        .font(.body).foregroundStyle(.secondary)
                }

                // Today's usuals — one tap each to confirm.
                if !model.ghosts.isEmpty {
                    Text("Anything usual today?").font(.headline)
                    ForEach(model.ghosts) { ghost in
                        Button {
                            GoldengoHaptics.spendLanded()
                            Task { await model.confirm(ghost) }
                        } label: {
                            HStack {
                                Text(ghost.displayName)
                                Spacer()
                                Text(Money(amount: ghost.amount,
                                           currency: CurrencyCode(ghost.currencyCode)).formatted())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "plus.circle.fill").foregroundStyle(GoldengoTheme.accent)
                            }
                            .padding()
                            .background(Color.goldengoSurface)
                            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Calm spend recap (no judgement framing).
                HStack {
                    Text("Today").foregroundStyle(.secondary)
                    Spacer()
                    Text(model.todayTotalText).font(.headline)
                }
                .padding(.vertical, GoldengoTheme.Spacing.s)

                Text("You were trying. Rest well.")
                    .font(.body).foregroundStyle(.secondary)

                Button(action: onDone) {
                    Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                }
                .background(GoldengoTheme.accent).foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .task { await model.load() }
        // Mark the night closed on ANY dismissal — Done OR an interactive swipe-down — so a
        // swiped-away reflection is not re-presented later the same evening session.
        .onDisappear { model.markReflected() }
    }
}
