import WidgetKit
import SwiftUI
import GoldengoData
import GoldengoIntents

struct GoldengoEntry: TimelineEntry { let date: Date; let totalText: String; let reveal: Bool }

struct GoldengoProvider: TimelineProvider {
    func placeholder(in c: Context) -> GoldengoEntry {
        .init(date: .now, totalText: SharedSummary().todayDisplayText(), reveal: false)
    }
    func getSnapshot(in c: Context, completion: @escaping (GoldengoEntry) -> Void) {
        let s = SharedSummary()
        completion(.init(date: .now, totalText: s.todayDisplayText(), reveal: s.read().revealOnLockScreen))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<GoldengoEntry>) -> Void) {
        let s = SharedSummary()
        let reveal = s.read().revealOnLockScreen
        let now = Date.now
        let midnight = Calendar.current.nextDate(after: now,
                                                 matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        // Two entries: today's total now, and 0 at midnight (the cache's date is no longer "today" by
        // then, so todayDisplayText returns 0) — so it rolls over even without an exact-midnight refresh.
        let entries = [
            GoldengoEntry(date: now, totalText: s.todayDisplayText(now: now), reveal: reveal),
            GoldengoEntry(date: midnight, totalText: s.todayDisplayText(now: midnight), reveal: reveal),
        ]
        completion(Timeline(entries: entries, policy: .after(midnight)))
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
