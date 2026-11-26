import Foundation

public enum HomeWidget: String, Codable, CaseIterable, Identifiable, Sendable {
    case player, calendar, quests, achievement, quitting, gym, health, goals, puzzles, mentalMath, chat, agenda
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .player: "Player progress"; case .calendar: "Consistency calendar"; case .quests: "Today’s quests"
        case .achievement: "Achievement streak"; case .quitting: "Quitting streaks"; case .gym: "Gym progress"
        case .health: "Apple Health"; case .goals: "Long-term goals"; case .puzzles: "Puzzle feed"
        case .mentalMath: "Mental math"; case .chat: "AI chat"; case .agenda: "Calendar agenda"
        }
    }
    public var summary: String {
        switch self {
        case .player: "Your level, rank and next XP milestone."
        case .calendar: "See your consistency across the month."
        case .quests: "Daily tasks and scheduled workouts."
        case .achievement: "Keep your activity streak growing."
        case .quitting: "Check in and track your quitting goals."
        case .gym: "Plan workouts and track muscle progress."
        case .health: "Read your activity and sleep from Apple Health."
        case .goals: "Follow progress toward your long-term goals."
        case .puzzles: "Practice a subject with daily questions."
        case .mentalMath: "Train arithmetic with a timed drill."
        case .chat: "Talk to your AI and build a personal plan."
        case .agenda: "See events from your connected calendars."
        }
    }
    public var icon: String {
        switch self {
        case .player: "shield"; case .calendar: "calendar"; case .quests: "checklist"; case .achievement: "flame"
        case .quitting: "leaf"; case .gym: "figure.strengthtraining.traditional"; case .health: "heart"
        case .goals: "scope"; case .puzzles: "puzzlepiece.extension"; case .mentalMath: "plus.forwardslash.minus"
        case .chat: "bubble.left.and.bubble.right"; case .agenda: "calendar.badge.clock"
        }
    }
}
public struct HomeLayout: Codable, Equatable, Sendable {
    public var order: [HomeWidget] = HomeWidget.allCases
    public var hidden: Set<HomeWidget> = []
    public var wide: Set<HomeWidget> = []
    public init() {}
    public var visible: [HomeWidget] { normalized.order.filter { !hidden.contains($0) } }
    public var normalized: HomeLayout {
        var result = self, seen = Set<HomeWidget>()
        result.order = (order + HomeWidget.allCases).filter { seen.insert($0).inserted }
        return result
    }
    public mutating func move(_ widget: HomeWidget, by offset: Int) {
        let shown = visible
        guard let i = shown.firstIndex(of: widget), shown.indices.contains(i + offset),
              let from = order.firstIndex(of: widget), let to = order.firstIndex(of: shown[i + offset]) else { return }
        order.swapAt(from, to)
    }
    /// Rows preserve reading order, including full-width cards in a two-column layout.
    public func rows(twoColumns: Bool) -> [[HomeWidget]] {
        var rows: [[HomeWidget]] = []
        for widget in visible {
            if twoColumns, !wide.contains(widget), let last = rows.last, last.count == 1, !wide.contains(last[0]) {
                rows[rows.count - 1].append(widget)
            } else { rows.append([widget]) }
        }
        return rows
    }
}

public struct StreakStatus: Equatable, Sendable {
    public var count: Int
    public var completedToday: Bool
    public var frozen: Bool
    public var recoverBy: String?
    public var expired: Bool
}
public enum StreakRules {
    /// Two missed days may be bridged. Return by the end of the third day after
    /// the last activity. Frozen days preserve the count but never add credit.
    public static func status(days: Set<String>, today: String, planning: Planning) -> StreakStatus {
        let days = days.filter { Planning.validDay($0) && $0 <= today }.sorted()
        guard let last = days.last else { return .init(count: 0, completedToday: false, frozen: false, recoverBy: nil, expired: false) }
        var count = 0, previous: String?
        for day in days {
            if let previous, day > planning.adding(3, to: previous) { count = 0 }
            count += 1; previous = day
        }
        let deadline = planning.adding(3, to: last)
        let expired = today > deadline
        return .init(count: expired ? 0 : count, completedToday: last == today,
                     frozen: !expired && today > planning.adding(1, to: last),
                     recoverBy: expired || last == today ? nil : deadline, expired: expired)
    }
}

public struct QuitHabit: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name: String
    public var startedDay: String
    public var checkInHour = 20
    public var archived = false
    public init(name: String, startedDay: String) { self.name = name; self.startedDay = startedDay }
    public static let presets = ["Weed", "Alcohol", "Smoking", "Drugs"]
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              Planning.validDay(startedDay), (18...23).contains(checkInHour) else { throw DataError.invalid("Give your quitting goal a name and choose an evening check-in time.") }
    }
    public func canCheckIn(now: Date, planning: Planning) -> Bool {
        !archived && planning.day(now) >= startedDay && planning.calendar.component(.hour, from: now) >= checkInHour
    }
}
public struct QuitCheckIn: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(habitID)|\(day)" }
    public var habitID: String
    public var day: String
    public var stayedFree: Bool
    public var loggedAt: Date
    public init(habitID: String, day: String, stayedFree: Bool, loggedAt: Date) {
        self.habitID = habitID; self.day = day; self.stayedFree = stayedFree; self.loggedAt = loggedAt
    }
}
public enum Quitting {
    public static func status(habit: QuitHabit, checkIns: [QuitCheckIn], today: String, planning: Planning) -> StreakStatus {
        let entries = checkIns.filter { $0.habitID == habit.id && $0.day >= habit.startedDay && $0.day <= today }
        let restart = entries.filter { !$0.stayedFree }.map(\.day).max() ?? ""
        return StreakRules.status(days: Set(entries.filter { $0.stayedFree && $0.day > restart }.map(\.day)), today: today, planning: planning)
    }
}

public enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case upperBack, lowerBack, lats, chest, shoulders, abs, calves, quads, hamstrings, glutes, triceps, biceps, forearms, cardio
    public var id: String { rawValue }
    public var title: String {
        switch self { case .upperBack: "Upper back"; case .lowerBack: "Lower back"; case .triceps: "Triceps"; default: rawValue.capitalized }
    }
    public var isBack: Bool { [.upperBack, .lowerBack, .lats, .hamstrings, .glutes, .triceps].contains(self) }
}
public struct WorkoutExercise: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name = ""
    public var muscles: Set<MuscleGroup> = []
    public var sets = 3
    public var prescription = "8–12 reps"
    public init() {}
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 150,
              !muscles.isEmpty, (1...30).contains(sets), prescription.count <= 80 else {
            throw DataError.invalid("Each exercise needs a name, at least one muscle group, and 1–30 sets.")
        }
    }
}
public struct WorkoutPlan: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name = ""
    public var exercises: [WorkoutExercise] = [WorkoutExercise()]
    public var weekdays: Set<Int> = []
    public init() {}
    public var muscles: Set<MuscleGroup> { exercises.reduce(into: []) { $0.formUnion($1.muscles) } }
    public func scheduled(on day: String, planning: Planning) -> Bool { weekdays.contains(planning.calendar.component(.weekday, from: planning.date(day))) }
    public func validate() throws {
        guard weekdays.allSatisfy({ (1...7).contains($0) }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 150,
              (1...30).contains(exercises.count), Set(exercises.map(\.id)).count == exercises.count else {
            throw DataError.invalid("Name your workout and add between 1 and 30 exercises.")
        }
        for exercise in exercises { try exercise.validate() }
    }
}
public struct WorkoutLog: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var planID: String
    public var name: String
    public var day: String
    public var exercises: [WorkoutExercise]
    public var loggedAt: Date
    public init(plan: WorkoutPlan, day: String, loggedAt: Date) {
        planID = plan.id; name = plan.name; exercises = plan.exercises; self.day = day; self.loggedAt = loggedAt
    }
    public var muscles: Set<MuscleGroup> { exercises.reduce(into: []) { $0.formUnion($1.muscles) } }
    public func validate() throws {
        var plan = WorkoutPlan(); plan.name = name; plan.exercises = exercises; try plan.validate()
        guard Planning.validDay(day), !planID.isEmpty else { throw DataError.invalid("Invalid workout date or plan.") }
    }
}
public struct GymSettings: Codable, Equatable, Sendable {
    public var targets: [MuscleGroup: Int] = [:]
    public init() {}
    public func target(_ muscle: MuscleGroup) -> Int { targets[muscle] ?? 3 }
    public func validate() throws {
        guard targets.values.allSatisfy({ (1...14).contains($0) }) else { throw DataError.invalid("Choose a weekly target between 1 and 14 sessions.") }
    }
}
public enum GymProgress {
    public static func sessions(_ muscle: MuscleGroup, logs: [WorkoutLog], today: String, planning: Planning) -> Int {
        let week = planning.week(today)
        return logs.filter { $0.day >= week && $0.day <= today && $0.muscles.contains(muscle) }.count
    }
}

public enum HealthIntervals {
    /// Union overlapping asleep samples, including overlapping watch/phone sources.
    public static func duration(_ intervals: [DateInterval], within window: DateInterval) -> TimeInterval {
        let intervals = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start), end = min(interval.end, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0, current: DateInterval?
        for interval in intervals {
            if let old = current, interval.start <= old.end { current = DateInterval(start: old.start, end: max(old.end, interval.end)) }
            else { total += current?.duration ?? 0; current = interval }
        }
        return total + (current?.duration ?? 0)
    }
}
