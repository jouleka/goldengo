import WidgetKit
import SwiftUI
import GoldengoData
import GoldengoIntents

struct GoldengoEntry: TimelineEntry { let date: Date; let totalText: String; let reveal: Bool }

struct GoldengoProvider: TimelineProvider {
    func placeholder(in c: Context) -> GoldengoEntry {
        .init(date: .now, totalText: "L 0", reveal: false)
    }
    func getSnapshot(in c: Context, completion: @escaping (GoldengoEntry) -> Void) {
        let snap = SharedSummary().read()
        completion(.init(date: .now, totalText: snap.todayTotalText, reveal: snap.revealOnLockScreen))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<GoldengoEntry>) -> Void) {
        let snap = SharedSummary().read()
        let e = GoldengoEntry(date: .now, totalText: snap.todayTotalText, reveal: snap.revealOnLockScreen)
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct GoldengoWidgetView: View {
    var entry: GoldengoEntry
    var body: some View {
        VStack(alignment: .leading) {
            Text("Today").font(.caption).foregroundStyle(.secondary)
            Text(entry.totalText).font(.title2.bold()).minimumScaleFactor(0.6)
                .privacySensitive(!entry.reveal)   // redacted on Lock Screen unless the user opted in
            Spacer()
            Label("Add", systemImage: "plus.circle.fill").font(.caption)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "goldengo://quickadd"))
    }
}

@main
struct GoldengoWidgetBundle: WidgetBundle {
    var body: some Widget {
        GoldengoWidget()
        if #available(iOS 18.0, *) { GoldengoControl() }
    }
}

struct GoldengoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoldengoWidget", provider: GoldengoProvider()) { entry in
            GoldengoWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's spending")
        .description("Today's total — tap to add.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
