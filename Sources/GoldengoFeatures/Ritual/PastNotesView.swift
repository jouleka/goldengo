import SwiftUI
import GoldengoCore
import GoldengoDesignSystem

/// A quiet, read-only journal of past mornings' intentions (GOL-93). Newest first.
public struct PastNotesView: View {
    let notes: [IntentionEntry]
    public init(notes: [IntentionEntry]) { self.notes = notes }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                Text("Past notes").font(.system(.title2, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.date.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                        Text("“\(note.text)”").font(.body).foregroundStyle(GoldengoTheme.inkPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
    }
}
