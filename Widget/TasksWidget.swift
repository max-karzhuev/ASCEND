import SwiftUI
import WidgetKit

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSummary.tasksKind, provider: Provider()) { entry in
            TasksWidgetView(entry: entry)
                .foregroundStyle(.white)
                .containerBackground(for: .widget) { Color(white: 0.075) }
                .widgetURL(URL(string: "ascend://widget/tasks"))
        }
        .configurationDisplayName("Tasks to Complete")
        .description("See unfinished quests for today and open your quest list.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TasksWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let accent = (entry.summary?.theme ?? .shadow).accent
        VStack(alignment: .leading, spacing: 5) {
            Label("Today’s quests", systemImage: "checklist")
                .font(.headline).foregroundStyle(accent)
            if let summary = entry.summary, let titles = summary.pendingTitles,
               let count = summary.pendingCount, entry.date < summary.expires {
                if count == 0 {
                    Spacer(minLength: 0)
                    Label("No unfinished quests", systemImage: "checkmark.circle").font(.subheadline)
                } else {
                    let limit = family == .systemLarge ? 8 : 3
                    ForEach(Array(titles.prefix(limit).enumerated()), id: \.offset) { _, title in
                        HStack(spacing: 6) {
                            Circle().strokeBorder(accent.opacity(0.8), lineWidth: 1).frame(width: 7, height: 7)
                            Text(title).font(.subheadline).lineLimit(1)
                        }.privacySensitive()
                    }
                    if count > limit { Text("+\(count - limit) more").font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                Spacer(minLength: 0)
                Text("Open ASCEND for today’s quests.").font(.subheadline)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
