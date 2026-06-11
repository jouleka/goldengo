import SwiftUI
import GoldengoData
import GoldengoDesignSystem

/// Morning intention capture — "a letter from this-morning-you". One line + Save / Skip.
public struct MorningView: View {
    let onDone: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    public init(onDone: @escaping () -> Void) { self.onDone = onDone }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        focused = false
        if !trimmed.isEmpty {
            SharedSummary().setIntention(trimmed, on: .now)
            GoldengoHaptics.spendLanded()
        }
        onDone()
    }

    public var body: some View {
        VStack(spacing: GoldengoTheme.Spacing.l) {
            Spacer()
            Image(systemName: "sun.max.fill")
                .font(.system(size: 48)).foregroundStyle(GoldengoTheme.accent)
            Text("What's today about?")
                .font(.title2.weight(.bold))
            Text("One line for tonight-you to read back.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, GoldengoTheme.Spacing.xl)
            TextField("Today, I want to…", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, GoldengoTheme.Spacing.l)
            Spacer()
            Button(action: save) {
                Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
            }
            .background(GoldengoTheme.accent).foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
            .padding(.horizontal, GoldengoTheme.Spacing.l)
            Button("Skip for today", action: onDone)
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.bottom, GoldengoTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.goldengoBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { focused = false }     // tap-outside dismissal (no keyboard toolbar)
        .onAppear { focused = true }
        // GOL-97: leaving without saving — Skip button OR an interactive swipe-down — marks the
        // morning skipped so it never re-prompts today. (A save sets intentionDate, which already
        // suppresses; the extra marker is harmless then.)
        .onDisappear {
            let summary = SharedSummary()
            let savedToday = summary.readIntentionDate().map { Calendar.current.isDate($0, inSameDayAs: .now) } ?? false
            if !savedToday { summary.setMorningSkipped(on: .now) }
        }
    }
}
