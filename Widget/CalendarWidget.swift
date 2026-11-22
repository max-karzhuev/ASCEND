import SwiftUI
import WidgetKit

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSummary.calendarKind, provider: Provider()) { entry in
            CalendarWidgetView(entry: entry)
                .foregroundStyle(.white)
                .containerBackground(for: .widget) { Color(white: 0.075) }
                .widgetURL(URL(string: "ascend://widget/calendar"))
        }
        .configurationDisplayName("Calendar Glow")
        .description("Your monthly calendar. Each planned quest you complete brightens its date.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CalendarWidgetView: View {
    let entry: Entry
    var body: some View {
        if let summary = entry.summary, let month = summary.month, let days = summary.days, !days.isEmpty {
            VStack(spacing: 4) {
                Text(month).font(.caption.bold()).lineLimit(1)
                GeometryReader { area in
                    let gap: CGFloat = 2
                    let rows = CGFloat((days.count + 6) / 7)
                    let side = max(1, floor(min((area.size.width - 6 * gap) / 7,
                                                (area.size.height - (rows - 1) * gap) / rows)))
                    VStack(spacing: gap) {
                        ForEach(0..<Int(rows), id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(days.dropFirst(row * 7).prefix(7), id: \.date) { day in
                                    if day.inMonth {
                                        ZStack {
                                            CalendarGlow(intensity: day.intensity, accent: summary.theme.accent,
                                                         cornerRadius: min(7, side * 0.17))
                                            Text("\(day.number)")
                                                .font(.system(size: min(15, side * 0.58), weight: .medium, design: .rounded))
                                                .foregroundStyle(day.intensity >= 0.53 ? Color.black : Color.white)
                                                .underline(day.isToday && entry.date < summary.expires)
                                        }.frame(width: side, height: side)
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel("\(day.date), \(day.planned == 0 ? "no recorded plan" : "\(day.completed) of \(day.planned) planned quests completed")")
                                    } else { Color.clear.frame(width: side, height: side).accessibilityHidden(true) }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else { Text("Open ASCEND to load your calendar.").font(.subheadline) }
    }
}
