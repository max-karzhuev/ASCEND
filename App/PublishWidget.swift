#if os(macOS)
import WidgetKit
import Foundation
import OSLog

extension AppStore {
    func publishWidget() {
        guard !isValidation, !isDemo, let file = WidgetSummary.location else { return }
        do {
            if profile.onboarded {
                let day = Progression.day(today, ledger: ledger, today: today)
                let player = progress
                var summary = WidgetSummary(theme: profile.theme, level: player.level, xp: player.intoLevel,
                                            target: player.required, planned: day.planned, completed: day.completed,
                                            expires: planning.nextMidnight(after: clockNow))
                let pending = todayQuests.filter { ledger.completion($0.id)?.active != true }
                summary.pendingCount = pending.count
                summary.pendingTitles = pending.prefix(8).map { $0.quest.title }
                let formatter = DateFormatter()
                formatter.calendar = planning.calendar
                formatter.timeZone = planning.calendar.timeZone
                formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
                summary.month = formatter.string(from: clockNow)
                // Decode the occurrence and completion histories once for the entire month.
                let plannedByDate = Dictionary(grouping: ledger.occurrences.filter(\.planned), by: \.day)
                let completedIDs = Set(ledger.completions.map(\.occurrenceID))
                summary.days = planning.monthDays(containing: clockNow).map { date in
                    let planned = plannedByDate[date] ?? []
                    let completed = planned.filter { completedIDs.contains($0.id) }.count
                    let day = DaySummary(day: date, planned: planned.count, completed: completed, extras: 0,
                                         xp: 0, brainSessions: 0, isFuture: date > today)
                    return WidgetSummary.Day(date: date, number: Int(date.suffix(2)) ?? 1,
                                             planned: planned.count, completed: completed,
                                             intensity: day.intensity, inMonth: date.prefix(7) == today.prefix(7),
                                             isToday: date == today)
                }
                if let data = try? Data(contentsOf: file),
                   (try? JSONDecoder().decode(WidgetSummary.self, from: data)) == summary { return }
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try JSONEncoder().encode(summary).write(to: file, options: .atomic)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            } else { return }
            for kind in [WidgetSummary.kind, WidgetSummary.tasksKind, WidgetSummary.calendarKind] {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        } catch {
            Logger(subsystem: "ASCEND", category: "Widget").error("Could not publish desktop summary: \(error.localizedDescription)")
        }
    }
}
#endif
