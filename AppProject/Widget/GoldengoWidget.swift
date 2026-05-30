import WidgetKit
import SwiftUI
import GoldengoData

struct GoldengoEntry: TimelineEntry { let date: Date; let totalText: String }

struct GoldengoProvider: TimelineProvider {
    func placeholder(in c: Context) -> GoldengoEntry { .init(date: .now, totalText: "L 0") }
    func getSnapshot(in c: Context, completion: @escaping (GoldengoEntry) -> Void) {
        completion(.init(date: .now, totalText: SharedSummary().read().todayTotalText))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<GoldengoEntry>) -> Void) {
        let e = GoldengoEntry(date: .now, totalText: SharedSummary().read().todayTotalText)
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct GoldengoWidgetView: View {
    var entry: GoldengoEntry
    var body: some View {
        VStack(alignment: .leading) {
            Text("Today").font(.caption).foregroundStyle(.secondary)
            Text(entry.totalText).font(.title2.bold()).minimumScaleFactor(0.6)
            Spacer()
            Label("Add", systemImage: "plus.circle.fill").font(.caption)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "goldengo://quickadd"))
    }
}

@main
struct GoldengoWidgetBundle: WidgetBundle {
    var body: some Widget { GoldengoWidget() }
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
