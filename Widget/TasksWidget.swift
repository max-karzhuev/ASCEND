import SwiftUI
import WidgetKit

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSummary.tasksKind, provider: Provider()) { entry in
            TasksWidgetView(entry: entry)
                .ascendWidgetSurface(entry.summary?.theme)
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
        let theme = entry.summary?.theme ?? .shadow
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                WidgetSymbol(name: "checklist", theme: theme)
                Text("Today’s quests").font(.headline).opacity(0.89)
            }
            if let summary = entry.summary, let titles = summary.pendingTitles,
               let count = summary.pendingCount, entry.date < summary.expires {
                if count == 0 {
                    Spacer(minLength: 0)
                    Label("No unfinished quests", systemImage: "checkmark.circle").font(.subheadline)
                } else {
                    let limit = family == .systemLarge ? 8 : 3
                    ForEach(Array(titles.prefix(limit).enumerated()), id: \.offset) { _, title in
                        HStack(spacing: 6) {
                            WidgetColorMark(size: CGSize(width: 9, height: 9)) {
                                Circle().strokeBorder(theme.accent, lineWidth: 1.25).frame(width: 7, height: 7)
                            }.accessibilityHidden(true)
                            Text(title).font(.subheadline).lineLimit(1).opacity(0.85)
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
