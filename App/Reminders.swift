import Foundation
import UserNotifications
import Observation

@MainActor @Observable final class ReminderService {
    var status = "Reminders are off"
    private var refreshID = UUID()
    func requestPermission() async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { throw DataError.invalid("Notifications are not allowed. Enable ASCEND in System Settings → Notifications.") }
    }
    func refresh(store: AppStore) async {
        let id = UUID(); refreshID = id
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard refreshID == id else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("ascend.") }.map(\.identifier))
        guard store.profile.reminderDevice == store.actor else {
            status = store.profile.reminderDevice.isEmpty ? "Reminders are off" : "Another device is selected for reminders"; return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { status = "Notifications are disabled in system settings"; return }
        guard refreshID == id else { return }
        let p = store.planning
        var requests: [(Date, UNNotificationRequest)] = []
        func enqueue(key: String, title: String, body: String, day: String, minute: Int) {
            var components = p.calendar.dateComponents([.year,.month,.day], from: p.date(day))
            components.timeZone = p.calendar.timeZone; components.hour = minute / 60; components.minute = minute % 60
            guard let fire = p.calendar.date(from: components), fire > Date() else { return }
            let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            requests.append((fire, UNNotificationRequest(identifier: "ascend.\(key).\(day)", content: content, trigger: trigger)))
        }
        for offset in 0..<7 {
            let day = p.adding(offset, to: store.today)
            for occurrence in store.occurrences(on: day) {
                if let minute = occurrence.quest.reminderMinutes, store.ledger.completion(occurrence.id)?.active != true {
                    enqueue(key: occurrence.id, title: occurrence.quest.title, body: "One small step toward your next level.", day: day, minute: minute)
                }
            }
            if p.calendar.component(.weekday, from: p.date(day)) == 2 {
                for quest in store.ledger.quests where quest.schedule == .weekly && !quest.archived && quest.startDay <= day {
                    if let minute = quest.reminderMinutes { enqueue(key: quest.id, title: quest.title, body: "Your weekly target: \(quest.weeklyTarget) sessions, at your pace.", day: day, minute: minute) }
                }
            }
            for habit in store.quitHabits where !habit.archived && habit.startedDay <= day {
                if !store.quitCheckIns.contains(where: { $0.habitID == habit.id && $0.day == day }) {
                    enqueue(key: "quit.\(habit.id)", title: "Your evening check-in", body: "Take a moment to check in on your quitting goal.", day: day, minute: habit.checkInHour * 60)
                }
            }
            if store.profile.dailyCheckIn { enqueue(key: "checkin", title: "A moment for your ascent", body: "Check in with your quests. Every small step counts.", day: day, minute: 20 * 60) }
            if store.profile.brainReminder { enqueue(key: "brain", title: "Keep your curiosity moving", body: "A short Brainmaxing session is waiting when you’re ready.", day: day, minute: 18 * 60) }
        }
        var scheduled = 0
        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(60) {
            guard refreshID == id else { return }
            do { try await center.add(request); scheduled += 1 } catch { status = "Reminder scheduling failed: \(error.localizedDescription)"; return }
        }
        status = "\(scheduled) reminders scheduled on this device · next 7 days"
    }
}
