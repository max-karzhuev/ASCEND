import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, summary: nil) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = read()
        var entries = [entry]
        if let expiry = entry.summary?.expires, expiry > entry.date {
            entries.append(Entry(date: expiry, summary: entry.summary))
        }
        completion(Timeline(entries: entries, policy: .after(Date.now.addingTimeInterval(1800))))
    }

    private func read() -> Entry {
        let data = WidgetSummary.location.flatMap { try? Data(contentsOf: $0) }
        return Entry(date: .now, summary: data.flatMap { try? JSONDecoder().decode(WidgetSummary.self, from: $0) })
    }
}

@main
struct ASCENDWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TasksWidget()
        CalendarWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSummary.kind, provider: Provider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    WidgetSymbol(name: "chevron.up", theme: entry.summary?.theme ?? .shadow)
                    Text("ASCEND").font(.caption.bold())
                }
                Spacer(minLength: 2)
                if let data = entry.summary {
                    Text("Level \(data.level)").font(.title2.bold())
                    GeometryReader { area in
                        let ratio = min(1, max(0, Double(data.xp) / Double(max(data.target, 1))))
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white).opacity(0.09)
                            if ratio > 0 {
                                WidgetColorMark(size: CGSize(width: max(1, area.size.width * ratio), height: 6)) {
                                    Capsule().fill(data.theme.accent)
                                }
                            }
                        }
                    }.frame(height: 6).accessibilityHidden(true)
                    Text("\(data.xp) / \(data.target) XP").font(.caption)
                    if entry.date >= data.expires { Text("Open ASCEND for today’s plan").font(.caption) }
                    else if data.planned == 0 { Text("No quests planned today").font(.caption) }
                    else { Text("Today · \(data.completed)/\(data.planned) quests").font(.subheadline.bold()) }
                } else {
                    Text("Today’s Progress").font(.headline)
                    Text("Open ASCEND to load your progress.").font(.caption)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .ascendWidgetSurface(entry.summary?.theme)
                .environment(\.colorScheme, .dark)
        }
        .configurationDisplayName("Today’s Progress")
        .description("See today’s quest count and your progress toward the next level.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
