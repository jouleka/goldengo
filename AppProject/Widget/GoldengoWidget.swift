import WidgetKit
import SwiftUI
import GoldengoCore
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

// MARK: - Pocket Truth (GOL-98): the lock screen claims what's in your pocket.

struct PocketEntry: TimelineEntry { let date: Date; let payload: PocketPayload?; let reveal: Bool }

struct PocketProvider: TimelineProvider {
    func placeholder(in c: Context) -> PocketEntry {
        .init(date: .now, payload: SharedSummary().readPocketPayload(), reveal: false)
    }
    func getSnapshot(in c: Context, completion: @escaping (PocketEntry) -> Void) {
        let s = SharedSummary()
        completion(.init(date: .now, payload: s.readPocketPayload(), reveal: s.read().revealOnLockScreen))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<PocketEntry>) -> Void) {
        let s = SharedSummary()
        let payload = s.readPocketPayload()
        let reveal = s.read().revealOnLockScreen
        let now = Date.now
        // One entry per upcoming midnight so "since Tue" wording could go stale at most a day
        // without app opens; saves/reconciles reload all timelines anyway (existing call).
        let cal = Calendar.current
        var entries = [PocketEntry(date: now, payload: payload, reveal: reveal)]
        for offset in 1...2 {
            if let d = cal.date(byAdding: .day, value: offset, to: now) {
                entries.append(PocketEntry(date: cal.startOfDay(for: d), payload: payload, reveal: reveal))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PocketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PocketEntry
    var body: some View {
        Group {
            if family == .accessoryInline {
                Text(entry.payload.map { entry.reveal ? $0.revealedInline : $0.hiddenInline } ?? "Set your wallet")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if let payload = entry.payload, payload.hasWallet {
                        ForEach((entry.reveal ? payload.revealedLines : payload.hiddenLines).prefix(3),
                                id: \.self) { line in
                            Text(line).font(.caption2).minimumScaleFactor(0.7).lineLimit(1)
                        }
                    } else {
                        Text("In your pocket").font(.caption2).foregroundStyle(.secondary)
                        Text("Set your wallet to begin").font(.caption2)
                    }
                }
            }
        }
        .privacySensitive(!entry.reveal)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "goldengo://wallet"))
    }
}

struct PocketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PocketWidget", provider: PocketProvider()) { entry in
            PocketWidgetView(entry: entry)
        }
        .configurationDisplayName("In your pocket")
        .description("What the books say you're carrying — tap to set it straight.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}

@main
struct GoldengoWidgetBundle: WidgetBundle {
    var body: some Widget {
        GoldengoWidget()
        PocketWidget()
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
