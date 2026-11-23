import SwiftUI
import WidgetKit

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSummary.calendarKind, provider: Provider()) { entry in
            CalendarWidgetView(entry: entry)
                .ascendWidgetSurface(entry.summary?.theme)
                .widgetURL(URL(string: "ascend://widget/calendar"))
        }
        .configurationDisplayName("Calendar Glow")
        .description("Your monthly calendar. Each planned quest you complete brightens its date.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CalendarWidgetView: View {
    @Environment(\.widgetRenderingMode) private var mode
    let entry: Entry
    var body: some View {
        if let summary = entry.summary, let month = summary.month, let days = summary.days, !days.isEmpty {
            VStack(spacing: 4) {
                Text(month).font(.caption.bold()).opacity(0.89).lineLimit(1)
                GeometryReader { area in
                    let gap: CGFloat = 2
                    let rows = CGFloat((days.count + 6) / 7)
                    let side = max(1, floor(min((area.size.width - 6 * gap) / 7,
                                                (area.size.height - (rows - 1) * gap) / rows)))
                    let grid = VStack(spacing: gap) {
                        ForEach(0..<Int(rows), id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(days.dropFirst(row * 7).prefix(7), id: \.date) { day in
                                    if day.inMonth {
                                        dayTile(day, summary: summary, side: side)
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel("\(day.date), \(day.planned == 0 ? "no recorded plan" : "\(day.completed) of \(day.planned) planned quests completed")")
                                    } else { Color.clear.frame(width: side, height: side).accessibilityHidden(true) }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if supportsColorMarks {
                        WidgetColorMark(size: area.size) { grid }
                            .accessibilityRepresentation { grid }
                    } else {
                        grid
                    }
                }
            }
        } else { Text("Open ASCEND to load your calendar.").font(.subheadline) }
    }
    @ViewBuilder private func dayTile(_ day: WidgetSummary.Day, summary: WidgetSummary, side: CGFloat) -> some View {
        let light = day.intensity
        let accent = summary.theme.accent
        let radius = min(7, side * 0.17)
        let number = Text("\(day.number)")
            .font(.system(size: min(15, side * 0.58), weight: day.isToday ? .bold : .medium, design: .rounded))
            .underline(day.isToday && entry.date < summary.expires)
        if light > 0, mode == .fullColor || supportsColorMarks {
            ZStack {
                CalendarGlow(intensity: light, accent: accent, cornerRadius: radius)
                number.foregroundStyle(light >= 0.53 ? Color.black.opacity(0.9) : Color.white.opacity(0.88))
            }.frame(width: side, height: side)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(mode == .fullColor ? accent : Color.primary)
                    .opacity(0.06 + 0.30 * light)
                    .shadow(color: .primary.opacity(0.16 * light), radius: 3 * light)
                number.foregroundStyle(mode == .fullColor ? .white : .primary)
                    .opacity(day.isToday || light > 0 ? 0.94 : 0.70)
            }.frame(width: side, height: side)
        }
    }

    private var supportsColorMarks: Bool {
        if #available(macOS 15, *) { return mode == .accented }
        return false
    }

}
